/* ============================================================================
 * 万象记 / Mosaic — UI v2 设计系统生成器（Figma Plugin）
 * ----------------------------------------------------------------------------
 * Batch A 版本：Token 收敛 + 组件树 + 嵌套架构 + 共享反馈组件。
 *
 *   📐 Foundations   收敛后的 Token（7 spacing · 5 radius · 3 icon · 2 row · 2 motion）
 *                    + 系统几何值（豁免组）+ 全局按下规则 + 15 文字样式
 *   🧩 Components    组件树全部节点（本轮只建 default / 架构性变体）
 *   📱 Screens       9 屏（现状对照屏 ①③⑦ 已按 D-08 移除）
 *
 * 架构原则（见 REMEDIATION_PLAN.md §6.0）：
 *   1. 禁止变体笛卡尔积 —— 用嵌套组件 + Boolean / Instance Swap 属性组合
 *   2. pressed/focused 按「是否产生真实视觉差异」判断，不机械建变体
 *   3. 只为真实存在且有明显差异的状态建变体
 *
 * Batch A 边界：不填 AI Summary 9 态 · 不填 Block 完整状态 · 不做 Sheet 全量
 *              · 不做 Prototype · 不做 Dynamic Type 验证（属 Batch B / C）
 * ========================================================================== */

// =============================================================== 1. 设计令牌

const COLORS = {
  'bg/primary':       ['#F2F2F7FF', '#000000FF'],
  'bg/card':          ['#FFFFFFFF', '#1C1C1EFF'],
  'bg/fill':          ['#78788020', '#7878803D'],
  'bg/fill-strong':   ['#7878802A', '#78788052'],
  'text/primary':     ['#000000FF', '#FFFFFFFF'],
  'text/secondary':   ['#3C3C4399', '#EBEBF599'],
  'text/tertiary':    ['#3C3C434D', '#EBEBF54D'],
  'text/on-accent':   ['#FFFFFFFF', '#FFFFFFFF'],
  'separator':        ['#3C3C434A', '#545458A6'],
  'accent/blue':      ['#007AFFFF', '#0A84FFFF'],
  'accent/blue-bg':   ['#007AFF24', '#0A84FF38'],
  'accent/orange':    ['#FF9500FF', '#FF9F0AFF'],
  'accent/red':       ['#FF3B30FF', '#FF453AFF'],
  'accent/red-bg':    ['#FF3B3024', '#FF453A38'],
  'accent/green':     ['#34C759FF', '#30D158FF'],
  'scrim':            ['#00000024', '#00000066'],
};

/** 收敛后的数值令牌。与 tokens.js 保持一致（Figma 插件不支持 require）。 */
const SCALE = {
  // — spacing：8pt 网格，7 档 —
  'space/4': 4, 'space/8': 8, 'space/12': 12, 'space/16': 16,
  'space/20': 20, 'space/24': 24, 'space/32': 32,
  // — radius：4 档 + capsule —
  'radius/xs': 4, 'radius/sm': 8, 'radius/md': 12, 'radius/lg': 16, 'radius/full': 999,
  // — icon：3 档通用 —
  'icon/sm': 16, 'icon/md': 20, 'icon/lg': 24,
  // — row —
  'row/standard': 44, 'row/two-line': 56,
  // — motion（秒）—
  'duration/fast': 0.2, 'duration/normal': 0.3,
  // — 系统几何值：iOS 规定，不参与收敛 —
  'system/tap-min': 44, 'system/nav-height': 44, 'system/toolbar-height': 49,
  'system/status-height': 54, 'system/home-indicator': 34, 'system/device-radius': 47,
  'system/screen-w': 393, 'system/screen-h': 852,
};

/** 组件专属视觉锚点：有意保留的非网格值。检查器读取此表做豁免。 */
const ANCHOR = { 34: '音频播放按钮', 52: '空状态插画', 38: '文件夹图标底板', 9: '未读圆点', 14: '置顶图标' };

const TYPE = {
  'iOS/LargeTitle':             [34, 41, 'b',  -2.0],
  'iOS/Title1':                 [28, 34, 'b',  -1.6],
  'iOS/Title2':                 [22, 28, 'b',  -1.4],
  'iOS/Title3':                 [20, 25, 'sb', -1.2],
  'iOS/Headline':               [17, 22, 'sb', -0.6],
  'iOS/Body':                   [17, 25, 'r',  -0.6],
  'iOS/Callout':                [16, 21, 'r',  -0.4],
  'iOS/Subheadline':            [15, 20, 'r',   0],
  'iOS/Subheadline Emphasized': [15, 20, 'sb',  0],
  'iOS/Footnote':               [13, 18, 'r',   0],
  'iOS/Footnote Emphasized':    [13, 18, 'sb',  0],
  'iOS/Caption1':               [12, 16, 'r',   0],
  'iOS/Caption1 Emphasized':    [12, 16, 'sb',  0],
  'iOS/Caption2':               [11, 14, 'r',   0],
  'iOS/Caption2 Emphasized':    [11, 14, 'sb',  0],
};

// elevation/fab 已随 D-01 删除
const EFFECTS = {
  'elevation/menu': [{ type: 'DROP_SHADOW', color: { r: 0, g: 0, b: 0, a: 0.26 },
                       offset: { x: 0, y: 12 }, radius: 44, spread: 0, visible: true, blendMode: 'NORMAL' }],
  'elevation/drag': [{ type: 'DROP_SHADOW', color: { r: 0, g: 0, b: 0, a: 0.18 },
                       offset: { x: 0, y: 4 }, radius: 12, spread: 0, visible: true, blendMode: 'NORMAL' }],
};

const FOLDER_COLORS = { work: '#0A84FF', book: '#FF9F0A', idea: '#30D158', trip: '#5E5CE6' };

// =============================================================== 2. 图标路径

const ICONS = {
  gear: '<circle cx="12" cy="12" r="3.2"/><path d="M19.4 15a1.6 1.6 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.6 1.6 0 0 0-1.8-.3 1.6 1.6 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1A1.6 1.6 0 0 0 9 19.4a1.6 1.6 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.6 1.6 0 0 0 .3-1.8 1.6 1.6 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1A1.6 1.6 0 0 0 4.6 9a1.6 1.6 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.6 1.6 0 0 0 1.8.3H9a1.6 1.6 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.6 1.6 0 0 0 1 1.5 1.6 1.6 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.6 1.6 0 0 0-.3 1.8V9a1.6 1.6 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.6 1.6 0 0 0-1.5 1z"/>',
  search: '<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.9-3.9"/>',
  pencil: '<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>',
  compose: '<path d="M19 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2h7"/><path d="M17.5 3.5a2.1 2.1 0 0 1 3 3L12 15l-4 1 1-4z"/>',
  chevronR: '<path d="M9 5l7 7-7 7"/>',
  chevronD: '<path d="M5 9l7 7 7-7"/>',
  chevronU: '<path d="M19 15l-7-7-7 7"/>',
  back: '<path d="M15 5l-7 7 7 7"/>',
  pin: '<path d="M12 17v5"/><path d="M9 3h6l-1 6 3 3v2H7v-2l3-3z"/>',
  dots: '<circle cx="5" cy="12" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="19" cy="12" r="1.5"/>',
  sparkle: '<path d="M12 3l1.9 5.1L19 10l-5.1 1.9L12 17l-1.9-5.1L5 10l5.1-1.9z"/><path d="M18.5 15.5l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8z"/>',
  camera: '<path d="M3 8h3.5L8 5.5h8L17.5 8H21v11H3z"/><circle cx="12" cy="13.5" r="3.6"/>',
  mic: '<rect x="9" y="2.5" width="6" height="11.5" rx="3"/><path d="M5 11.5a7 7 0 0 0 14 0"/><path d="M12 18.5V22"/>',
  doc: '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/>',
  link: '<path d="M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7"/><path d="M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7L12.2 19"/>',
  tag: '<path d="M20.6 13.4l-7.2 7.2a2 2 0 0 1-2.8 0l-7.2-7.2a2 2 0 0 1-.6-1.4V4a1 1 0 0 1 1-1h8a2 2 0 0 1 1.4.6l7.4 7.4a2 2 0 0 1 0 2.8z"/><circle cx="7.5" cy="7.5" r="1.3"/>',
  plus: '<path d="M12 5v14"/><path d="M5 12h14"/>',
  play: '<path d="M7 4.5l12 7.5-12 7.5z"/>',
  pause: '<rect x="6" y="4" width="4" height="16" rx="1"/><rect x="14" y="4" width="4" height="16" rx="1"/>',
  folder: '<path d="M3 7a2 2 0 0 1 2-2h4l2 2.5h8a2 2 0 0 1 2 2V18a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
  photo: '<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="8.5" cy="10" r="1.8"/><path d="M21 16l-5-5-6.5 8"/>',
  wave: '<path d="M4 10v4M8 6v12M12 3v18M16 7v10M20 10v4"/>',
  trash: '<path d="M4 6h16"/><path d="M9 6V4h6v2"/><path d="M6 6l1 14h10l1-14"/>',
  share: '<path d="M12 15V3"/><path d="M8 7l4-4 4 4"/><path d="M4 13v6a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-6"/>',
  refresh: '<path d="M20 11a8 8 0 1 0-1.2 5"/><path d="M20 5v6h-6"/>',
  book: '<path d="M4 4.5A2.5 2.5 0 0 1 6.5 2H20v18H6.5A2.5 2.5 0 0 0 4 22z"/>',
  briefcase: '<rect x="2.5" y="7" width="19" height="13" rx="2"/><path d="M8.5 7V5a2 2 0 0 1 2-2h3a2 2 0 0 1 2 2v2"/>',
  bulb: '<path d="M9.5 18h5"/><path d="M10 21.5h4"/><path d="M12 2.5a6 6 0 0 0-3.5 10.9V15h7v-1.6A6 6 0 0 0 12 2.5z"/>',
  grip: '<path d="M4 8h16M4 12h16M4 16h16"/>',
  check: '<path d="M4 12.5l5 5L20 6.5"/>',
  warning: '<path d="M12 3L1.5 21h21z"/><path d="M12 10v5"/><path d="M12 18h.01"/>',
  xmark: '<path d="M6 6l12 12M18 6L6 18"/>',
  ellipsisCircle: '<circle cx="12" cy="12" r="9"/><circle cx="8" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="16" cy="12" r="1"/>',
  bold: '<path d="M7 4h7a4 4 0 0 1 0 8H7z"/><path d="M7 12h8a4 4 0 0 1 0 8H7z"/>',
  italic: '<path d="M15 4h-6"/><path d="M15 20H9"/><path d="M14 4l-4 16"/>',
};

// =============================================================== 3. 全局状态

const W = SCALE['system/screen-w'], H = SCALE['system/screen-h'];
const NOTE_MAIN_W = 275;  // 393 − 左右 20 内边距 − 12 间距 − 右侧时间列约 66（ACCESS-004 将改为自适应）

/* Search 文案常量 —— 见 design/SEARCH_CONTRACT.md
 *
 * 用户侧禁用词表：embedding / 向量 / 余弦 / RRF / fusion / chunk / Recall@K / MRR /
 * rerank / top-k / index / config version / contentHash / stale。
 * 下面每一条文案都必须能通过这张表（Gate C3 会检）。 */
const SEARCH_PLACEHOLDER = '搜索关键词，或描述你记得的内容';
const SEARCH_QUERY = '延期毕业';
/** 自然语言 query —— 与笔记正文几乎不共享词汇，keyword 通道返回 0 条。 */
const SEARCH_QUERY_NL = '我之前问学校能不能晚一点毕业的事情';

/**
 * 各变体的「本体文案」。
 *
 * Figma 的 TEXT 组件属性**全变体共用一个默认值** —— 实例只要不显式赋值，
 * 拿到的就是那一个默认值，而不是自己变体里写的那句。所以凡是变体间文案不同的
 * 组件，实例助手必须把本体文案显式写回去。checks.text-prop 守这条。
 */
const NOTE_PREVIEW_TEXT = {
  'ai-summary': 'AI 生成的一句话概述，最多显示两行，超出的部分会自动截断并显示省略号',
  'text': '正文首行的纯文本预览，不含任何 Markdown 标记，最多两行后截断',
  'audio': '1 段录音',
  'image': '3 张图片',
  'empty': '空笔记',
};
/** buildComponents 里回填，供 iSummaryBar 兜底使用。 */
const SUMMARY_TEXT = {};

/** idle 态的自然语言示例。教会用户「这个框不止能搜关键词」的唯一时机。 */
const SEARCH_EXAMPLES = [
  '我之前问学校能不能晚一点毕业的事情',
  '老师 demo 要准备什么',
  '之前说过图片加载失败怎么办',
];

/** RetrievalCapability 的用户侧投影。progress 百分比不做 —— PRD 未定义（Correction 3）。 */
const SEARCH_STATUS_SPEC = {
  building:   { icon: 'refresh', msg: '正在准备智能搜索…',              cta: null },
  rebuilding: { icon: 'refresh', msg: '正在更新搜索数据…',              cta: null },
  degraded:   { icon: 'warning', msg: '智能搜索暂不可用，已按关键词搜索', cta: '重试' },
  offline:    { icon: 'warning', msg: '离线中，已按关键词搜索',          cta: null },
};

let FONT = null;
let COL_C = null, MODE_L = null, MODE_D = null;
let COL_S = null, MODE_S = null;
const V = {}, N = {}, TS = {}, ES = {}, C = {}, P = {}, ICON_COMP = {};
let PG = {};

// =============================================================== 4. 字体

const FONT_CANDIDATES = [
  { family: 'PingFang SC', r: 'Regular', m: 'Medium', sb: 'Semibold', b: 'Semibold' },
  { family: 'SF Pro Text', r: 'Regular', m: 'Medium', sb: 'Semibold', b: 'Bold' },
  { family: 'SF Pro',      r: 'Regular', m: 'Medium', sb: 'Semibold', b: 'Bold' },
  { family: 'Inter',       r: 'Regular', m: 'Medium', sb: 'Semi Bold', b: 'Bold' },
  { family: 'Roboto',      r: 'Regular', m: 'Medium', sb: 'Medium',    b: 'Bold' },
];

async function resolveFont() {
  for (const cand of FONT_CANDIDATES) {
    try {
      const styles = Array.from(new Set([cand.r, cand.m, cand.sb, cand.b]));
      for (const s of styles) await figma.loadFontAsync({ family: cand.family, style: s });
      return cand;
    } catch (e) { /* 下一个 */ }
  }
  throw new Error('找不到可用字体，请安装 PingFang SC / SF Pro Text / Inter 之一');
}
function fn(w) { return { family: FONT.family, style: FONT[w || 'r'] }; }

// =============================================================== 5. 颜色工具

function hexToRGBA(hex) {
  const s = hex.replace('#', '');
  const n = parseInt(s.slice(0, 6), 16);
  const a = s.length >= 8 ? parseInt(s.slice(6, 8), 16) / 255 : 1;
  return { r: ((n >> 16) & 255) / 255, g: ((n >> 8) & 255) / 255, b: (n & 255) / 255, a: a };
}
function paint(token) {
  if (V[token]) {
    return figma.variables.setBoundVariableForPaint(
      { type: 'SOLID', color: { r: 0, g: 0, b: 0 }, opacity: 1 }, 'color', V[token]);
  }
  const c = hexToRGBA(token);
  return { type: 'SOLID', color: { r: c.r, g: c.g, b: c.b }, opacity: c.a };
}
function litHex(token) { return COLORS[token] ? COLORS[token][0].slice(0, 7) : token; }

// =============================================================== 6. 变量 / 样式

function buildVariables() {
  try {
    figma.variables.getLocalVariableCollections()
      .filter(c => c.name === 'Mosaic Color' || c.name === 'Mosaic Scale')
      .forEach(c => c.remove());
  } catch (e) { }

  COL_C = figma.variables.createVariableCollection('Mosaic Color');
  MODE_L = COL_C.modes[0].modeId;
  COL_C.renameMode(MODE_L, 'Light');
  MODE_D = COL_C.addMode('Dark');
  Object.keys(COLORS).forEach(name => {
    const v = figma.variables.createVariable(name, COL_C, 'COLOR');
    v.setValueForMode(MODE_L, hexToRGBA(COLORS[name][0]));
    v.setValueForMode(MODE_D, hexToRGBA(COLORS[name][1]));
    V[name] = v;
  });

  COL_S = figma.variables.createVariableCollection('Mosaic Scale');
  MODE_S = COL_S.modes[0].modeId;
  COL_S.renameMode(MODE_S, 'Default');
  Object.keys(SCALE).forEach(name => {
    const v = figma.variables.createVariable(name, COL_S, 'FLOAT');
    v.setValueForMode(MODE_S, SCALE[name]);
    N[name] = v;
  });
}

function buildTextStyles() {
  try { figma.getLocalTextStyles().filter(s => s.name.indexOf('iOS/') === 0).forEach(s => s.remove()); } catch (e) { }
  Object.keys(TYPE).forEach(name => {
    const sp = TYPE[name];
    const st = figma.createTextStyle();
    st.name = name;
    st.fontName = fn(sp[2]);
    st.fontSize = sp[0];
    st.lineHeight = { unit: 'PIXELS', value: sp[1] };
    st.letterSpacing = { unit: 'PERCENT', value: sp[3] };
    TS[name] = st;
  });
}

function buildEffectStyles() {
  try { figma.getLocalEffectStyles().filter(s => s.name.indexOf('elevation/') === 0).forEach(s => s.remove()); } catch (e) { }
  Object.keys(EFFECTS).forEach(name => {
    const st = figma.createEffectStyle();
    st.name = name; st.effects = EFFECTS[name];
    ES[name] = st;
  });
}

function setMode(node, modeId) {
  try { node.setExplicitVariableModeForCollection(COL_C, modeId); }
  catch (e) { try { node.setExplicitVariableModeForCollection(COL_C.id, modeId); } catch (e2) { } }
}
function bindNum(node, field, token) {
  if (!N[token]) return;
  try { node.setBoundVariable(field, N[token]); } catch (e) { }
}

// =============================================================== 7. 布局助手

