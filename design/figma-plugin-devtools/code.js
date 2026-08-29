/* ============================================================================
 * Mosaic Dev Tools 线框生成器 —— Track B
 * ----------------------------------------------------------------------------
 * 与 `design/figma-plugin/`（Production 生成器）**完全分离**：
 *
 *   · 独立 manifest / 独立插件，不共享任何代码
 *   · 只创建并重建一个页面：🔧 Dev Tools (Wireframe)
 *   · 不创建 / 不读取任何 Variable、Text Style、Effect Style
 *   · 不进 calibration，不做 ±1pt 校验，不做 Dark Mode
 *   · 灰度盒子 + 原生控件近似，不追求视觉
 *
 * 目标：Functional Specification > Visual Polish。
 * 一个 SwiftUI 工程师看完能直接写出来，且不需要现场决定信息结构。
 *
 * 页面清单（10 屏）
 *   D0 入口规格                设置 › 高级 要新增的那一节
 *   D1 Developer Mode          入口列表
 *   D2 Retrieval Lab           Query + Config + Result Inspector
 *   D3 Retrieval Lab · Compare Keyword / Vector / Hybrid 对比
 *   D4 Retrieval Trace         Pipeline + Index metadata
 *   D5 Eval Center             Dataset × Config → 指标
 *   D6 Eval Center · Compare   Current vs Baseline vs Delta
 *   D7 Release Gate · PASS
 *   D8 Release Gate · BLOCKED
 *   D9 Failure Inspection      （SwiftUI-first，线框只为把 Flow B/C 走通）
 * ========================================================================== */

const W = 393, H = 852;
const PAGE = '🔧 Dev Tools (Wireframe)';

/* 灰度 + 原生控件近似色。刻意不用 Variable —— Track B 不引入任何 token。 */
const C = {
  bg: 'F2F2F7', card: 'FFFFFF', fill: 'E9E9EB',
  text: '000000', sec: '6B6B70', ter: '9A9AA0',
  sep: 'D1D1D6', accent: '007AFF', ok: '2E7D32', bad: 'C62828',
  okBg: 'E6F4EA', badBg: 'FCE8E6',
};
const FONT = { R: { family: 'PingFang SC', style: 'Regular' }, S: { family: 'PingFang SC', style: 'Semibold' } };
/* 字号阶：不建立 Text Style，直接给数值。低保真够用。 */
const SZ = { title: 22, h: 17, body: 16, sub: 14, cap: 12, big: 34 };

function paint(hex) {
  const n = parseInt(hex, 16);
  return [{ type: 'SOLID', color: { r: ((n >> 16) & 255) / 255, g: ((n >> 8) & 255) / 255, b: (n & 255) / 255 } }];
}

function F(o) {
  const f = figma.createFrame();
  f.name = o.name || 'Frame';
  f.layoutMode = o.dir === 'h' ? 'HORIZONTAL' : o.dir === 'none' ? 'NONE' : 'VERTICAL';
  f.fills = o.fill ? paint(o.fill) : [];
  f.clipsContent = !!o.clip;
  if (o.radius) f.cornerRadius = o.radius;
  if (f.layoutMode !== 'NONE') {
    f.itemSpacing = o.gap || 0;
    f.primaryAxisAlignItems = o.main || 'MIN';
    f.counterAxisAlignItems = o.cross || 'MIN';
    const p = o.pad || [0, 0, 0, 0];
    f.paddingTop = p[0]; f.paddingRight = p[1]; f.paddingBottom = p[2]; f.paddingLeft = p[3];
    if (f.layoutMode === 'HORIZONTAL') {
      f.primaryAxisSizingMode = o.w ? 'FIXED' : 'AUTO';
      f.counterAxisSizingMode = o.h ? 'FIXED' : 'AUTO';
    } else {
      f.primaryAxisSizingMode = o.h ? 'FIXED' : 'AUTO';
      f.counterAxisSizingMode = o.w ? 'FIXED' : 'AUTO';
    }
  }
  (o.children || []).forEach(c => { if (c) f.appendChild(c); });
  if (o.w || o.h) f.resize(o.w || Math.max(0.01, f.width), o.h || Math.max(0.01, f.height));
  if (o.grow) f.layoutGrow = 1;
  if (o.stretch) f.layoutAlign = 'STRETCH';
  return f;
}

