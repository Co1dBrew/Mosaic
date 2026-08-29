# Mosaic 设计 — 人工 QA 待办

> 范围：**Figma 设计阶段**的人工检查。
> SwiftUI 实现阶段的验证已迁出到 [`IMPLEMENTATION_QA.md`](IMPLEMENTATION_QA.md)。
> 设计基线：[`DESIGN_BASELINE.md`](DESIGN_BASELINE.md)
> 最后更新：2026-08-07（第二次 MCP 实读 + 校准语义收口后）

---

## BLOCKER

**0**

---

## DESIGN MANUAL-P0

**0**

原有的 5 项已全部关闭或迁出：

| 原编号 | 处置 |
|---|---|
| M-P0-1 校准基准刷新 | ✅ 完成 — 已用 2026-08-07 实读值刷新，EXACT 36/36、NUMERIC 50/50 |
| M-P0-2 两行摘要确认 | ✅ 完成 — 实读确认 `Note Row` 在 72.5（一行）/ 90.5（两行）间自适应 |
| M-P0-3 Adaptive Toolbar 手感 | → 迁至 `IMPLEMENTATION_QA.md` **I-P0-1** |
| M-P0-4 Dynamic Type | → 迁至 `IMPLEMENTATION_QA.md` **I-P0-2** |
| M-P0-5 VoiceOver | → 迁至 `IMPLEMENTATION_QA.md` **I-P0-3** |

**开发前不需要任何 Figma 侧的人工检查。设计可以直接交付。**

---

## MANUAL-P1

以下是设计与实现交界处的人工判断项，按**验证阶段**分组。

### 阶段：Design Handoff（交付给工程师时）

#### M-P1-1 · 光学对齐

自动检查只验证数值对齐，不验证光学重心。需人工看：
- `Bar / Nav` 中标题与左右图标的视觉居中（图标有内白，数值居中往往看起来偏移）
- `Chip / Folder` 内色点与文字的基线关系
- `Block / Audio` 播放按钮（34pt，登记为视觉锚点）与波形的视觉重量平衡

#### M-P1-3 · SF Symbols 替换

当前 35 个图标是手绘 SVG 路径。交付 SwiftUI 时应逐个替换为对应 SF Symbol，替换后需重新确认光学尺寸（SF Symbol 的视觉重量与自绘路径不同）。

建议映射：`compose→square.and.pencil` · `sparkle→sparkles` · `pin→pin.fill` · `warning→exclamationmark.triangle` · `check→checkmark` · `grip→line.3.horizontal` · `ellipsisCircle→ellipsis.circle` · `xmark→xmark.circle.fill`

#### M-P1-7 · Block / Audio 的转写区默认值

`Block / Audio` 的 `Transcript` 是 INSTANCE_SWAP 属性，默认值为 `short`。因此在组件库中，`state=transcribing` 与 `state=failed` 两个变体也会显示一段已完成的转写文本。

这是 Figma 组件属性默认值的正常行为（实例可自由替换），但**在组件库预览时看起来略有歧义**。两态本身仍可通过状态行（「转写中…」/「转写失败 + 重试」）明确区分，因此不作为缺陷处理。

交付时请在实现中明确：`transcribing` 与 `failed` 状态下**不应渲染已完成的转写文本**。

---

### 阶段：SwiftUI 实现中

#### M-P1-2 · 阴影强度

`elevation/menu`（y12 blur44 α.26）与 `elevation/drag`（y4 blur12 α.18）是按 iOS 观感估的，需在真实深色模式下确认不过重。

#### M-P1-6 · 深色模式下的图片占位

`Block / Image` 的 `loaded` 态用 `bg/fill-strong` 作占位。真实图片在深色模式下需确认是否需要降低亮度或加边框。

---

### 阶段：Pre-release

#### M-P1-4 · 动效手感

`duration/fast=0.2` / `duration/normal=0.3` 是 Token，但摘要展开/收起的实际曲线与阻尼需在真机上调。同时确认 `accessibilityReduceMotion` 下的降级效果。

#### M-P1-5 · 中文断行

PingFang SC 的标点避头尾规则在 Figma 与 CoreText 中可能不同。需确认 `Note / Preview` 的两行截断处不会出现标点孤字。

---

## PRODUCT-DECISION-TODO

**0**。8 条决策（D-01 ~ D-08）已在 Phase 0 冻结并全部落地，执行过程中未遇到需要新决策的情况。

---

## 如何重新运行全部自动验证

```bash
cd design/figma-plugin && node test/all.js
```

| 套件 | 内容 |
|---|---|
| `checks.js` | 9 项结构检查 |
| `gates.js` | 9 项 Batch Gate（A1-A3 · B1-B4 · C1-C2） |
| `calibration.js` | 桩 vs 真实 Figma，EXACT 36 项 + NUMERIC 50 项 |
| `tolerance.js` | 校准容差的 7 个边界用例 |
| `selftest.js` | 13 个变异，证明每个检查器都能报警 |