function conf(f, o) {
  o = o || {};
  f.name = o.name || f.name;
  const mode = o.dir === 'h' ? 'HORIZONTAL' : o.dir === 'none' ? 'NONE' : 'VERTICAL';
  f.layoutMode = mode;
  f.fills = o.fill ? [paint(o.fill)] : [];
  if (o.radius !== undefined) {
    f.cornerRadius = typeof o.radius === 'number' ? o.radius : SCALE[o.radius];
    if (typeof o.radius === 'string')
      ['topLeftRadius', 'topRightRadius', 'bottomLeftRadius', 'bottomRightRadius'].forEach(k => bindNum(f, k, o.radius));
  }
  f.clipsContent = o.clip === undefined ? false : o.clip;

  if (mode !== 'NONE') {
    const gapTok = typeof o.gap === 'string' ? o.gap : null;
    f.itemSpacing = gapTok ? SCALE[gapTok] : (o.gap || 0);
    if (gapTok) bindNum(f, 'itemSpacing', gapTok);
    f.primaryAxisAlignItems = o.main || 'MIN';
    f.counterAxisAlignItems = o.cross || 'MIN';
    const p = o.pad || [0, 0, 0, 0];
    const fields = ['paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft'];
    p.forEach((val, i) => {
      const tok = typeof val === 'string' ? val : null;
      f[fields[i]] = tok ? SCALE[tok] : val;
      if (tok) bindNum(f, fields[i], tok);
    });
    const wTok = typeof o.w === 'string', hTok = typeof o.h === 'string';
    const wv = wTok ? SCALE[o.w] : o.w, hv = hTok ? SCALE[o.h] : o.h;
    const wFixed = o.w !== undefined, hFixed = o.h !== undefined;
    if (mode === 'HORIZONTAL') {
      f.primaryAxisSizingMode = wFixed ? 'FIXED' : 'AUTO';
      f.counterAxisSizingMode = hFixed ? 'FIXED' : 'AUTO';
    } else {
      f.primaryAxisSizingMode = hFixed ? 'FIXED' : 'AUTO';
      f.counterAxisSizingMode = wFixed ? 'FIXED' : 'AUTO';
    }
    o._wv = wv; o._hv = hv; o._wTok = wTok; o._hTok = hTok;
  }

  (o.children || []).forEach(c => { if (c) f.appendChild(c); });

  if (o.w !== undefined || o.h !== undefined) {
    const wv = typeof o.w === 'string' ? SCALE[o.w] : o.w;
    const hv = typeof o.h === 'string' ? SCALE[o.h] : o.h;
    f.resize(wv !== undefined ? wv : Math.max(0.01, f.width), hv !== undefined ? hv : Math.max(0.01, f.height));
    if (typeof o.w === 'string') bindNum(f, 'width', o.w);
    if (typeof o.h === 'string') bindNum(f, 'height', o.h);
  }
  if (o.grow) f.layoutGrow = 1;
  if (o.stretch) f.layoutAlign = 'STRETCH';
  if (o.effect && ES[o.effect]) { try { f.effectStyleId = ES[o.effect].id; } catch (e) { f.effects = EFFECTS[o.effect]; } }
  if (o.strokeToken) { f.strokes = [paint(o.strokeToken)]; f.strokeWeight = o.strokeWeight || 0.5; }
  return f;
}
function F(o) { return conf(figma.createFrame(), o); }
function CMP(o) { return conf(figma.createComponent(), o); }

function T(chars, o) {
  o = o || {};
  const styleName = o.s || 'iOS/Body';
  const sp = TYPE[styleName] || TYPE['iOS/Body'];
  const t = figma.createText();
  t.name = o.name || chars.slice(0, 12) || 'Text';
  t.fontName = fn(sp[2]);
  t.fontSize = sp[0];
  t.lineHeight = { unit: 'PIXELS', value: sp[1] };
  t.letterSpacing = { unit: 'PERCENT', value: sp[3] };
  t.characters = chars;
  if (TS[styleName]) { try { t.textStyleId = TS[styleName].id; } catch (e) { } }
  t.fills = [paint(o.c || 'text/primary')];
  if (o.align) t.textAlignHorizontal = o.align;
  if (o.lines) { try { t.maxLines = o.lines; t.textTruncation = 'ENDING'; } catch (e) { } }
  // 定宽文本：
  //   · 给了 lines → 固定成「lines × 行高」的盒子。实测 Figma 在设了 maxLines 后，
  //     resize + textAutoResize='HEIGHT' 不会重算成多行（会停在 1 行），
  //     所以这里不依赖它的重算语义，直接把盒子高度算出来。
  //   · 没给 lines → 先定宽再交回自动高度。
  if (o.width !== undefined) {
    if (o.lines) t.resize(o.width, sp[1] * o.lines);
    else { t.resize(o.width, Math.max(1, t.height)); t.textAutoResize = 'HEIGHT'; }
  }
  else if (o.grow || o.stretch) t.textAutoResize = 'HEIGHT';
  else t.textAutoResize = 'WIDTH_AND_HEIGHT';
  if (o.grow) t.layoutGrow = 1;
  if (o.stretch) t.layoutAlign = 'STRETCH';
  return t;
}

function tint(node, token) {
  if ('strokes' in node && Array.isArray(node.strokes) && node.strokes.length)
    node.strokes = node.strokes.map(() => paint(token));
  if ('fills' in node && Array.isArray(node.fills) && node.fills.length)
    node.fills = node.fills.map(() => paint(token));
  if ('children' in node) node.children.forEach(c => tint(c, token));
}

function R(w, h, token, radius) {
  const r = figma.createRectangle();
  r.name = 'Shape';
  r.resize(Math.max(0.01, w), Math.max(0.01, h));
  r.fills = [paint(token)];
  if (radius !== undefined) {
    r.cornerRadius = typeof radius === 'number' ? radius : SCALE[radius];
    if (typeof radius === 'string')
      ['topLeftRadius', 'topRightRadius', 'bottomLeftRadius', 'bottomRightRadius'].forEach(k => bindNum(r, k, radius));
  }
  return r;
}
function spacer() { const f = F({ name: 'Spacer', w: 1, h: 1 }); f.layoutGrow = 1; return f; }
function hr(w) { const r = R(w === undefined ? W : w, 0.5, 'separator'); r.name = 'Separator'; return r; }
function abs(parent, node, x, y) {
  parent.appendChild(node);
  try { node.layoutPositioning = 'ABSOLUTE'; } catch (e) { }
  node.x = x; node.y = y;
  return node;
}
function setConstraintsScale(node) {
  if ('constraints' in node) { try { node.constraints = { horizontal: 'SCALE', vertical: 'SCALE' }; } catch (e) { } }
  if ('children' in node) node.children.forEach(setConstraintsScale);
}

/** 44pt 触控底板：视觉尺寸不变，hit area 撑到 HIG 最小值。 */
/** 行内 CTA 按钮：满足 44pt 触控高度。 */
function ctaBtn(label, destructive) {
  return F({
    name: 'CTA', dir: 'h', h: 'system/tap-min', cross: 'CENTER', main: 'CENTER',
    pad: [0, 'space/12', 0, 'space/12'], radius: 'radius/sm',
    fill: destructive ? 'accent/red-bg' : 'accent/blue-bg',
    children: [T(label, { s: 'iOS/Subheadline Emphasized', c: destructive ? 'accent/red' : 'accent/blue', name: 'CTA Label' })],
  });
}

function tappable(child, name) {
  return F({
    name: name || 'Tappable', w: 'system/tap-min', h: 'system/tap-min',
    main: 'CENTER', cross: 'CENTER', children: [child],
  });
}

function variantSet(name, keys, combos, build, parent) {
  const comps = combos.map(props => {
    const c = figma.createComponent();
    build(c, props);
    c.name = keys.map(k => k + '=' + props[k]).join(', ');
    return c;
  });
  const set = figma.combineAsVariants(comps, parent);
  set.name = name;
  conf(set, { dir: 'h', gap: 'space/24', pad: ['space/24', 'space/24', 'space/24', 'space/24'], name: name });
  return set;
}
function bindPropAll(set, nodeName, refField, propId) {
  set.children.forEach(variant => {
    const n = variant.findOne(x => x.name === nodeName);
    if (n) { const cur = n.componentPropertyReferences || {}; cur[refField] = propId; n.componentPropertyReferences = cur; }
  });
}
function bindProp(node, refField, propId) {
  if (!node) return;
  const cur = node.componentPropertyReferences || {};
  cur[refField] = propId;
  node.componentPropertyReferences = cur;
}

// =============================================================== 8. 图标组件集

function buildIconSet(page) {
  const names = Object.keys(ICONS);
  const comps = names.map(name => {
    const c = figma.createComponent();
    c.name = 'name=' + name;
    c.layoutMode = 'NONE'; c.fills = []; c.resize(24, 24);
    const filled = (name === 'play');
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" ' +
      'fill="' + (filled ? litHex('accent/blue') : 'none') + '" stroke="' + (filled ? 'none' : litHex('accent/blue')) +
      '" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">' + ICONS[name] + '</svg>';
    const g = figma.createNodeFromSvg(svg);
    g.children.slice().forEach(v => c.appendChild(v));
    setConstraintsScale(c);
    tint(c, 'accent/blue');
    g.remove();
    ICON_COMP[name] = c;
    return c;
  });
  const set = figma.combineAsVariants(comps, page);
  set.name = 'Icon';
  conf(set, { dir: 'h', gap: 'space/16', pad: ['space/20', 'space/20', 'space/20', 'space/20'], name: 'Icon' });
  C.icon = set;
  return set;
}

/** 图标实例。size 传 Token 名或字面量。 */
function ic(name, size, token) {
  const comp = ICON_COMP[name] || ICON_COMP.doc;
  const inst = comp.createInstance();
  inst.name = 'Icon / ' + name;
  const s = typeof size === 'string' ? SCALE[size] : (size || SCALE['icon/lg']);
  inst.resize(s, s);
  tint(inst, token || 'accent/blue');
  return inst;
}

// =============================================================== 9. 组件库