function T(chars, o) {
  o = o || {};
  const t = figma.createText();
  t.fontName = o.bold ? FONT.S : FONT.R;
  t.fontSize = o.size || SZ.body;
  t.lineHeight = { unit: 'PIXELS', value: Math.round((o.size || SZ.body) * 1.35) };
  t.characters = chars;
  t.name = o.name || (chars.slice(0, 16) || 'Text');
  t.fills = paint(o.c || C.text);
  if (o.align) t.textAlignHorizontal = o.align;
  if (o.w) { t.resize(o.w, Math.max(1, t.height)); t.textAutoResize = 'HEIGHT'; }
  else if (o.grow || o.stretch) t.textAutoResize = 'HEIGHT';
  else t.textAutoResize = 'WIDTH_AND_HEIGHT';
  if (o.grow) t.layoutGrow = 1;
  if (o.stretch) t.layoutAlign = 'STRETCH';
  return t;
}

function rect(w, h, hex, r) {
  const x = figma.createRectangle();
  x.name = 'Box'; x.resize(Math.max(0.01, w), Math.max(0.01, h)); x.fills = paint(hex);
  if (r) x.cornerRadius = r;
  return x;
}
const sep = () => rect(W - 32, 0.5, C.sep);
const spacer = () => { const f = F({ name: 'Spacer', w: 1, h: 1 }); f.layoutGrow = 1; return f; };

/* ---------------------------------------------------------------- 原生控件近似 */

function navBar(title, back) {
  return F({
    name: 'Nav Bar', dir: 'h', w: W, h: 44, cross: 'CENTER', pad: [0, 16, 0, 16], fill: C.card,
    children: [
      back ? T('‹ 返回', { size: SZ.body, c: C.accent, name: 'Back' }) : T('', { size: SZ.body }),
      spacer(),
      T(title, { size: SZ.h, bold: true, name: 'Title' }),
      spacer(),
      T('', { size: SZ.body }),
    ],
  });
}

function header(text) {
  return F({
    name: 'Section Header', dir: 'v', w: W, pad: [18, 16, 6, 16],
    children: [T(text.toUpperCase(), { size: SZ.cap, c: C.ter })],
  });
}

/** Form / List 行。type: value | chevron | toggle | action | plain */
function row(label, value, type, opts) {
  opts = opts || {};
  const right = [];
  if (value !== undefined && value !== null && value !== '')
    right.push(T(String(value), { size: SZ.body, c: opts.valueColor || C.sec, name: 'Value' }));
  if (type === 'chevron') right.push(T('›', { size: SZ.body, c: C.ter }));
  if (type === 'toggle') right.push(rect(51, 31, opts.on ? C.accent : C.sep, 16));
  return F({
    name: (opts.name || 'Row') + ' / ' + label, dir: 'h', w: W, h: opts.h || 44, cross: 'CENTER',
    pad: [0, 16, 0, 16], fill: C.card,
    children: [
      T(label, { size: SZ.body, c: type === 'action' ? C.accent : C.text, bold: !!opts.bold, name: 'Label' }),
      spacer(),
    ].concat(right),
  });
}

/** 指标行：label 左，右侧一列数值。 */
function metric(label, value, note) {
  return F({
    name: 'Metric / ' + label, dir: 'h', w: W, h: 40, cross: 'CENTER', pad: [0, 16, 0, 16], fill: C.card,
    children: [
      T(label, { size: SZ.sub, name: 'Label' }), spacer(),
      note ? T(note, { size: SZ.cap, c: C.ter }) : null,
      T(value, { size: SZ.sub, bold: true, name: 'Value' }),
    ].filter(Boolean),
  });
}

/** 四列对比行：Metric / Current / Baseline / Delta。 */
function cmpRow(label, cur, base, delta, tone) {
  const col = (s, o) => T(s, Object.assign({ size: SZ.cap, w: 74, align: 'RIGHT' }, o || {}));
  return F({
    name: 'Compare / ' + label, dir: 'h', w: W, h: 36, cross: 'CENTER', pad: [0, 16, 0, 16], fill: C.card,
    children: [
      T(label, { size: SZ.cap, w: 105, name: 'Label' }),
      col(cur, { bold: true }), col(base, { c: C.sec }),
      col(delta, { c: tone === 'bad' ? C.bad : tone === 'ok' ? C.ok : C.sec, bold: true }),
    ],
  });
}

