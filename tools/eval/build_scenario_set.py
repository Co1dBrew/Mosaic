#!/usr/bin/env python3
"""构建 v5 场景化评测集（`scenario-v5`）。

# 这个脚本存在的理由

评测集是一份 300 KB 的 JSON。直接手改那份 JSON 有两个问题：改动无法审查
（diff 是一堆花括号），以及**没有地方写「为什么这条用例是这样标的」**。
所以数据在这里以 Python 字面量的形式被写出来，JSON 是产物。

# 数据来源标记（重要）

这里的全部 query 与新增笔记都是 **agent 编写的场景化用例**，
provenance 一律标 `agent_authored_realistic`。

**不得**把它们称为 real user logs / actual user queries / human collected /
organic traffic / production traffic。它们可以证明评测管线与覆盖结构成立，
不能用来声称「真实用户 Recall 提升 x%」。

# 用法

    python3 tools/eval/build_scenario_set.py            # 重新生成 JSON + 打印质量报告
    python3 tools/eval/build_scenario_set.py --report   # 只打印质量报告，不写文件
"""

import argparse
import collections
import hashlib
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FIXTURE = os.path.join(ROOT, "Sources/MosaicKitChecks/Fixtures/HumanLikeGoldenSet.json")
# v4 的快照。**构建的输入必须是它，不能是产物本身** —— 读产物的话脚本就不再幂等，
# 跑第二遍会在自己生成的笔记上再叠一层，checksum 也会随运行次数漂移。
BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "base_v4.json")

VERSION = "scenario-v5"
DISCLAIMER = (
    "Agent-authored, production-style evaluation cases over a synthetic corpus. "
    "provenance=agent_authored_realistic. This is NOT real user data, not real user "
    "queries, and not production traffic; it must never be reported as such."
)
PROV = "agent_authored_realistic"

# ---------------------------------------------------------------------------
# 1 · 新增笔记：把已有的 3 篇同构簇扩到 6–8 篇
#
# v4 的簇是 3 篇，而 Top-5 装得下整簇 —— 于是 in-scope R@5 恒为 1.000，
# 那个指标什么都没测到（HANDOFF_NEXT P1 #5 记的「一半没达成」）。
# 簇扩到 6–8 篇之后，Top-5 装不下整簇，R@5 才重新有区分度。
#
# 每一篇新笔记都必须**自身可信**：它是一份真的会出现在用户笔记里的东西，
# 而不是为了凑数把目标笔记改一个数字。
# ---------------------------------------------------------------------------

NEW_NOTES = [
    # ---- cluster: cs5330-hw（课程作业，7 篇）——「哪一次作业允许组队 / 截止是哪天」
    ("T50", "CS5330 第一周作业", "text", "zh", "distractor", "cs5330-hw",
     "CS5330 第一周作业：完成开发环境搭建并跑通示例图像读写，截止时间是九月十二日晚上十一点五十九分。"
     "交付物是一张运行截图。不计入总成绩，只作为环境检查。"),
    ("T51", "CS5330 第五周作业", "text", "zh", "distractor", "cs5330-hw",
     "CS5330 第五周作业：实现基于特征匹配的图像拼接，截止时间是十月十七日晚上十一点五十九分。"
     "交付物是 stitch.py 加三组拼接结果。允许两人一组，但要各自提交。"),
    ("T52", "CS5330 第九周作业", "text", "zh", "distractor", "cs5330-hw",
     "CS5330 第九周作业：用 PyTorch 训练一个数字识别网络并报告混淆矩阵，截止时间是十一月二十八日晚上十一点五十九分。"
     "交付物是训练脚本加一页误分类分析。必须独立完成。"),
    ("T53", "CS5330 期末项目提案", "text", "zh", "distractor", "cs5330-hw",
     "CS5330 期末项目提案：一页 A4，说明题目、数据来源、评估方式和分工，截止时间是十一月七日下午五点。"
     "提案不打分，但没交提案的不能提交期末项目。"),
    ("T54", "CS5330 期末项目提交", "text", "zh", "distractor", "cs5330-hw",
     "CS5330 期末项目：代码、五页报告和三分钟演示视频，截止时间是十二月十九日晚上十一点五十九分。"
     "允许三人一组，提交一份即可，报告里要写清楚每个人做了什么。"),

    # ---- cluster: reimbursement（报销政策，8 篇）——版本迭代型近似
    ("D50", "报销政策 第三版 草案", "extracted", "zh", "distractor", "reimbursement",
     "差旅报销政策 第三版 草案 单日餐饮报销上限拟调整为一百五十美元，尚未生效，仍以第二版为准。"
     "本草案仅供财务内部讨论，不对外发布。"),
    ("D51", "报销政策 常见问题", "extracted", "zh", "distractor", "reimbursement",
     "差旅报销常见问题 问：餐饮上限包含小费吗？答：包含。问：多人同行如何拆分？答：按人头平摊后各自提交。"
     "本文不规定具体金额，请以现行版本政策为准。"),
    ("D52", "团建费用政策", "extracted", "zh", "distractor", "reimbursement",
     "团队建设费用政策 每人每季度上限一百美元，需部门负责人事前审批。团建费用与差旅餐饮报销分开计算，"
     "不共用上限，也不适用差旅政策的收据门槛。"),

    # ---- cluster: extension-email（延期/材料邮件，7 篇）
    ("L50", "项目主任邮件 已收到材料", "link", "zh", "distractor", "extension-email",
     "邮件主题 关于你的延期申请 内容 材料已收到，正在排队审核，通常需要五到十个工作日。"
     "在收到正式批准前请不要离境。"),
    ("L51", "国际学生办公室邮件 预约", "link", "zh", "distractor", "extension-email",
     "邮件主题 关于你的延期申请 内容 请预约一次线下面谈，带上护照、现有 I-20 和资助证明。"
     "面谈本身不构成批准，批准结果会另行邮件通知。"),
    ("L52", "导师邮件 提醒截止", "link", "zh", "distractor", "extension-email",
     "邮件主题 关于你的延期申请 内容 提醒一下，延期申请最迟要在项目结束日期前三十天提交，"
     "过期就只能走恢复身份的流程，那个要麻烦很多。"),
    ("L53", "系统通知 状态变更", "link", "zh", "distractor", "extension-email",
     "系统通知 你的申请状态由「待补材料」变更为「审核中」。本邮件为自动发送，不代表最终结果，请勿回复。"),

    # ---- cluster: toner（耗材型号，7 篇）——纯词面对抗
    ("I50", "Toner CF276A label", "ocr", "en", "distractor", "toner",
     "HP LaserJet Toner Cartridge CF276A Standard Yield approx 3000 pages Compatible M404 M428 Black "
     "Not interchangeable with the 59 series"),
    ("I51", "Toner CF276X label", "ocr", "en", "distractor", "toner",
     "HP LaserJet Toner Cartridge CF276X High Yield approx 10000 pages Compatible M404 M428 Black "
     "Manufactured 2025-06"),
    ("I52", "Toner CF259X remanufactured", "ocr", "en", "distractor", "toner",
     "Remanufactured Toner Cartridge compatible with CF259X High Yield approx 10000 pages "
     "Third party product not made by HP Chip may require firmware downgrade"),
    ("I53", "Drum unit label", "ocr", "en", "distractor", "toner",
     "HP LaserJet Imaging Drum Unit approx 30000 pages Compatible M404 M428 This is a drum not a toner "
     "Replace when print quality degrades"),

    # ---- cluster: apartment-tour（看房预约，7 篇）
    ("L54", "Apartment tour Unit 7C", "link", "en", "distractor", "apartment-tour",
     "Your tour for Unit 7C is confirmed for Sunday at 11am. Unit 7C is a one bedroom on the seventh floor, "
     "rent 2410 per month, available from November 1."),
    ("L55", "Apartment tour rescheduled", "link", "en", "distractor", "apartment-tour",
     "Your Saturday 11am tour has been moved to Saturday 3pm at the leasing office. The unit shown is unchanged. "
     "Please bring a photo ID."),
    ("L56", "Apartment application received", "link", "en", "distractor", "apartment-tour",
     "We received your application for a one bedroom. No tour is scheduled by this message. "
     "Screening takes two to three business days."),
    ("L57", "Apartment tour cancelled", "link", "en", "distractor", "apartment-tour",
     "Your tour scheduled for Saturday has been cancelled because the unit was leased. "
     "We can show you a comparable unit next week if you are still interested."),

    # ---- cluster: dosage（用药剂量，7 篇）——数字型近似，跨语料
    ("A50", "复查时的用药确认", "transcript", "zh", "distractor", "dosage",
     "复查的时候我又问了一次，医生说现在这个八百七十五毫克的方案吃满五天就可以停，不用再来复诊。"
     "如果还有低烧再打电话。"),
    ("A51", "药师电话 服用提醒", "transcript", "zh", "distractor", "dosage",
     "药师说这个药要饭后吃，两次之间至少隔六小时。如果漏了一次就跳过，不要一次吃两粒。"
     "这通电话没有说具体毫克数。"),
    ("I54", "阿莫西林药盒 875", "ocr", "zh", "distractor", "dosage",
     "药品名称 阿莫西林胶囊 规格 零点八七五克 用法 每次一粒 每十二小时一次 饭后服用 疗程五天 有效期 二零二八年一月"),
    ("I55", "阿莫西林药盒 500", "ocr", "zh", "distractor", "dosage",
     "药品名称 阿莫西林胶囊 规格 零点五克 用法 每次一粒 每八小时一次 饭后服用 疗程七天 有效期 二零二七年十一月"),

    # ---- cluster: lease-notice（解约通知期，与 D38/D39/D40 合成 7 篇）
    ("D53", "转租附录 通知期", "extracted", "zh", "distractor", "lease-notice",
     "转租附录 第二条 承租人如需转租，应提前四十五日以书面形式通知出租人，并由出租人对接租人进行资格审核。"
     "本条只适用于转租，不改变提前解约的通知期。"),
    ("D54", "车位租赁 通知期", "extracted", "zh", "distractor", "lease-notice",
     "车位租赁协议 第六条 承租人如需退租车位，应提前十五日书面通知。车位租赁独立于房屋租约，"
     "退租车位不影响房屋租约的通知期。"),
    ("D55", "室友协议 搬离通知", "extracted", "zh", "distractor", "lease-notice",
     "室友协议 第四条 任何一方搬离应提前三十日通知其他室友并结清公共费用。本协议是室友之间的约定，"
     "对房东不产生效力，也不替代租约规定的通知义务。"),

    # ---- 补齐 exact-fact 与 contextual 用得上的几篇独立笔记
    ("T55", "退课截止与流程", "text", "zh", "target", None,
     "老师在课上说，如果要退这门课，必须在第八周结束前先和导师谈一次并拿到签字，然后才能在系统里提交退课申请。"
     "第八周之后退课会在成绩单上留 W。"),
    ("T56", "会议室预订规则", "text", "zh", "target", None,
     "ISEC 六楼小会议室要提前一天在飞书日历上预订，连续占用不能超过两小时。"
     "临时会议可以用四楼开放区，不需要预订。"),
    ("A52", "客服电话 退款进度", "transcript", "zh", "target", None,
     "客服说退款已经在九月十八日发起，原路退回需要三到五个工作日，具体到账时间看发卡行。"
     "如果七个工作日还没到账就把订单号发给他们再查。"),
    ("D56", "健身房合约 转让条款", "extracted", "zh", "target", None,
     "会籍转让 会员可将剩余会籍一次性转让给他人，需双方到店办理并支付五十美元手续费。"
     "转让后原会员不再享有任何权益，剩余月份不退款。"),
    ("L58", "航司改签 同日免费", "link", "en", "target", None,
     "Same-day standby is free for Main Cabin and above on flights between the same city pair. "
     "Confirmed same-day changes cost seventy five dollars unless you hold elite status."),
]