function buildComponents(page) {
  buildIconSet(page);

  // ---------------------------------------------------- 嵌套子组件（A-14）

  // Note / Preview —— 首页笔记行第二行内容，5 种来源
  C.notePreview = variantSet('Note / Preview', ['type'],
    [{ type: 'ai-summary' }, { type: 'text' }, { type: 'audio' }, { type: 'image' }, { type: 'empty' }],
    (c, p) => {
      let kids;
      const txt = NOTE_PREVIEW_TEXT[p.type];
      if (p.type === 'ai-summary') {
        kids = [T(txt, { s: 'iOS/Subheadline', c: 'text/secondary', lines: 2, width: NOTE_MAIN_W, name: 'Text' })];
      } else if (p.type === 'text') {
        kids = [T(txt, { s: 'iOS/Subheadline', c: 'text/tertiary', lines: 2, width: NOTE_MAIN_W, name: 'Text' })];
      } else if (p.type === 'audio') {
        kids = [F({ name: 'Row', dir: 'h', gap: 'space/4', cross: 'CENTER', children: [
          ic('wave', 'icon/sm', 'text/secondary'),
          T(txt, { s: 'iOS/Subheadline', c: 'text/secondary', name: 'Text' })] })];
      } else if (p.type === 'image') {
        kids = [F({ name: 'Row', dir: 'h', gap: 'space/4', cross: 'CENTER', children: [
          ic('photo', 'icon/sm', 'text/secondary'),
          T(txt, { s: 'iOS/Subheadline', c: 'text/secondary', name: 'Text' })] })];
      } else {
        kids = [T(txt, { s: 'iOS/Subheadline', c: 'text/tertiary', name: 'Text' })];
      }
      conf(c, { name: 'Preview', dir: 'v', w: NOTE_MAIN_W, children: kids });
    }, page);
  // 刻意**不给** Note / Preview 加 TEXT 属性。
  //
  // 事故记录（2026-08-07 第 4 轮实读）：原本有个 Text 属性，默认值 'AI 一句话概述'。
  // 结果首页两条 ai-summary 笔记行显示的都是这句默认值，而不是各自的摘要 ——
  // Preview 是**嵌套实例**，文本被属性绑定驱动，直接写 characters 会被默认值盖回去。
  // 这一点只在 ai-summary 行上暴露：它的 INSTANCE_SWAP 目标恰好等于属性默认值，
  // Figma 视作没换，绑定始终有效；其它几种预览因为发生了真实 swap 反而写得进去。
  //
  // 去掉属性 = 去掉绑定，直接写 characters 在所有情况下都成立
  // （`Block / Text` 的 Content 一直是这么写的，从没出过问题）。
  // 各变体本体文案见 NOTE_PREVIEW_TEXT，仍是 Figma 里的默认显示内容。

  // Note / AI Badge —— 首页 AI 任务指示（D-05：failed 不占主摘要区）
  C.noteAIBadge = variantSet('Note / AI Badge', ['state'],
    [{ state: 'none' }, { state: 'generating' }, { state: 'failed' }],
    (c, p) => {
      const kids = [];
      if (p.state === 'generating') kids.push(ic('sparkle', 'icon/sm', 'accent/blue'));
      if (p.state === 'failed') kids.push(ic('warning', 'icon/sm', 'accent/orange'));
      conf(c, { name: 'AI Badge', dir: 'h', w: p.state === 'none' ? 0.01 : SCALE['icon/sm'],
                h: SCALE['icon/sm'], main: 'CENTER', cross: 'CENTER', children: kids });
    }, page);

  // Audio / Transcript —— 转写显示状态（避免与播放态做 4×4 笛卡尔积）
  C.audioTranscript = variantSet('Audio / Transcript', ['state'],
    [{ state: 'none' }, { state: 'short' }, { state: 'collapsed' }, { state: 'expanded' }],
    (c, p) => {
      const kids = [];
      if (p.state !== 'none') {
        const lines = p.state === 'short' ? 2 : p.state === 'collapsed' ? 3 : 8;
        kids.push(T('「关于排期我们再确认一下，设计这边下周一给终稿，后端同步开始，预算部分等财务回复后再定。」',
          { s: 'iOS/Footnote', c: 'text/secondary', lines: lines, width: 329, name: 'Transcript' }));
        if (p.state === 'collapsed') kids.push(T('展开', { s: 'iOS/Footnote', c: 'accent/blue', name: 'Toggle' }));
        if (p.state === 'expanded') kids.push(T('收起', { s: 'iOS/Footnote', c: 'accent/blue', name: 'Toggle' }));
      }
      conf(c, { name: 'Transcript', dir: 'v', gap: 'space/4', w: 329,
                h: p.state === 'none' ? 0.01 : undefined, children: kids });
    }, page);

  // Form / Action Status —— 测试连接等动作行的状态
  C.formActionStatus = variantSet('Form / Action Status', ['state'],
    [{ state: 'idle' }, { state: 'testing' }, { state: 'success' }, { state: 'failure' }],
    (c, p) => {
      const kids = [];
      if (p.state === 'testing') kids.push(ic('refresh', 'icon/sm', 'text/secondary'));
      if (p.state === 'success') kids.push(ic('check', 'icon/sm', 'accent/green'));
      if (p.state === 'failure') kids.push(ic('xmark', 'icon/sm', 'accent/red'));
      conf(c, { name: 'Action Status', dir: 'h', w: p.state === 'idle' ? 0.01 : SCALE['icon/sm'],
                h: SCALE['icon/sm'], main: 'CENTER', cross: 'CENTER', children: kids });
    }, page);

  // ---------------------------------------------------- Chips

  C.chipFolder = variantSet('Chip / Folder', ['state'],
    [{ state: 'default' }, { state: 'selected' }, { state: 'more' }],
    (c, p) => {
      const sel = p.state === 'selected';
      const kids = [];
      if (p.state !== 'more') kids.push(R(14, 14, FOLDER_COLORS.work, 'radius/xs'));
      kids.push(T(p.state === 'more' ? '更多' : '文件夹',
        { s: 'iOS/Subheadline', c: sel ? 'text/on-accent' : 'text/primary', name: 'Label' }));
      if (p.state === 'more') kids.push(ic('chevronD', 'icon/sm', 'text/secondary'));
      conf(c, {
        name: 'Chip', dir: 'h', gap: 'space/4', h: 32, cross: 'CENTER',
        pad: [0, 'space/12', 0, 'space/12'], radius: 'radius/lg',
        fill: sel ? 'accent/blue' : 'bg/fill', children: kids,
      });
      if (p.state !== 'more') c.children[0].name = 'Dot';
    }, page);
  P.chipFolder = {
    Label: C.chipFolder.addComponentProperty('Label', 'TEXT', '文件夹'),
    Dot: C.chipFolder.addComponentProperty('Dot', 'BOOLEAN', true),
  };
  bindPropAll(C.chipFolder, 'Label', 'characters', P.chipFolder.Label);
  bindPropAll(C.chipFolder, 'Dot', 'visible', P.chipFolder.Dot);

  // Chip / Folder Meta —— 笔记内的归属入口（D-02）
  C.chipFolderMeta = variantSet('Chip / Folder Meta', ['state'],
    [{ state: 'assigned' }, { state: 'unassigned' }],
    (c, p) => {
      const un = p.state === 'unassigned';
      conf(c, {
        name: 'Folder Meta', dir: 'h', gap: 'space/4', cross: 'CENTER',
        pad: ['space/4', 'space/8', 'space/4', 'space/8'], radius: 'radius/full',
        fill: un ? 'bg/fill' : 'accent/blue-bg', children: [
          ic('folder', 'icon/sm', un ? 'text/secondary' : 'accent/blue'),
          T(un ? '未归类' : '工作', { s: 'iOS/Caption1', c: un ? 'text/secondary' : 'accent/blue', name: 'Label' }),
          ic('chevronD', 'icon/sm', un ? 'text/secondary' : 'accent/blue'),
        ],
      });
    }, page);
  P.chipFolderMeta = { Label: C.chipFolderMeta.addComponentProperty('Label', 'TEXT', '工作') };
  bindPropAll(C.chipFolderMeta, 'Label', 'characters', P.chipFolderMeta.Label);

  C.chipTag = variantSet('Chip / Tag', ['state'],
    [{ state: 'default' }, { state: 'selected' }],
    (c, p) => {
      const sel = p.state === 'selected';
      conf(c, {
        name: 'Tag', dir: 'h', pad: ['space/4', 'space/8', 'space/4', 'space/8'], radius: 'radius/full',
        fill: sel ? 'accent/blue' : 'accent/blue-bg',
        children: [T('标签', { s: 'iOS/Caption1', c: sel ? 'text/on-accent' : 'accent/blue', name: 'Label' })],
      });
    }, page);
  P.chipTag = { Label: C.chipTag.addComponentProperty('Label', 'TEXT', '标签') };
  bindPropAll(C.chipTag, 'Label', 'characters', P.chipTag.Label);

  // Chip / Topic —— added 用「实心 + checkmark」，不只靠颜色（D-06 / ACCESS-002）
  C.chipTopic = variantSet('Chip / Topic', ['state'],
    [{ state: 'default' }, { state: 'added' }],
    (c, p) => {
      const added = p.state === 'added';
      const kids = [];
      if (added) kids.push(ic('check', 'icon/sm', 'text/on-accent'));
      kids.push(T('主题', { s: 'iOS/Caption1', c: added ? 'text/on-accent' : 'accent/blue', name: 'Label' }));
      const c2 = conf(c, {
        name: 'Topic', dir: 'h', gap: 'space/4', cross: 'CENTER',
        pad: ['space/4', 'space/8', 'space/4', 'space/8'], radius: 'radius/full',
        fill: added ? 'accent/blue' : undefined, children: kids,
      });
      if (!added) { c2.strokes = [paint('accent/blue')]; c2.strokeWeight = 1; }
    }, page);
  P.chipTopic = { Label: C.chipTopic.addComponentProperty('Label', 'TEXT', '主题') };
  bindPropAll(C.chipTopic, 'Label', 'characters', P.chipTopic.Label);

  // ---------------------------------------------------- Rows

  // Row / Note —— 主件 0 变体，靠嵌套 + 布尔组合（§6.2）
  const npInst = C.notePreview.children[0].createInstance(); npInst.name = 'Preview';
  const abInst = C.noteAIBadge.children[0].createInstance(); abInst.name = 'AI Badge';
  const pinIcon = ic('pin', 14, 'accent/orange'); pinIcon.name = 'Pin';
  const unreadDot = F({ name: 'Unread', w: 9, h: 9, radius: 'radius/full', fill: 'accent/red' });

  C.rowNote = CMP({
    name: 'Row / Note', dir: 'v', w: 'system/screen-w', cross: 'MAX', children: [
      F({ name: 'Content', dir: 'h', gap: 'space/12', w: 'system/screen-w', main: 'SPACE_BETWEEN',
          pad: ['space/12', 'space/20', 'space/12', 'space/20'], children: [
        F({ name: 'Main', dir: 'v', gap: 'space/4', w: NOTE_MAIN_W, children: [
          F({ name: 'TitleRow', dir: 'h', gap: 'space/4', cross: 'CENTER', w: NOTE_MAIN_W, children: [
            pinIcon, T('笔记标题', { s: 'iOS/Headline', lines: 1, grow: 1, name: 'Title' })] }),
          npInst,
        ] }),
        F({ name: 'Meta', dir: 'v', gap: 'space/8', cross: 'MAX', pad: ['space/4', 0, 0, 0], children: [
          T('刚刚', { s: 'iOS/Subheadline', c: 'text/secondary', name: 'Time' }),
          F({ name: 'Indicators', dir: 'h', gap: 'space/4', cross: 'CENTER', children: [abInst, unreadDot] }),
        ] }),
      ] }),
      hr(W - 20),
    ],
  });
  P.rowNote = {
    Title:      C.rowNote.addComponentProperty('Title', 'TEXT', '笔记标题'),
    Time:       C.rowNote.addComponentProperty('Time', 'TEXT', '刚刚'),
    Preview:    C.rowNote.addComponentProperty('Preview', 'INSTANCE_SWAP', C.notePreview.children[0].id),
    AIBadge:    C.rowNote.addComponentProperty('AI State', 'INSTANCE_SWAP', C.noteAIBadge.children[0].id),
    ShowPin:    C.rowNote.addComponentProperty('Show Pin', 'BOOLEAN', false),
    ShowUnread: C.rowNote.addComponentProperty('Show Unread', 'BOOLEAN', false),
  };
  bindProp(C.rowNote.findOne(n => n.name === 'Title'), 'characters', P.rowNote.Title);
  bindProp(C.rowNote.findOne(n => n.name === 'Time'), 'characters', P.rowNote.Time);
  bindProp(C.rowNote.findOne(n => n.name === 'Preview'), 'mainComponent', P.rowNote.Preview);
  bindProp(C.rowNote.findOne(n => n.name === 'AI Badge'), 'mainComponent', P.rowNote.AIBadge);
  bindProp(C.rowNote.findOne(n => n.name === 'Pin'), 'visible', P.rowNote.ShowPin);
  bindProp(C.rowNote.findOne(n => n.name === 'Unread'), 'visible', P.rowNote.ShowUnread);
  page.appendChild(C.rowNote);

  // Row / Folder —— trailing 是真实结构差异；dragging 用布尔
  C.rowFolder = variantSet('Row / Folder', ['trailing'],
    [{ trailing: 'chevron' }, { trailing: 'grip' }],
    (c, p) => {
      const folderIcon = ic('briefcase', 'icon/md', 'text/on-accent');
      folderIcon.name = 'Folder Icon';
      const badge = F({ name: 'Badge', w: 38, h: 38, radius: 'radius/sm', main: 'CENTER', cross: 'CENTER',
                        fill: FOLDER_COLORS.work, children: [folderIcon] });
      conf(c, {
        name: 'Folder Row', dir: 'h', gap: 'space/12', w: W - 32, cross: 'CENTER',
        pad: ['space/12', 'space/16', 'space/12', 'space/16'], children: [
          badge,
          F({ name: 'Text', dir: 'v', gap: 'space/4', grow: 1, children: [
            T('文件夹', { s: 'iOS/Body', name: 'Name' }),
            T('0 张笔记', { s: 'iOS/Caption1', c: 'text/secondary', name: 'Count' })] }),
          p.trailing === 'grip' ? ic('grip', 'icon/md', 'text/secondary') : ic('chevronR', 'icon/sm', 'text/tertiary'),
        ],
      });
    }, page);
  P.rowFolder = {
    Name: C.rowFolder.addComponentProperty('Name', 'TEXT', '文件夹'),
    Count: C.rowFolder.addComponentProperty('Count', 'TEXT', '0 张笔记'),
    Icon: C.rowFolder.addComponentProperty('Icon', 'INSTANCE_SWAP', ICON_COMP.briefcase.id),
  };
  bindPropAll(C.rowFolder, 'Name', 'characters', P.rowFolder.Name);
  bindPropAll(C.rowFolder, 'Count', 'characters', P.rowFolder.Count);
  bindPropAll(C.rowFolder, 'Folder Icon', 'mainComponent', P.rowFolder.Icon);

  // Row / Form —— 4 个结构性变体；disabled/destructive/toggle 用布尔；状态用嵌套
  C.rowForm = variantSet('Row / Form', ['type'],
    [{ type: 'value' }, { type: 'chevron' }, { type: 'toggle' }, { type: 'action' }],
    (c, p) => {
      const right = [];
      if (p.type === 'value' || p.type === 'chevron') right.push(T('值', { s: 'iOS/Body', c: 'text/secondary', name: 'Value' }));
      if (p.type === 'chevron') right.push(ic('chevronR', 'icon/sm', 'text/tertiary'));
      if (p.type === 'toggle') {
        right.push(F({ name: 'Toggle', dir: 'h', w: 51, h: 31, radius: 'radius/lg', cross: 'CENTER',
                       main: 'MAX', pad: [2, 2, 2, 2], fill: 'accent/green', children: [R(27, 27, '#FFFFFF', 'radius/full')] }));
      }
      if (p.type === 'action') {
        const st = C.formActionStatus.children[0].createInstance(); st.name = 'Action Status';
        right.push(st);
      }
      conf(c, {
        name: 'Form Row', dir: 'h', w: W - 32, h: 'row/standard',
        main: p.type === 'action' ? 'CENTER' : 'SPACE_BETWEEN', cross: 'CENTER',
        pad: [0, 'space/16', 0, 'space/16'], children: [
          T('标签', { s: 'iOS/Body', c: p.type === 'action' ? 'accent/blue' : 'text/primary', name: 'Label' }),
          right.length ? F({ name: 'Right', dir: 'h', gap: 'space/4', cross: 'CENTER', children: right }) : null,
        ].filter(Boolean),
      });
    }, page);
  P.rowForm = {
    Label: C.rowForm.addComponentProperty('Label', 'TEXT', '标签'),
    Value: C.rowForm.addComponentProperty('Value', 'TEXT', '值'),
    Status: C.rowForm.addComponentProperty('Action Status', 'INSTANCE_SWAP', C.formActionStatus.children[0].id),
  };
  bindPropAll(C.rowForm, 'Label', 'characters', P.rowForm.Label);
  bindPropAll(C.rowForm, 'Value', 'characters', P.rowForm.Value);
  bindPropAll(C.rowForm, 'Action Status', 'mainComponent', P.rowForm.Status);

  C.menuItem = variantSet('Row / Menu Item', ['type'],
    [{ type: 'default' }, { type: 'destructive' }],
    (c, p) => {
      const del = p.type === 'destructive';
      conf(c, {
        name: 'Menu Item', dir: 'h', w: 255, h: 'row/standard', main: 'SPACE_BETWEEN', cross: 'CENTER',
        pad: [0, 'space/16', 0, 'space/16'],
        children: [T('菜单项', { s: 'iOS/Body', c: del ? 'accent/red' : 'text/primary', name: 'Label' }),
                   ic('doc', 'icon/md', del ? 'accent/red' : 'text/primary')],
      });
      c.children[1].name = 'Trailing Icon';
    }, page);
  P.menuItem = {
    Label: C.menuItem.addComponentProperty('Label', 'TEXT', '菜单项'),
    Icon: C.menuItem.addComponentProperty('Icon', 'INSTANCE_SWAP', ICON_COMP.doc.id),
  };
  bindPropAll(C.menuItem, 'Label', 'characters', P.menuItem.Label);
  bindPropAll(C.menuItem, 'Trailing Icon', 'mainComponent', P.menuItem.Icon);

  // ---------------------------------------------------- Navigation

  C.barStatus = CMP({
    name: 'Bar / Status', dir: 'h', w: 'system/screen-w', h: 'system/status-height',
    main: 'SPACE_BETWEEN', cross: 'MAX', pad: [0, 'space/32', 'space/8', 'space/32'],
    children: [T('9:41', { s: 'iOS/Subheadline Emphasized' }), T('▮▮▮ ◗', { s: 'iOS/Caption1' })],
  });
  abs(C.barStatus, R(125, 36, '#000000', 'radius/lg'), (W - 125) / 2, 11).name = 'Dynamic Island';
  page.appendChild(C.barStatus);

  // Bar / Nav —— 无变体：标题 + 左右图标全部走属性（D-02 后不再有 folder 变体）
  const navLead = tappable(ic('back', 'icon/lg', 'accent/blue'), 'Leading');
  const navTrail = tappable(ic('dots', 'icon/lg', 'accent/blue'), 'Trailing');
  C.barNav = CMP({
    name: 'Bar / Nav', dir: 'h', w: 'system/screen-w', h: 'system/nav-height', cross: 'CENTER',
    pad: [0, 'space/8', 0, 'space/8'], children: [
      navLead,
      F({ name: 'Middle', dir: 'h', gap: 'space/4', cross: 'CENTER', main: 'CENTER', grow: 1,
          children: [T('标题', { s: 'iOS/Headline', name: 'Title' })] }),
      navTrail,
    ],
  });
  P.barNav = {
    Title:        C.barNav.addComponentProperty('Title', 'TEXT', '标题'),
    Leading:      C.barNav.addComponentProperty('Leading', 'INSTANCE_SWAP', ICON_COMP.back.id),
    Trailing:     C.barNav.addComponentProperty('Trailing', 'INSTANCE_SWAP', ICON_COMP.dots.id),
    ShowLeading:  C.barNav.addComponentProperty('Show Leading', 'BOOLEAN', true),
    ShowTrailing: C.barNav.addComponentProperty('Show Trailing', 'BOOLEAN', true),
  };
  bindProp(C.barNav.findOne(n => n.name === 'Title'), 'characters', P.barNav.Title);
  bindProp(C.barNav.findOne(n => n.name === 'Leading'), 'visible', P.barNav.ShowLeading);
  bindProp(C.barNav.findOne(n => n.name === 'Trailing'), 'visible', P.barNav.ShowTrailing);
  bindProp(navLead.findOne(n => n.name && n.name.indexOf('Icon /') === 0), 'mainComponent', P.barNav.Leading);
  bindProp(navTrail.findOne(n => n.name && n.name.indexOf('Icon /') === 0), 'mainComponent', P.barNav.Trailing);
  page.appendChild(C.barNav);

  // Bar / Bottom —— D-01：取代 FAB 的原生底部工具栏
  C.barBottom = CMP({
    name: 'Bar / Bottom', dir: 'h', w: 'system/screen-w', h: 'system/toolbar-height',
    main: 'SPACE_BETWEEN', cross: 'CENTER', pad: [0, 'space/8', 0, 'space/8'], fill: 'bg/card',
    children: [spacer(), tappable(ic('compose', 'icon/lg', 'accent/blue'), 'Compose')],
  });
  page.appendChild(C.barBottom);

  // Bar / Toolbar —— D-03：单层自适应，聚焦时媒体插入仍可达
  C.barToolbar = variantSet('Bar / Toolbar', ['mode'],
    [{ mode: 'insert' }, { mode: 'adaptive' }],
    (c, p) => {
      let kids;
      if (p.mode === 'insert') {
        kids = [
          F({ name: 'Insert Actions', dir: 'h', gap: 'space/8', cross: 'CENTER', children: [
            tappable(ic('camera', 'icon/lg'), 'Camera'), tappable(ic('mic', 'icon/lg'), 'Audio'),
            tappable(ic('doc', 'icon/lg'), 'Document'), tappable(ic('link', 'icon/lg'), 'Link')] }),
          tappable(ic('tag', 'icon/lg'), 'Tag'),
        ];
      } else {
        // ＋ 收纳媒体插入；B / I / • 为高频 Markdown；… 为次级格式 overflow
        kids = [
          F({ name: 'Editing Actions', dir: 'h', gap: 'space/4', cross: 'CENTER', children: [
            tappable(ic('plus', 'icon/lg'), 'Media Insert'),
            tappable(ic('bold', 'icon/lg'), 'Bold'), tappable(ic('italic', 'icon/lg'), 'Italic'),
            tappable(ic('ellipsisCircle', 'icon/lg'), 'More Format')] }),
          tappable(ic('tag', 'icon/lg'), 'Tag'),
        ];
      }
      conf(c, {
        name: 'Toolbar', dir: 'h', w: 'system/screen-w', h: 'system/toolbar-height',
        main: 'SPACE_BETWEEN', cross: 'CENTER', pad: [0, 'space/8', 0, 'space/8'],
        fill: 'bg/card', children: kids,
      });
    }, page);

  C.barHome = CMP({
    name: 'Bar / Home Indicator', w: 'system/screen-w', h: 'system/home-indicator',
    main: 'CENTER', cross: 'CENTER', children: [R(139, 5, 'text/primary', 'radius/xs')],
  });
  page.appendChild(C.barHome);

  // ---------------------------------------------------- AI（Batch A 仅 default）

  // ---- Bar / Summary —— 9 个真实业务状态（见 REMEDIATION_PLAN §7.1）----
  // 单一维度、每态都对应一个真实触发条件，属合理 Variant，不做嵌套拆分。
  const SUMMARY_STATES = [
    { k: 'hidden',           icon: null,      text: '',                          c: 'text/tertiary', cta: null },
    { k: 'pending',          icon: 'sparkle', text: '退出后将自动生成总结',        c: 'text/tertiary', cta: null },
    { k: 'generating',       icon: 'refresh', text: 'AI 正在总结…',               c: 'text/secondary', cta: null },
    { k: 'success',          icon: 'sparkle', text: 'AI 一句话概述',              c: 'text/secondary', cta: null },
    { k: 'success-unread',   icon: 'sparkle', text: 'AI 一句话概述',              c: 'text/secondary', cta: null, dot: true },
    { k: 'error-auth',       icon: 'warning', text: 'API Key 无效或未配置',       c: 'text/primary',   cta: '去设置', tone: 'warn' },
    { k: 'error-network',    icon: 'warning', text: '网络连接失败',               c: 'text/primary',   cta: '重试',   tone: 'warn' },
    { k: 'error-rate-limit', icon: 'warning', text: '调用频率超限，请稍后重试',    c: 'text/primary',   cta: '重试',   tone: 'warn' },
    { k: 'error-content',    icon: null,      text: '内容太少，暂无可总结的内容',  c: 'text/secondary', cta: null },
  ];
  SUMMARY_STATES.forEach(x => { SUMMARY_TEXT[x.k] = x.text; });
  C.barSummary = variantSet('Bar / Summary', ['state'],
    SUMMARY_STATES.map(x => ({ state: x.k })),
    (c, p) => {
      const spec = SUMMARY_STATES.find(x => x.k === p.state);
      if (spec.k === 'hidden') {
        conf(c, { name: 'Summary Bar', dir: 'v', w: 'system/screen-w', h: 0.01 });
        return;
      }
      const row = [];
      if (spec.dot) row.push(F({ name: 'Unread', w: 9, h: 9, radius: 'radius/full', fill: 'accent/red' }));
      if (spec.icon) row.push(ic(spec.icon, 'icon/md', spec.tone === 'warn' ? 'accent/orange' : 'accent/blue'));
      row.push(T(spec.text, { s: 'iOS/Subheadline', c: spec.c, lines: 1, grow: 1, name: 'Text' }));
      if (spec.cta) {
        row.push(F({ name: 'CTA', dir: 'h', h: 'system/tap-min', cross: 'CENTER', main: 'CENTER',
          pad: [0, 'space/12', 0, 'space/12'], radius: 'radius/sm', fill: 'accent/blue-bg',
          children: [T(spec.cta, { s: 'iOS/Subheadline Emphasized', c: 'accent/blue', name: 'CTA Label' })] }));
      } else if (spec.k === 'success' || spec.k === 'success-unread') {
        row.push(ic('chevronD', 'icon/sm', 'text/secondary'));
      }
      conf(c, {
        name: 'Summary Bar', dir: 'v', w: 'system/screen-w', children: [
          F({ name: 'Content', dir: 'h', gap: 'space/8', w: 'system/screen-w', h: 'row/standard', cross: 'CENTER',
              pad: [0, 'space/16', 0, 'space/16'], fill: spec.tone === 'warn' ? 'accent/red-bg' : 'bg/card', children: row }),
          hr(W),
        ],
      });
    }, page);
  P.barSummary = { Text: C.barSummary.addComponentProperty('Text', 'TEXT', 'AI 一句话概述') };
  bindPropAll(C.barSummary, 'Text', 'characters', P.barSummary.Text);

  const bullet = txt => F({ name: 'Point', dir: 'h', gap: 'space/4',
    children: [T('•', { s: 'iOS/Subheadline', c: 'text/secondary' }), T(txt, { s: 'iOS/Subheadline' })] });
  const topicInst = added => { const i = C.chipTopic.children[added ? 1 : 0].createInstance(); i.name = 'Topic / state=' + (added ? 'added' : 'default'); return i; };
  const logCard = () => F({ name: 'Log', dir: 'v', gap: 'space/4', w: W - 32,
    pad: ['space/8', 'space/8', 'space/8', 'space/8'], radius: 'radius/sm', fill: 'bg/fill', children: [
      T('补充了预算讨论部分', { s: 'iOS/Subheadline Emphasized' }),
      T('· 新增一段 42 秒录音及转写', { s: 'iOS/Caption1', c: 'text/secondary' }),
      T('2026-08-06 16:02', { s: 'iOS/Caption2', c: 'text/secondary' })] });

  C.panelSummary = variantSet('Panel / Summary', ['logCount'],
    [{ logCount: '0' }, { logCount: '1' }, { logCount: 'many' }],
    (c, p) => {
      const kids = [
        F({ name: 'Header', dir: 'h', gap: 'space/8', cross: 'CENTER', w: W - 32, children: [
          ic('sparkle', 'icon/md', 'accent/blue'),
          T('初始总结', { s: 'iOS/Caption1 Emphasized', c: 'text/secondary' }), spacer(),
          T('kimi-k2.6 · 08-06 14:30', { s: 'iOS/Caption2', c: 'text/secondary' }),
          ic('chevronU', 'icon/sm', 'text/secondary')] }),
        F({ name: 'Topics', dir: 'h', gap: 'space/4', cross: 'CENTER',
            children: [topicInst(true), topicInst(false), topicInst(false)] }),
        T('点主题即加为标签（已加的显示 ✓）', { s: 'iOS/Caption2', c: 'text/secondary' }),
        F({ name: 'Key Points', dir: 'v', gap: 'space/4', children: [
          bullet('确定下周三上线，设计先给终稿'), bullet('新增三位负责人，各自认领模块')] }),
        T('本次评审围绕 Q3 排期与人力分工展开，确认了下周三的上线时间点与三位模块负责人。',
          { s: 'iOS/Subheadline', width: W - 32 }),
      ];
      if (p.logCount !== '0') {
        kids.push(hr(W - 32));
        kids.push(F({ name: 'Logs Header', dir: 'h', cross: 'CENTER', w: W - 32, children: [
          T(p.logCount === '1' ? '更新记录 (1)' : '更新记录 (3)', { s: 'iOS/Caption1 Emphasized', c: 'text/secondary' }),
          spacer(), ic('chevronD', 'icon/sm', 'text/secondary')] }));
        kids.push(logCard());   // 最新一条始终展开
        if (p.logCount === 'many') {
          kids.push(T('还有 2 条更早的更新记录', { s: 'iOS/Caption1', c: 'accent/blue', name: 'More Logs' }));
        }
      }
      conf(c, { name: 'Summary Panel', dir: 'v', gap: 'space/12', w: 'system/screen-w',
                pad: ['space/16', 'space/16', 'space/16', 'space/16'], fill: 'bg/card', children: kids });
    }, page);

  // ---------------------------------------------------- Blocks

  C.blockText = variantSet('Block / Text', ['state'],
    [{ state: 'rendered' }, { state: 'editing' }],
    (c, p) => {
      const editing = p.state === 'editing';
      const kids = [T(editing ? '## 会议纪要\n今天讨论了**排期**与分工。' : '会议纪要\n今天讨论了排期与分工。',
        { s: 'iOS/Body', width: 353, name: 'Content' })];
      if (editing) kids.push(R(2, 21, 'accent/blue'));
      conf(c, { name: 'Text Block', dir: 'h', gap: 1, w: 353, cross: 'MIN', children: kids });
    }, page);

  // ---- Block / Image ----
  C.blockImage = variantSet('Block / Image', ['state'],
    [{ state: 'loaded' }, { state: 'loading' }, { state: 'failed' }, { state: 'missing' }],
    (c, p) => {
      if (p.state === 'loaded') {
        conf(c, { name: 'Image Block', w: 353, h: 158, radius: 'radius/md', fill: 'bg/fill-strong' });
        return;
      }
      const kids = [];
      if (p.state === 'loading') {
        kids.push(ic('refresh', 'icon/lg', 'text/tertiary'));
        kids.push(T('加载中…', { s: 'iOS/Subheadline', c: 'text/secondary', name: 'Message' }));
      } else {
        kids.push(ic('photo', 'icon/lg', 'text/tertiary'));
        kids.push(T(p.state === 'failed' ? '图片加载失败' : '文件已丢失',
          { s: 'iOS/Subheadline', c: 'text/secondary', name: 'Message' }));
        const ctas = [];
        if (p.state === 'failed') ctas.push(ctaBtn('重试'));
        ctas.push(ctaBtn('移除', true));
        kids.push(F({ name: 'CTAs', dir: 'h', gap: 'space/8', children: ctas }));
      }
      conf(c, { name: 'Image Block', dir: 'v', gap: 'space/8', w: 353, h: 158,
                main: 'CENTER', cross: 'CENTER', radius: 'radius/md', fill: 'bg/fill', children: kids });
    }, page);

  // ---- Block / Audio ----
  const mkWave = active => [7, 14, 22, 11, 18, 9, 24, 13, 19, 8, 16, 22, 11, 6, 17, 21, 12, 9, 15, 20, 10, 7, 18, 13]
    .map((h, i) => R(2.5, h, i < active ? 'accent/blue' : 'text/tertiary', 2));
  C.blockAudio = variantSet('Block / Audio', ['state'],
    [{ state: 'idle' }, { state: 'playing' }, { state: 'transcribing' }, { state: 'failed' }],
    (c, p) => {
      const tr = C.audioTranscript.children[p.state === 'transcribing' || p.state === 'failed' ? 0 : 1].createInstance();
      tr.name = 'Transcript';
      const kids = [
        F({ name: 'Player', dir: 'h', gap: 'space/12', cross: 'CENTER', w: 329, children: [
          ic(p.state === 'playing' ? 'pause' : 'play', 34, 'accent/blue'),
          F({ name: 'Waveform', dir: 'h', gap: 2.5, cross: 'CENTER', h: 28, grow: 1,
              children: mkWave(p.state === 'playing' ? 12 : 6) }),
          T(p.state === 'playing' ? '00:18' : '00:42', { s: 'iOS/Caption1', c: 'text/secondary' })] }),
      ];
      if (p.state === 'transcribing') {
        kids.push(F({ name: 'Status', dir: 'h', gap: 'space/4', cross: 'CENTER', children: [
          ic('refresh', 'icon/sm', 'text/secondary'),
          T('转写中…', { s: 'iOS/Footnote', c: 'text/secondary', name: 'Status Text' })] }));
      } else if (p.state === 'failed') {
        kids.push(F({ name: 'Status', dir: 'h', gap: 'space/8', cross: 'CENTER', w: 329, children: [
          ic('warning', 'icon/sm', 'accent/orange'),
          T('转写失败', { s: 'iOS/Footnote', c: 'text/secondary', grow: 1, name: 'Status Text' }),
          ctaBtn('重试')] }));
      }
      kids.push(tr);
      conf(c, { name: 'Audio Block', dir: 'v', gap: 'space/8', w: 353,
                pad: ['space/12', 'space/12', 'space/12', 'space/12'], radius: 'radius/md', fill: 'bg/fill', children: kids });
    }, page);
  P.blockAudio = { Transcript: C.blockAudio.addComponentProperty('Transcript', 'INSTANCE_SWAP', C.audioTranscript.children[1].id) };
  bindPropAll(C.blockAudio, 'Transcript', 'mainComponent', P.blockAudio.Transcript);

  // ---- Block / Document ----
  C.blockDocument = variantSet('Block / Document', ['state'],
    [{ state: 'normal' }, { state: 'unsupported' }, { state: 'missing' }],
    (c, p) => {
      const miss = p.state === 'missing';
      const meta = p.state === 'unsupported' ? 'PPTX · 暂不支持提取文字' : miss ? '文件已丢失' : 'PDF';
      const trailing = miss ? ctaBtn('移除', true) : ic('chevronR', 'icon/sm', 'text/tertiary');
      conf(c, {
        name: 'Document Block', dir: 'h', gap: 'space/12', w: 353, cross: 'CENTER',
        pad: ['space/12', 'space/12', 'space/12', 'space/12'], radius: 'radius/md', fill: 'bg/fill', children: [
          ic('doc', 'icon/lg', miss ? 'text/tertiary' : 'accent/blue'),
          F({ name: 'Text', dir: 'v', gap: 'space/4', grow: 1, children: [
            T('产品需求文档.pdf', { s: 'iOS/Subheadline Emphasized', lines: 1, c: miss ? 'text/tertiary' : 'text/primary', name: 'Name' }),
            T(meta, { s: 'iOS/Caption1', c: p.state === 'unsupported' ? 'accent/orange' : 'text/secondary', name: 'Meta' })] }),
          trailing,
        ],
      });
    }, page);

  // ---- Block / Link —— failed / url-only 都必须保持链接可点 ----
  C.blockLink = variantSet('Block / Link', ['state'],
    [{ state: 'preview' }, { state: 'url-only' }, { state: 'loading' }, { state: 'failed' }],
    (c, p) => {
      const textKids = [];
      if (p.state === 'preview') {
        textKids.push(T('示例站点标题', { s: 'iOS/Subheadline Emphasized', lines: 1, name: 'Title' }));
        textKids.push(T('这是站点描述，来自 metadata', { s: 'iOS/Caption1', c: 'text/secondary', lines: 1, name: 'Description' }));
      }
      textKids.push(T('example.com', { s: p.state === 'preview' ? 'iOS/Caption1' : 'iOS/Subheadline Emphasized',
                                       c: p.state === 'preview' ? 'text/secondary' : 'accent/blue', lines: 1, name: 'URL' }));
      if (p.state === 'loading') textKids.push(T('正在获取预览…', { s: 'iOS/Caption1', c: 'text/tertiary', name: 'Status' }));
      if (p.state === 'failed') textKids.push(T('预览获取失败 · 链接仍可打开', { s: 'iOS/Caption1', c: 'text/tertiary', name: 'Status' }));
      conf(c, {
        name: 'Link Block', dir: 'h', gap: 'space/12', w: 353, cross: 'CENTER',
        pad: ['space/12', 'space/12', 'space/12', 'space/12'], radius: 'radius/md', fill: 'bg/fill', children: [
          ic(p.state === 'loading' ? 'refresh' : 'link', 'icon/lg', 'accent/blue'),
          F({ name: 'Text', dir: 'v', gap: 'space/4', grow: 1, children: textKids }),
        ].concat(p.state === 'failed' ? [ctaBtn('重试预览')] : []),
      });
    }, page);

  // ---------------------------------------------------- Feedback（A-15）

  C.emptyState = CMP({
    name: 'Empty State', dir: 'v', gap: 'space/12', w: 'system/screen-w',
    pad: ['space/32', 'space/32', 'space/32', 'space/32'], main: 'CENTER', cross: 'CENTER', children: [
      ic('pencil', 52, 'text/tertiary'),
      T('还没有笔记', { s: 'iOS/Headline', name: 'Title' }),
      T('说明文案', { s: 'iOS/Subheadline', c: 'text/secondary', align: 'CENTER', width: 300, name: 'Message' }),
      F({ name: 'CTA', dir: 'h', h: 'system/tap-min', cross: 'CENTER', main: 'CENTER',
          pad: [0, 'space/16', 0, 'space/16'], radius: 'radius/md', fill: 'accent/blue-bg',
          children: [T('操作', { s: 'iOS/Subheadline Emphasized', c: 'accent/blue', name: 'CTA Label' })] }),
    ],
  });
  P.emptyState = {
    Title: C.emptyState.addComponentProperty('Title', 'TEXT', '还没有笔记'),
    Message: C.emptyState.addComponentProperty('Message', 'TEXT', '说明文案'),
    CTALabel: C.emptyState.addComponentProperty('CTA Label', 'TEXT', '操作'),
    ShowCTA: C.emptyState.addComponentProperty('Show CTA', 'BOOLEAN', false),
    Icon: C.emptyState.addComponentProperty('Icon', 'INSTANCE_SWAP', ICON_COMP.pencil.id),
  };
  bindProp(C.emptyState.findOne(n => n.name === 'Title'), 'characters', P.emptyState.Title);
  bindProp(C.emptyState.findOne(n => n.name === 'Message'), 'characters', P.emptyState.Message);
  bindProp(C.emptyState.findOne(n => n.name === 'CTA Label'), 'characters', P.emptyState.CTALabel);
  bindProp(C.emptyState.findOne(n => n.name === 'CTA'), 'visible', P.emptyState.ShowCTA);
  bindProp(C.emptyState.findOne(n => n.name && n.name.indexOf('Icon /') === 0), 'mainComponent', P.emptyState.Icon);
  page.appendChild(C.emptyState);

  C.errorRow = variantSet('Error Row', ['ctaCount'],
    [{ ctaCount: '0' }, { ctaCount: '1' }, { ctaCount: '2' }],
    (c, p) => {
      const n = parseInt(p.ctaCount, 10);
      const ctas = [];
      for (let i = 0; i < n; i++) {
        ctas.push(F({ name: 'CTA ' + (i + 1), dir: 'h', h: 'row/standard', cross: 'CENTER',
          pad: [0, 'space/12', 0, 'space/12'], radius: 'radius/md', fill: 'accent/blue-bg',
          children: [T(i === 0 ? '重试' : '去设置', { s: 'iOS/Subheadline Emphasized', c: 'accent/blue', name: 'CTA ' + (i + 1) + ' Label' })] }));
      }
      conf(c, {
        name: 'Error Row', dir: 'v', gap: 'space/8', w: 353,
        pad: ['space/12', 'space/12', 'space/12', 'space/12'], radius: 'radius/md', fill: 'accent/red-bg', children: [
          F({ name: 'Message Row', dir: 'h', gap: 'space/8', cross: 'MIN', w: 329, children: [
            ic('warning', 'icon/sm', 'accent/red'),
            T('错误信息', { s: 'iOS/Subheadline', c: 'text/primary', grow: 1, name: 'Message' })] }),
        ].concat(ctas.length ? [F({ name: 'CTAs', dir: 'h', gap: 'space/8', children: ctas })] : []),
      });
    }, page);
  P.errorRow = { Message: C.errorRow.addComponentProperty('Message', 'TEXT', '错误信息') };
  bindPropAll(C.errorRow, 'Message', 'characters', P.errorRow.Message);

  C.loadingRow = variantSet('Loading Row', ['style'],
    [{ style: 'spinner' }, { style: 'skeleton' }],
    (c, p) => {
      const kids = p.style === 'spinner'
        ? [ic('refresh', 'icon/sm', 'text/secondary'), T('加载中…', { s: 'iOS/Subheadline', c: 'text/secondary', name: 'Label' })]
        : [F({ name: 'Skeleton', dir: 'v', gap: 'space/8', w: 329, children: [
            R(240, 14, 'bg/fill-strong', 'radius/xs'), R(180, 14, 'bg/fill-strong', 'radius/xs')] })];
      conf(c, { name: 'Loading Row', dir: 'h', gap: 'space/8', w: 353, cross: 'CENTER',
                pad: ['space/12', 'space/12', 'space/12', 'space/12'], children: kids });
    }, page);

  // ---------------------------------------------------- Search（Goal 1 · Production Semantic Search）

  // Search Field —— 用户永远只面对一个框；三态是「输入进程」，不是 retrieval mode。
  C.searchField = variantSet('Search Field', ['state'],
    [{ state: 'idle' }, { state: 'typing' }, { state: 'searching' }],
    (c, p) => {
      const idle = p.state === 'idle';
      let trailing = null;
      if (p.state === 'typing') { trailing = ic('xmark', 'icon/md', 'text/tertiary'); trailing.name = 'Clear'; }
      if (p.state === 'searching') { trailing = ic('refresh', 'icon/md', 'text/tertiary'); trailing.name = 'Spinner'; }
      conf(c, {
        name: 'Search Field', dir: 'h', gap: 'space/4', w: W - 32, h: 36, cross: 'CENTER',
        pad: [0, 'space/8', 0, 'space/8'], radius: 'radius/sm', fill: 'bg/fill',
        children: [
          ic('search', 'icon/md', idle ? 'text/tertiary' : 'text/secondary'),
          T(idle ? SEARCH_PLACEHOLDER : SEARCH_QUERY,
            { s: 'iOS/Body', c: idle ? 'text/tertiary' : 'text/primary', lines: 1, grow: 1, name: 'Value' }),
        ].concat(trailing ? [trailing] : []),
      });
    }, page);
  P.searchField = { Value: C.searchField.addComponentProperty('Value', 'TEXT', SEARCH_PLACEHOLDER) };
  bindPropAll(C.searchField, 'Value', 'characters', P.searchField.Value);

  // Row / Search Result —— 副标题槽位是 Matched Excerpt，不是 AI one_liner。
  // 命中出处（转写 / 文档 / 链接 / 图片 OCR）走 BOOLEAN + INSTANCE_SWAP，不占变体轴。
  C.rowSearchResult = variantSet('Row / Search Result', ['state'],
    [{ state: 'default' }, { state: 'pressed' }],
    (c, p) => {
      // 出处图标放在**常驻的 20pt 槽位**里，只有图标本身随 Show Source Icon 显隐。
      // 若让图标直接参与 auto-layout，隐藏时它会退出布局流，excerpt 的左边缘会在
      // 有无出处的行之间来回跳 —— 槽位常驻换来所有行的 excerpt 严格左对齐。
      const srcIcon = ic('wave', 'icon/sm', 'text/tertiary'); srcIcon.name = 'Source Icon';
      const srcSlot = F({ name: 'Source', dir: 'h', w: 'icon/md', h: 'icon/md',
                          main: 'CENTER', cross: 'CENTER', children: [srcIcon] });
      conf(c, {
        name: 'Row / Search Result', dir: 'v', w: 'system/screen-w', cross: 'MAX',
        fill: p.state === 'pressed' ? 'bg/fill' : null,
        children: [
          F({ name: 'Row', dir: 'v', gap: 'space/4', w: 'system/screen-w',
              pad: ['space/12', 'space/20', 'space/12', 'space/20'], children: [
            // 显式定宽，不用 grow —— grow + maxLines 在 Figma 里不会换行，
            // 文本会拉成一条长行被屏幕裁掉（2026-08-07 MCP 实读发现）。
            T('笔记标题', { s: 'iOS/Headline', lines: 1, width: W - 40, name: 'Title' }),
            F({ name: 'Excerpt', dir: 'h', gap: 'space/4', w: W - 40, cross: 'MIN', children: [
              srcSlot,
              T('命中片段', { s: 'iOS/Subheadline', c: 'text/secondary', lines: 2,
                            width: W - 64, name: 'Excerpt Text' }),
            ] }),
            F({ name: 'Meta', dir: 'h', w: W - 40, main: 'SPACE_BETWEEN', cross: 'CENTER', children: [
              F({ name: 'Folder', dir: 'h', gap: 'space/4', cross: 'CENTER', children: [
                ic('briefcase', 'icon/sm', 'text/tertiary'),
                T('工作', { s: 'iOS/Caption1', c: 'text/tertiary', name: 'Folder Name' })] }),
              T('刚刚', { s: 'iOS/Caption1', c: 'text/tertiary', name: 'Time' }),
            ] }),
          ] }),
          hr(W - 20),
        ],
      });
    }, page);
  P.rowSearchResult = {
    Title:      C.rowSearchResult.addComponentProperty('Title', 'TEXT', '笔记标题'),
    Excerpt:    C.rowSearchResult.addComponentProperty('Excerpt', 'TEXT', '命中片段'),
    Folder:     C.rowSearchResult.addComponentProperty('Folder', 'TEXT', '工作'),
    Time:       C.rowSearchResult.addComponentProperty('Time', 'TEXT', '刚刚'),
    ShowSource: C.rowSearchResult.addComponentProperty('Show Source Icon', 'BOOLEAN', false),
    SourceIcon: C.rowSearchResult.addComponentProperty('Source Icon', 'INSTANCE_SWAP', ICON_COMP.wave.id),
  };
  bindPropAll(C.rowSearchResult, 'Title', 'characters', P.rowSearchResult.Title);
  bindPropAll(C.rowSearchResult, 'Excerpt Text', 'characters', P.rowSearchResult.Excerpt);
  bindPropAll(C.rowSearchResult, 'Folder Name', 'characters', P.rowSearchResult.Folder);
  bindPropAll(C.rowSearchResult, 'Time', 'characters', P.rowSearchResult.Time);
  bindPropAll(C.rowSearchResult, 'Source Icon', 'visible', P.rowSearchResult.ShowSource);
  bindPropAll(C.rowSearchResult, 'Source Icon', 'mainComponent', P.rowSearchResult.SourceIcon);

  // Bar / Search Status —— 只表达 RetrievalCapability，与 QueryPhase 无关。
  // 没有 full 变体：capability=full 时组件不进入层级，不做零高度幽灵节点。
  C.barSearchStatus = variantSet('Bar / Search Status', ['state'],
    [{ state: 'building' }, { state: 'rebuilding' }, { state: 'degraded' }, { state: 'offline' }],
    (c, p) => {
      const spec = SEARCH_STATUS_SPEC[p.state];
      const kids = [
        ic(spec.icon, 'icon/sm', 'text/tertiary'),
        T(spec.msg, { s: 'iOS/Footnote', c: 'text/secondary', lines: 1, grow: 1, name: 'Message' }),
      ];
      if (spec.cta) kids.push(ctaBtn(spec.cta));
      conf(c, {
        name: 'Bar / Search Status', dir: 'h', gap: 'space/8', w: 'system/screen-w',
        h: 'system/tap-min', cross: 'CENTER', pad: [0, 'space/16', 0, 'space/16'],
        fill: 'bg/fill', children: kids,
      });
    }, page);
  // 刻意**不给** Message / CTA Label 加 TEXT 组件属性。
  //
  // 事故记录（2026-08-07 第 3 轮实读）：原本两者都是 TEXT 属性，结果 degraded 变体
  // 在屏上显示成了 building 的文案。根因是 Figma 的 TEXT 属性**全变体共用一个默认值**，
  // 切换变体不会跟着换文案 —— 四个变体里有三个在说谎。
  //
  // 更根本的是：这四句文案是**状态定义的一部分**，不是可填内容。做成属性等于给了
  // 一个把 embedding / 向量 / RRF 打进产品界面的入口，正面违反 §1.1.1 的用户侧禁用词表。
  // 状态决定文案，作者不参与。

  // ---------------------------------------------------- Overlays（A-13：仅 default 占位）

  const overlayShell = (name, title, bodyKids, w, radius) => {
    const comp = CMP({
      name: name, dir: 'v', gap: 'space/12', w: w || W - 64,
      pad: ['space/20', 'space/20', 'space/20', 'space/20'], radius: radius || 'radius/lg',
      fill: 'bg/card', effect: 'elevation/menu',
      children: [T(title, { s: 'iOS/Headline', align: 'CENTER', stretch: true, name: 'Title' })].concat(bodyKids || []),
    });
    page.appendChild(comp);
    return comp;
  };

  C.dialogConfirmation = variantSet('Dialog / Confirmation', ['tone'],
    [{ tone: 'default' }, { tone: 'destructive' }],
    (c, p) => {
      const del = p.tone === 'destructive';
      conf(c, {
        name: 'Confirmation', dir: 'v', gap: 'space/12', w: W - 64,
        pad: ['space/20', 'space/20', 'space/20', 'space/20'], radius: 'radius/lg', fill: 'bg/card',
        effect: 'elevation/menu', children: [
          T('确认操作', { s: 'iOS/Headline', align: 'CENTER', stretch: true, name: 'Title' }),
          T('说明文案', { s: 'iOS/Footnote', c: 'text/secondary', align: 'CENTER', width: W - 104, name: 'Message' }),
          F({ name: 'Actions', dir: 'h', gap: 'space/8', stretch: true, children: [
            F({ name: 'Cancel', dir: 'h', h: 'row/standard', grow: 1, main: 'CENTER', cross: 'CENTER',
                radius: 'radius/md', fill: 'bg/fill', children: [T('取消', { s: 'iOS/Body' })] }),
            F({ name: 'Confirm', dir: 'h', h: 'row/standard', grow: 1, main: 'CENTER', cross: 'CENTER',
                radius: 'radius/md', fill: del ? 'accent/red-bg' : 'accent/blue-bg',
                children: [T(del ? '删除' : '确认', { s: 'iOS/Subheadline Emphasized', c: del ? 'accent/red' : 'accent/blue', name: 'Confirm Label' })] }),
          ] }),
        ],
      });
    }, page);
  P.dialogConfirmation = {
    Title: C.dialogConfirmation.addComponentProperty('Title', 'TEXT', '确认操作'),
    Message: C.dialogConfirmation.addComponentProperty('Message', 'TEXT', '说明文案'),
  };
  bindPropAll(C.dialogConfirmation, 'Title', 'characters', P.dialogConfirmation.Title);
  bindPropAll(C.dialogConfirmation, 'Message', 'characters', P.dialogConfirmation.Message);

  C.sheetRecorder = variantSet('Sheet / Recorder', ['state'],
    [{ state: 'idle' }, { state: 'recording' }, { state: 'paused' }, { state: 'done' }, { state: 'failed' }],
    (c, p) => {
      const active = p.state === 'recording';
      const bars = [7, 18, 30, 14, 24, 10, 34, 16, 26, 12]
        .map((h, i) => R(3, active ? h : Math.max(4, h * 0.4), active || p.state === 'paused' ? 'accent/blue' : 'text/tertiary', 2));
      const kids = [
        T('录音', { s: 'iOS/Headline', align: 'CENTER', stretch: true, name: 'Title' }),
      ];
      if (p.state === 'failed') {
        kids.push(F({ name: 'Error', dir: 'h', gap: 'space/8', cross: 'CENTER', main: 'CENTER', stretch: true, children: [
          ic('warning', 'icon/md', 'accent/orange'),
          T('录音失败，请检查麦克风权限', { s: 'iOS/Subheadline', c: 'text/secondary', name: 'Message' })] }));
        kids.push(ctaBtn('重试'));
      } else {
        kids.push(F({ name: 'Waveform', dir: 'h', gap: 'space/4', cross: 'CENTER', h: 48, main: 'CENTER', stretch: true, children: bars }));
        kids.push(T(p.state === 'idle' ? '00:00' : p.state === 'done' ? '00:42' : '00:18',
          { s: 'iOS/Title2', align: 'CENTER', stretch: true, name: 'Duration' }));
        const ctl = [];
        if (p.state === 'idle') ctl.push(tappable(ic('mic', 'icon/lg', 'accent/red'), 'Record'));
        if (p.state === 'recording') ctl.push(tappable(ic('pause', 'icon/lg', 'accent/blue'), 'Record'));
        if (p.state === 'paused') { ctl.push(tappable(ic('play', 'icon/lg', 'accent/blue'), 'Record')); ctl.push(ctaBtn('完成')); }
        if (p.state === 'done') { ctl.push(tappable(ic('play', 'icon/lg', 'accent/blue'), 'Record')); ctl.push(ctaBtn('插入笔记')); }
        kids.push(F({ name: 'Controls', dir: 'h', gap: 'space/16', main: 'CENTER', cross: 'CENTER', stretch: true, children: ctl }));
      }
      conf(c, { name: 'Recorder', dir: 'v', gap: 'space/12', w: 'system/screen-w',
                pad: ['space/20', 'space/20', 'space/20', 'space/20'], radius: 'radius/lg',
                fill: 'bg/card', effect: 'elevation/menu', children: kids });
    }, page);

  C.sheetTagEditor = overlayShell('Sheet / Tag Editor', '标签', [
    F({ name: 'Tags', dir: 'h', gap: 'space/8', children: [C.chipTag.children[0].createInstance()] }),
    F({ name: 'Input', dir: 'h', h: 'row/standard', stretch: true, cross: 'CENTER', pad: [0, 'space/12', 0, 'space/12'],
        radius: 'radius/sm', fill: 'bg/fill', children: [T('添加标签', { s: 'iOS/Body', c: 'text/tertiary' })] }),
  ], W, 'radius/lg');

  C.sheetFolderEditor = variantSet('Sheet / Folder Editor', ['mode'],
    [{ mode: 'create' }, { mode: 'rename' }],
    (c, p) => {
      conf(c, {
        name: 'Folder Editor', dir: 'v', gap: 'space/12', w: 'system/screen-w',
        pad: ['space/20', 'space/20', 'space/20', 'space/20'], radius: 'radius/lg', fill: 'bg/card', children: [
          T(p.mode === 'create' ? '新建文件夹' : '重命名文件夹', { s: 'iOS/Headline', align: 'CENTER', stretch: true, name: 'Title' }),
          F({ name: 'Name Input', dir: 'h', h: 'row/standard', stretch: true, cross: 'CENTER', pad: [0, 'space/12', 0, 'space/12'],
              radius: 'radius/sm', fill: 'bg/fill', children: [T('文件夹名称', { s: 'iOS/Body', c: 'text/tertiary' })] }),
          F({ name: 'Color Picker', dir: 'h', gap: 'space/8', children:
            Object.keys(FOLDER_COLORS).map(k => F({ name: 'Swatch ' + k, w: 32, h: 32, radius: 'radius/full', fill: FOLDER_COLORS[k] })) }),
        ],
      });
    }, page);

  C.sheetImageViewer = overlayShell('Sheet / Image Viewer', '', [
    F({ name: 'Image', w: W - 40, h: 320, radius: 'radius/md', fill: 'bg/fill-strong' }),
  ], W, 'radius/lg');

  C.sheetURLInput = overlayShell('Sheet / URL Input', '添加链接', [
    F({ name: 'URL Input', dir: 'h', h: 'row/standard', stretch: true, cross: 'CENTER', pad: [0, 'space/12', 0, 'space/12'],
        radius: 'radius/sm', fill: 'bg/fill', children: [T('https://', { s: 'iOS/Body', c: 'text/tertiary' })] }),
  ], W - 64, 'radius/lg');

  C.sheetPermission = variantSet('Sheet / Permission', ['type'],
    [{ type: 'camera' }, { type: 'photo' }, { type: 'microphone' }],
    (c, p) => {
      const spec = { camera: ['camera', '需要相机权限', '请在系统设置中允许访问相机，以便拍照插入笔记。'],
                     photo: ['photo', '需要相册权限', '请在系统设置中允许访问照片，以便从相册插入图片。'],
                     microphone: ['mic', '需要麦克风权限', '请在系统设置中允许访问麦克风，以便录音。'] }[p.type];
      conf(c, {
        name: 'Permission', dir: 'v', gap: 'space/12', w: W - 64,
        pad: ['space/20', 'space/20', 'space/20', 'space/20'], radius: 'radius/lg',
        fill: 'bg/card', effect: 'elevation/menu', children: [
          ic(spec[0], 'icon/lg', 'accent/blue'),
          T(spec[1], { s: 'iOS/Headline', align: 'CENTER', stretch: true, name: 'Title' }),
          T(spec[2], { s: 'iOS/Subheadline', c: 'text/secondary', align: 'CENTER', width: W - 104, name: 'Message' }),
          F({ name: 'Go To Settings', dir: 'h', h: 'system/tap-min', stretch: true, main: 'CENTER', cross: 'CENTER',
              radius: 'radius/md', fill: 'accent/blue-bg',
              children: [T('去设置', { s: 'iOS/Subheadline Emphasized', c: 'accent/blue' })] }),
        ],
      });
    }, page);

  const mkMenuItem = (label, icon, del) => {
    const i = C.menuItem.children[del ? 1 : 0].createInstance();
    i.name = 'Menu Item / ' + label;
    const pr = {}; pr[P.menuItem.Label] = label;
    if (ICON_COMP[icon]) pr[P.menuItem.Icon] = ICON_COMP[icon].id;
    try { i.setProperties(pr); } catch (e) { }
    return i;
  };
  C.menuFolderPicker = CMP({
    name: 'Menu / Folder Picker', dir: 'v', w: 255, radius: 'radius/lg', fill: 'bg/card',
    clip: true, effect: 'elevation/menu', children: [
      mkMenuItem('未归类', 'folder'), hr(255), mkMenuItem('工作', 'briefcase'), hr(255),
      mkMenuItem('读书', 'book'), R(255, 8, 'separator'), mkMenuItem('新建文件夹…', 'plus'),
    ],
  });
  page.appendChild(C.menuFolderPicker);

  C.menuMediaInsert = CMP({
    name: 'Menu / Media Insert', dir: 'v', w: 255, radius: 'radius/lg', fill: 'bg/card',
    clip: true, effect: 'elevation/menu', children: [
      mkMenuItem('拍照', 'camera'), hr(255), mkMenuItem('从相册选图', 'photo'), hr(255),
      mkMenuItem('录音', 'mic'), hr(255), mkMenuItem('导入文档', 'doc'), hr(255), mkMenuItem('添加链接', 'link'),
    ],
  });
  page.appendChild(C.menuMediaInsert);
}

