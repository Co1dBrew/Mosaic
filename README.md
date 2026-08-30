# 万象记 / Mosaic

一个 iOS 多媒体笔记 App，外加一套**可以用数据判断该不该上线**的检索质量平台。

- **笔记**：一条笔记里混装文字、图片、录音、文档、链接；AI 生成一句话概述与
  完整总结，之后每次实质修改追加一条「这次变了什么」。
- **搜索**：词法 + 语义混合检索，用户侧没有任何模式开关。
- **质量平台**：场景化评测集 · 分级标注 · development / holdout · 统计置信的发布判定 ·
  真机延迟基准 · 内部开发者工具。

> **当前发布结论：不可上线（BLOCKED）。** 判定链路是闭合的，但候选配置在
> development 上没有达到质量下限，云端臂缺凭据未跑。详见
> [`GATE_POLICY.md`](GATE_POLICY.md) §5 与 [`PROJECT_STATUS.md`](PROJECT_STATUS.md)。

---

## Source of Truth

冲突时按这个顺序：

| 文件 | 讲什么 |
|---|---|
| **PRD v1.0**（用户持有，不在仓库） | 最高权威。缺精确数值时**不要编** |
| [`PROJECT_STATUS.md`](PROJECT_STATUS.md) | **现在到底是什么状态** —— 先读这份 |
| [`UI_REDESIGN.md`](UI_REDESIGN.md) | 生产设计（v2，已冻结、已实现） |
| [`design/SEARCH_CONTRACT.md`](design/SEARCH_CONTRACT.md) | 生产搜索契约（已冻结） |
| [`EVAL_SPEC.md`](EVAL_SPEC.md) | 评测方法：数据怎么来、指标怎么算 |
| [`GATE_POLICY.md`](GATE_POLICY.md) | 发布标准：达到什么条件才允许上线 |
| [`RETRIEVAL_ARCHITECTURE.md`](RETRIEVAL_ARCHITECTURE.md) | 工程决策记录（长，按 § 查） |
| [`design/DECISION_LOG.md`](design/DECISION_LOG.md) | 产品决策 |
| [`HANDOFF_NEXT.md`](HANDOFF_NEXT.md) | 下一步做什么 |

已归档、**不要据此判断现状**的文档见 [`docs/ARCHIVED.md`](docs/ARCHIVED.md)。

---

## 架构

分两层，让易错的逻辑在没有 Xcode 的环境里也能跑起来测。

```
Mosaic/
├── Package.swift                 # MosaicKit（库）+ mosaic-checks（断言跑批）
├── Sources/MosaicKit/            # 纯 Swift 内核 —— 不引 SwiftData、不引 UIKit
│   ├── Provider/ AI/             # 服务商配置 · 提示词 · 请求构造 · 响应解析
│   ├── Aggregation/ Diff/        # 内容聚合 · 内容哈希 · 快照 diff
│   ├── Retrieval/                # 分块 · 词法 · 向量 · 融合 · 索引状态 · 一致性对账
│   ├── Search/                   # 匹配 · 结果呈现 · Result→Note 落点
│   ├── Notes/                    # 列表取值规则 · 摘要条状态 · 权限文案
│   ├── Eval/                     # 评测集 · Runner · 指标 · 发布判定 · 配对 bootstrap
│   └── Sync/ Security/           # 同步状态口径 · Keychain
├── Sources/MosaicKitChecks/      # 断言跑批（3600+ 条），含评测集与基线评测
├── tools/                        # 评测集生成 · 图标生成 · 发布前核对
└── App/
    ├── project.yml               # XcodeGen 规格（生成 Mosaic.xcodeproj）
    ├── Mosaic/
    │   ├── App/                  # 入口 · 根导航 · 路由 · 容器工厂
    │   ├── Persistence/          # @Model：Folder / Card / Block / 摘要 / 更新记录
    │   ├── Features/Notes/       # 首页笔记流 · 笔记页 · 摘要条（UI v2）
    │   ├── Features/Search/      # 生产搜索
    │   ├── Features/Editor/      # 五类内容块
    │   ├── Retrieval/            # 索引服务 · derived store · 检索栈持有者
    │   ├── Settings/             # 设置（两层）
    │   └── DeveloperTools/       # **只在 DEBUG / INTERNAL_BUILD 编译**
    ├── MosaicTests/              # XCTest（93 条）
    ├── MosaicUITests/            # XCUITest 核心流程（6 条）
    └── MosaicBench/              # 真机性能基准（独立 scheme）
```

**边界**：`MosaicKit` 从不 import SwiftData 或 UIKit。App 在边界上把 SwiftData
模型适配成 `MosaicKit` 的值类型，所以哈希 / diff / 聚合 / 检索 / 评测全部平台无关、可测。