# ---------------------------------------------------------------------------
# 2 · 从 v4 沿用的用例，逐条重新打标
#
# 沿用而不是重写：v4 的 query 本身是按「真人怎么问」写的，质量没有问题，
# 缺的是**分类 / 难度 / 分级相关性 / 硬负例 / split** 这些标注。
#
# 分类是**逐条人工指定**的，不从 `style` 机械推导 —— `style` 说的是措辞形态，
# 与「这条考的是哪一种检索能力」不是一回事（一条 exact 措辞的 query 完全可以
# 考的是近似区分）。
# ---------------------------------------------------------------------------

# (case_id, category, difficulty)
REUSED = [
    # ---- semantic_recall：记得意思、不记得原词 ----
    ("HG002", "semantic_recall", "medium"), ("HG004", "semantic_recall", "medium"),
    ("HG006", "semantic_recall", "easy"),   ("HG008", "semantic_recall", "medium"),
    ("HG018", "semantic_recall", "medium"), ("HG020", "semantic_recall", "medium"),
    ("HG022", "semantic_recall", "medium"), ("HG024", "semantic_recall", "medium"),
    ("HG148", "semantic_recall", "medium"), ("HG040", "semantic_recall", "easy"),
    ("HG041", "semantic_recall", "hard"),   ("HG043", "semantic_recall", "hard"),
    ("HG045", "semantic_recall", "hard"),   ("HG051", "semantic_recall", "hard"),
    ("HG052", "semantic_recall", "hard"),   ("HG053", "semantic_recall", "hard"),
    # 长文的中段 / 末段锚点用例：六篇长语料各要一对，
    # 否则 chunk 策略实验只测得到第一块。
    ("HG047", "semantic_recall", "hard"),   ("HG049", "semantic_recall", "hard"),
    ("HG116", "semantic_recall", "hard"),   ("HG137", "semantic_recall", "hard"),
    ("HV003", "semantic_recall", "medium"), ("HV005", "semantic_recall", "medium"),
    ("HV007", "semantic_recall", "hard"),   ("HV014", "semantic_recall", "medium"),
    ("HV016", "semantic_recall", "medium"), ("HV021", "semantic_recall", "medium"),
    ("HV010", "semantic_recall", "medium"), ("HV030", "semantic_recall", "easy"),
    ("HG140", "semantic_recall", "hard"), ("HV036", "semantic_recall", "medium"),
    ("HV038", "semantic_recall", "medium"), ("HG134", "semantic_recall", "medium"),
    ("HV040", "semantic_recall", "hard"),   ("HV044", "semantic_recall", "medium"),
    ("HG031", "semantic_recall", "medium"),   ("HV046", "semantic_recall", "medium"),
    ("HG146", "semantic_recall", "medium"),   ("HV050", "semantic_recall", "easy"),
    ("HV013", "semantic_recall", "medium"),   ("HV054", "semantic_recall", "medium"),
    ("HV057", "semantic_recall", "medium"), ("HV059", "semantic_recall", "easy"),

    # ---- exact_fact：要准确找到日期 / 金额 / 编号 / 版本号 ----
    ("HG001", "exact_fact", "easy"),  ("HG005", "exact_fact", "easy"),
    ("HG007", "exact_fact", "easy"),  ("HG009", "exact_fact", "easy"),
    ("HG011", "exact_fact", "easy"),  ("HG013", "exact_fact", "easy"),
    ("HG015", "exact_fact", "easy"),  ("HG019", "exact_fact", "easy"),
    ("HG023", "exact_fact", "easy"),  ("HG025", "exact_fact", "medium"),
    ("HG027", "exact_fact", "medium"),("HG033", "exact_fact", "medium"),
    ("HG035", "exact_fact", "medium"),("HG037", "exact_fact", "medium"),
    ("HG039", "exact_fact", "easy"),  ("HG115", "exact_fact", "medium"),
    ("HG120", "exact_fact", "hard"),  ("HG122", "exact_fact", "hard"),
    ("HG123", "exact_fact", "hard"),  ("HG128", "exact_fact", "hard"),
    ("HG132", "exact_fact", "medium"),("HG133", "exact_fact", "medium"),
    ("HG136", "exact_fact", "hard"),  ("HG138", "exact_fact", "hard"),
    ("HG144", "exact_fact", "hard"),  ("HV020", "exact_fact", "medium"),
    ("HG029", "exact_fact", "easy"),  ("HV024", "exact_fact", "easy"),
    ("HV025", "exact_fact", "easy"),  ("HV028", "exact_fact", "medium"),

    # ---- cross_language：中文 query 找英文笔记，或反过来 ----
    ("HG010", "cross_language", "medium"), ("HG012", "cross_language", "medium"),
    ("HV061", "cross_language", "medium"), ("HV062", "cross_language", "medium"),
    ("HV063", "cross_language", "hard"),   ("HV064", "cross_language", "hard"),
    ("HV065", "cross_language", "medium"), ("HV066", "cross_language", "hard"),
    ("HV067", "cross_language", "medium"), ("HV068", "cross_language", "hard"),
    ("HV069", "cross_language", "medium"), ("HV070", "cross_language", "hard"),
    ("HV071", "cross_language", "medium"), ("HV072", "cross_language", "hard"),
    ("HV073", "cross_language", "medium"), ("HV074", "cross_language", "hard"),
    ("HV075", "cross_language", "hard"),   ("HV076", "cross_language", "medium"),
    ("HV077", "cross_language", "medium"), ("HV078", "cross_language", "medium"),
    # 长文末段的跨语言问法（同上，六篇长语料的另一半）
    ("HG044", "cross_language", "hard"),    ("HG046", "cross_language", "hard"),
    ("HG048", "cross_language", "hard"),    ("HG050", "cross_language", "hard"),
    ("HG054", "cross_language", "hard"),
]

# 沿用的负例（10 条）。v4 的 30 条里挑覆盖面最广的十个生活领域。
REUSED_NEGATIVES = ["HN001", "HN002", "HN003", "HN004", "HN005",
                    "HN006", "HN007", "HN008", "HN009", "HN010"]