/** Gate 检查行：条件 + PASS/FAIL 徽标。 */
function gateRow(label, expr, pass, cta) {
  return F({
    name: 'Gate / ' + label, dir: 'h', w: W, h: 52, cross: 'CENTER', pad: [0, 16, 0, 16],
    fill: pass ? C.card : C.badBg,
    children: [
      F({ name: 'Text', dir: 'v', gap: 2, children: [
        T(label, { size: SZ.sub, bold: true, name: 'Label' }),
        T(expr, { size: SZ.cap, c: C.sec, name: 'Expr' }),
      ] }),
      spacer(),
      cta ? T(cta, { size: SZ.cap, c: C.accent, name: 'Open Failures' }) : null,
      F({ name: 'Badge', dir: 'h', h: 22, pad: [0, 8, 0, 8], cross: 'CENTER', radius: 4,
          fill: pass ? C.okBg : C.badBg,
          children: [T(pass ? 'PASS' : 'FAIL', { size: SZ.cap, bold: true, c: pass ? C.ok : C.bad })] }),
    ].filter(Boolean),
  });
}

function primaryBtn(label, disabled) {
  return F({
    name: 'Primary Action', dir: 'h', w: W - 32, h: 48, main: 'CENTER', cross: 'CENTER', radius: 10,
    fill: disabled ? C.fill : C.accent,
    children: [T(label, { size: SZ.body, bold: true, c: disabled ? C.ter : 'FFFFFF' })],
  });
}

function screen(name, children) {
  return F({ name: name, dir: 'v', w: W, h: H, fill: C.bg, clip: true, children: children });
}
function body(children, gap) {
  return F({ name: 'Body', dir: 'v', gap: gap === undefined ? 0 : gap, w: W, grow: 1, clip: true, children: children });
}

/* ---------------------------------------------------------------- 结果检查器
 *
 * D-UI-DEV-002：竖排卡片，不用横向表格。
 * 393pt 放不下 8 列；把「排名证据」压成一行 K/V/→ 记号，
 * 目标是 5 秒内能解释「为什么 Hybrid 把这条排在这里」。
 */
function resultCard(o) {
  return F({
    name: 'Result / ' + o.title, dir: 'v', gap: 4, w: W, pad: [12, 16, 12, 16], fill: C.card,
    children: [
      F({ name: 'Head', dir: 'h', gap: 8, cross: 'CENTER', w: W - 32, children: [
        T('#' + o.rank, { size: SZ.h, bold: true, name: 'Final Rank' }),
        T(o.title, { size: SZ.h, bold: true, grow: 1, name: 'Note Title' }),
      ] }),
      T(o.source, { size: SZ.cap, c: C.ter, name: 'Source' }),
      T(o.excerpt, { size: SZ.sub, c: C.sec, w: W - 32, name: 'Matched Text' }),
      F({ name: 'Evidence', dir: 'h', gap: 12, cross: 'CENTER', w: W - 32, children: [
        T(o.evidence, { size: SZ.cap, bold: true, c: C.accent, name: 'Rank Evidence' }),
        T(o.sim, { size: SZ.cap, c: C.ter, name: 'Similarity' }),
      ] }),
    ],
  });
}

/* ================================================================ 屏幕 */

/**
 * D0 · 入口规格 —— 「设置 › 高级」底部要新增的那一节。
 *
 * 刻意不画进 Production 的 `11 · 高级设置`：那一屏四节内容已达 699pt，
 * 逼近 720pt 可视区，再加一节会被裁掉 —— 看不见的入口比没有入口更糟。
 * 真机上它是可滚动 Form，加一节没问题；问题只在静态设计稿的表现力。
 * 所以入口规格放在这里，工程师照此在生产 Settings 里实现。
 */
function d0Entry() {
  return screen('D0 · 入口 · 设置 › 高级', [
    navBar('高级', true),
    body([
      F({ name: 'Context', dir: 'v', w: W, pad: [12, 16, 12, 16], children: [
        T('以下是要加进生产「设置 › 高级」页**末尾**的一节。上方既有的 AI 参数 / 语音转写 / 同步与数据 / 隐私 四节不变。',
          { size: SZ.cap, c: C.ter, w: W - 32 })] }),
      F({ name: 'Existing', dir: 'v', gap: 6, w: W, pad: [0, 16, 12, 16], children: [
        rect(W - 32, 30, C.fill, 6), rect(W - 32, 30, C.fill, 6),
        rect(W - 32, 30, C.fill, 6), rect(W - 32, 30, C.fill, 6),
        T('（既有四节，示意）', { size: SZ.cap, c: C.ter }),
      ] }),
      header('开发者'),
      row('开发者模式', '', 'toggle', { on: false, name: 'Dev Toggle' }), sep(),
      row('开发者工具', '', 'chevron', { name: 'Entry' }),
      F({ name: 'Footer', dir: 'v', gap: 6, w: W, pad: [8, 16, 0, 16], children: [
        T('仅供开发与评测使用。开启后可进入 Retrieval Lab / Eval / Release Gate / Trace。',
          { size: SZ.cap, c: C.ter, w: W - 32 }),
        T('规则：默认 OFF；Toggle=OFF 时「开发者工具」整行不出现（不是置灰）—— 置灰会让普通用户去猜它是什么。',
          { size: SZ.cap, c: C.sec, w: W - 32 }),
      ] }),
    ]),
  ]);
}

