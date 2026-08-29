/* ============================================================================
 * 万象记 / Mosaic — Design Tokens（Batch A / Step 2 收敛后）
 * ----------------------------------------------------------------------------
 * 本文件是 Token 的唯一真源。code.js 内联同一份定义（Figma 插件不支持模块化），
 * 两处必须保持一致；`npm run check` 会校验一致性。
 *
 * 收敛原则：
 *   · spacing 走 8pt 网格，只保留 7 档
 *   · radius 只保留 4 档 + capsule
 *   · icon 只保留 3 档通用尺寸
 *   · 系统几何值（44/49/54/34/47/393/852）单独分组，**不参与收敛**
 *   · 微观视觉值（波形条宽、描边）不进 Token，直接写字面量并在检查中豁免
 * ========================================================================== */

const SPACING = {
  'space/4': 4,
  'space/8': 8,
  'space/12': 12,
  'space/16': 16,
  'space/20': 20,
  'space/24': 24,
  'space/32': 32,
};

const RADIUS = {
  'radius/xs': 4,     // 微元素：键帽、波形条
  'radius/sm': 8,     // chip、小卡片
  'radius/md': 12,    // 按钮、内容块
  'radius/lg': 16,    // 卡片、菜单、Sheet
  'radius/full': 999, // capsule
};

const ICON = {
  'icon/sm': 16,
  'icon/md': 20,
  'icon/lg': 24,
};

const ROW = {
  'row/standard': 44,
  'row/two-line': 56,
};

const MOTION = {
  'duration/fast': 0.2,
  'duration/normal': 0.3,
};

/** 系统几何值 —— 由 iOS 规定，不是设计自由度，豁免于收敛检查。 */
const SYSTEM = {
  'system/tap-min': 44,          // HIG 最小触控目标
  'system/nav-height': 44,       // 导航栏
  'system/toolbar-height': 49,   // 底部工具栏
  'system/status-height': 54,    // 状态栏（灵动岛机型）
  'system/home-indicator': 34,   // Home 指示条区域
  'system/device-radius': 47,    // 设备物理圆角
  'system/screen-w': 393,        // iPhone 15 逻辑宽
  'system/screen-h': 852,        // iPhone 15 逻辑高
};

/** 微观视觉值：不进 Token，检查时豁免。 */
const MICRO_EXEMPT = [1, 1.5, 2, 2.5, 3, 0.5];

/** 组件专属视觉锚点：有意保留的非网格值，需逐个说明理由。 */
const ANCHOR_EXEMPT = {
  34: '音频播放按钮 —— 视觉锚点，缩到 24 会失去主次',
  52: '空状态插画 —— 大尺寸留白构图',
  38: '文件夹图标底板 —— 与 44pt 行高配合的既有规格',
  56: '两行行高（row/two-line）',
  9: '未读圆点直径',
  14: '置顶图标 —— 需小于正文字号',
};

module.exports = { SPACING, RADIUS, ICON, ROW, MOTION, SYSTEM, MICRO_EXEMPT, ANCHOR_EXEMPT };