# 硬负例：沿用用例里那些「同簇 / 同格式 / 同主题」的干扰项。
# 只给中高难度的用例标 —— easy 的那些本来就没有像样的竞争者，
# 硬凑一个反而是在编造「这条容易误判」。
REUSED_HARD_NEGATIVES = {
    "HG116": ["T39", "T40", "T51", "T54"],
    "HG137": ["I44", "I46", "I50", "I51"],
    "HG115": ["T39", "T40", "T53"],
    "HG120": ["I39", "I40"],
    "HG122": ["I42"],
    "HG123": ["A39", "A40", "I54"],
    "HG128": ["D42", "D50", "D43"],
    "HG132": ["L42", "L43"],
    "HG133": ["T45", "T46"],
    "HG136": ["I44", "I46", "I52"],
    "HG138": ["I48", "I49"],
    "HG144": ["D48", "D49"],
    "HV003": ["T31", "T32", "D39"],
    "HV007": ["T33", "A42", "A43"],
    "HV021": ["D42", "D43", "D52"],
    "HV029": ["I32", "I43", "I54"],
    "HV030": ["I21", "I55"],
    "HV036": ["A01", "A06"],
    "HV040": ["A39", "L07"],
    "HV057": ["A02"],
    "HV061": ["T45", "T46"],
    "HV062": ["T48", "T49"],
    "HV063": ["I44", "I46"],
    "HV064": ["I48", "I49"],
    "HV065": ["A45", "A46"],
    "HV066": ["A48", "A49"],
    "HV067": ["D45", "D46"],
    "HV068": ["D48", "D49"],
    "HV069": ["L45", "L46"],
    "HV070": ["L48", "L54"],
    "HV071": ["T42", "T43"],
    "HV072": ["T39", "T40", "T51"],
    "HV073": ["I39", "I40"],
    "HV074": ["A42", "A43"],
    "HV075": ["D39", "D40", "D53"],
    "HV076": ["D42", "D50"],
    "HV077": ["L39", "L40", "L50"],
    "HV078": ["L42", "L43"],
    "HG041": ["A05", "A06"],
    "HG043": ["T12"],
    "HG045": ["T11"],
    # 下面这一批是本轮补的：v4 只标了「同簇」那几条，而任何 medium/hard 的用例
    # 都该说得出「哪一篇容易被误判成答案」—— 说不出就说明它其实是 easy。
    "HG002": ["T22", "L38", "L39"],
    "HG004": ["A06", "A20"],
    "HG008": ["L07", "A38", "I32"],
    "HG018": ["A05", "A06", "A07"],
    "HG020": ["A26", "A27"],
    "HG022": ["A37", "L28"],
    "HG024": ["A28", "T46"],
    "HG025": ["D05", "D24", "D39"],
    "HG027": ["I38", "I39", "I40"],
    "HG031": ["D31", "D47", "D48"],
    "HG033": ["D44", "D46", "L30"],
    "HG035": ["L10", "L20"],
    "HG037": ["L08", "L28", "L46"],
    "HG051": ["D07", "D33"],
    "HG052": ["D07", "D36"],
    "HG053": ["L12", "D11"],
    "HG044": ["T12"], "HG046": ["T11"], "HG047": ["I12"], "HG048": ["I12"],
    "HG049": ["A12"], "HG050": ["A12"], "HG054": ["L12"],
    "HG134": ["T45", "T46"],
    "HG140": ["A45", "A46"],
    "HG146": ["L45", "L46"],
    "HG148": ["L54", "L55"],
    "HV005": ["D06", "I47", "D54"],
    "HV010": ["T21", "T24"],
    "HV013": ["T20", "T23"],
    "HV014": ["T21", "T23", "L01"],
    "HV016": ["T20", "T25"],
    "HV020": ["D09", "D25", "T34"],
    "HV028": ["I44", "I45", "I46"],
    "HG029": ["D10", "D49", "D33"],
    "HV038": ["A24", "A09"],
    "HV044": ["D07", "D10", "D49"],
    "HV046": ["I41", "I42"],
    "HV054": ["L24", "L09"],
}

# 沿用用例的场景补写。没有场景就没法让第二个人复核「这条像不像真人问的」。
REUSED_SCENARIOS = {
    "HG002": "学期中途在想要不要延毕，先翻自己当时记的那次谈话",
    "HG008": "吃了两天药忘了频次，站在药盒前翻笔记",
    "HG020": "牙医打电话来问能不能改期，先确认原来约的是哪天",
    "HG041": "老板在群里问搜索为什么还没上，需要把会议纪要和录音串起来",
    "HG116": "作业快到期了，只记得交付物文件名",
    "HG137": "打印机没墨了要下单，两个型号分不清哪个更耐用",
    "HV007": "退租一个月了押金还没到账，想确认应该等多久",
    "HV021": "填报销单时不确定住宿超了没有",
    "HV040": "感冒好了一半，想知道能不能停药",
    "HV057": "补牙那天临时有事，先确认改期后是哪天",
}

# ---------------------------------------------------------------------------
# 3 · 新增用例
#
# 五类此前完全没有覆盖的能力：词面陷阱 · 近似区分 · 噪声 query · 场景回忆 · 歧义。
#
# 每条的字段：
#   id · query · lang · targets{noteID: 相关度 0–3} · hard[] · cat · diff
#   scenario（用户处境）· behavior（期望的产品行为）· why（这条为什么值得测）
#
# `targets` 里 ≥2 的进 binary 相关集；1 分是「部分相关」，既不算命中也不算错误。
# ---------------------------------------------------------------------------

def C(id, query, lang, targets, cat, diff, scenario, behavior, why, hard=()):
    return dict(id=id, query=query, lang=lang, targets=targets, hard=list(hard),
                cat=cat, diff=diff, scenario=scenario, behavior=behavior, why=why)