// =============================================================== 10. 实例助手

function iNav(o) {
  o = o || {};
  const inst = C.barNav.createInstance();
  inst.name = 'Nav Bar';
  const props = {};
  props[P.barNav.Title] = o.title || '';
  props[P.barNav.ShowLeading] = !!o.leading;
  props[P.barNav.ShowTrailing] = !!o.trailing;
  if (o.leading && ICON_COMP[o.leading]) props[P.barNav.Leading] = ICON_COMP[o.leading].id;
  if (o.trailing && ICON_COMP[o.trailing]) props[P.barNav.Trailing] = ICON_COMP[o.trailing].id;
  try { inst.setProperties(props); } catch (e) { }
  return inst;
}

function iNoteRow(o) {
  const inst = C.rowNote.createInstance();
  inst.name = 'Note Row / ' + o.title;
  const previewIdx = { 'ai-summary': 0, 'text': 1, 'audio': 2, 'image': 3, 'empty': 4 }[o.preview || 'ai-summary'];
  const badgeIdx = { 'none': 0, 'generating': 1, 'failed': 2 }[o.ai || 'none'];
  const props = {};
  props[P.rowNote.Title] = o.title;
  props[P.rowNote.Time] = o.time;
  props[P.rowNote.Preview] = C.notePreview.children[previewIdx].id;
  props[P.rowNote.AIBadge] = C.noteAIBadge.children[badgeIdx].id;
  props[P.rowNote.ShowPin] = !!o.pinned;
  props[P.rowNote.ShowUnread] = !!o.unread;
  try { inst.setProperties(props); } catch (e) { }
  // Preview 的文案必须显式写回：Note / Preview 五个变体各有各的文案，
  // 但它们共用一个 TEXT 属性默认值 'AI 一句话概述'。不写回的话，
  // audio / image / empty 三种预览在首页上都会显示成 'AI 一句话概述'。
  //
  // 而且必须走**嵌套实例自己的 setProperties**，不能直接写 characters ——
  // Preview 是个嵌套实例，它的文本受 Note / Preview 的 TEXT 属性驱动，
  // 直接改 characters 会被属性默认值盖回去。这一点只在 ai-summary 行上暴露：
  // 它的 INSTANCE_SWAP 目标恰好等于属性默认值，Figma 视作没换，于是绑定始终有效。
  setInstText(inst, 'Text', o.sub || NOTE_PREVIEW_TEXT[o.preview || 'ai-summary']);
  return inst;
}