function d1DeveloperMode() {
  return screen('D1 · Developer Mode', [
    navBar('开发者模式', true),
    body([
      header('检索'),
      row('Retrieval Lab', '', 'chevron', { name: 'Entry' }), sep(),
      row('Retrieval Eval', '', 'chevron', { name: 'Entry' }), sep(),
      row('Release Gate', '', 'chevron', { name: 'Entry' }), sep(),
      row('Retrieval Trace', '', 'chevron', { name: 'Entry' }),
      header('配置'),
      row('Retrieval Config', 'retrieval-v5', 'chevron', { name: 'Entry' }),
      F({ name: 'Footer', dir: 'v', w: W, pad: [8, 16, 0, 16], children: [
        T('这些工具只面向开发者与 AI TPM。普通用户不会看到本页，也不会在产品界面里见到 embedding / 向量 / RRF 等词。',
          { size: SZ.cap, c: C.ter, w: W - 32 })] }),
    ]),
  ]);
}

function d2RetrievalLab() {
  return screen('D2 · Retrieval Lab', [
    navBar('Retrieval Lab', true),
    body([
      header('query'),
      F({ name: 'Query Input', dir: 'h', w: W, h: 44, cross: 'CENTER', pad: [0, 16, 0, 16], fill: C.card,
          children: [T('延期毕业', { size: SZ.body, grow: 1, name: 'Query' })] }),
      header('configuration'),
      row('Retrieval Mode', 'Hybrid', 'chevron', { name: 'Config' }), sep(),
      row('Embedding Provider', 'Local · bge-small-zh', 'chevron', { name: 'Config' }), sep(),
      row('Chunk Strategy', 'Block · 240 字', 'chevron', { name: 'Config' }), sep(),
      row('Top K', '20', 'chevron', { name: 'Config' }), sep(),
      row('Fusion Method', 'RRF (k=60)', 'chevron', { name: 'Config' }),
      F({ name: 'Run', dir: 'v', w: W, pad: [12, 16, 4, 16], children: [primaryBtn('Run')] }),
      F({ name: 'Result Header', dir: 'h', w: W, pad: [6, 16, 4, 16], cross: 'CENTER', children: [
        T('RESULTS · 12', { size: SZ.cap, c: C.ter }), spacer(),
        T('Compare Modes', { size: SZ.cap, c: C.accent, name: 'Compare' })] }),
      resultCard({ rank: 1, title: 'Graduate Handbook.pdf', source: 'Document · 提取正文 · chunk 3/11',
        excerpt: '…学生如需延期毕业，应在学期开始前四周向学院提交书面申请…',
        evidence: 'K #1 · V #4 → #1', sim: 'similarity 0.881' }),
      sep(),
      resultCard({ rank: 2, title: '和 advisor 的邮件往来', source: 'Text Block · chunk 1/2',
        excerpt: '…我问了能不能延期一个学期毕业，他说要先跟系里确认…',
        evidence: 'K #3 · V #7 → #2', sim: 'similarity 0.842' }),
      sep(),
      resultCard({ rank: 3, title: 'NEU Extended Study Option', source: 'Link · description',
        excerpt: '…students who need additional time to complete degree requirements…',
        evidence: 'K — · V #1 → #3', sim: 'similarity 0.907' }),
    ]),
  ]);
}