NEW_CASES = [
    # ======================= near_duplicate（30）=======================
    # 目标笔记住在一个 6–8 篇的同构簇里，同簇其它篇都是合理的干扰项。
    # 这一类考的是**排序区分度**，不是召回。
    C("ND01", "期末那个项目最多几个人一组", "zh", {"T54": 3}, "near_duplicate", "hard",
      "要找人组队做期末项目，先确认人数上限",
      "返回期末项目提交那一条，而不是别的周作业",
      "同一门课七次作业格式几乎一样，只有组队规则不同",
      hard=["T38", "T51", "T52", "T53"]),
    C("ND02", "提案那一页什么时候交", "zh", {"T53": 3}, "near_duplicate", "hard",
      "期末项目提案和项目本身是两个截止时间，容易混",
      "返回提案那一条（十一月七日），不是十二月十九日的项目",
      "同簇里有两个截止日期，问的是前一个",
      hard=["T54", "T38", "T52"]),
    C("ND03", "哪一次作业不算分", "zh", {"T50": 3}, "near_duplicate", "medium",
      "学期末算成绩，想确认哪次可以不管",
      "返回第一周那条（不计入总成绩）",
      "七次作业只有一次不计分，其余格式完全相同",
      hard=["T39", "T51", "T52"]),
    C("ND04", "现在执行的是第几版报销政策，餐费上限多少", "zh", {"D41": 3}, "near_duplicate", "hard",
      "提交报销单前确认现行标准",
      "返回第二版（一百二十美元），不是第一版也不是草案",
      "同一份政策有三个版本 + 两份周边文档，只有一个是现行",
      hard=["D42", "D50", "D51", "D43"]),
    C("ND05", "听说餐费上限要涨到一百五，是已经生效了吗", "zh", {"D50": 3}, "near_duplicate", "hard",
      "同事说上限涨了，想确认是不是真的",
      "返回第三版草案那条，它明确写着尚未生效",
      "用户带着一个**错误前提**来问；正确答案是那份草案本身",
      hard=["D41", "D42"]),
    C("ND06", "团建的钱和出差吃饭的额度是一起算的吗", "zh", {"D52": 3}, "near_duplicate", "medium",
      "组里聚餐前确认走哪个口子",
      "返回团建费用政策，它明说与差旅餐饮分开计算",
      "两份政策都写「上限」和「每人」，区别在适用范围",
      hard=["D41", "D51"]),
    C("ND07", "延期到底批了没有", "zh", {"L38": 3}, "near_duplicate", "hard",
      "等了两周还没消息，想确认最新状态",
      "返回「已经批准」那封，不是补材料或审核中",
      "七封同主题邮件，标题一模一样，只有结论不同",
      hard=["L39", "L50", "L51", "L53"]),
    C("ND08", "去面谈那次要带什么材料", "zh", {"L51": 3}, "near_duplicate", "medium",
      "第二天要去国际学生办公室",
      "返回预约面谈那封（护照 / I-20 / 资助证明）",
      "同簇里另外几封也提到材料，但不是面谈要带的",
      hard=["L38", "L39", "L52"]),
    C("ND09", "延期申请最晚什么时候交", "zh", {"L52": 3}, "near_duplicate", "hard",
      "还没准备好材料，想知道能拖到什么时候",
      "返回提醒截止那封（结束日期前三十天）",
      "同簇七封里只有一封写了时限",
      hard=["L38", "L50", "L51", "L53"]),
    C("ND10", "五百毫克那盒是几小时吃一次", "zh", {"I55": 3}, "near_duplicate", "hard",
      "家里两盒阿莫西林规格不同，拿错了会吃错",
      "返回 0.5 克那盒的标签（每八小时一次）",
      "两张药盒 OCR 格式相同，只有规格与频次不同",
      hard=["I54", "I43", "A39"]),
    C("ND11", "换成大剂量那盒之后疗程是几天", "zh", {"I54": 3}, "near_duplicate", "hard",
      "医生改了方案，要确认还要吃几天",
      "返回 0.875 克那盒（五天）",
      "同一种药两个规格，疗程也不同",
      hard=["I55", "A38", "A50"]),
    C("ND12", "转租要提前多少天通知房东", "zh", {"D53": 3}, "near_duplicate", "hard",
      "想把房子转租出去，先看合同",
      "返回转租附录（四十五日），不是提前解约的通知期",
      "同簇五份文件都写「提前 N 日书面通知」，适用情形各不相同",
      hard=["D38", "D39", "D54", "D55"]),

    C("ND13", "which tour is on Sunday morning", "en", {"L54": 3}, "near_duplicate", "hard",
      "Booked several viewings in one weekend and lost track",
      "Return the Unit 7C confirmation, not the Saturday ones",
      "Seven near-identical leasing emails differing only in unit, day and time",
      hard=["L47", "L48", "L55", "L57"]),
    C("ND14", "did my Saturday morning tour get moved", "en", {"L55": 3}, "near_duplicate", "hard",
      "Not sure whether to show up at 11 or 3",
      "Return the reschedule notice, not the original confirmation",
      "A reschedule that supersedes an earlier message in the same cluster",
      hard=["L47", "L57", "L49"]),
    C("ND15", "why was my tour cancelled", "en", {"L57": 3}, "near_duplicate", "medium",
      "Got a cancellation and wants the reason",
      "Return the cancellation notice (unit was leased)",
      "Cancellation vs reschedule vs waitlist all live in the same cluster",
      hard=["L55", "L49", "L56"]),
    C("ND16", "how long does the application screening take", "en", {"L56": 3}, "near_duplicate", "medium",
      "Applied and is waiting to hear back",
      "Return the application-received email (two to three business days)",
      "Only one of the seven mentions screening time",
      hard=["L49", "L57", "L47"]),
    C("ND17", "does the 76 series have a high yield version", "en", {"I51": 3}, "near_duplicate", "hard",
      "Comparing cartridges before ordering",
      "Return the CF276X label",
      "Four labels differ by two characters; yield is the only distinguishing field",
      hard=["I50", "I45", "I52"]),
    C("ND18", "the cheaper third party cartridge, does it need anything special", "en", {"I52": 3},
      "near_duplicate", "hard",
      "Tempted by a cheap compatible cartridge",
      "Return the remanufactured label (chip may require firmware downgrade)",
      "Only the remanufactured one carries the firmware caveat",
      hard=["I45", "I51", "I44"]),
    C("ND19", "which part lasts 30000 pages", "en", {"I53": 3}, "near_duplicate", "medium",
      "Printer says replace something, unsure what",
      "Return the drum unit label, not a toner",
      "Same brand, same printer model, same label layout — different part entirely",
      hard=["I45", "I51", "I50"]),
    C("ND20", "can I put a 76 cartridge in place of a 59", "en", {"I50": 3}, "near_duplicate", "hard",
      "Has the wrong cartridge in hand and wonders if it fits",
      "Return the CF276A label, which states it is not interchangeable with the 59 series",
      "The answer is a negative statement buried in a near-identical label",
      hard=["I46", "I44", "I45"]),
    C("ND21", "which room is the midterm in now", "en", {"T44": 3}, "near_duplicate", "hard",
      "Two notices in the inbox, one supersedes the other",
      "Return the rescheduled notice (Snell 108)",
      "Original vs rescheduled vs final, all same course",
      hard=["T45", "T46"]),
    C("ND22", "how many cheat sheets for the final", "en", {"T46": 3}, "near_duplicate", "medium",
      "Packing for the exam",
      "Return the final exam notice (two double-sided sheets)",
      "Midterm allows one, final allows two — same wording otherwise",
      hard=["T44", "T45"]),
    C("ND23", "when can I drop in on the TA this week", "en", {"T47": 3}, "near_duplicate", "medium",
      "Wants help without booking anything",
      "Return the moved TA hours (Thursday 2pm, walk-in)",
      "TA original vs TA moved vs professor (appointment only)",
      hard=["T48", "T49"]),
    C("ND24", "do I need an appointment for the professor", "en", {"T49": 3}, "near_duplicate", "medium",
      "About to walk over to ISEC",
      "Return the professor's hours (by appointment, email a day ahead)",
      "Three office-hour notes; only one requires an appointment",
      hard=["T47", "T48"]),
    C("ND25", "how long before the defense does the committee need the full draft", "en", {"A44": 3},
      "near_duplicate", "hard",
      "Planning backwards from the defense date",
      "Return the thesis defense call (six weeks), not the proposal one",
      "Thesis vs proposal vs another student's — the six-week rule appears in two of them",
      hard=["A45", "A46", "A33"]),
    C("ND26", "what does the committee need for the proposal", "en", {"A45": 3}, "near_duplicate", "hard",
      "Proposal is closer than the defense",
      "Return the proposal call (ten page outline)",
      "Same speaker, same topic, different milestone",
      hard=["A44", "A46"]),
    C("ND27", "what is my new program end date", "en", {"D44": 3}, "near_duplicate", "medium",
      "Filling in a form that asks for the current end date",
      "Return the approved extension (2027-05-15)",
      "Approved vs pending vs initial issuance, same document type",
      hard=["D45", "D46"]),
    C("ND28", "when did my current I-20 originally start", "en", {"D46": 3}, "near_duplicate", "hard",
      "A form asks for the original program start, not the extension",
      "Return the initial issuance (2024-09-04)",
      "Three I-20 documents; the extension ones do not carry the original start date",
      hard=["D44", "D45"]),
    C("ND29", "was the signing bonus paid at once or split", "en", {"D48": 3}, "near_duplicate", "hard",
      "Two offer letters in the folder, one revised",
      "Return the revised offer (two equal installments)",
      "Same salary, same layout, only the bonus terms differ",
      hard=["D47", "D49"]),
    C("ND30", "if I move my Main Cabin flight do I still pay the fare difference", "en", {"L44": 3},
      "near_duplicate", "medium",
      "Wants to change a flight and is checking the cost",
      "Return the Main Cabin change policy (no change fee, fare difference applies)",
      "Change policy vs baggage policy vs Basic Economy — all airline fine print",
      hard=["L45", "L46", "L58"]),
]