function iChip(label, state, dotColor) {
  const idx = { 'default': 0, 'selected': 1, 'more': 2 }[state || 'default'];
  const inst = C.chipFolder.children[idx].createInstance();
  inst.name = 'Chip / ' + label;
  const props = {};
  props[P.chipFolder.Label] = label;
  if (idx !== 2) props[P.chipFolder.Dot] = !!dotColor;
  try { inst.setProperties(props); } catch (e) { }
  if (dotColor) { const d = inst.findOne(n => n.name === 'Dot'); if (d) d.fills = [paint(dotColor)]; }
  return inst;
}
function iFolderMeta(label, unassigned) {
  const inst = C.chipFolderMeta.children[unassigned ? 1 : 0].createInstance();
  inst.name = 'Folder Meta / ' + label;
  const p = {}; p[P.chipFolderMeta.Label] = label;
  try { inst.setProperties(p); } catch (e) { }
  return inst;
}
function iTag(label, selected) {
  const inst = C.chipTag.children[selected ? 1 : 0].createInstance();
  inst.name = 'Tag / ' + label;
  const p = {}; p[P.chipTag.Label] = label;
  try { inst.setProperties(p); } catch (e) { }
  return inst;
}
function iTopic(label, added) {
  const inst = C.chipTopic.children[added ? 1 : 0].createInstance();
  inst.name = 'Topic / ' + label;
  const p = {}; p[P.chipTopic.Label] = label;
  try { inst.setProperties(p); } catch (e) { }
  return inst;
}
function iFolderRow(name, count, color, iconName, grip) {
  const inst = C.rowFolder.children[grip ? 1 : 0].createInstance();
  inst.name = 'Folder Row / ' + name;
  const props = {};
  props[P.rowFolder.Name] = name;
  props[P.rowFolder.Count] = count;
  if (ICON_COMP[iconName]) props[P.rowFolder.Icon] = ICON_COMP[iconName].id;
  try { inst.setProperties(props); } catch (e) { }
  const badge = inst.findOne(n => n.name === 'Badge');
  if (badge) badge.fills = [paint(color)];
  const gi = inst.findOne(n => n.name === 'Folder Icon');
  if (gi) tint(gi, 'text/on-accent');
  return inst;
}
function iFormRow(type, label, value, status) {
  const order = ['value', 'chevron', 'toggle', 'action'];
  const inst = C.rowForm.children[order.indexOf(type)].createInstance();
  inst.name = 'Form Row / ' + label;
  const props = {}; props[P.rowForm.Label] = label;
  if (value !== undefined) props[P.rowForm.Value] = value;
  if (type === 'action' && status) {
    const si = { idle: 0, testing: 1, success: 2, failure: 3 }[status];
    props[P.rowForm.Status] = C.formActionStatus.children[si].id;
  }
  try { inst.setProperties(props); } catch (e) { }
  return inst;
}
function iEmptyState(title, message, cta) {
  const inst = C.emptyState.createInstance();
  inst.name = 'Empty State / ' + title;
  const p = {};
  p[P.emptyState.Title] = title;
  p[P.emptyState.Message] = message;
  p[P.emptyState.ShowCTA] = !!cta;
  if (cta) p[P.emptyState.CTALabel] = cta;
  try { inst.setProperties(p); } catch (e) { }
  return inst;
}

/* ---- Search 实例助手 ---- */

const SEARCH_FIELD_ORDER = ['idle', 'typing', 'searching'];
function iSearchField(state, value) {
  const st = state || 'idle';
  const inst = C.searchField.children[Math.max(0, SEARCH_FIELD_ORDER.indexOf(st))].createInstance();
  inst.name = 'Search Field';
  // 兜底到该变体自己的文案。idle 恰好与属性默认值相同，但不能靠这个巧合 ——
  // 一旦有人改了默认值，12 屏会跟着悄悄变。
  const p = {}; p[P.searchField.Value] = value !== undefined ? value : (st === 'idle' ? SEARCH_PLACEHOLDER : SEARCH_QUERY);
  try { inst.setProperties(p); } catch (e) { }
  return inst;
}

const SEARCH_STATUS_ORDER = ['building', 'rebuilding', 'degraded', 'offline'];
function iSearchStatus(state) {
  const inst = C.barSearchStatus.children[Math.max(0, SEARCH_STATUS_ORDER.indexOf(state || 'building'))].createInstance();
  inst.name = 'Search Status';
  return inst;
}

/**
 * 命中高亮：把 excerpt 里命中 query 的字符区间提到 text/primary，
 * 其余上下文保持 text/secondary。**对比式高亮**，不是背景色块 ——
 * Figma 的文本不支持分段背景，而分段前景色 Figma 与 AttributedString 都原生支持，
 * 因此设计稿与实现能一比一对上（见 SEARCH_CONTRACT §2.4）。
 * ranges 为 [start, end) 字符下标，由检索层给出，不在 UI 层重新做字符串搜索。
 */
function markHits(node, ranges) {
  if (!node || !ranges) return node;
  ranges.forEach(r => { try { node.setRangeFills(r[0], r[1], [paint('text/primary')]); } catch (e) { } });
  return node;
}

/**
 * 仅用于**生成 mock 数据**的取样助手：把 terms 在 text 中的出现位置转成区间。
 * 实现侧不得这样做 —— 运行时的高亮区间必须由检索层返回，
 * 否则高亮会与实际命中不一致，而「解释相关性」的可信度正建立在这一致性上。
 */