function d3LabCompare() {
  const modeChip = (label, on) => F({
    name: 'Mode / ' + label, dir: 'h', h: 30, pad: [0, 12, 0, 12], cross: 'CENTER', radius: 8,
    fill: on ? C.accent : C.fill,
    children: [T(label, { size: SZ.cap, bold: on, c: on ? 'FFFFFF' : C.sec })],
  });
  const cmp = (rank, title, k, v, tag) => F({
    name: 'Compare Result / ' + title, dir: 'v', gap: 2, w: W, pad: [10, 16, 10, 16], fill: C.card,
    children: [
      F({ dir: 'h', gap: 8, cross: 'CENTER', w: W - 32, name: 'Line', children: [
        T('#' + rank, { size: SZ.sub, bold: true }),
        T(title, { size: SZ.sub, grow: 1 }),
      ] }),
      F({ dir: 'h', gap: 10, cross: 'CENTER', w: W - 32, name: 'Origin', children: [
        T('K ' + k, { size: SZ.cap, c: k === '—' ? C.ter : C.text }),
        T('V ' + v, { size: SZ.cap, c: v === '—' ? C.ter : C.text }),
        T('→ #' + rank, { size: SZ.cap, c: C.accent, bold: true }),
        tag ? T(tag, { size: SZ.cap, c: C.bad }) : null,
      ].filter(Boolean) }),
    ],
  });
  return screen('D3 · Retrieval Lab · Compare', [
    navBar('Compare Modes', true),
    body([
      F({ name: 'Query Echo', dir: 'h', w: W, h: 40, cross: 'CENTER', pad: [0, 16, 0, 16], fill: C.card,
          children: [T('延期毕业', { size: SZ.sub, grow: 1 }), T('Top 20 · RRF', { size: SZ.cap, c: C.ter })] }),
      F({ name: 'Mode Picker', dir: 'h', gap: 8, w: W, pad: [10, 16, 10, 16],
          children: [modeChip('Keyword'), modeChip('Vector'), modeChip('Hybrid'), modeChip('Compare', true)] }),
      header('hybrid final ranking'),
      cmp(1, 'Graduate Handbook.pdf', '#1', '#4'), sep(),
      cmp(2, '和 advisor 的邮件往来', '#3', '#7'), sep(),
      cmp(3, 'NEU Extended Study Option', '—', '#1', 'vector only'), sep(),
      cmp(4, '周会录音 · 10/22', '#2', '—', 'keyword only'),
      header('unique hits'),
      F({ name: 'Unique', dir: 'v', gap: 6, w: W, pad: [10, 16, 12, 16], fill: C.card, children: [
        T('Keyword only · 2', { size: SZ.cap, bold: true }),
        T('周会录音 · 10/22   ·   延期毕业申请材料清单', { size: SZ.cap, c: C.sec, w: W - 32 }),
        T('Vector only · 1', { size: SZ.cap, bold: true }),
        T('NEU Extended Study Option', { size: SZ.cap, c: C.sec, w: W - 32 }),
        T('两路都命中 · 6', { size: SZ.cap, bold: true }),
      ] }),
    ]),
  ]);
}

function d4Trace() {
  const step = (label, ms, last) => F({
    name: 'Step / ' + label, dir: 'h', w: W, h: 36, cross: 'CENTER', pad: [0, 16, 0, 16], fill: C.card,
    children: [
      T(label, { size: SZ.sub, bold: !!last }), spacer(),
      T(ms, { size: SZ.sub, bold: !!last, c: last ? C.text : C.sec }),
    ],
  });
  return screen('D4 · Retrieval Trace', [
    navBar('Trace', true),
    body([
      header('query'),
      row('Query', '延期毕业', 'value'), sep(),
      row('Config Version', 'retrieval-v5', 'value'), sep(),
      row('Embedding Version', 'bge-small-zh-v1.5', 'value'), sep(),
      row('Index Version', 'idx_2026080701', 'value'),
      header('pipeline'),
      step('Query Processing', '3 ms'), sep(),
      step('Query Embedding', '41 ms'), sep(),
      step('Keyword Retrieval', '8 ms'), sep(),
      step('Vector Retrieval', '22 ms'), sep(),
      step('Fusion · RRF', '2 ms'), sep(),
      step('Ranking', '1 ms'), sep(),
      step('Total', '77 ms', true),
      header('index'),
      row('chunkCount', '1,284', 'value'), sep(),
      row('candidateCount', '60', 'value'), sep(),
      row('resultCount', '12', 'value'), sep(),
      row('contentHash', 'a91c…7f30 · fresh', 'value'),
      F({ name: 'Footer', dir: 'v', w: W, pad: [8, 16, 0, 16], children: [
        T('contentHash 与索引记录一致 → 本次结果没有用到过期 embedding。不一致时此处标 stale，并给出重建入口。',
          { size: SZ.cap, c: C.ter, w: W - 32 })] }),
    ]),
  ]);
}