NEW_CASES += [
    # ======================= lexical_trap（30）=======================
    # query 的用词与**错误**笔记重合更多，正确笔记要靠语义找到。
    # 这是 hybrid 检索最该被验证的一类：纯 keyword 会稳定选错。
    C("LT01", "会议里说搜索这周不上线，那到底哪天发", "zh", {"A01": 3}, "lexical_trap", "hard",
      "记得开会说过，但不记得是哪个会",
      "返回产品例会那条（周五发内部 TestFlight）",
      "另外两段录音里「搜索 / 会议 / 版本 / 日期」词面命中更多，但都明说没讨论这件事",
      hard=["A05", "A06", "A07"]),
    C("LT02", "感冒那次开的药一天吃几次", "zh", {"T04": 3}, "lexical_trap", "medium",
      "药盒扔了，只记得是感冒时开的",
      "返回看诊记录（每天三次，饭后）",
      "感冒饮食建议那篇「感冒」出现更多，却明说不含处方药剂量",
      hard=["L07", "I21", "A32"]),
    C("LT03", "在学校停车怎么收费", "zh", {"I22": 3}, "lexical_trap", "medium",
      "开车去学校，不知道要交多少",
      "返回南门访客停车牌（每小时 3 元，上限 20 元）",
      "校园停车证规则的「学校 / 停车」词面更密，但它讲的是许可证不是收费",
      hard=["D06", "I05", "I47"]),
    C("LT04", "实习那份合同里说做出来的东西版权算谁的", "zh", {"D33": 3}, "lexical_trap", "medium",
      "实习快结束，想把项目放进作品集",
      "返回实习协议（著作权归公司）",
      "研究助理合同同样写「每周 / 工作 / 合同」，但没有著作权条款",
      hard=["D07", "D10", "D49"]),
    C("LT05", "押金退还有没有时间要求", "zh", {"D23": 3}, "lexical_trap", "medium",
      "准备退租，先看合同怎么写",
      "返回租约的押金退还条款（三十日，逾期双倍）",
      "共享单车押金那条「押金 / 退还 / 工作日」几乎全中，却和租房无关",
      hard=["T33", "A43", "D25"]),
    C("LT06", "车险一年要交多少钱", "zh", {"I38": 3}, "lexical_trap", "medium",
      "算年度开支",
      "返回车险保单（年保费一千二百美元）",
      "道路救援附加条款也写「每年 / 美元 / 车」，但那是附加险的价格",
      hard=["D28", "I39", "I40"]),
    C("LT07", "选课那天系统维护到几点", "zh", {"L41": 3}, "lexical_trap", "hard",
      "怕维护耽误抢课",
      "返回春季选课通知（开放前十分钟维护）",
      "图书馆闭馆通知同样是十一月十日 + 系统维护，且明说不是同一件事",
      hard=["L43", "L42"]),
    C("LT08", "上周会上定的那三个槽位是什么", "zh", {"A22": 3}, "lexical_trap", "medium",
      "要照着定稿改实现",
      "返回设计评审录音（标题 / 命中片段 / 文件夹和时间）",
      "周会杂项同步那条「周会 / 本周」词面更近，但明说没有工程议题",
      hard=["A24", "A05", "A09"]),
    C("LT09", "差旅政策里餐费能报多少", "zh", {"D41": 3}, "lexical_trap", "hard",
      "填报销单",
      "返回报销政策第二版（一百二十美元）",
      "差旅预订政策标题里就有「差旅政策」，却明说不涉及餐饮上限",
      hard=["D43", "D42", "D50"]),
    C("LT10", "押金什么时候退，扣多少", "zh", {"A41": 3}, "lexical_trap", "hard",
      "刚退租，等钱回来",
      "返回今年那通房东电话（二十一天，扣一百五十美元清洁费）",
      "中介电话同样满是「押金 / 一个月 / 房租」，但讲的是签约时交押金",
      hard=["A43", "A42", "T33"]),
    C("LT11", "我们组的组会在周几开", "zh", {"T41": 3}, "lexical_trap", "medium",
      "新学期第一周，不确定时间有没有变",
      "返回改期通知（周四）",
      "视觉组的周会那条格式相同、词面更全，但明说和我们组无关",
      hard=["T43", "T42", "T56"]),
    C("LT12", "装修能在周末做吗", "zh", {"D36": 3}, "lexical_trap", "medium",
      "工人问周末能不能开工",
      "返回物业管理规约（周末禁止噪音作业）",
      "装修报价单的「装修 / 工期 / 工作日」更密，但它只讲价格与工期",
      hard=["D34", "D08", "L05"]),

    C("LT13", "moving day, when do I get the keys", "en", {"T03": 3}, "lexical_trap", "medium",
      "Movers are booked and the handover time is still unclear",
      "Return the two-week moving checklist (September 3 at 10:00 AM)",
      "The moving-day meal plan and the packing guide share more surface words but hold no handover time",
      hard=["T07", "T05", "L05"]),
    C("LT14", "on the cheapest United fare can I bring a carry-on", "en", {"L03": 3}, "lexical_trap", "hard",
      "About to book the cheapest ticket and worried about bags",
      "Return the Basic Economy rules (one carry-on and one personal item)",
      "The checked-bag comparison explicitly says it does not cover Basic Economy carry-on eligibility",
      hard=["L08", "L28", "L46"]),
    C("LT15", "before making a property required what should I do first", "en", {"L09": 3},
      "lexical_trap", "hard",
      "Adding a field to the model and afraid of breaking the store",
      "Return the SwiftData migration guide (add optional first)",
      "The CloudKit tutorial and the versioned-schema guide both talk about models and stores",
      hard=["L04", "L24", "A21"]),
    C("LT16", "written notice before moving out", "en", {"D01": 3}, "lexical_trap", "hard",
      "Deciding whether to renew, needs the notice window",
      "Return the current lease (30 calendar days)",
      "Three other lease documents use nearly identical wording with different numbers",
      hard=["D05", "D24", "D21", "D39"]),
    C("LT17", "what is my deductible before the plan starts paying", "en", {"D26": 3},
      "lexical_trap", "hard",
      "Deciding whether to see a doctor now or wait",
      "Return the health plan deductible ($1,250 in-network)",
      "Renters, dental, car and the student plan all contain the word deductible with different numbers",
      hard=["D09", "D25", "T34", "I38"]),
    C("LT18", "are teeth cleanings covered and is there a deductible", "en", {"T34": 3},
      "lexical_trap", "medium",
      "Booking a cleaning and checking the cost",
      "Return the dental plan summary (twice a year, no deductible)",
      "The health plan summary says dental cleanings are NOT included — a strong lexical match, wrong answer",
      hard=["D09", "D26"]),
    C("LT19", "how much of the stock is mine after the first year", "en", {"D30": 3},
      "lexical_trap", "medium",
      "One year into the job, checking the cliff",
      "Return the equity vesting clause (25% at the first anniversary)",
      "The non-compete and both offer letters share employment vocabulary but no vesting schedule",
      hard=["D29", "D47", "D48"]),
    C("LT20", "why does the index have to be rebuilt from scratch every launch", "en", {"A21": 3},
      "lexical_trap", "hard",
      "Debugging slow cold starts",
      "Return the infra sync (the store is memory-only)",
      "The flaky-test standup is also about CI and rebuilds, and shares more surface words",
      hard=["A25", "A09", "L09"]),
    C("LT21", "how long can I park near the office on a weekday", "en", {"I23": 3},
      "lexical_trap", "medium",
      "Driving in for a meeting",
      "Return the street sign near the office (2 hour parking, 9AM–6PM)",
      "Two campus permits and a street-cleaning sign match parking vocabulary more densely",
      hard=["I02", "I47", "I48", "I10"]),
    C("LT22", "is chapter three on the final", "en", {"A04": 3}, "lexical_trap", "medium",
      "Deciding what to skip while revising",
      "Return the data structures lecture, which states the covered chapters",
      "The graph-algorithms lecture and the CS7180 final notice both talk about exams and chapters",
      hard=["A28", "T46", "T44"]),
    C("LT23", "which parts of a rental agreement should I read first", "en", {"L32": 3},
      "lexical_trap", "medium",
      "First time signing a lease",
      "Return the how-to-read-a-lease guide (three clauses)",
      "The actual lease documents contain far more lease vocabulary but are not advice",
      hard=["D01", "D05", "D21"]),
    C("LT24", "how long before the internship do I file the paperwork", "en", {"D03": 3},
      "lexical_trap", "hard",
      "Got an internship offer and needs work authorisation",
      "Return the international student handbook (CPT, 15 business days)",
      "Both internship offers mention start dates and paperwork but not the filing window",
      hard=["D10", "D49", "D33"]),
    C("LT25", "should I start from a leaderboard or a user task", "en", {"L11": 3},
      "lexical_trap", "medium",
      "Setting up an evaluation and unsure where to start",
      "Return the retrieval evaluation guide",
      "The vector database comparison is denser in retrieval vocabulary and answers a different question",
      hard=["L12", "L09", "A11"]),
    C("LT26", "when is a model score actually useful", "en", {"A11": 3}, "lexical_trap", "hard",
      "Writing up why an offline number did not convince anyone",
      "Return the trustworthy AI guest lecture",
      "The design critique and career fair recordings share meeting vocabulary; the answer is a claim, not a keyword",
      hard=["A09", "A12", "L11"]),
    C("LT27", "how many remote days does the offer allow", "en", {"D04": 3}, "lexical_trap", "hard",
      "Comparing two offers before deciding",
      "Return the accepted offer letter (three days per week)",
      "The other company's offer letter has the same layout and a different number",
      hard=["D31", "D47", "D48"]),
    C("LT28", "how many times a day and for how many days", "en", {"I32": 3}, "lexical_trap", "medium",
      "Holding the bottle, can't read the small print",
      "Return the prescription label (three times daily, 7 days)",
      "Three Chinese medicine labels share the dosage pattern; the query is in English",
      hard=["I43", "I55", "I54"]),
    C("LT29", "if a pipe bursts is that covered", "en", {"D25": 3}, "lexical_trap", "medium",
      "Upstairs neighbour flooded the bathroom",
      "Return the renters insurance policy (water damage from plumbing failure)",
      "Travel and health policies match insurance vocabulary but not this peril",
      hard=["D12", "D26", "D09"]),
    C("LT30", "do I need to skip breakfast before the appointment", "en", {"A27": 3},
      "lexical_trap", "medium",
      "Appointment is tomorrow morning",
      "Return the clinic voicemail (fast beforehand)",
      "The pharmacy voicemail and two Chinese appointment reminders match appointment vocabulary",
      hard=["A08", "A02", "A26"]),
]

