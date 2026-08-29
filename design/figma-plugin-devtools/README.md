# Mosaic Dev Tools 线框生成器（Track B）

**与 [`../figma-plugin/`](../figma-plugin/)（Production 生成器）完全分离的第二个插件。**

## 为什么分开

Production 生成器带着一整套流水线：5 个测试套件、86+ 点数值校准、±1pt 容差、
Light/Dark 双模式、Variable / Text Style / Effect Style。那套东西是为**生产 UI** 服务的。

Developer Tools 的判断标准是「信息结构对不对」，不是「像素准不准」。
把它塞进那条流水线，成本远超收益。所以它有自己的 manifest、自己的 code.js、
自己的冒烟测试，**不共享一行代码**，只创建并重建一个页面：`🔧 Dev Tools (Wireframe)`。

设计规格见 [`../DEVTOOLS.md`](../DEVTOOLS.md)。

## 运行

```
1. Figma 桌面版 → Plugins → Development → Import plugin from manifest…
   选本目录的 manifest.json
2. Plugins → Development → Mosaic Dev Tools 线框（Track B）
3. 生成 9 屏 + 10 条原型连线到 🔧 Dev Tools (Wireframe) 页
```

**重复运行幂等**：只清空并重建 `🔧 Dev Tools (Wireframe)` 这一页。
`📐 Foundations` / `🧩 Components` / `📱 Screens` 三页**不会被触碰** —— 冒烟测试对此有断言。

## 自检

```
node test/run.js
```

六项：屏数 · 屏尺寸 · 内容不溢出 852pt · 连线数 · Track B 边界 · Production 页未受影响。

其中两项是**边界断言**，用来保证 Track B 的承诺不是口头的：

- `track-b` —— 未创建任何 Variable / Text Style / Effect Style
- `production-untouched` —— Production 三页未被清空

## 屏幕

| ID | 屏 | 说明 |
|---|---|---|
| D1 | Developer Mode | 入口列表。不做 Dashboard，不做 KPI overview |
| D2 | Retrieval Lab | Query + 六个 Config Picker + 竖排 Result Inspector |
| D3 | Retrieval Lab · Compare | Mode Picker 的第四个状态，不是独立页。重点是 unique hit |
| D4 | Retrieval Trace | SwiftUI-first；线框只为把 Flow A 走通。禁止 waterfall chart |
| D5 | Eval Center | Dataset × Config → 六个数字。无图表 |
| D6 | Eval Center · Compare | Current / Baseline / Delta，质量与延迟同屏 |
| D7 | Release Gate · PASS | |
| D8 | Release Gate · BLOCKED | 任一项 FAIL 即阻断，不做加权总分 |
| D9 | Failure Inspection | SwiftUI-first；线框只为把 Flow B / C 走通 |

## 边界

不做：Dark Mode · 像素校准 · Variable / Style · Figma 组件库 · 自定义图表 · 插画 ·
production 级视觉打磨。

做：灰度 box · 文本 · 原生控件近似（导航栏 / Form 行 / Toggle / Segmented / 主按钮）。

> 屏幕里的数字（`0.875` / `181 ms` / `40 cases`）都是**占位样例**，
> 不是实测基线。真实数字见 [`../GOAL1_BACKLOG.md`](../GOAL1_BACKLOG.md) Week 6 回填。
