# 万象记 / Mosaic — Xcode 手动验收清单 / Manual Verification Checklist

> 本项目的纯逻辑核心(`MosaicKit`)已在命令行用 `swift run mosaic-checks` 验证(117 断言通过)。
> 但 **iOS App target 没有在本环境编译过**(本机只有 Command Line Tools)。请按本清单在**完整 Xcode**(建议 16+,iOS 17 SDK)中打开、配置、运行并逐项验收。

---

## 0. 打开项目 / Open the project

```bash
# 如未安装 / if needed
brew install xcodegen

cd App
xcodegen generate          # 由 project.yml 生成 Mosaic.xcodeproj
open Mosaic.xcodeproj
```

- Scheme 选 **Mosaic**,运行目标选 **iOS 17+ 模拟器或真机**。
- 首次打开时 Xcode 会解析本地 Swift Package `MosaicKit`(位于仓库根目录,`..`)。等待 Package 解析完成。

---

## 1. 签名与能力 / Signing & Capabilities(需要你本地操作)

打开 **Target `Mosaic` → Signing & Capabilities**:

1. **Team**:选择你的开发者账号 Team。
2. **Bundle Identifier**:当前为 `com.mosaic.app`。请改成你自己的唯一反向域名,例如 `com.<yourname>.mosaic`。
3. **CloudKit 容器(二选一)**:
   - **A. 暂时不用 iCloud(最快跑起来,推荐先这样)**:
     删除 `App/Mosaic/Mosaic.entitlements` 里的全部键(iCloud 容器、ubiquity、aps-environment),或在 Signing & Capabilities 里移除 **iCloud** 与 **Push Notifications** 能力。`ModelContainerFactory` 在无 CloudKit 时会自动回退到本地存储,App 仍可正常离线使用。
   - **B. 启用 iCloud 同步**:
     - 把 entitlements 里的容器标识 `iCloud.com.mosaic.app` 改成 `iCloud.<你的 bundle id>`(或你在账号里创建的容器)。
     - 在 Signing & Capabilities 中添加 **iCloud → CloudKit**,勾选/创建该容器;并添加 **Push Notifications**(用于 CloudKit 订阅推送)。
     - 真机需登录 iCloud 账号。
4. **Background Modes**:Info.plist 已开启 `remote-notification`(供 CloudKit 推送)。不用 CloudKit 时可忽略。

> ⚠️ 常见坑:如果 entitlements 引用了一个你账号里**不存在**的 CloudKit 容器,签名会失败。所以要么按 A 删除相关键,要么按 B 创建并对齐容器标识。

---

## 2. 权限说明 / Permission usage strings(已内置)

Info.plist 已包含中文用途说明:麦克风、语音识别、相机、相册。首次使用对应功能时系统会弹窗,请允许。

---

## 3. 需要测试的页面 / Pages to test

文件夹列表(首页) → 文件夹详情(卡片折叠列表) → 卡片编辑器 → AI 摘要贴纸 → 设置。

---

## 4. P0 功能逐项验收 / Per-feature acceptance

> 图标说明:✅ 预期结果 / ⚠️ 可能的错误与修复。

### 4.1 文件夹管理 Folders
- 步骤:首页点右上「＋」→ 输入名称、选颜色与图标 → 保存。再左滑某文件夹试「重命名」「删除」。
- ✅ 列表显示文件夹(图标+颜色)、名称、卡片数;删除时弹「将同时删除其中 N 张卡片」确认。
- ⚠️ 若列表不刷新:确认 `@Query` 正常;重启 App 再看。

### 4.2 卡片管理 Cards
- 步骤:进入文件夹 → 右上「✎」新建卡片 → 自动进入编辑器 → 返回。
- ✅ 返回后卡片以折叠长条出现;多张卡片按「最后修改时间倒序」排列;无标题时显示「未命名笔记」(有 AI 标题后显示 AI 标题)。左滑可删除(二次确认)。

### 4.3 编辑器与内容块 Editor & blocks
- 步骤:在编辑器底部「添加内容」分别添加:文字、相册选图、拍照、录音、导入文档、链接。点右上 Edit 进入排序/删除模式,拖动重排、左滑删除。
- ✅ 各类型块正确渲染;编辑后约 0.8s 自动保存(返回再进仍在);全程可离线;排序与删除生效且媒体文件随之清理。
- ⚠️ **拍照**在模拟器不可用(无摄像头)——用真机;相册选图在模拟器可用。