---

## 构建与测试

### 内核（只要 Swift 工具链）

```bash
swift run mosaic-checks
```

3600+ 条断言，覆盖服务商配置、JSON 解析健壮性、内容哈希、快照 diff、检索管线、
评测集质量、发布判定口径、UI 取值规则。失败时非零退出，可直接当 CI 闸门。

### iOS App（需要完整 Xcode）

```bash
cd App && xcodegen generate
```

```bash
xcodebuild test -scheme Mosaic -project App/Mosaic.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### 发布前核对

```bash
./tools/verify_release.sh
```

检查 Release **产物**：内部工具是否真的不在包里、隐私清单与图标是否打包、
权限说明是否与实际用途一致、CloudKit 标记是否与 entitlements 一致。

### 真机性能基准（需要连真机）

```bash
xcodebuild test -scheme MosaicBench -project App/Mosaic.xcodeproj -configuration Release -destination 'platform=iOS,id=<设备 UDID>' -allowProvisioningUpdates
```

**延迟结论只在真机 release 上成立。** Mac / 模拟器的数字不冒充真机数字。

---

## 检索与评测（Goal 1）

### 生产搜索

隐式混合检索，用户侧没有 mode 开关（`design/SEARCH_CONTRACT.md` §1.1）。
结果行三槽位：标题 · **命中片段** · 文件夹与时间。命中片段的唯一职责是回答
「为什么这条与我搜的有关」，它不是笔记摘要。

中文 query 走 **CJK 二元组切分**：在此之前一句没有空格的中文是一个 token，
匹配要求整句原样出现在笔记里，于是长口语 query 在词法路上**全灭**
（`QuerySegmentation` 里记着那次实测）。

### 评测集

`scenario-v5`：242 篇合成语料 + **207 条 agent 编写的场景化 query**，
九类检索能力、分级相关性、硬负例、development / holdout。

> **不是真实用户数据。** provenance 一律 `agent_authored_realistic`。
> 它能证明评测管线闭合与两套配置可比较，**不能**支持任何关于真实用户
> Recall 的绝对结论。详见 [`EVAL_SPEC.md`](EVAL_SPEC.md) §1。

### 发布判定

`gate-v1` = baseline 相对（配对 bootstrap 置信区间）+ **绝对下限** + 分层延迟预算 +
回归通过率。任一项 FAIL 即阻断，不做加权、不算总分。
详见 [`GATE_POLICY.md`](GATE_POLICY.md)。

### 开发者工具

Retrieval Lab / Compare / Trace / Eval Center / Release Gate。
**只在 DEBUG 或显式 `INTERNAL_BUILD` 的构建里编译** —— 正式 Release 里这些类型
根本不存在（`tools/verify_release.sh` 核对符号）。

---

## 配置

1. **设置 → AI 服务商**：选 Kimi / DeepSeek / 自定义。
2. 填 **API Key**（只存 Keychain）；自定义服务商时 Base URL 与模型名会提升到第一屏。
3. 点 **测试连接**（只发一个无内容的 ping，不走内容同意闸门）。
4. 首次生成总结前会有一次性隐私弹窗，同意后内容才会外发。

**三类内容外发各有独立同意，默认全部关闭，关闭时零请求**（有断言守着）：

| 外发 | 开关 |
|---|---|
| 笔记文字 + 图片 → AI 总结 | 首次弹窗 |
| 录音音频 → 云端转写 | 首次弹窗（Apple 本地转写不上传音频，是默认值） |
| 笔记文字 → 云端智能搜索 | 设置 → 高级，默认关闭 |

---

## 明确的非功能与限制

| | 状态 |
|---|---|
| **iCloud 同步** | **此版本不提供**。entitlements 里没有 CloudKit 容器，设置页据实显示「此版本不提供」而不是给一个必然失败的开关 |
| **语义弃答（abstention）** | **EXPERIMENTAL，未接入生产**。TD-10 未解决（余量 0.0002）。有断言守着它不出现在生产路径里 |
| **App 图标** | **临时品牌资产**，由 `tools/branding/make_app_icon.py` 生成，等最终品牌设计替换 |
| **媒体文件同步** | 未实现。媒体存在 App 沙盒（`MediaStore`），元数据可同步、二进制不同步 |
| **PDF 导出** | 未实现。当前支持 Markdown / 纯文本导出 |
| **部署目标** | iOS 17（SwiftData / `@Observable`） |

## Figma

https://www.figma.com/design/vUc6N3SJ01327qX27lFeug/Mosaic?m=auto&t=srI2bH5QHDjrubSL-6