function hits(text, terms) {
  const out = [];
  terms.forEach(t => {
    let i = text.indexOf(t);
    while (i >= 0) { out.push([i, i + t.length]); i = text.indexOf(t, i + t.length); }
  });
  return out;
}

/**
 * o = { title, excerpt, folder, time, source, hitsIn, pressed }
 *   source  ── 命中出处：'text' | 'transcript' | 'document' | 'link' | 'image'（'text' 与标题命中不显示图标）
 *   hitsIn  ── excerpt 内的命中区间 [[s,e], …]
 *
 * 标题不做命中高亮：标题本身就是 text/primary，对比式高亮在它身上是零效果
 * （2026-08-07 MCP 实读确认）。标题命中靠「标题里肉眼可见地含有 query」表达。
 */
const SEARCH_SOURCE_ICON = { transcript: 'wave', document: 'doc', link: 'link', image: 'photo' };
function iSearchResult(o) {
  const inst = C.rowSearchResult.children[o.pressed ? 1 : 0].createInstance();
  inst.name = 'Search Result / ' + o.title;
  const iconName = SEARCH_SOURCE_ICON[o.source];
  const props = {};
  props[P.rowSearchResult.Title] = o.title;
  props[P.rowSearchResult.Excerpt] = o.excerpt;
  props[P.rowSearchResult.Folder] = o.folder;
  props[P.rowSearchResult.Time] = o.time;
  props[P.rowSearchResult.ShowSource] = !!iconName;
  if (iconName && ICON_COMP[iconName]) props[P.rowSearchResult.SourceIcon] = ICON_COMP[iconName].id;
  try { inst.setProperties(props); } catch (e) { }
  const si = inst.findOne(n => n.name === 'Source Icon');
  if (si) tint(si, 'text/tertiary');
  markHits(inst.findOne(n => n.name === 'Excerpt Text'), o.hitsIn);
  return inst;
}

const iStatus = () => { const i = C.barStatus.createInstance(); i.name = 'Status Bar'; return i; };
const iBottom = () => { const i = C.barBottom.createInstance(); i.name = 'Bottom Bar'; return i; };
const iToolbar = m => { const i = C.barToolbar.children[m === 'adaptive' ? 1 : 0].createInstance(); i.name = 'Toolbar'; return i; };
const iHome = () => { const i = C.barHome.createInstance(); i.name = 'Home Indicator'; return i; };
const iAudio = st => { const i = C.blockAudio.children[['idle','playing','transcribing','failed'].indexOf(st || 'idle')].createInstance(); i.name = 'Audio Block'; return i; };
const iImage = st => { const i = C.blockImage.children[['loaded','loading','failed','missing'].indexOf(st || 'loaded')].createInstance(); i.name = 'Image Block'; return i; };
const iDocument = st => { const i = C.blockDocument.children[['normal','unsupported','missing'].indexOf(st || 'normal')].createInstance(); i.name = 'Document Block'; return i; };
const iLink = st => { const i = C.blockLink.children[['preview','url-only','loading','failed'].indexOf(st || 'preview')].createInstance(); i.name = 'Link Block'; return i; };
const iTextBlock = e => { const i = C.blockText.children[e ? 1 : 0].createInstance(); i.name = 'Text Block'; return i; };
const SUMMARY_ORDER = ['hidden', 'pending', 'generating', 'success', 'success-unread',
                       'error-auth', 'error-network', 'error-rate-limit', 'error-content'];
const iSummaryBar = (txt, state) => {
  const st = state || 'success';
  const idx = Math.max(0, SUMMARY_ORDER.indexOf(st));
  const i = C.barSummary.children[idx].createInstance();
  i.name = 'Summary Bar';
  // 不给 txt 时兜底到**该状态自己的文案**。不兜底的话实例会拿到 TEXT 属性的
  // 单一默认值 'AI 一句话概述' —— 19 屏九态一览曾因此八行显示同一句话。
  const v = txt || SUMMARY_TEXT[st];
  if (v) { const p = {}; p[P.barSummary.Text] = v; try { i.setProperties(p); } catch (e) { } }
  return i;
};
const iPanel = lc => { const i = C.panelSummary.children[['0','1','many'].indexOf(lc || '1')].createInstance(); i.name = 'Summary Panel'; return i; };

function menuOf(items) {
  const kids = [];
  items.forEach((it, i) => { kids.push(it); if (i < items.length - 1) kids.push(hr(255)); });
  return F({ name: 'Menu', dir: 'v', w: 255, radius: 'radius/lg', fill: 'bg/card',
             clip: true, effect: 'elevation/menu', children: kids });
}
function mi(label, icon, del) {
  const i = C.menuItem.children[del ? 1 : 0].createInstance();
  i.name = 'Menu Item / ' + label;
  const p = {}; p[P.menuItem.Label] = label;
  if (ICON_COMP[icon]) p[P.menuItem.Icon] = ICON_COMP[icon].id;
  try { i.setProperties(p); } catch (e) { }
  return i;
}
function screen(name, children) {
  return F({ name: name, dir: 'v', w: 'system/screen-w', h: 'system/screen-h',
             fill: 'bg/primary', radius: 'system/device-radius', clip: true, children: children });
}
function scrim(p) { abs(p, R(W, H, 'scrim'), 0, 0).name = 'Scrim'; }

// =============================================================== 11. 界面（9 屏）

function scHome() {
  return screen('01 · 首页 · 全部笔记', [
    iStatus(), iNav({ title: '全部笔记', leading: 'gear', trailing: 'search' }),
    F({ name: 'Folder Filter', dir: 'h', gap: 'space/8', w: 'system/screen-w',
        pad: ['space/8', 'space/16', 'space/12', 'space/16'], clip: true, children: [
      iChip('全部', 'selected'), iChip('未归类'), iChip('工作', 'default', FOLDER_COLORS.work),
      iChip('读书', 'default', FOLDER_COLORS.book), iChip('更多', 'more')] }),
    F({ name: 'Feed', dir: 'v', w: 'system/screen-w', grow: 1, clip: true, children: [
      iNoteRow({ title: 'Q3 产品评审会', sub: '确定了排期与三位负责人，下周三上线，设计先行后端跟进', time: '3小时前', pinned: true, unread: true }),
      iNoteRow({ title: '读《人类简史》第 4 章', sub: '围绕认知革命展开，记了 5 条要点与两段书摘', time: '昨天' }),
      iNoteRow({ title: '周会录音 · 10/22', preview: 'audio', time: '昨天', ai: 'generating' }),
      iNoteRow({ title: '合同评审要点', preview: 'text', sub: '法务反馈三处需修改，附 PDF 与批注', time: '10月15日', ai: 'failed' }),
      iNoteRow({ title: '现场照片', preview: 'image', time: '10月14日' }),
      iNoteRow({ title: '未命名笔记', preview: 'empty', time: '10月12日' }),
    ] }),
    iBottom(), iHome(),
  ]);
}

function noteHeader(folderLabel, unassigned, withTags, title) {
  const metaKids = [iFolderMeta(folderLabel, unassigned)];
  if (withTags) { metaKids.push(iTag('排期')); metaKids.push(iTag('分工')); }
  return F({ name: 'Head', dir: 'v', gap: 'space/8', w: 'system/screen-w',
             pad: ['space/16', 'space/20', 0, 'space/20'], children: [
    T(title || 'Q3 产品评审会', { s: 'iOS/Title1' }),
    F({ name: 'Metadata', dir: 'h', gap: 'space/4', cross: 'CENTER', children: metaKids }),
  ] });
}

function scNoteCollapsed() {
  return screen('02 · 笔记页 · 摘要收起', [
    iStatus(), iNav({ title: '', leading: 'back', trailing: 'dots' }),
    iSummaryBar('确定了排期与三位负责人，下周三上线'),
    F({ name: 'Body', dir: 'v', w: 'system/screen-w', grow: 1, clip: true, children: [
      noteHeader('工作', false, true),
      F({ name: 'Blocks', dir: 'v', gap: 'space/12', w: 'system/screen-w',
          pad: ['space/12', 'space/20', 'space/12', 'space/20'],
          children: [iTextBlock(false), iAudio(), iImage(), iDocument(), iLink()] }),
    ] }),
    iToolbar('insert'), iHome(),
  ]);
}

function scNoteExpanded() {
  return screen('03 · 笔记页 · 摘要展开', [
    iStatus(), iNav({ title: '', leading: 'back', trailing: 'dots' }),
    iPanel(), hr(),
    F({ name: 'Body', dir: 'v', w: 'system/screen-w', grow: 1, clip: true, children: [
      noteHeader('工作', false, true),
      F({ name: 'Blocks', dir: 'v', gap: 'space/12', w: 'system/screen-w',
          pad: ['space/12', 'space/20', 'space/12', 'space/20'], children: [iTextBlock(false)] }),
    ] }),
    iToolbar('insert'), iHome(),
  ]);
}

function scNoteMenu() {
  const p = screen('04 · 笔记页 · ⋯ 菜单', [
    iStatus(), iNav({ title: '', leading: 'back', trailing: 'dots' }),
    iSummaryBar('确定了排期与三位负责人，下周三上线'),
    F({ name: 'Body', dir: 'v', w: 'system/screen-w', grow: 1, clip: true, children: [
      noteHeader('工作', false, true)] }),
    iToolbar('insert'), iHome(),
  ]);
  scrim(p);
  abs(p, menuOf([
    mi('置顶', 'pin'), mi('移动到文件夹…', 'folder'),
    mi('立即更新总结', 'refresh'), mi('重新生成完整总结', 'sparkle'), mi('清除 AI 摘要', 'sparkle'),
    mi('导出为 Markdown', 'share'), mi('导出为纯文本', 'doc'), mi('删除笔记', 'trash', true),
  ]), W - 12 - 255, 100);
  return p;
}

function scEditing() {
  const keyRows = [];
  [10, 9, 9].forEach(n => {
    const row = []; for (let i = 0; i < n; i++) row.push(R(32, 42, 'bg/card', 'radius/xs'));
    keyRows.push(F({ name: 'Key Row', dir: 'h', gap: 'space/4', children: row }));
  });
  keyRows.push(F({ name: 'Key Row', dir: 'h', gap: 'space/4', children: [
    R(32, 42, 'bg/card', 'radius/xs'), R(150, 42, 'bg/card', 'radius/xs'),
    R(32, 42, 'bg/card', 'radius/xs'), R(32, 42, 'bg/card', 'radius/xs')] }));

  return screen('05 · 编辑器 · 聚焦（单层自适应工具条）', [
    iStatus(), iNav({ title: '', leading: 'back', trailing: 'dots' }),
    F({ name: 'Body', dir: 'v', w: 'system/screen-w', grow: 1, clip: true, children: [
      F({ name: 'Head', dir: 'v', gap: 'space/8', w: 'system/screen-w', pad: ['space/16', 'space/20', 0, 'space/20'], children: [
        T('标题（可留空）', { s: 'iOS/Title3', c: 'text/tertiary' }),
        F({ name: 'Metadata', dir: 'h', gap: 'space/4', cross: 'CENTER', children: [iFolderMeta('未归类', true)] })] }),
      F({ name: 'Blocks', dir: 'v', w: 'system/screen-w', pad: ['space/12', 'space/20', 0, 'space/20'],
          children: [iTextBlock(true)] }),
    ] }),
    iToolbar('adaptive'),
    F({ name: 'Keyboard', dir: 'v', gap: 'space/8', w: 'system/screen-w', h: 291, main: 'CENTER', cross: 'CENTER',
        fill: 'bg/fill-strong', children: keyRows }),
    iHome(),
  ]);
}

/**
 * 06 · 搜索 —— QueryPhase=ready × RetrievalCapability=full。
 *
 * 这一屏要证明的是 Goal 1 的产品价值本身：**副标题槽位是 Matched Excerpt，
 * 回答「为什么这条与 Query 有关」，而不是 AI one_liner 的「这条讲什么」。**
 *
 * 五条结果刻意覆盖五种命中出处，其中第 4 条是纯语义命中（无 exact keyword，
 * 因此无高亮）—— 混合列表里部分有高亮、部分没有是正常状态，不加任何解释行
 * （SEARCH_CONTRACT §2.6：只有整页零高亮时才加一行说明）。
 *
 * Tag chip 行只属于 idle 态：一旦有 query 就让位给结果。这同时解决了 13 屏
 * 缺 Tag 行的规则不明问题 —— 13 有 query，所以本来就不该有。
 */
/* Search 的 mock 结果集。
 *
 * `keyword` 是这份数据里最要紧的一个字段：
 *   true  ── 含 exact keyword 命中。semantic 不可用时它**仍然出得来**。
 *   false ── 纯语义命中。索引未就绪 / 降级时它会**消失**。
 * 22 / 23 两屏正是靠这个区别证明 Progressive Enhancement ——
 * 降级不是「搜索坏了」，而是「结果少了几条、不那么聪明了」。 */
const SEARCH_Q_TERMS = ['延期', '毕业'];
const SEARCH_HITS = [
  // 1 · 正文块命中
  { title: '和 advisor 的邮件往来', source: 'text', folder: '学习', time: '3小时前', keyword: true,
    excerpt: '…我问了能不能延期一个学期毕业，他说要先跟系里确认，让我别急着提交…' },
  // 2 · 录音转写命中
  { title: '周会录音 · 10/22', source: 'transcript', folder: '工作', time: '昨天', keyword: true,
    excerpt: '…延期的事你先别急，等下周开会再定，反正毕业时间还有缓冲…' },
  // 3 · 文档提取正文命中
  { title: 'Graduate Handbook.pdf', source: 'document', folder: '学习', time: '上周', keyword: true,
    excerpt: '…学生如需延期毕业，应在学期开始前四周向学院提交书面申请…' },
  // 4 · 纯语义命中：无 exact keyword，故无高亮，且降级时消失
  { title: 'NEU Extended Study Option', source: 'link', folder: '学习', time: '上周', keyword: false,
    excerpt: '…students who need additional time to complete degree requirements may apply…' },
  // 5 · 标题命中：标题不高亮，excerpt 槽位放笔记开头做上下文
  { title: '延期毕业申请材料清单', source: 'text', folder: '学习', time: '2周前', keyword: true,
    excerpt: '需要准备：导师签字页、系主任签字、最新成绩单与个人说明，材料齐了再交给系里' },
];

/* 24 屏用：同一批笔记，但 query 是一句自然语言，与正文几乎不共享词汇。
 * 因此 excerpt 里刻意不出现「毕业」——整页零高亮才成立，§2.6 的说明行才该出现。 */
const SEARCH_HITS_NL = [
  { title: '和 advisor 的邮件往来', source: 'text', folder: '学习', time: '3小时前',
    excerpt: '…我问了能不能延期一个学期，他说要先跟系里确认，让我别急着提交…' },
  { title: '周会录音 · 10/22', source: 'transcript', folder: '工作', time: '昨天',
    excerpt: '…延期的事你先别急，等下周开会再定，反正时间上还有缓冲…' },
  { title: 'Graduate Handbook.pdf', source: 'document', folder: '学习', time: '上周',
    excerpt: '…学生如需延长学习期限，应在学期开始前四周向学院提交书面申请…' },
  { title: 'NEU Extended Study Option', source: 'link', folder: '学习', time: '上周',
    excerpt: '…students who need additional time to complete degree requirements may apply…' },
  { title: '延期毕业申请材料清单', source: 'text', folder: '学习', time: '2周前',
    excerpt: '需要准备：导师签字页、系主任签字、最新成绩单与个人说明，材料齐了再交给系里' },
];

/** o.keyword 为 false 时不做高亮（纯语义命中）。 */
const iHit = o => iSearchResult({
  title: o.title, excerpt: o.excerpt, folder: o.folder, time: o.time, source: o.source,
  hitsIn: o.keyword ? hits(o.excerpt, SEARCH_Q_TERMS) : null,
});

function scSearch() {
  return screen('06 · 搜索', [
    iStatus(), iNav({ title: '搜索', leading: 'back' }),
    F({ name: 'Body', dir: 'v', w: 'system/screen-w', grow: 1, cross: 'CENTER', clip: true,
        children: [iSearchField('typing', SEARCH_QUERY)].concat(SEARCH_HITS.map(iHit)) }),
    iHome(),
  ]);
}

/** 21 · QueryPhase=searching。
 *
 *  搜索框里是**已经被改长的 query**（延期毕业 → 延期毕业申请），而下面还是
 *  上一次 query 的结果 —— 这样这一屏才说得通：用户又敲了两个字，新结果还没回来，
 *  旧结果原封不动留在屏上照常可读、可点（不变量 I5：不用覆盖结果的 spinner）。
 *  如果这里的 query 与 06 相同，"为什么它还在转"就无法解释。 */
function scSearching() {
  return screen('21 · 搜索 · 检索中', [
    iStatus(), iNav({ title: '搜索', leading: 'back' }),
    F({ name: 'Body', dir: 'v', w: 'system/screen-w', grow: 1, cross: 'CENTER', clip: true,
        children: [iSearchField('searching', SEARCH_QUERY + '申请')].concat(SEARCH_HITS.map(iHit)) }),
    iHome(),
  ]);
}

/** 22 / 23 —— RetrievalCapability 降级。keyword 结果照常，纯语义那条消失。 */
function scSearchDegraded(title, capability) {
  return screen(title, [
    iStatus(), iNav({ title: '搜索', leading: 'back' }),
    F({ name: 'Body', dir: 'v', w: 'system/screen-w', grow: 1, cross: 'CENTER', clip: true,
        children: [iSearchField('typing', SEARCH_QUERY), iSearchStatus(capability)]
          .concat(SEARCH_HITS.filter(h => h.keyword).map(iHit)) }),
    iHome(),
  ]);
}

/** 24 · 整页零高亮 —— 自然语言 query 找回了同一批笔记，但一个关键词都没对上。
 *  §2.6：只有这种情况才加一行说明，混合命中时不加。 */
function scSearchSemanticOnly() {
  return screen('24 · 搜索 · 全部为相关结果', [
    iStatus(), iNav({ title: '搜索', leading: 'back' }),
    F({ name: 'Body', dir: 'v', w: 'system/screen-w', grow: 1, cross: 'CENTER', clip: true, children: [
      iSearchField('typing', SEARCH_QUERY_NL),
      F({ name: 'Result Note', dir: 'v', w: 'system/screen-w',
          pad: ['space/8', 'space/20', 'space/8', 'space/20'], children: [
        T('没有完全匹配的关键词，以下是相关内容', { s: 'iOS/Footnote', c: 'text/tertiary' })] }),
    ].concat(SEARCH_HITS_NL.map(iHit)) }),
    iHome(),
  ]);
}

/**
 * 25 / 26 · 从搜索结果落到笔记（SEARCH_CONTRACT §3）。
 *
 * 高亮是**盖在 block 背后的一个矩形**，不是文本属性 —— 与编辑器的
 * attributed text / 光标 / 撤销栈完全解耦（§3.3.1）。
 *
 * 版式上有个坑：高亮要比 block 外扩 8pt，而 auto-layout 没有负外边距。
 * 解法是把**每一个** block 都套进同样的 8pt 槽位，只有命中的那个槽位有底色。
 * 这样所有 block 的左边缘仍然落在 x=20（与 02 屏一致），高亮才是"外扩"而不是"缩进"。
 */