NEW_CASES += [
    # ======================= noisy_query（20）=======================
    # 错别字 · 缩写 · 口语 · 实体记错一半 · 没有标点。
    # 真人在手机上打字就是这样，评测集里全是工整 query 会高估线上表现。
    C("NQ01", "roialign 那个作业几号截至", "zh", {"T38": 3}, "noisy_query", "hard",
      "赶作业，随手在手机上打",
      "「截至」是错别字，仍应返回第七周作业",
      "错别字 + 只记得交付物文件名",
      hard=["T39", "T40", "T51"]),
    C("NQ02", "洗牙那个预约是8月几号来着 27还是28", "zh", {"A02": 3}, "noisy_query", "medium",
      "同事约了同一天，想确认自己是哪天",
      "返回牙医语音留言（8月27日）",
      "自问自答式的口语，且候选日期给错了一个",
      hard=["A26", "A27"]),
    C("NQ03", "餐补上限是120还是150 我记不清了", "zh", {"D41": 3}, "noisy_query", "hard",
      "报销卡在财务那边",
      "返回现行第二版（120），而不是那份写着 150 的草案",
      "用户把草案里的数字记成了现行值 —— 噪声来自记忆而不是拼写",
      hard=["D50", "D42"]),
    C("NQ04", "南门停车费 一小时几块 上限多少", "zh", {"I22": 3}, "noisy_query", "easy",
      "车已经开到门口了",
      "返回南门停车牌",
      "电报式短语，没有完整句子",
      hard=["I05", "D06"]),
    C("NQ05", "去日本旅游 免签能呆多久", "zh", {"L23": 3}, "noisy_query", "easy",
      "订机票前确认能待几天",
      "「呆」是「待」的常见错字，仍应返回日本入境规则",
      "高频错别字",
      hard=["L01", "L30"]),
    C("NQ06", "apikey 轮换 步奏", "zh", {"T29": 3}, "noisy_query", "medium",
      "值班时要换 key，凭记忆搜",
      "「步奏」是「步骤」的错字；应返回轮换手册",
      "英文缩写连写 + 中文错别字同时出现",
      hard=["L04", "T35"]),
    C("NQ07", "水笼头 哪天修", "zh", {"A30": 3}, "noisy_query", "easy",
      "要请假在家等师傅",
      "「水笼头」是错字，应返回和房东的通话",
      "错别字 + 极短 query",
      hard=["T10", "A43"]),
    C("NQ08", "厨房翻新 报价 台面多少钱来着", "zh", {"D34": 3}, "noisy_query", "medium",
      "和家人对预算",
      "返回装修报价单（台面九千）",
      "口语尾缀「来着」，且只问其中一项",
      hard=["D36", "T35"]),
    C("NQ09", "wheres the midterm now, snell or richards", "en", {"T44": 3}, "noisy_query", "hard",
      "Walking to campus and unsure which building",
      "Return the rescheduled notice (Snell 108)",
      "No apostrophe, lowercase, and the query offers both candidate rooms",
      hard=["T45", "T46"]),
    C("NQ10", "wifi pw for the guest network", "en", {"I03": 3}, "noisy_query", "easy",
      "A friend is asking for the Wi-Fi",
      "Return the router label",
      "Abbreviation pw for password",
      hard=["L29", "I24"]),
    C("NQ11", "whats my ded again for in network", "en", {"D26": 3}, "noisy_query", "medium",
      "On the phone with a clinic",
      "Return the health plan deductible",
      "ded is a colloquial shortening of deductible",
      hard=["D25", "T34", "D09"]),
    C("NQ12", "can i chnage my main cabin flight w/o fee", "en", {"L44": 3}, "noisy_query", "medium",
      "Typing fast on a phone at the gate",
      "Return the Main Cabin change policy",
      "Transposed letters plus w/o shorthand",
      hard=["L45", "L46"]),
    C("NQ13", "meal reimburstment cap now?", "en", {"A47": 3}, "noisy_query", "medium",
      "Filing an expense report",
      "Return the HR call with the new cap",
      "Misspelling plus the word now doing the work of superseded",
      hard=["A48", "A49", "D41"]),
    C("NQ14", "equity cliff 1 yr how much vests", "en", {"D30": 3}, "noisy_query", "medium",
      "Approaching the first anniversary",
      "Return the equity vesting clause",
      "Telegraphic, digits instead of words",
      hard=["D29", "D47"]),
    C("NQ15", "parking permit zone b whcih garage", "en", {"I47": 3}, "noisy_query", "medium",
      "Driving in with a new permit",
      "Return the Zone B permit (Renaissance Garage)",
      "Transposed letters in which",
      hard=["I48", "I49"]),
    C("NQ16", "united basic econ carry on allowed?", "en", {"L03": 3}, "noisy_query", "easy",
      "At the check-in counter",
      "Return the Basic Economy rules",
      "econ abbreviation and missing hyphen",
      hard=["L08", "L28"]),
    C("NQ17", "ta OH moved to thurs?", "en", {"T47": 3}, "noisy_query", "hard",
      "Wants to go today and is not sure it is still Tuesday",
      "Return the moved TA office hours",
      "OH is an in-group abbreviation for office hours; thurs is truncated",
      hard=["T48", "T49"]),
    C("NQ18", "cpt how many bus days b4 start", "en", {"D03": 3}, "noisy_query", "hard",
      "Internship starts soon and paperwork is late",
      "Return the international student handbook",
      "b4 for before, bus days for business days",
      hard=["D10", "D49"]),
    C("NQ19", "ds final chapters covered", "en", {"A04": 3}, "noisy_query", "medium",
      "Two days before the exam",
      "Return the data structures lecture",
      "ds is a course abbreviation that collides with nothing in the corpus",
      hard=["A28", "T46"]),
    C("NQ20", "printer serial vnb3k something", "en", {"I24": 3}, "noisy_query", "hard",
      "Filing a warranty claim and only remembers part of the serial",
      "Return the printer label with serial VNB3K21099",
      "Partial entity — the user remembers a prefix and gives up",
      hard=["I47", "I25", "I45"]),

    # ======================= contextual_recall（10）=======================
    # 只记得「上次谁说过什么场景」，没有任何可检索的关键词。
    C("CR01", "上次老师说那个不能退课之前要先做什么", "zh", {"T55": 3}, "contextual_recall", "hard",
      "临近退课截止，只记得老师提过一句",
      "返回退课截止与流程（先和导师谈并拿签字）",
      "query 里没有一个词与答案原文重合，全靠语义",
      hard=["T41", "T22", "T56"]),
    C("CR02", "上次说小会议室是不是要提前订", "zh", {"T56": 3}, "contextual_recall", "medium",
      "临时要开会，想知道能不能直接用",
      "返回会议室预订规则",
      "「上次说」是典型的模糊指代开头",
      hard=["T41", "I29"]),
    C("CR03", "上次打电话问退款，他们说大概几天到账", "zh", {"A52": 3}, "contextual_recall", "medium",
      "钱还没到，想确认是不是该催了",
      "返回客服通话（三到五个工作日）",
      "记得场景（打过电话），不记得任何具体词",
      hard=["I01", "I28", "T33"]),
    C("CR04", "健身房那个卡好像能转给别人，当时说要交手续费", "zh", {"D56": 3}, "contextual_recall", "medium",
      "不想去了，想把卡转手",
      "返回会籍转让条款（五十美元手续费）",
      "用户凭印象描述，措辞与条款原文不同",
      hard=["T32", "D08"]),
    C("CR05", "上次房东说修东西那天是不是要有人在家", "zh", {"A30": 3}, "contextual_recall", "medium",
      "在安排请假",
      "返回和房东的通话",
      "问的是一个附带条件，不是主要事实",
      hard=["T10", "A41", "A43"]),
    C("CR06", "上次说组会改时间是因为导师有别的事，改到哪天了", "zh", {"T41": 3},
      "contextual_recall", "medium",
      "要不要请假取决于是周三还是周四",
      "返回组会改期通知",
      "把原因当线索来找结论",
      hard=["T42", "T43"]),
    C("CR07", "someone told me standby is free on my fare, was that right", "en", {"L58": 3},
      "contextual_recall", "medium",
      "At the airport hoping to get on an earlier flight",
      "Return the same-day standby policy",
      "The user recalls a claim, not any wording from the note",
      hard=["L44", "L45", "L46"]),
    C("CR08", "in that infra sync someone said the store being memory only was the blocker, what were we changing",
      "en", {"A21": 3}, "contextual_recall", "hard",
      "Writing the sprint summary from memory",
      "Return the infra sync recording",
      "The user paraphrases the blocker and asks for the decision attached to it",
      hard=["A25", "A09", "L09"]),
    C("CR09", "the leasing office mentioned a notice period when I signed, how long was it", "en",
      {"D01": 3}, "contextual_recall", "hard",
      "Considering moving out and cannot find the paperwork",
      "Return the current lease termination clause",
      "Four lease documents give different notice periods; only the context identifies the right one",
      hard=["D05", "D24", "D39", "A10"]),
    C("CR10", "the guest speaker said a score alone means nothing without something, what was it", "en",
      {"A11": 3}, "contextual_recall", "hard",
      "Quoting the lecture in a write-up",
      "Return the trustworthy AI guest lecture",
      "The user remembers the shape of a claim but none of its words",
      hard=["L11", "A09", "A12"]),
]

NEW_CASES += [
    # ======================= ambiguous（10）=======================
    # 存在两个都合理的候选。**不强行制造唯一答案** —— 标注里两个都给 ≥2 分，
    # 于是 Recall 的口径（全部 expected 都要在 Top K）会要求系统把两个都召回。
    #
    # 这是刻意的严格：面对一条歧义 query，只返回其中一个而漏掉另一个，
    # 对用户来说就是一次「没找到」。
    C("AM01", "押金多久退", "zh", {"A41": 3, "D23": 3}, "ambiguous", "hard",
      "刚退租，既有合同也有和房东的通话",
      "合同条款（三十日）与房东电话（二十一天）都该出现，由用户自己判断以哪个为准",
      "两个来源给的期限不同且都成立 —— 系统不该替用户选一个",
      hard=["A42", "A43", "T33"]),
    C("AM02", "提前解约要提前多久通知", "zh", {"D38": 3, "D39": 2}, "ambiguous", "hard",
      "想提前搬走，手上有原租约和一份续租附录",
      "附录（三十日）与原租约（六十日）都该出现；附录声明冲突时以它为准",
      "「哪个有效」是法律判断，检索该做的是把冲突摆出来",
      hard=["D40", "D53", "T31"]),
    # D26 给 3 分：不带限定词的「my deductible」最常见的所指是医疗保险；
    # 租客险同样成立，所以给 2 分而不是 0 —— 两个都要召回，但主次不同。
    C("AM03", "what is my deductible", "en", {"D26": 3, "D25": 2}, "ambiguous", "hard",
      "Filling in a form that just says deductible",
      "Both the health plan and the renters policy should surface",
      "The query does not say which policy; picking one silently would be a guess",
      hard=["D09", "T34", "I38"]),
    C("AM04", "阿莫西林要怎么吃", "zh", {"A38": 3, "A39": 3}, "ambiguous", "hard",
      "手里两盒规格不同，医生前后说过两次",
      "初诊方案与复诊调整都该出现",
      "没有时间线索时，两个方案都成立",
      hard=["A40", "I54", "I55"]),
    C("AM05", "office hours on Thursday", "en", {"T47": 3, "T49": 3}, "ambiguous", "medium",
      "Thursday afternoon, wants to talk to someone",
      "Both the TA slot and the professor slot should surface",
      "Two different people hold Thursday hours; the query does not say which",
      hard=["T48"]),
    C("AM06", "what is the signing bonus", "en", {"D48": 3, "D47": 2}, "ambiguous", "hard",
      "Comparing the original and the revised offer",
      "Both offers should surface; the revised one supersedes",
      "Without the word revised there is no way to pick one from the query alone",
      hard=["D49", "D31"]),
    C("AM07", "选课什么时候开始", "zh", {"L41": 3, "L42": 3}, "ambiguous", "medium",
      "学期中间随手一搜",
      "春季与秋季两份通知都该出现",
      "query 没有说是哪个学期",
      hard=["L43"]),
    C("AM08", "where can I park with my permit", "en", {"I47": 3, "I48": 3}, "ambiguous", "medium",
      "Has held two permits on the same vehicle",
      "Both Zone A and Zone B permits should surface",
      "Same vehicle, two zones, two garages — the query does not disambiguate",
      hard=["I49", "I23"]),
    C("AM09", "when is my apartment tour", "en", {"L47": 3, "L48": 3}, "ambiguous", "medium",
      "Two viewings booked on the same Saturday",
      "Both confirmations should surface",
      "Both are equally valid answers to the question as asked",
      hard=["L54", "L55", "L57"]),
    C("AM10", "报销上限是多少", "zh", {"D41": 3, "T35": 3}, "ambiguous", "hard",
      "出差回来一次性报餐费和住宿",
      "餐饮上限（一百二十美元）与住宿上限（一百八十美元）都该出现",
      "「报销上限」本身涵盖两个不同科目",
      hard=["D42", "D52", "D43"]),
]