function d5EvalCenter() {
  return screen('D5 · Eval Center', [
    navBar('Retrieval Eval', true),
    body([
      header('setup'),
      row('Dataset', 'Golden Set v1', 'chevron', { name: 'Setup' }), sep(),
      row('Cases', '40', 'value'), sep(),
      row('Configuration', 'retrieval-v5', 'chevron', { name: 'Setup' }),
      F({ name: 'Run', dir: 'v', w: W, pad: [16, 16, 8, 16], children: [primaryBtn('Run Evaluation')] }),
      header('quality'),
      metric('Recall@1', '0.700'), sep(),
      metric('Recall@3', '0.825'), sep(),
      metric('Recall@5', '0.875'), sep(),
      metric('MRR', '0.781'),
      header('performance'),
      metric('P50', '96 ms'), sep(),
      metric('P95', '181 ms'),
      header('failures'),
      row('Failed Cases', '5', 'chevron', { name: 'Failed' }),
      F({ name: 'Compare Entry', dir: 'v', w: W, pad: [16, 16, 0, 16],
          children: [row('Compare With Baseline', '', 'chevron', { name: 'Compare' })] }),
    ]),
  ]);
}

function d6EvalCompare() {
  return screen('D6 · Eval Center · Compare', [
    navBar('Compare', true),
    body([
      row('Current', 'retrieval-v5', 'value'), sep(),
      row('Baseline', 'Production · retrieval-v4', 'chevron', { name: 'Baseline' }),
      header('quality'),
      F({ name: 'Compare Head', dir: 'h', w: W, h: 26, cross: 'CENTER', pad: [0, 16, 0, 16], children: [
        T('', { size: SZ.cap, w: 105 }),
        T('CURRENT', { size: SZ.cap, c: C.ter, w: 74, align: 'RIGHT' }),
        T('BASELINE', { size: SZ.cap, c: C.ter, w: 74, align: 'RIGHT' }),
        T('DELTA', { size: SZ.cap, c: C.ter, w: 74, align: 'RIGHT' }),
      ] }),
      cmpRow('Recall@1', '0.700', '0.650', '+0.050', 'ok'), sep(),
      cmpRow('Recall@3', '0.825', '0.800', '+0.025', 'ok'), sep(),
      cmpRow('Recall@5', '0.875', '0.825', '+0.050', 'ok'), sep(),
      cmpRow('MRR', '0.781', '0.742', '+0.039', 'ok'),
      header('performance'),
      cmpRow('P50', '96 ms', '88 ms', '+8 ms', 'bad'), sep(),
      cmpRow('P95', '181 ms', '154 ms', '+27 ms', 'bad'),
      F({ name: 'Tradeoff', dir: 'v', gap: 4, w: W, pad: [14, 16, 14, 16], fill: C.card, children: [
        T('质量提升，延迟回退。', { size: SZ.sub, bold: true }),
        T('Recall@5 +0.050，代价是 P95 +27ms（仍在 250ms 预算内）。是否上线由 Release Gate 判定 —— Eval 本身只负责把 trade-off 讲清楚，不给结论。',
          { size: SZ.cap, c: C.sec, w: W - 32 }),
      ] }),
      header('failures'),
      row('Failed Cases', '5', 'chevron', { name: 'Failed Query' }),
    ]),
  ]);
}

function gateHead(pass, sub) {
  return F({
    name: 'Gate Status', dir: 'v', gap: 6, w: W, pad: [20, 16, 20, 16], fill: pass ? C.okBg : C.badBg,
    children: [
      T(pass ? 'PASS' : 'PROMOTION BLOCKED',
        { size: SZ.big, bold: true, c: pass ? C.ok : C.bad, name: 'Gate Verdict' }),
      T(sub, { size: SZ.sub, c: C.sec, w: W - 32, name: 'Gate Reason' }),
    ],
  });
}

function d7GatePass() {
  return screen('D7 · Release Gate · PASS', [
    navBar('Release Gate', true),
    body([
      gateHead(true, '4 项检查全部通过，可以上线。'),
      header('configuration'),
      row('Candidate', 'retrieval-v5', 'value'), sep(),
      row('Baseline', 'Production · retrieval-v4', 'value'), sep(),
      row('Dataset', 'Golden Set v1 · 40 cases', 'value'),
      header('checks'),
      gateRow('Recall@5', '0.875  ≥  baseline 0.825', true), sep(),
      gateRow('MRR', '0.781  ≥  baseline 0.742 − 0.010 容差', true), sep(),
      gateRow('P95', '181 ms  ≤  budget 250 ms', true), sep(),
      gateRow('Regression', '100%  ≥  threshold 98%  ·  40/40', true),
      F({ name: 'Promote', dir: 'v', w: W, pad: [20, 16, 8, 16], children: [primaryBtn('Promote to Production')] }),
    ]),
  ]);
}