function blockSlot(child, highlighted) {
  return F({
    name: highlighted ? 'Search Highlight' : 'Block Slot', dir: 'v',
    pad: ['space/8', 'space/8', 'space/8', 'space/8'],
    radius: 'radius/md', fill: highlighted ? 'accent/blue-bg' : null, children: [child],
  });
}
/**
 * 改写实例内某个**文本**节点。用于让 25 / 26 屏的内容与引它们过来的搜索结果对得上。
 *
 * 必须限定 type === 'TEXT'：`Audio / Transcript` 把组件本身和它内部的文本节点
 * 都叫 'Transcript'，不限定类型时 findOne 会先命中外层实例，
 * 往非文本节点上写 characters 既不报错也不生效 —— 26 屏的转写因此一直是旧文案。
 *
 * 找不到就抛错。生成器宁可当场炸掉，也不要安静地渲染出错误的文案。
 */
function setInstText(inst, nodeName, chars) {
  const n = inst.findOne(x => x.name === nodeName && x.type === 'TEXT');
  if (!n) throw new Error('setInstText: 找不到名为 "' + nodeName + '" 的文本节点');
  n.characters = chars;
  return inst;
}

function blocksWithHighlight(slots) {
  // 左右 12 + 槽位 8 = 20，与其它笔记屏的 block 左边缘对齐
  return F({ name: 'Blocks', dir: 'v', gap: 'space/4', w: 'system/screen-w',
             pad: ['space/4', 'space/12', 'space/4', 'space/12'], children: slots });
}

/* 25 / 26 必须落在**引它们过来的那条搜索结果所属的笔记**上。
 * 第 3 轮实读前这两屏用的是通用样例笔记「Q3 产品评审会」，于是原型走下来是：
 * 搜「延期毕业」→ 点「和 advisor 的邮件往来」→ 落到一条讲排期的会议纪要。
 * Demo 最关键的一步在这里断掉。内容必须对得上，这不是文案润色。 */

function scNoteFromSearchText() {
  // 对应 SEARCH_HITS[0]：正文块命中
  const tb = setInstText(iTextBlock(false), 'Content',
    '和 advisor 聊了下学期的安排。\n我问了能不能延期一个学期毕业，他说要先跟系里确认，让我别急着提交。');
  return screen('25 · 笔记页 · 来自搜索（正文命中）', [
    iStatus(), iNav({ title: '', leading: 'back', trailing: 'dots' }),
    iSummaryBar('问了延期一个学期的事，等系里确认'),
    F({ name: 'Body', dir: 'v', w: 'system/screen-w', grow: 1, clip: true, children: [
      noteHeader('学习', false, false, '和 advisor 的邮件往来'),
      blocksWithHighlight([
        blockSlot(tb, true),
        blockSlot(iAudio()),
        blockSlot(iImage()),
      ]),
    ] }),
    iToolbar('insert'), iHome(),
  ]);
}

function scNoteFromSearchTranscript() {
  // 对应 SEARCH_HITS[1]：录音转写命中。
  // 先展开 Transcript 再定位 —— 展开会改变布局高度，实现侧必须
  // expand → 等一次 layout pass → scroll，不能同帧执行（§3.4）。
  const audio = iAudio();
  try {
    const p = {}; p[P.blockAudio.Transcript] = C.audioTranscript.children[3].id;
    audio.setProperties(p);
  } catch (e) { }
  // expanded 变体给了 8 行的位置。塞一段真实长度的会议转写，
  // 既让命中句有上下文，也避免大片空白让这一屏看起来像坏了。
  setInstText(audio, 'Transcript',
    '「那我们过一下下周的事。排期这边设计下周一给终稿，后端同步开始。' +
    '延期的事你先别急，等下周开会再定，反正毕业时间还有缓冲，先把材料准备起来。' +
    '预算部分等财务回复后再定，别卡在这儿。」');
  return screen('26 · 笔记页 · 来自搜索（转写命中）', [
    iStatus(), iNav({ title: '', leading: 'back', trailing: 'dots' }),
    iSummaryBar('延期的事下周开会再定，时间还有缓冲'),
    F({ name: 'Body', dir: 'v', w: 'system/screen-w', grow: 1, clip: true, children: [
      noteHeader('工作', false, false, '周会录音 · 10/22'),
      blocksWithHighlight([
        blockSlot(setInstText(iTextBlock(false), 'Content', '周会要点：排期、分工、延期申请。')),
        blockSlot(audio, true),
      ]),
    ] }),
    iToolbar('insert'), iHome(),
  ]);
}

function scSettings() {
  const group = rows => {
    const kids = [];
    rows.forEach((r, i) => { kids.push(r); if (i < rows.length - 1) kids.push(hr(W - 32)); });
    return F({ name: 'Form Group', dir: 'v', w: W - 32, radius: 'radius/sm', fill: 'bg/card', clip: true, children: kids });
  };
  const sec = (hdr, g, foot) => {
    const kids = [];
    if (hdr) kids.push(F({ name: 'Header', dir: 'v', w: 'system/screen-w', pad: [0, 'space/32', 'space/4', 'space/32'],
                           children: [T(hdr, { s: 'iOS/Footnote', c: 'text/secondary' })] }));
    kids.push(g);
    if (foot) kids.push(F({ name: 'Footer', dir: 'v', w: 'system/screen-w', pad: ['space/4', 'space/32', 0, 'space/32'],
                            children: [T(foot, { s: 'iOS/Footnote', c: 'text/secondary', width: 329 })] }));
    return F({ name: 'Section / ' + (hdr || 'Other'), dir: 'v', w: 'system/screen-w', cross: 'CENTER', children: kids });
  };
  return screen('07 · 设置', [
    iStatus(), iNav({ title: '设置', leading: 'back' }),
    F({ name: 'Body', dir: 'v', gap: 'space/24', w: 'system/screen-w', grow: 1, cross: 'CENTER',
        pad: ['space/16', 0, 0, 0], clip: true, children: [
      sec('AI 服务商', group([iFormRow('chevron', '服务商', 'Kimi'), iFormRow('value', 'API Key', '••••••••••'),
                              iFormRow('action', '测试连接', undefined, 'idle')])),
      sec('摘要', group([iFormRow('toggle', '内容变更后自动追加更新总结')])),
      sec('语音转写', group([iFormRow('chevron', '转写方式', 'Apple 本地转写'), iFormRow('chevron', '识别语言', '自动')]),
          'Apple 本地转写在设备上完成，不上传音频，可离线。'),
      sec(null, group([iFormRow('chevron', '高级', ''), iFormRow('chevron', '关于', '')])),
    ] }),
    iHome(),
  ]);
}

function scFolders() {
  return screen('08 · 文件夹管理', [
    iStatus(), iNav({ title: '文件夹', leading: 'back', trailing: 'plus' }),
    F({ name: 'Body', dir: 'v', gap: 'space/12', w: 'system/screen-w', grow: 1, cross: 'CENTER',
        pad: ['space/8', 0, 0, 0], clip: true, children: [
      F({ name: 'List', dir: 'v', w: W - 32, radius: 'radius/sm', fill: 'bg/card', clip: true, children: [
        iFolderRow('工作', '12 张笔记', FOLDER_COLORS.work, 'briefcase', true), hr(W - 32),
        iFolderRow('读书', '8 张笔记', FOLDER_COLORS.book, 'book', true), hr(W - 32),
        iFolderRow('灵感', '3 张笔记', FOLDER_COLORS.idea, 'bulb', true), hr(W - 32),
        iFolderRow('旅行', '5 张笔记', FOLDER_COLORS.trip, 'folder', true)] })] }),
    iHome(),
  ]);
}

function scEmpty() {
  return screen('09 · 首启空状态', [
    iStatus(), iNav({ title: '全部笔记', leading: 'gear', trailing: 'search' }),
    F({ name: 'Body', dir: 'v', w: 'system/screen-w', grow: 1, main: 'CENTER', cross: 'CENTER', clip: true,
        children: [iEmptyState('还没有笔记', '点右下角 ✎ 写下第一条\n文字、录音、图片、文档、链接都能塞进来')] }),
    iBottom(), iHome(),
  ]);
}


// ---- Batch B 新增屏幕 ----

function settingsShell(title, sections) {
  return screen(title, [
    iStatus(), iNav({ title: title.split(' · ')[1] || '设置', leading: 'back' }),
    F({ name: 'Body', dir: 'v', gap: 'space/24', w: 'system/screen-w', grow: 1, cross: 'CENTER',
        pad: ['space/16', 0, 0, 0], clip: true, children: sections }),
    iHome(),
  ]);
}
function fgroup(rows) {
  const kids = [];
  rows.forEach((r, i) => { kids.push(r); if (i < rows.length - 1) kids.push(hr(W - 32)); });
  return F({ name: 'Form Group', dir: 'v', w: W - 32, radius: 'radius/sm', fill: 'bg/card', clip: true, children: kids });
}
function fsec(hdr, g, foot) {
  const kids = [];
  if (hdr) kids.push(F({ name: 'Header', dir: 'v', w: 'system/screen-w', pad: [0, 'space/32', 'space/4', 'space/32'],
                         children: [T(hdr, { s: 'iOS/Footnote', c: 'text/secondary' })] }));
  kids.push(g);
  if (foot) kids.push(F({ name: 'Footer', dir: 'v', w: 'system/screen-w', pad: ['space/4', 'space/32', 0, 'space/32'],
                          children: [T(foot, { s: 'iOS/Footnote', c: 'text/secondary', width: 329 })] }));
  return F({ name: 'Section / ' + (hdr || 'Other'), dir: 'v', w: 'system/screen-w', cross: 'CENTER', children: kids });
}

function scSettingsCustom() {
  return settingsShell('10 · 设置 · 自定义服务商', [
    fsec('AI 服务商', fgroup([
      iFormRow('chevron', '服务商', '自定义'),
      iFormRow('value', 'Base URL', 'https://…/v1'),
      iFormRow('value', '模型名称', 'gpt-4o-mini'),
      iFormRow('value', 'API Key', '••••••••••'),
      iFormRow('action', '测试连接', undefined, 'testing'),
    ]), '选择「自定义」后，Base URL 与模型名称从「高级」提升到第一屏 —— 此时它们是必填项。'),
    fsec('摘要', fgroup([iFormRow('toggle', '内容变更后自动追加更新总结')])),
  ]);
}

function scAdvancedSettings() {
  return settingsShell('11 · 高级设置', [
    fsec('AI 参数', fgroup([
      iFormRow('value', 'Base URL', 'https://api.moonshot.cn/v1'),
      iFormRow('value', '模型名称', 'kimi-k2.6'),
      iFormRow('toggle', '发送图片给 AI（视觉理解）'),
      iFormRow('toggle', '使用 JSON 输出模式'),
    ])),
    fsec('语音转写', fgroup([
      iFormRow('value', 'STT 模型', 'whisper-1'),
      iFormRow('value', 'STT Base URL', '留空复用上方'),
      iFormRow('value', 'STT API Key', '留空复用上方'),
    ]), 'Kimi 与 DeepSeek 均不提供 /audio/transcriptions，云端转写需指向 OpenAI 兼容服务。'),
    fsec('同步与数据', fgroup([iFormRow('toggle', '启用 iCloud 同步')]),
      'iCloud 同步需要付费开发者账号。更改后需重启 App 生效。'),
    fsec('隐私', fgroup([
      iFormRow('action', '重置隐私同意状态'),
      iFormRow('action', '重置音频上传同意状态'),
    ])),
    // Developer Mode 的入口规格在 design/DEVTOOLS.md §1 与 Track B 线框 D0。
    // 刻意**不画进这一屏**：本屏四节内容合计已达 699pt，逼近 720pt 的可视区，
    // 再加一节会被裁掉 —— 一个看不见的入口比没有入口更糟。
    // 真机上这是可滚动 Form，加一节没有问题；问题只在静态设计稿的表现力。
  ]);
}

function scSearchEmpty() {
  return screen('12 · 搜索 · 未输入', [
    iStatus(), iNav({ title: '搜索', leading: 'back' }),
    F({ name: 'Body', dir: 'v', w: 'system/screen-w', grow: 1, cross: 'CENTER', clip: true, children: [
      iSearchField('idle'),
      F({ name: 'Tag Filter', dir: 'h', gap: 'space/8', w: 'system/screen-w',
          pad: ['space/8', 'space/16', 'space/12', 'space/16'], clip: true,
          children: [iTag('#排期'), iTag('#分工'), iTag('#读书')] }),
      // 自然语言示例区。空 query 是教会用户「这个框不止能搜关键词」的唯一时机 ——
      // 一张通用空状态插画在这里不如三句可点的例子有用。
      F({ name: 'Header', dir: 'v', w: 'system/screen-w',
          pad: ['space/8', 'space/20', 'space/4', 'space/20'], children: [
        T('试试这样搜', { s: 'iOS/Footnote', c: 'text/secondary' })] }),
      F({ name: 'Examples', dir: 'v', w: 'system/screen-w',
          children: SEARCH_EXAMPLES.map(q => F({
            name: 'Example', dir: 'h', gap: 'space/12', w: 'system/screen-w',
            h: 'system/tap-min', cross: 'CENTER', pad: [0, 'space/20', 0, 'space/20'], children: [
              ic('search', 'icon/sm', 'text/tertiary'),
              T(q, { s: 'iOS/Subheadline', c: 'accent/blue', lines: 1, grow: 1, name: 'Query' })] })) }),
      // Goal 1 检索语料：文字 / 转写稿 / 图片文字 / 文档 / 链接 + 标题 · 标签作为 lexical signal。
      // AI 摘要不在语料内（Correction 4），故文案不提它。
      F({ name: 'Footer', dir: 'v', w: 'system/screen-w',
          pad: ['space/12', 'space/20', 0, 'space/20'], children: [
        T('搜索标题、文字、转写稿、图片文字、文档与链接',
          { s: 'iOS/Footnote', c: 'text/tertiary', width: W - 40 })] }),
    ] }),
    iHome(),
  ]);
}

function scSearchNoResult() {
  return screen('13 · 搜索 · 无结果', [
    iStatus(), iNav({ title: '搜索', leading: 'back' }),
    F({ name: 'Body', dir: 'v', w: 'system/screen-w', grow: 1, cross: 'CENTER', clip: true, children: [
      iSearchField('typing', '量子纠缠'),
      iEmptyState('没有找到匹配的笔记', '换个说法试试'),
    ] }),
    iHome(),
  ]);
}

function scFolderEmpty() {
  return screen('14 · 文件夹管理 · 空', [
    iStatus(), iNav({ title: '文件夹', leading: 'back', trailing: 'plus' }),
    F({ name: 'Body', dir: 'v', w: 'system/screen-w', grow: 1, main: 'CENTER', cross: 'CENTER', clip: true,
        children: [iEmptyState('还没有文件夹', '文件夹是可选的 —— 不建也能正常记笔记，\n所有笔记都会留在「未归类」', '新建文件夹')] }),
    iHome(),
  ]);
}

function scHomeFolderEmpty() {
  return screen('15 · 首页 · 文件夹为空', [
    iStatus(), iNav({ title: '灵感', leading: 'gear', trailing: 'search' }),
    F({ name: 'Folder Filter', dir: 'h', gap: 'space/8', w: 'system/screen-w',
        pad: ['space/8', 'space/16', 'space/12', 'space/16'], clip: true, children: [
      iChip('全部'), iChip('未归类'), iChip('工作', 'default', FOLDER_COLORS.work),
      iChip('灵感', 'selected', FOLDER_COLORS.idea), iChip('更多', 'more')] }),
    F({ name: 'Body', dir: 'v', w: 'system/screen-w', grow: 1, main: 'CENTER', cross: 'CENTER', clip: true,
        children: [iEmptyState('这个文件夹还是空的', '点右下角新建，或切换到其它文件夹', '查看全部笔记')] }),
    iBottom(), iHome(),
  ]);
}

/** 覆盖层集中展示屏：Dialog / Sheet / Menu 的实际渲染。 */
function scOverlays() {
  const p = screen('16 · 覆盖层 · Dialog / Sheet', [
    iStatus(), iNav({ title: '', leading: 'back', trailing: 'dots' }),
    F({ name: 'Body', dir: 'v', w: 'system/screen-w', grow: 1, clip: true, children: [
      F({ name: 'Head', dir: 'v', w: 'system/screen-w', pad: ['space/16', 'space/20', 0, 'space/20'],
          children: [T('Q3 产品评审会', { s: 'iOS/Title1' })] })] }),
    iHome(),
  ]);
  scrim(p);
  const dlg = C.dialogConfirmation.children[1].createInstance();
  dlg.name = 'Dialog / 删除确认';
  const dp = {};
  dp[P.dialogConfirmation.Title] = '删除笔记';
  dp[P.dialogConfirmation.Message] = '此操作不可撤销。';
  try { dlg.setProperties(dp); } catch (e) { }
  abs(p, dlg, 32, 300);
  return p;
}

function scRecorderSheet() {
  const p = screen('17 · 录音 Sheet · 录制中', [
    iStatus(), iNav({ title: '', leading: 'back', trailing: 'dots' }),
    F({ name: 'Body', dir: 'v', w: 'system/screen-w', grow: 1, clip: true, children: [
      F({ name: 'Head', dir: 'v', w: 'system/screen-w', pad: ['space/16', 'space/20', 0, 'space/20'],
          children: [T('Q3 产品评审会', { s: 'iOS/Title1' })] })] }),
    iHome(),
  ]);
  scrim(p);
  const sh = C.sheetRecorder.children[1].createInstance();
  sh.name = 'Recorder Sheet';
  abs(p, sh, 0, H - 34 - sh.height);
  return p;
}

function scPermissionDenied() {
  const p = screen('18 · 权限被拒 · 麦克风', [
    iStatus(), iNav({ title: '', leading: 'back', trailing: 'dots' }),
    F({ name: 'Body', dir: 'v', w: 'system/screen-w', grow: 1, clip: true, children: [
      F({ name: 'Head', dir: 'v', w: 'system/screen-w', pad: ['space/16', 'space/20', 0, 'space/20'],
          children: [T('Q3 产品评审会', { s: 'iOS/Title1' })] })] }),
    iHome(),
  ]);
  scrim(p);
  const sh = C.sheetPermission.children[2].createInstance();
  sh.name = 'Permission Sheet';
  abs(p, sh, 32, 280);
  return p;
}

function scAIStates() {
  const rows = SUMMARY_ORDER.map(st => {
    // 走 iSummaryBar 而不是自己 createInstance —— 兜底文案就在那里。
    // 这一屏的全部意义就是九个状态各不相同，之前八行显示同一句「AI 一句话概述」。
    const inst = iSummaryBar(null, st);
    inst.name = 'Summary / ' + st;
    return F({ name: 'Row / ' + st, dir: 'v', gap: 'space/4', w: 'system/screen-w', children: [
      F({ name: 'Label', dir: 'v', w: 'system/screen-w', pad: [0, 'space/16', 0, 'space/16'],
          children: [T('state = ' + st, { s: 'iOS/Caption2', c: 'text/secondary' })] }),
      inst] });
  });
  return screen('19 · AI 摘要 9 态一览', [
    iStatus(), iNav({ title: 'AI 摘要状态', leading: 'back' }),
    F({ name: 'Body', dir: 'v', gap: 'space/8', w: 'system/screen-w', grow: 1, clip: true,
        pad: ['space/8', 0, 0, 0], children: rows }),
    iHome(),
  ]);
}