### 4.4 录音块 Audio(建议真机)
- 步骤:添加「录音」→ 录制(可暂停/继续)→ 完成。回到块上点播放,拖动波形定位进度;展开「转写稿」查看/编辑,可「重新转写」。
- ✅ 录音保存可回放;波形随播放进度变色;拖动波形可 seek;录音停止后自动端上转写出文字(音频不外传)。
- ⚠️ 模拟器的语音识别/麦克风支持有限;若转写为空或报「不支持离线识别」,请在**真机**并确保系统已下载对应语言(设置→通用→键盘/听写 或 首次使用触发下载)。

### 4.5 图片块 Image
- 步骤:相册选 1~多张图 → 缩略图显示 → 点开全屏缩放 → 填写「图片说明」。
- ✅ 缩略图显示;全屏可双指缩放;说明可保存;发送给 AI 前会压缩到长边 ≤1568px。

### 4.6 文档块 Document
- 步骤:导入一个 **PDF** 与一个 **.docx**。点击在应用内 QuickLook 预览。
- ✅ PDF 可预览且正文文字被提取(用于 AI,不展示给用户);.docx 可预览但标注「暂不支持提取文字」。
- ⚠️ 若 QuickLook 空白,确认文件已复制进沙盒(导入成功)。

### 4.7 链接块 Link
- 步骤:添加链接输入网址(可不带 http)→ 点击在应用内打开;长按选「用 Safari 打开/复制链接」。
- ✅ 应用内 SFSafari 打开;长按菜单可用。

### 4.8 AI 摘要贴纸 Summary sticker(需先在设置配置 Key)
- 步骤:折叠长条点末尾小三角 ▸ 展开 → 首次触发「生成总结」(先弹隐私同意)→ 看到 类型/主题 chips/要点/总结段/模型·时间。再编辑卡片并退出 → 自动追加一条「更新记录」(倒序,保留初始总结),长条小三角旁出现红点;展开后红点清除。试「立即更新」「重新生成」「清除」。
- ✅ 初始总结按固定结构渲染;更新记录倒序追加且不覆盖;loading/错误/重试/空态正确;错误为配置类时显示「去设置」。
- ⚠️ 报「内容太少」=卡片几乎为空;报「API Key 无效」=检查设置;报「网络未连接」=联网后重试。

### 4.9 设置 Settings
- 步骤:首页左上齿轮 → 选服务商(Kimi/DeepSeek/自定义)→ 填 Key(自定义另填 Base URL+模型)→「测试连接」。切换「内容变更后自动追加更新总结」「发送图片给 AI」「JSON 输出模式」「iCloud 同步」。
- ✅ Key 存 Keychain(切换服务商各自独立);测试连接成功显示绿勾,失败显示红字原因。改 iCloud 开关后提示需重启生效。
- ⚠️「测试连接」只发 ping 不含卡片内容,因此不弹隐私窗(设计如此)。

### 4.10 隐私 Privacy
- ✅ 首次任何「会发送卡片内容/图片」的 AI 调用前必弹隐私窗;同意后才发送;原始录音不发送(只发转写文字)。设置里可「重置隐私同意状态」重新触发。

---

## 5. 常见错误与修复 / Common errors & fixes

| 现象 | 原因 | 修复 |
|---|---|---|
| 签名失败 / Provisioning error | 未设 Team、bundle id 重复、或 CloudKit 容器不存在 | 设 Team + 唯一 bundle id;按 §1 处理 CloudKit(删键或建容器) |
| 启动崩溃 / 无法创建 ModelContainer | CloudKit 配置不全 | 已内置回退到本地;若仍崩溃,先按 §1-A 移除 CloudKit 能力 |
| 拍照无反应 | 模拟器无摄像头 | 用真机 |
| 转写为空 / 提示不支持离线 | 模拟器或语言未下载 | 真机 + 下载对应听写语言 |
| AI 报「尚未设置 API Key」 | 未配置 | 设置页填 Key |
| 测试连接失败 | Key/BaseURL/模型错或网络问题 | 核对设置;自定义服务确认兼容 OpenAI `/chat/completions` |
| Package 解析失败 | Xcode 未解析本地包 | File → Packages → Reset/Resolve;确保 `Package.swift` 在仓库根 |

---

## 6. 仍需你确认的本地配置 / Things only you can set locally

- [ ] 开发者 **Team**(签名)。
- [ ] 唯一 **Bundle Identifier**(替换 `com.mosaic.app`)。
- [ ] **CloudKit 容器**:删除 entitlements 中相关键(快速本地跑)**或**创建 `iCloud.<你的 bundle id>` 容器并对齐(启用同步)。
- [ ] **真机**用于验证:录音/端上转写、拍照。
- [ ] 有效的 **API Key**(Kimi/DeepSeek/自定义)用于验证 AI 总结。