function d8GateBlocked() {
  return screen('D8 · Release Gate · BLOCKED', [
    navBar('Release Gate', true),
    body([
      gateHead(false, '2 项检查未通过：P95 超预算，Regression 未达阈值。'),
      header('configuration'),
      row('Candidate', 'retrieval-v6', 'value'), sep(),
      row('Baseline', 'Production · retrieval-v5', 'value'), sep(),
      row('Dataset', 'Golden Set v1 · 40 cases', 'value'),
      header('checks'),
      gateRow('Recall@5', '0.861  ≥  baseline 0.825', true), sep(),
      gateRow('MRR', '0.766  ≥  baseline 0.742 − 0.010 容差', true), sep(),
      gateRow('P95', '310 ms  >  budget 250 ms', false), sep(),
      gateRow('Regression', '97.5%  <  threshold 98%  ·  39/40', false, 'Open Failures'),
      F({ name: 'Promote', dir: 'v', w: W, pad: [20, 16, 8, 16], children: [primaryBtn('Promote to Production', true)] }),
      F({ name: 'Footer', dir: 'v', w: W, pad: [4, 16, 0, 16], children: [
        T('Promote 被禁用，直到全部检查转为 PASS。Gate 不做加权、不做总分 —— 任何一项 FAIL 即阻断。',
          { size: SZ.cap, c: C.ter, w: W - 32 })] }),
    ]),
  ]);
}

function d9FailureInspection() {
  const note = (title, state, bad) => F({
    name: 'Note / ' + title, dir: 'h', w: W, h: 40, cross: 'CENTER', pad: [0, 16, 0, 16], fill: C.card,
    children: [T(title, { size: SZ.sub, grow: 1 }), T(state, { size: SZ.cap, c: bad ? C.bad : C.sec })],
  });
  return screen('D9 · Failure Inspection', [
    navBar('Failure', true),
    body([
      header('query'),
      F({ name: 'Query', dir: 'v', w: W, pad: [12, 16, 12, 16], fill: C.card,
          children: [T('老师 demo 要准备什么', { size: SZ.body, w: W - 32 })] }),
      header('expected'),
      note('周会录音 · 10/22', 'not returned', true),
      header('returned'),
      note('#1 合同评审要点', ''), sep(),
      note('#2 现场照片', ''),
      header('per-mode'),
      row('Keyword', 'not found', 'value', { valueColor: C.bad }), sep(),
      row('Vector', '#9', 'value'), sep(),
      row('Hybrid', 'not in top 5', 'value', { valueColor: C.bad }),
      header('diagnosis'),
      row('Failure Type', 'Chunking', 'chevron', { name: 'Failure Type' }),
      F({ name: 'Note', dir: 'v', w: W, pad: [8, 16, 12, 16], children: [
        T('转写稿被切在「demo」与「要准备」之间，两个 chunk 都不完整。',
          { size: SZ.cap, c: C.ter, w: W - 32 })] }),
      F({ name: 'Action', dir: 'v', w: W, pad: [8, 16, 8, 16],
          children: [primaryBtn('Add to Regression Set')] }),
    ]),
  ]);
}

/* ================================================================ 组装 */

const SCREENS = [
  { fn: d0Entry, title: 'D0 · 入口 · 设置 › 高级', note: '要加进生产「设置 › 高级」末尾的一节。默认 OFF；OFF 时第二行整行不出现' },
  { fn: d1DeveloperMode, title: 'D1 · Developer Mode', note: 'Settings → 高级 → 开发者模式（默认 OFF）。纯入口列表，不做 KPI overview' },
  { fn: d2RetrievalLab, title: 'D2 · Retrieval Lab', note: 'Query + Config + 竖排 Result Inspector。K/V/→ 一行讲清排名来源' },
  { fn: d3LabCompare, title: 'D3 · Retrieval Lab · Compare', note: 'Mode Picker 的第四个状态，不是独立页。重点是 unique hit' },
  { fn: d4Trace, title: 'D4 · Retrieval Trace', note: 'SwiftUI-first；线框只为把 Flow A 走通。禁止 waterfall chart' },
  { fn: d5EvalCenter, title: 'D5 · Eval Center', note: 'Dataset × Config → Run → 指标。无图表' },
  { fn: d6EvalCompare, title: 'D6 · Eval Center · Compare', note: 'Current / Baseline / Delta 三列。同时看到质量提升与延迟回退' },
  { fn: d7GatePass, title: 'D7 · Release Gate · PASS', note: '顶部一眼可见判定 + 4 项检查的具体条件' },
  { fn: d8GateBlocked, title: 'D8 · Release Gate · BLOCKED', note: '2 秒内回答「能不能上线 / 为什么不能」。任一 FAIL 即阻断' },
  { fn: d9FailureInspection, title: 'D9 · Failure Inspection', note: 'SwiftUI-first；线框只为把 Flow B / C 走通' },
];