function scBlockStates() {
  // 宽度必须是容器内宽 353，用 393 会在 x=20 处右溢出 20pt
  const label = t => F({ name: 'Block State Label', dir: 'v', w: 353,
                         children: [T(t, { s: 'iOS/Caption2', c: 'text/secondary' })] });
  return screen('20 · 内容块状态一览', [
    iStatus(), iNav({ title: '内容块状态', leading: 'back' }),
    F({ name: 'Body', dir: 'v', gap: 'space/8', w: 'system/screen-w', grow: 1, clip: true,
        pad: ['space/8', 'space/20', 'space/8', 'space/20'], children: [
      label('Image · failed'), iImage('failed'),
      label('Audio · transcribing'), iAudio('transcribing'),
      label('Audio · failed'), iAudio('failed'),
      label('Document · unsupported'), iDocument('unsupported'),
      label('Link · failed（链接仍可点）'), iLink('failed'),
    ] }),
    iHome(),
  ]);
}

// =============================================================== 12. 基础规范板

function foundationsBoard() {
  const swatch = name => F({ name: 'Swatch / ' + name, dir: 'v', gap: 'space/4', children: [
    F({ name: 'Color', w: 104, h: 56, radius: 'radius/sm', fill: name, strokeToken: 'separator' }),
    T(name, { s: 'iOS/Caption2', c: 'text/secondary', width: 104 })] });

  const scaleGroup = (label, prefix) => {
    const keys = Object.keys(SCALE).filter(k => k.indexOf(prefix) === 0);
    return F({ name: 'Scale / ' + label, dir: 'v', gap: 'space/4', children: [
      T(label, { s: 'iOS/Footnote Emphasized', c: 'text/secondary' }),
      F({ name: 'Values', dir: 'h', gap: 'space/8', cross: 'MAX', children: keys.map(k =>
        F({ name: k, dir: 'v', gap: 'space/4', cross: 'CENTER', children: [
          R(Math.max(4, Math.min(72, SCALE[k])), 24, 'accent/blue-bg', 'radius/xs'),
          T(k.split('/')[1] + ' = ' + SCALE[k], { s: 'iOS/Caption2', c: 'text/tertiary' })] })) }),
    ] });
  };

  const typeRows = Object.keys(TYPE).map(name => F({
    name: 'Type / ' + name, dir: 'h', gap: 'space/16', cross: 'CENTER', children: [
      T(name.replace('iOS/', ''), { s: 'iOS/Caption1', c: 'text/secondary', width: 150 }),
      T(TYPE[name][0] + ' / ' + TYPE[name][1], { s: 'iOS/Caption1', c: 'text/tertiary', width: 56 }),
      T('万象记 Mosaic 多媒体笔记', { s: name })] }));

  return F({
    name: '基础规范', dir: 'v', gap: 'space/24', pad: ['space/32', 'space/32', 'space/32', 'space/32'],
    fill: 'bg/primary', radius: 'radius/lg', children: [
      T('万象记 Mosaic — 设计基础（Batch A 收敛后）', { s: 'iOS/LargeTitle' }),
      T('颜色 · 变量集合「Mosaic Color」，Light / Dark 双模式', { s: 'iOS/Subheadline Emphasized', c: 'text/secondary' }),
      F({ name: 'Colors 1', dir: 'h', gap: 'space/12', children: Object.keys(COLORS).slice(0, 8).map(swatch) }),
      F({ name: 'Colors 2', dir: 'h', gap: 'space/12', children: Object.keys(COLORS).slice(8).map(swatch) }),
      T('数值 · 变量集合「Mosaic Scale」', { s: 'iOS/Subheadline Emphasized', c: 'text/secondary' }),
      scaleGroup('spacing（8pt 网格 · 7 档）', 'space/'),
      scaleGroup('radius（4 档 + capsule）', 'radius/'),
      scaleGroup('icon（3 档）', 'icon/'),
      scaleGroup('row', 'row/'),
      T('系统几何值 —— 由 iOS 规定，不参与收敛', { s: 'iOS/Subheadline Emphasized', c: 'text/secondary' }),
      F({ name: 'System Values', dir: 'v', gap: 'space/4', children:
        Object.keys(SCALE).filter(k => k.indexOf('system/') === 0).map(k =>
          T(k + ' = ' + SCALE[k], { s: 'iOS/Caption1', c: 'text/secondary' })) }),
      T('全局按下规则', { s: 'iOS/Subheadline Emphasized', c: 'text/secondary' }),
      T('按下态 = 背景叠加 8% 或整体 opacity 0.7。仅当按下外观与常态有结构性差异时才建 Variant；\n'
        + '列表行按下高亮由 iOS List 自动提供，不做设计交付。', { s: 'iOS/Footnote', c: 'text/secondary', width: 700 }),
      T('触控目标规则', { s: 'iOS/Subheadline Emphasized', c: 'text/secondary' }),
      T('所有可点元素的 hit area ≥ 44×44pt（system/tap-min）。视觉尺寸可小于该值，\n'
        + '由透明底板撑开；组件中以 Tappable 容器表达。', { s: 'iOS/Footnote', c: 'text/secondary', width: 700 }),
      T('字阶 · 文字样式 iOS/*', { s: 'iOS/Subheadline Emphasized', c: 'text/secondary' }),
      F({ name: 'Type', dir: 'v', gap: 'space/8', children: typeRows }),
    ],
  });
}


// =============================================================== 12.5 原型连线

/** 10 条核心 Flow 的连线定义。fromScreen / hotspot / toScreen 均按名称匹配。 */
const FLOWS = [
  { flow: 1, from: '01 · 首页', hot: 'Note Row / Q3 产品评审会', to: '02 · 笔记页 · 摘要收起', desc: '首页 → 打开笔记' },
  { flow: 1, from: '01 · 首页', hot: 'Compose', to: '05 · 编辑器', desc: '首页 → 新建笔记' },
  { flow: 1, from: '05 · 编辑器', hot: 'Nav Bar', to: '01 · 首页', desc: '返回 → 触发 AI 生成' },
  { flow: 2, from: '05 · 编辑器', hot: 'Media Insert', to: '17 · 录音 Sheet', desc: '聚焦态 ＋ → 媒体插入（键盘不收起）' },
  { flow: 2, from: '17 · 录音 Sheet', hot: 'Recorder Sheet', to: '02 · 笔记页 · 摘要收起', desc: '录音完成 → 插入笔记' },
  { flow: 3, from: '01 · 首页', hot: 'Bottom Bar', to: '15 · 首页 · 文件夹为空', desc: '切换文件夹筛选' },
  { flow: 4, from: '02 · 笔记页 · 摘要收起', hot: 'Folder Meta / 工作', to: '16 · 覆盖层', desc: '笔记内改归属 → Folder Picker' },
  { flow: 4, from: '04 · 笔记页 · ⋯ 菜单', hot: 'Menu Item / 移动到文件夹…', to: '16 · 覆盖层', desc: '⋯ 次入口 → 同一 Picker' },
  { flow: 5, from: '02 · 笔记页 · 摘要收起', hot: 'Summary Bar', to: '03 · 笔记页 · 摘要展开', desc: '摘要收起 → 展开' },
  { flow: 5, from: '03 · 笔记页 · 摘要展开', hot: 'Summary Panel', to: '02 · 笔记页 · 摘要收起', desc: '摘要展开 → 收起' },
  { flow: 6, from: '02 · 笔记页 · 摘要收起', hot: 'Nav Bar', to: '04 · 笔记页 · ⋯ 菜单', desc: '⋯ 菜单' },
  { flow: 6, from: '04 · 笔记页 · ⋯ 菜单', hot: 'Menu Item / 重新生成完整总结', to: '16 · 覆盖层', desc: '重新生成 → 确认对话框' },
  { flow: 6, from: '16 · 覆盖层', hot: 'Dialog / 删除确认', to: '19 · AI 摘要 9 态一览', desc: '确认 → 进入 generating' },
  { flow: 7, from: '01 · 首页', hot: 'Nav Bar', to: '12 · 搜索 · 未输入', desc: '首页 → 搜索' },
  { flow: 7, from: '12 · 搜索 · 未输入', hot: 'Tag / #排期', to: '06 · 搜索', desc: '点标签 → 出结果' },
  // 结果落到的是**高亮态**笔记页，不是普通笔记页 —— 定位反馈是这条 Flow 的重点
  { flow: 7, from: '06 · 搜索', hot: 'Search Result', to: '25 · 笔记页 · 来自搜索（正文命中）', desc: '结果 → 打开笔记并定位高亮' },
  { flow: 7, from: '25 · 笔记页 · 来自搜索（正文命中）', hot: 'Nav Bar', to: '06 · 搜索', desc: '返回 → query / 结果 / 滚动位置全部恢复' },
  { flow: 7, from: '06 · 搜索', hot: 'Search Field', to: '13 · 搜索 · 无结果', desc: '换关键词 → 无结果' },
  { flow: 7, from: '12 · 搜索 · 未输入', hot: 'Example', to: '24 · 搜索 · 全部为相关结果', desc: '点自然语言示例 → 整页相关结果' },
  { flow: 7, from: '23 · 搜索 · 智能搜索不可用', hot: 'Search Status', to: '06 · 搜索', desc: '重试成功 → 恢复 Hybrid' },
  { flow: 8, from: '08 · 文件夹管理', hot: 'Nav Bar', to: '14 · 文件夹管理 · 空', desc: '文件夹增删改' },
  { flow: 9, from: '07 · 设置', hot: 'Form Row / 服务商', to: '10 · 设置 · 自定义服务商', desc: '切换 Provider' },
  { flow: 9, from: '07 · 设置', hot: 'Form Row / 测试连接', to: '10 · 设置 · 自定义服务商', desc: '测试连接 → testing 态' },
  { flow: 10, from: '07 · 设置', hot: 'Form Row / 高级', to: '11 · 高级设置', desc: '进入高级设置' },
  // 05 是自适应工具条（只有 ＋），独立录音按钮在 02 的插入工具条上
  { flow: 2, from: '02 · 笔记页 · 摘要收起', hot: 'Audio', to: '18 · 权限被拒', desc: '录音 → 权限被拒' },
];

async function wirePrototype(screens) {
  const byPrefix = {};
  screens.forEach(sc => { byPrefix[sc.name.slice(0, 2)] = sc; });
  const find = title => screens.find(sc => sc.name.indexOf(title.slice(0, 2)) === 0);
  let wired = 0, missed = [];
  for (const f of FLOWS) {
    const from = find(f.from), to = find(f.to);
    if (!from || !to) { missed.push(f.desc + '（缺屏）'); continue; }
    const hot = from.findOne ? from.findOne(n => n.name === f.hot || (n.name || '').split(' / ')[0] === f.hot) : null;
    if (!hot) { missed.push(f.desc + '（缺热区 ' + f.hot + '）'); continue; }
    const reaction = {
      trigger: { type: 'ON_CLICK' },
      action: { type: 'NODE', destinationId: to.id, navigation: 'NAVIGATE',
                transition: { type: 'SMART_ANIMATE', easing: { type: 'EASE_OUT' }, duration: SCALE['duration/normal'] },
                preserveScrollPosition: false },
    };
    try { await hot.setReactionsAsync([reaction]); wired++; }
    catch (e) { try { hot.reactions = [reaction]; wired++; } catch (e2) { missed.push(f.desc + '（连线失败）'); } }
  }
  return { wired, missed };
}

// =============================================================== 13. 主流程

function sweep(page, keep) {
  page.children.slice().forEach(n => { if (keep.indexOf(n) < 0) { try { n.remove(); } catch (e) { } } });
}
function getPage(name) {
  const same = (figma.root.children || []).filter(p => p.name === name);
  if (same.length) {
    const keep = same[0];
    keep.children.slice().forEach(c => { try { c.remove(); } catch (e) { } });
    same.slice(1).forEach(p => { try { p.remove(); } catch (e) { } });
    return keep;
  }
  const p = figma.createPage(); p.name = name; return p;
}
function caption(title, note) {
  return F({ name: 'Caption', dir: 'v', gap: 'space/4', w: 'system/screen-w', children: [
    T(title, { s: 'iOS/Callout' }),
    T(note, { s: 'iOS/Caption1', c: 'text/secondary', width: W })] });
}

const SCREENS = [
  { fn: scHome, title: '01 · 首页 · 全部笔记', note: '底部 toolbar 新建（D-01）· Folder Chips 含「更多」溢出（D-04）· 笔记行含 5 种 Preview 与 AI Badge' },
  { fn: scNoteCollapsed, title: '02 · 笔记页 · 摘要收起', note: '导航栏留空标题；归属为标题下方 Folder Meta Chip（D-02）· 五种 Block 各一' },
  { fn: scNoteExpanded, title: '03 · 笔记页 · 摘要展开', note: 'Topic Chip 为独立组件，added 态用实心+✓（D-06）' },
  { fn: scNoteMenu, title: '04 · 笔记页 · ⋯ 菜单', note: '含「移动到文件夹…」次入口（D-02）' },
  { fn: scEditing, title: '05 · 编辑器 · 聚焦', note: '单层自适应工具条：＋ 收纳媒体插入，聚焦时媒体仍可达（D-03）' },
  { fn: scSearch, title: '06 · 搜索', note: '标签筛选的新家' },
  { fn: scSettings, title: '07 · 设置', note: '动作行状态由嵌套 Form / Action Status 表达' },
  { fn: scFolders, title: '08 · 文件夹管理', note: '原首页降级至此' },
  { fn: scEmpty, title: '09 · 首启空状态', note: '使用共享 Empty State 组件（A-15）' },
  { fn: scSettingsCustom, title: '10 · 设置 · 自定义服务商', note: 'Base URL 与模型名提升到第一屏；测试连接处于 testing 态' },
  { fn: scAdvancedSettings, title: '11 · 高级设置', note: '分 4 节：AI 参数 / 语音转写 / 同步 / 隐私 —— 不是一个长列表' },
  { fn: scSearchEmpty, title: '12 · 搜索 · 未输入', note: '标签 chip 可直接点选' },
  { fn: scSearchNoResult, title: '13 · 搜索 · 无结果', note: '与「未输入」文案不同' },
  { fn: scFolderEmpty, title: '14 · 文件夹管理 · 空', note: '文案说明文件夹是可选的，不诱导必须创建' },
  { fn: scHomeFolderEmpty, title: '15 · 首页 · 文件夹为空', note: '选中的 Folder Chip 始终留在主行（D-04）' },
  { fn: scOverlays, title: '16 · 覆盖层 · 删除确认', note: 'destructive 按钮红色且非默认焦点' },
  { fn: scRecorderSheet, title: '17 · 录音 Sheet · 录制中', note: '5 态之一；不套二级 Sheet' },
  { fn: scPermissionDenied, title: '18 · 权限被拒 · 麦克风', note: '必含「去设置」，不留死路' },
  { fn: scAIStates, title: '19 · AI 摘要 9 态一览', note: '错误态 CTA 各不相同：配置类→去设置，网络/限流→重试' },
  { fn: scBlockStates, title: '20 · 内容块状态一览', note: 'Link failed 仍显示可点 URL；Image failed 提供重试/移除' },
  { fn: scSearching, title: '21 · 搜索 · 检索中', note: 'spinner 只在搜索框尾部；上一次结果原封不动留在屏上（不变量 I5）' },
  { fn: () => scSearchDegraded('22 · 搜索 · 索引建立中', 'building'),
    title: '22 · 搜索 · 索引建立中', note: 'keyword 结果照常；只有纯语义那条消失 —— Progressive Enhancement 的证据屏' },
  { fn: () => scSearchDegraded('23 · 搜索 · 智能搜索不可用', 'degraded'),
    title: '23 · 搜索 · 智能搜索不可用', note: '带「重试」CTA；结果照常，不弹窗、不阻断' },
  { fn: scSearchSemanticOnly, title: '24 · 搜索 · 全部为相关结果',
    note: '自然语言 query 找回同一批笔记但一个关键词都没对上 —— 整页零高亮时才加那一行说明（§2.6）' },
  { fn: scNoteFromSearchText, title: '25 · 笔记页 · 来自搜索（正文命中）',
    note: 'block 级临时高亮：2.0s 保持 + 0.4s 淡出；正文内不注入 term 级高亮' },
  { fn: scNoteFromSearchTranscript, title: '26 · 笔记页 · 来自搜索（转写命中）',
    note: 'Transcript 先展开再定位；展开改变布局高度，实现侧不可与 scroll 同帧' },
];

async function main() {
  FONT = await resolveFont();
  buildVariables();
  buildTextStyles();
  buildEffectStyles();

  PG.foundations = getPage('📐 Foundations');
  PG.components = getPage('🧩 Components');
  PG.screens = getPage('📱 Screens');

  figma.currentPage = PG.components;
  buildComponents(PG.components);
  let cy = 0;
  PG.components.children
    .filter(n => n.type === 'COMPONENT' || n.type === 'COMPONENT_SET')
    .forEach(node => { node.x = 0; node.y = cy; cy += node.height + 60; });

  figma.currentPage = PG.foundations;
  const found = foundationsBoard();
  setMode(found, MODE_L);
  PG.foundations.appendChild(found);
  found.x = 0; found.y = 0;

  figma.currentPage = PG.screens;
  const build = () => SCREENS.map(s => ({ node: s.fn(), title: s.title, note: s.note }));
  const mkBoard = (name, modeId, items) => {
    const cols = items.map(it => F({ name: 'Column / ' + it.title, dir: 'v', gap: 'space/12',
                                     children: [caption(it.title, it.note), it.node] }));
    const b = F({ name: name, dir: 'h', gap: 'space/32', pad: ['space/32', 'space/32', 'space/32', 'space/32'],
                  fill: 'bg/primary', radius: 'radius/lg', children: cols });
    setMode(b, modeId);
    return b;
  };
  const lightItems = build();
  const lightBoard = mkBoard('01 · 全部界面（Light）', MODE_L, lightItems);
  PG.screens.appendChild(lightBoard); lightBoard.x = 0; lightBoard.y = 0;
  const darkBoard = mkBoard('02 · 全部界面（Dark）', MODE_D, build());
  PG.screens.appendChild(darkBoard); darkBoard.x = 0; darkBoard.y = lightBoard.height + 100;

  const proto = await wirePrototype(lightItems.map(i => i.node));

  sweep(PG.foundations, [found]);
  sweep(PG.components, PG.components.children.filter(n => n.type === 'COMPONENT' || n.type === 'COMPONENT_SET'));
  sweep(PG.screens, [lightBoard, darkBoard]);

  PG.screens.selection = [lightBoard];
  figma.viewport.scrollAndZoomIntoView([lightBoard]);

  const compCount = PG.components.children.length;
  figma.notify('✅ Batch B 生成完成：' + compCount + ' 个组件 · ' +
    Object.keys(COLORS).length + ' 色变量 · ' + Object.keys(SCALE).length + ' 数值变量 · ' +
    SCREENS.length + ' 屏 ×2 模式 · ' + proto.wired + ' 条原型连线 · 字体 ' + FONT.family, { timeout: 9000 });
  figma.closePlugin();
}

main().catch(err => {
  console.error(err);
  figma.notify('生成失败：' + (err && err.message ? err.message : String(err)), { error: true, timeout: 10000 });
  figma.closePlugin();
});