# ---------------------------------------------------------------------------
# 4 · 构建
# ---------------------------------------------------------------------------

CATEGORY_TARGET = {
    "semantic_recall": 0.20, "exact_fact": 0.15, "lexical_trap": 0.15,
    "near_duplicate": 0.15, "cross_language": 0.10, "noisy_query": 0.10,
    "contextual_recall": 0.05, "negative": 0.05, "ambiguous": 0.05,
}


def landing_target(note):
    """期望落点：录音命中要先展开转写，其余定位到块（SEARCH_CONTRACT §3.2）。"""
    return ("transcript:" if note["source"] == "transcript" else "block:") + note["id"] + "-block"


def assign_splits(items, key):
    """按类别分层的 70 / 30 划分。

    **确定性**：按 case id 排序后每 10 条取 3 条进 holdout。不用随机数 ——
    随机划分每次重跑都换一批，`holdout` 就没有「冻结」可言了。
    """
    out = {}
    by_cat = collections.defaultdict(list)
    for it in items:
        by_cat[key(it)].append(it)
    for cat, group in by_cat.items():
        for i, it in enumerate(sorted(group, key=lambda x: x["id"])):
            out[it["id"]] = "holdout" if i % 10 in (0, 4, 7) else "development"
    return out


def build():
    base = json.load(open(BASE, encoding="utf-8"))
    notes = {n["id"]: dict(n) for n in base["notes"]}

    # ---- 新增笔记 ----
    for nid, title, source, lang, role, cluster, content in NEW_NOTES:
        assert nid not in notes, f"note id 冲突：{nid}"
        notes[nid] = {"id": nid, "title": title, "source": source, "language": lang,
                      "role": role, "content": content, "cluster": cluster,
                      "middleMarker": None, "endMarker": None}

    # ---- 已有笔记补 cluster 标记（v4 的 3 篇簇与新增的合并成 6–8 篇）----
    existing_clusters = {
        "cs5330-hw": ["T38", "T39", "T40"],
        "reimbursement": ["D41", "D42", "D43", "A47", "A48", "A49"],
        "extension-email": ["L38", "L39", "L40", "D44", "D45", "D46"],
        "toner": ["I44", "I45", "I46"],
        "apartment-tour": ["L47", "L48", "L49"],
        "dosage": ["A38", "A39", "A40", "I43"],
        "lease-notice": ["D38", "D39", "D40"],
        "exam-schedule": ["T44", "T45", "T46", "T47", "T48", "T49"],
        "insurance-deductible": ["I38", "I39", "I40", "D25", "D26", "D09", "T34"],
        "lease-clause": ["D01", "D05", "D20", "D21", "D22", "D23", "D24"],
        "offer-letter": ["D47", "D48", "D49", "D04", "D31"],
        "defense-schedule": ["A44", "A45", "A46"],
        "flight-policy": ["L44", "L45", "L46", "L03", "L58"],
        "group-meeting": ["T41", "T42", "T43"],
        "parking-permit": ["I47", "I48", "I49"],
        "course-registration": ["L41", "L42", "L43"],
        "checkup-report": ["I41", "I42"],
        "deposit-return": ["A41", "A42", "A43"],
    }
    for cluster, ids in existing_clusters.items():
        for nid in ids:
            assert nid in notes, f"cluster {cluster} 引用了不存在的笔记 {nid}"
            notes[nid]["cluster"] = cluster
    for nid, title, source, lang, role, cluster, content in NEW_NOTES:
        if cluster:
            notes[nid]["cluster"] = cluster

    # ---- 用例 ----
    old_cases = {c["id"]: c for c in base["cases"]}
    old_negs = {q["id"]: q for q in base["negativeQueries"]}
    cases = []

    for cid, cat, diff in REUSED:
        src = old_cases[cid]
        target_note = notes[src["expectedNoteIDs"][0]]
        rel = {nid: 3 for nid in src["expectedNoteIDs"]}
        hard = REUSED_HARD_NEGATIVES.get(cid, [])
        for nid in hard:
            rel.setdefault(nid, 0)
        cases.append({
            "id": cid, "query": src["query"], "expectedNoteIDs": src["expectedNoteIDs"],
            "style": src["style"], "queryLanguage": src["queryLanguage"],
            "expectedLanguage": src["expectedLanguage"], "scope": src["scope"],
            "longRegion": src.get("longRegion"), "note": src["note"],
            "scenario": REUSED_SCENARIOS.get(cid, src["note"]),
            "category": cat, "difficulty": diff, "contentType": target_note["source"],
            "relevance": rel, "hardNegativeNoteIDs": hard,
            "expectedBehavior": "命中期望笔记并落在对应块上",
            "expectedLandingTarget": landing_target(target_note),
            "rationale": src["note"], "provenance": PROV,
        })

    for c in NEW_CASES:
        targets = sorted(k for k, v in c["targets"].items() if v >= 2)
        assert targets, c["id"]
        target_note = notes[targets[0]]
        rel = dict(c["targets"])
        for nid in c["hard"]:
            rel.setdefault(nid, 0)
        langs = {notes[t]["language"] for t in targets}
        expected_lang = langs.pop() if len(langs) == 1 else "mixed"
        scope = "cross-language" if (c["cat"] == "cross_language"
                                     or (expected_lang in ("zh", "en") and expected_lang != c["lang"]
                                         and c["cat"] not in ("ambiguous",))) else "in-scope"
        cases.append({
            "id": c["id"], "query": c["query"], "expectedNoteIDs": targets,
            "style": "natural", "queryLanguage": c["lang"], "expectedLanguage": expected_lang,
            "scope": scope, "longRegion": None, "note": c["why"],
            "scenario": c["scenario"], "category": c["cat"], "difficulty": c["diff"],
            "contentType": target_note["source"], "relevance": rel,
            "hardNegativeNoteIDs": c["hard"],
            "expectedBehavior": c["behavior"],
            "expectedLandingTarget": landing_target(target_note),
            "rationale": c["why"], "provenance": PROV,
        })

    negatives = []
    for nid in REUSED_NEGATIVES:
        src = old_negs[nid]
        negatives.append({
            "id": nid, "query": src["query"], "reason": src["reason"],
            "scenario": src["reason"], "queryLanguage": "zh", "difficulty": "medium",
            "hardNegativeNoteIDs": [], "provenance": PROV,
        })

    # ---- split ----
    split_for = assign_splits(cases, key=lambda c: c["category"])
    for c in cases:
        c["split"] = split_for[c["id"]]
    neg_split = assign_splits(negatives, key=lambda c: "negative")
    for n in negatives:
        n["split"] = neg_split[n["id"]]

    # 任何被标成答案的笔记，角色一律是 target。
    # v4 的簇里有些成员原来是纯干扰项，v5 给它们各写了一条 query（这正是
    # 「近似区分」这一类要考的），角色就必须跟着改 —— 否则
    # 「干扰项从不被标成 expected」这条不变量会被悄悄破坏。
    answered = {nid for c in cases for nid in c["expectedNoteIDs"]}
    for nid in answered:
        notes[nid]["role"] = "target"

    ordered_notes = sorted(notes.values(), key=lambda n: (n["id"][0], n["id"]))
    dataset = {
        "version": VERSION,
        "disclaimer": DISCLAIMER,
        "notes": ordered_notes,
        "cases": sorted(cases, key=lambda c: c["id"]),
        "negativeQueries": sorted(negatives, key=lambda c: c["id"]),
    }
    payload = json.dumps({k: v for k, v in dataset.items() if k != "checksum"},
                         ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    dataset["checksum"] = "sha256:" + hashlib.sha256(payload.encode("utf-8")).hexdigest()
    return dataset


# ---------------------------------------------------------------------------
# 5 · 质量自检
#
# 生成之后立刻自查。**报告里写的是事实，不是目标** —— 分布没达标就如实印出来，
# 不去悄悄挪一条用例的类别把数字凑齐。
# ---------------------------------------------------------------------------

def quality_report(ds):
    notes = {n["id"]: n for n in ds["notes"]}
    cases, negs = ds["cases"], ds["negativeQueries"]
    total = len(cases) + len(negs)
    problems = []
    lines = []

    def head(t):
        lines.append("")
        lines.append(t)
        lines.append("-" * len(t))

    lines.append(f"Dataset Quality Report — {ds['version']}")
    lines.append(f"provenance: {PROV}（agent 编写的场景化用例，不是真实用户数据）")
    lines.append(f"checksum:   {ds['checksum']}")
    lines.append("")
    lines.append(f"notes {len(notes)} · positive cases {len(cases)} · negative cases {len(negs)} "
                 f"· total queries {total}")

    # --- 规模 ---
    if not (180 <= total <= 240):
        problems.append(f"query 总数 {total} 不在 180–240 区间")

    # --- 类别分布 ---
    head("Category")
    counts = collections.Counter(c["category"] for c in cases)
    counts["negative"] = len(negs)
    for cat, target in sorted(CATEGORY_TARGET.items(), key=lambda kv: -kv[1]):
        n = counts.get(cat, 0)
        share = n / total
        flag = "" if abs(share - target) <= 0.03 else "  ← 偏离目标 >3pp"
        lines.append(f"  {cat:<20} {n:>4}  {share:6.1%}  (target {target:.0%}){flag}")
        if abs(share - target) > 0.05:
            problems.append(f"类别 {cat} 占比 {share:.1%} 与目标 {target:.0%} 相差超过 5pp")

    # --- 语言分布 ---
    head("Language (retrieval direction)")
    lang = collections.Counter()
    for c in cases:
        lang["cross" if c["scope"] == "cross-language" else c["queryLanguage"]] += 1
    for n in negs:
        lang[n["queryLanguage"]] += 1
    for k in ("zh", "en", "mixed", "cross"):
        if lang.get(k):
            lines.append(f"  {k:<20} {lang[k]:>4}  {lang[k]/total:6.1%}")
    for k, target in (("zh", 0.45), ("en", 0.45), ("cross", 0.10)):
        share = lang.get(k, 0) / total
        if abs(share - target) > 0.07:
            problems.append(f"语言 {k} 占比 {share:.1%} 与目标 {target:.0%} 相差超过 7pp")

    # --- 难度 / 语料类型 / split ---
    head("Difficulty")
    for k, v in sorted(collections.Counter(c["difficulty"] for c in cases).items()):
        lines.append(f"  {k:<20} {v:>4}  {v/len(cases):6.1%}")

    head("Content type of the target note")
    for k, v in sorted(collections.Counter(c["contentType"] for c in cases).items()):
        lines.append(f"  {k:<20} {v:>4}  {v/len(cases):6.1%}")
    missing_types = {"text", "ocr", "transcript", "extracted", "link"} - {c["contentType"] for c in cases}
    if missing_types:
        problems.append(f"语料类型未覆盖：{sorted(missing_types)}")
    # 每种语料都要有 easy / medium / hard
    by_type = collections.defaultdict(set)
    for c in cases:
        by_type[c["contentType"]].add(c["difficulty"])
    for t, diffs in sorted(by_type.items()):
        if diffs != {"easy", "medium", "hard"}:
            problems.append(f"语料类型 {t} 缺少难度档：有 {sorted(diffs)}")

    head("Split")
    split = collections.Counter([c["split"] for c in cases] + [n["split"] for n in negs])
    for k, v in sorted(split.items()):
        lines.append(f"  {k:<20} {v:>4}  {v/total:6.1%}")
    if abs(split["holdout"] / total - 0.30) > 0.05:
        problems.append(f"holdout 占比 {split['holdout']/total:.1%} 偏离 30%")
    # 分层：每个类别都要既有 development 又有 holdout
    split_by_cat = collections.defaultdict(set)
    for c in cases:
        split_by_cat[c["category"]].add(c["split"])
    split_by_cat["negative"] = {n["split"] for n in negs}
    for cat, s in sorted(split_by_cat.items()):
        if s != {"development", "holdout"}:
            problems.append(f"类别 {cat} 的 split 不分层：{sorted(s)}")

    head("Clusters (near-duplicate 的干扰源)")
    clusters = collections.Counter(n.get("cluster") for n in notes.values() if n.get("cluster"))
    small = [c for c, n in clusters.items() if n < 6]
    for c, n in sorted(clusters.items(), key=lambda kv: -kv[1]):
        lines.append(f"  {c:<24} {n:>3} 篇" + ("   ← <6，Top-5 装得下整簇" if n < 6 else ""))
    big = sum(n for c, n in clusters.items() if n >= 6)
    lines.append(f"  ≥6 篇的簇共 {len([1 for n in clusters.values() if n >= 6])} 个，"
                 f"覆盖 {big} 篇笔记（Top-5 装不下整簇，R@5 才有区分度）")
    if small:
        lines.append(f"  {len(small)} 个簇仍是 3–5 篇：它们是真实存在的近似组，"
                     f"但在这些簇上 R@5 没有区分度，只有 R@1 有")

    # --- 一致性检查 ---
    head("Consistency")
    ids = [c["id"] for c in cases] + [n["id"] for n in negs]
    dup_ids = [k for k, v in collections.Counter(ids).items() if v > 1]
    if dup_ids:
        problems.append(f"重复的 case id：{dup_ids}")

    queries = [c["query"] for c in cases] + [n["query"] for n in negs]
    dup_q = [k for k, v in collections.Counter(queries).items() if v > 1]
    if dup_q:
        problems.append(f"重复的 query：{dup_q}")

    note_texts = [n["content"] for n in notes.values()]
    dup_n = [k for k, v in collections.Counter(note_texts).items() if v > 1]
    if dup_n:
        problems.append(f"重复的笔记正文：{len(dup_n)} 处")

    for c in cases:
        for nid in c["expectedNoteIDs"]:
            if nid not in notes:
                problems.append(f"{c['id']} 引用了不存在的笔记 {nid}")
        for nid in c["hardNegativeNoteIDs"]:
            if nid not in notes:
                problems.append(f"{c['id']} 的硬负例 {nid} 不存在")
            if nid in c["expectedNoteIDs"]:
                problems.append(f"{c['id']} 把 {nid} 同时标成了答案和硬负例")
        if not c["expectedNoteIDs"]:
            problems.append(f"{c['id']} 没有相关笔记")
        rel = c["relevance"]
        graded = sorted(k for k, v in rel.items() if v >= 2)
        if graded != sorted(c["expectedNoteIDs"]):
            problems.append(f"{c['id']} 的分级相关性与 expectedNoteIDs 不一致")
        if notes[c["expectedNoteIDs"][0]]["source"] != c["contentType"]:
            problems.append(f"{c['id']} 的 contentType 与目标笔记不符")
        # 中高难度要有硬负例
        if c["difficulty"] in ("medium", "hard") and not c["hardNegativeNoteIDs"] \
                and c["category"] not in ("cross_language",):
            problems.append(f"{c['id']}（{c['difficulty']}）没有硬负例")

    # --- 泄漏检查：query 原文不能出现在笔记里 ---
    head("Leakage")
    #
    # 要防的是「为了让某条 query 命中而把它写进笔记」。
    #
    # **`exact_fact` 例外**：那一类的定义就是「用户记得原词」——「CF259X High Yield
    # 10000 pages」「VNB3K21099」本来就是笔记上印着的字。把它判成泄漏等于取消
    # 这一整个类别。例外只对 exact_fact 开，其余类别一旦逐字出现即为数据错误。
    leaks, literal_recall = [], []
    for c in cases + negs:
        q = re.sub(r"\s+", "", c["query"]).lower()
        if len(q) < 12:
            continue
        for n in notes.values():
            body = re.sub(r"\s+", "", n["title"] + n["content"]).lower()
            if q in body:
                (literal_recall if c.get("category") == "exact_fact" else leaks).append(
                    (c["id"], n["id"]))
    if leaks:
        problems.append(f"query 原文出现在笔记里（泄漏）：{leaks}")
    lines.append(f"  非 exact_fact 类别的逐字重合：{len(leaks)} 条")
    lines.append(f"  exact_fact 的原词引用（预期行为）：{len(literal_recall)} 条")

    # --- 模板化检查：不能大量只换实体 ---
    head("Template similarity")
    #
    # 「只替换实体的模板」在中文里抓不到骨架 —— 中文没有空格，正则一归一化就把
    # 整句压成一个 X（第一版就是这样，把 67 条完全不同的 query 报成同一个模板）。
    #
    # 改成**字符三元组 Jaccard 两两比对**：它对语言无关，而且直接对应要防的东西 ——
    # 「把一条 query 抄一遍只换掉实体」得到的相似度必然很高。
    def trigrams(text):
        t = re.sub(r"\s+", "", text.lower())
        return {t[i:i + 3] for i in range(max(0, len(t) - 2))} or {t}

    grams = [(c["id"], c["query"], trigrams(c["query"])) for c in cases + negs]
    pairs = []
    for i in range(len(grams)):
        for j in range(i + 1, len(grams)):
            a, b = grams[i][2], grams[j][2]
            sim = len(a & b) / len(a | b)
            if sim >= 0.6:
                pairs.append((sim, grams[i][0], grams[j][0], grams[i][1], grams[j][1]))
    pairs.sort(reverse=True)
    for sim, ia, ib, qa, qb in pairs[:5]:
        lines.append(f"  {sim:.2f}  {ia} / {ib}   {qa!r} ~ {qb!r}")
    lines.append(f"  相似度 ≥0.60 的 query 对：{len(pairs)}")
    too_close = [p for p in pairs if p[0] >= 0.8]
    if too_close:
        problems.append(f"模板化：{len(too_close)} 对 query 相似度 ≥0.80 —— "
                        f"最高的一对是 {too_close[0][1]} / {too_close[0][2]}")

    head("Problems")
    if problems:
        for p in problems:
            lines.append(f"  ✗ {p}")
    else:
        lines.append("  ✓ 无")
    return "\n".join(lines), problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true", help="只打印报告，不写文件")
    args = ap.parse_args()

    ds = build()
    report, problems = quality_report(ds)
    print(report)

    if not args.report:
        with open(FIXTURE, "w", encoding="utf-8") as f:
            json.dump(ds, f, ensure_ascii=False, indent=2)
            f.write("\n")
        print(f"\n写入 {os.path.relpath(FIXTURE, ROOT)}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