/** 三条可演示 Flow（Package I）。按屏名前两位匹配。 */
const FLOWS = [
  { flow: 'A', from: 'D0', hot: 'Entry / 开发者工具', to: 'D1', desc: '设置 › 高级 › 开发者工具 → Developer Mode' },
  { flow: 'A', from: 'D1', hot: 'Entry / Retrieval Lab', to: 'D2', desc: 'Developer Mode → Retrieval Lab' },
  { flow: 'A', from: 'D2', hot: 'Compare', to: 'D3', desc: 'Lab → Compare Modes' },
  { flow: 'A', from: 'D2', hot: 'Result', to: 'D4', desc: '点结果 → 看 Trace（排名证据的下一层）' },
  { flow: 'A', from: 'D1', hot: 'Entry / Retrieval Trace', to: 'D4', desc: 'Developer Mode → Trace' },
  { flow: 'B', from: 'D1', hot: 'Entry / Retrieval Eval', to: 'D5', desc: 'Developer Mode → Eval' },
  { flow: 'B', from: 'D5', hot: 'Compare', to: 'D6', desc: 'Eval → Compare Baseline' },
  { flow: 'B', from: 'D6', hot: 'Failed Query', to: 'D9', desc: '失败用例 → Failure Inspection' },
  { flow: 'B', from: 'D5', hot: 'Failed', to: 'D9', desc: 'Failed Cases → Failure Inspection' },
  { flow: 'C', from: 'D1', hot: 'Entry / Release Gate', to: 'D7', desc: 'Developer Mode → Release Gate（PASS）' },
  { flow: 'C', from: 'D8', hot: 'Open Failures', to: 'D9', desc: 'BLOCKED → 打开失败用例' },
];

async function wire(screens) {
  const find = t => screens.find(s => s.name.indexOf(t) === 0);
  let wired = 0; const missed = [];
  for (const f of FLOWS) {
    const from = find(f.from), to = find(f.to);
    if (!from || !to) { missed.push(f.desc + '（缺屏）'); continue; }
    const hot = from.findOne(n => n.name === f.hot || (n.name || '').split(' / ')[0] === f.hot);
    if (!hot) { missed.push(f.desc + '（缺热区 ' + f.hot + '）'); continue; }
    const reaction = {
      trigger: { type: 'ON_CLICK' },
      action: { type: 'NODE', destinationId: to.id, navigation: 'NAVIGATE',
                transition: { type: 'SMART_ANIMATE', easing: { type: 'EASE_OUT' }, duration: 0.25 },
                preserveScrollPosition: false },
    };
    try { await hot.setReactionsAsync([reaction]); wired++; }
    catch (e) { try { hot.reactions = [reaction]; wired++; } catch (e2) { missed.push(f.desc + '（连线失败）'); } }
  }
  return { wired, missed };
}

function getPage(name) {
  const hit = figma.root.children.find(p => p.name === name);
  if (hit) { hit.children.slice().forEach(n => { try { n.remove(); } catch (e) { } }); return hit; }
  const p = figma.createPage(); p.name = name; return p;
}

async function main() {
  await figma.loadFontAsync(FONT.R);
  await figma.loadFontAsync(FONT.S);

  const page = getPage(PAGE);
  figma.currentPage = page;

  const board = F({ name: '01 · Dev Tools（低保真 · Track B）', dir: 'h', gap: 32,
                    pad: [32, 32, 32, 32], fill: 'FFFFFF' });
  page.appendChild(board);

  const nodes = [];
  SCREENS.forEach(s => {
    const node = s.fn();
    nodes.push(node);
    const col = F({ name: 'Column / ' + s.title, dir: 'v', gap: 12, w: W, children: [
      F({ name: 'Caption', dir: 'v', gap: 4, w: W, children: [
        T(s.title, { size: SZ.sub, bold: true }),
        T(s.note, { size: SZ.cap, c: C.ter, w: W }),
      ] }),
      node,
    ] });
    board.appendChild(col);
  });

  const proto = await wire(nodes);
  figma.notify('Dev Tools 线框：' + SCREENS.length + ' 屏 · ' + proto.wired + ' 条连线'
    + (proto.missed.length ? ' · 未连 ' + proto.missed.length : ''), { timeout: 6000 });
  if (proto.missed.length) console.log('未连线：', proto.missed);
  return { screens: SCREENS.length, proto: proto };
}

main();
