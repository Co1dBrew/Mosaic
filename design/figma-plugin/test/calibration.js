/* ============================================================================
 * 桩 vs 真实 Figma 校准
 * ----------------------------------------------------------------------------
 * 用法：node test/calibration.js
 *
 * 两类比较，容差规则不同：
 *
 *   EXACT（tolerance = 0）
 *     组件数 · 变体集数 · 变体数 · 变体名 · 组件属性名 · 变量绑定 · 原型目标
 *     这些是语义，不存在「差一点」——不一致就是错。
 *
 *   NUMERIC（按属性分别定容差）
 *     Figma 的文字排版会产生分数高度，字体度量与 auto-layout 取整也有出入。
 *     桩的目标是「足够准确地捕获 regression」，不是复制 Figma 排版引擎。
 *
 * 容差来源说明见 TOLERANCE 常量。
 *
 * 边界自检：环境变量 CALIB_INJECT_H=<delta> 会在比较前给桩的高度注入偏移，
 * 用于证明容差是代码里真实生效的规则，而不是报告里的口头承诺。
 * ========================================================================== */

require('./figma-stub.js');
require('../code.js');

/** 容差表。每一项都要写明为什么是这个数。 */
const TOLERANCE = {
  width: 1.0,
  //   宽度基本由显式尺寸 / Token 决定，只允许 auto-layout 取整误差。
  height: 2.0,
  //   高度受字体度量影响：桩用「字符数 × 字号」估算行宽，Figma 用真实字形推进量，
  //   多行文本的行数判断可能差一行的一部分。实测最大偏差 2.0pt（Summary Panel）。
  position: 1.0,
  //   x/y 由 auto-layout 累加得出，误差来源同宽度。
  float: 0.01,
  //   0.01 是「零宽/零高」哨兵值（如 state=hidden），需按浮点比较。
  exact: 0,
  //   语义类属性，不允许任何偏差。
};

// ---------------------------------------------------------------- EXACT 基准

/**
 * 待实读提示。非空时会在报告末尾打出「⏳ 待实读校准」。
 *
 * 规矩：计数与变体名是**确定性语义**（由 code.js 直接决定），可以在插件重跑前先行更新；
 * NUMERIC 尺寸**不能**凭空写 —— 那是 Figma 排版引擎的输出，必须实跑 + MCP 实读才能填。
 * 桩的数字和 Figma 的数字都由同一份 code.js 推导，互相比对没有意义。
 *
 * Search 三组件已于 2026-08-07 第 2 / 3 轮实读全部确认，故当前为空。
 */
const PROVISIONAL = '';   // 空 = 无待实读项。Search 三组件已于第 2 / 3 轮全部实读确认。

/** 2026-08-07 Dev Mode MCP 实读 + Search 改动后的确定性增量。任何不一致都是错误，容差 0。 */
const EXACT = {
  componentNodes: 40,      // 🧩 Components 页顶层节点数（37 + Search 3）
  variantSets: 29,         // 26 + Search 3
  plainComponents: 11,
  variantTotal: 125,       // 116 + 3(Field) + 2(Result) + 4(Status)
  screens: 26,             // 20 + 21/22/23/24（Search 状态）+ 25/26（Result → Note 落地）
  prototypeEdges: 25,     // 22 + Flow 7 的三条新连线（示例→相关结果 · 重试→恢复 · 返回→状态恢复）
  colorVariables: 16,
  scaleVariables: 27,
  textStyles: 15,
  effectStyles: 2,
};

/** 每个变体集的变体名（顺序无关，集合相等）。实读所得。 */
const EXACT_VARIANTS = {
  'Note / Preview': ['ai-summary', 'text', 'audio', 'image', 'empty'],
  'Note / AI Badge': ['none', 'generating', 'failed'],
  'Audio / Transcript': ['none', 'short', 'collapsed', 'expanded'],
  'Form / Action Status': ['idle', 'testing', 'success', 'failure'],
  'Chip / Folder': ['default', 'selected', 'more'],
  'Chip / Folder Meta': ['assigned', 'unassigned'],
  'Chip / Tag': ['default', 'selected'],
  'Chip / Topic': ['default', 'added'],
  'Row / Folder': ['chevron', 'grip'],
  'Row / Form': ['value', 'chevron', 'toggle', 'action'],
  'Row / Menu Item': ['default', 'destructive'],
  'Bar / Toolbar': ['insert', 'adaptive'],
  'Bar / Summary': ['hidden', 'pending', 'generating', 'success', 'success-unread',
                    'error-auth', 'error-network', 'error-rate-limit', 'error-content'],
  'Panel / Summary': ['0', '1', 'many'],
  'Block / Text': ['rendered', 'editing'],
  'Block / Image': ['loaded', 'loading', 'failed', 'missing'],
  'Block / Audio': ['idle', 'playing', 'transcribing', 'failed'],
  'Block / Document': ['normal', 'unsupported', 'missing'],
  'Block / Link': ['preview', 'url-only', 'loading', 'failed'],
  'Error Row': ['0', '1', '2'],
  'Loading Row': ['spinner', 'skeleton'],
  'Dialog / Confirmation': ['default', 'destructive'],
  'Sheet / Recorder': ['idle', 'recording', 'paused', 'done', 'failed'],
  'Sheet / Folder Editor': ['create', 'rename'],
  'Sheet / Permission': ['camera', 'photo', 'microphone'],
  // Production Semantic Search
  'Search Field': ['idle', 'typing', 'searching'],
  'Row / Search Result': ['default', 'pressed'],
  'Bar / Search Status': ['building', 'rebuilding', 'degraded', 'offline'],
};

/**
 * 尺寸基准待实读的节点。**不填猜测值** —— 桩的数字与 Figma 的数字都由同一份
 * code.js 推导，互相比对没有意义；只有真实 Figma 的排版输出才构成基准。
 * 插件重跑 + MCP 实读后，把这些 key 移入 NUMERIC_COMPONENTS 并清空本表。
 */
const NUMERIC_PENDING = [];

// ---------------------------------------------------------------- NUMERIC 基准

/** 组件本体尺寸 [w, h]。取自组件页而非屏幕实例 —— 组件是尺寸的源头，更稳定。 */
const NUMERIC_COMPONENTS = {
  'Note / Preview|type=ai-summary': [275, 40],
  'Note / Preview|type=audio': [275, 20],
  'Note / AI Badge|state=none': [0.01, 16],
  'Note / AI Badge|state=failed': [16, 16],
  'Audio / Transcript|state=short': [329, 36],
  'Audio / Transcript|state=collapsed': [329, 76],
  'Audio / Transcript|state=expanded': [329, 166],
  'Chip / Folder|state=default': [87, 32],
  'Chip / Folder|state=more': [89, 32],
  'Chip / Folder Meta|state=assigned': [80, 24],
  'Chip / Tag|state=default': [40, 24],
  'Chip / Topic|state=added': [60, 24],
  'Row / Folder|trailing=chevron': [361, 69],
  'Row / Form|type=value': [361, 44],
  'Row / Menu Item|type=default': [255, 44],
  'Bar / Toolbar|mode=insert': [393, 49],
  'Bar / Summary|state=hidden': [393, 0.01],
  'Bar / Summary|state=success': [393, 44.5],
  'Bar / Summary|state=error-auth': [393, 44.5],
  'Panel / Summary|logCount=0': [393, 224],
  'Panel / Summary|logCount=1': [393, 350.5],
  'Panel / Summary|logCount=many': [393, 378.5],
  'Block / Text|state=rendered': [353, 50],
  'Block / Image|state=loaded': [353, 158],
  'Block / Audio|state=idle': [353, 102],
  'Block / Audio|state=transcribing': [353, 128],
  'Block / Audio|state=failed': [353, 154],
  'Block / Document|state=normal': [353, 64],
  'Block / Document|state=missing': [353, 68],
  'Block / Link|state=preview': [353, 84],
  'Block / Link|state=url-only': [353, 48],
  'Block / Link|state=failed': [353, 68],
  'Error Row|ctaCount=1': [353, 96],
  'Loading Row|style=skeleton': [353, 60],
  'Dialog / Confirmation|tone=default': [329, 148],
  'Sheet / Recorder|state=idle': [393, 218],
  'Sheet / Recorder|state=failed': [393, 150],
  'Sheet / Folder Editor|mode=create': [393, 162],
  'Sheet / Permission|type=camera': [329, 206],
  // 2026-08-07 实读确认（screens 06/12/13 上的实例均为 361×36）。
  // w/h 双向定宽，不受字体度量影响，因此实例尺寸即组件尺寸。
  'Search Field|state=idle': [361, 36],
  'Search Field|state=typing': [361, 36],
  'Search Field|state=searching': [361, 36],
  // 2026-08-07 第 2 轮实读确认（06 屏五条实例均为 393×110.5）。
  // excerpt 走 resize(329, 40) → textAutoResize='NONE'，高度不随文案长短变化，
  // 因此组件本体与实例同尺寸；两个变体只差 fill，几何相同。
  'Row / Search Result|state=default': [393, 110.5],
  'Row / Search Result|state=pressed': [393, 110.5],
  // 2026-08-07 第 3 轮实读确认（22 / 23 两屏实例均为 393×44）。
  'Bar / Search Status|state=building': [393, 44],
  'Bar / Search Status|state=degraded': [393, 44],
};

/** 单组件（无变体）尺寸。 */
const NUMERIC_PLAIN = {
  'Row / Note': [393, 90.5],
  'Bar / Status': [393, 54],
  'Bar / Nav': [393, 44],
  'Bar / Bottom': [393, 49],
  'Bar / Home Indicator': [393, 34],
  'Empty State': [393, 182],
  'Sheet / Tag Editor': [393, 154],
  'Sheet / Image Viewer': [393, 394],
  'Sheet / URL Input': [329, 118],
  'Menu / Folder Picker': [255, 185],
  'Menu / Media Insert': [255, 222],
};

// ---------------------------------------------------------------- 比较

// 边界自检：只对指定节点注入高度偏移，避免影响其它项的判定
const INJECT_H = parseFloat(process.env.CALIB_INJECT_H || '0');
const INJECT_TARGET = process.env.CALIB_INJECT_TARGET || '';

const stats = { exactPass: 0, exactFail: [], numExact: 0, numWithin: 0, numOut: [] };

function cmpExact(label, stub, real) {
  if (stub === real) stats.exactPass++;
  else stats.exactFail.push(`${label}: 桩 ${stub} ≠ 真实 ${real}`);
}

function cmpNumeric(label, stubW, stubH, realW, realH) {
  const h = stubH + ((INJECT_TARGET && label === INJECT_TARGET) ? INJECT_H : 0);
  const dw = Math.abs(stubW - realW), dh = Math.abs(h - realH);
  const tolW = realW < 1 ? TOLERANCE.float : TOLERANCE.width;
  const tolH = realH < 1 ? TOLERANCE.float : TOLERANCE.height;
  if (dw === 0 && dh === 0) { stats.numExact++; return '精确'; }
  if (dw <= tolW && dh <= tolH) { stats.numWithin++; return `容差内 Δw=${dw.toFixed(1)} Δh=${dh.toFixed(1)}`; }
  stats.numOut.push(`${label}: 桩 ${stubW.toFixed(1)}×${h.toFixed(1)} vs 真实 ${realW}×${realH}（Δw=${dw.toFixed(1)}/tol ${tolW}, Δh=${dh.toFixed(1)}/tol ${tolH}）`);
  return '超限';
}

setTimeout(() => {
  const stub = require('./figma-stub.js');
  const comps = figma.root.children.find(p => p.name.includes('Components'));
  const scr = figma.root.children.find(p => p.name.includes('Screens'));
  const board = scr.children[0];
  const sets = comps.children.filter(c => c.type === 'COMPONENT_SET');
  const plains = comps.children.filter(c => c.type === 'COMPONENT');

  // ---- EXACT ----
  cmpExact('组件顶层节点数', comps.children.length, EXACT.componentNodes);
  cmpExact('变体集数', sets.length, EXACT.variantSets);
  cmpExact('单组件数', plains.length, EXACT.plainComponents);
  cmpExact('变体总数', sets.reduce((n, c) => n + c.children.length, 0), EXACT.variantTotal);
  cmpExact('屏幕数', board.children.length, EXACT.screens);
  cmpExact('原型连线数', board.findAll(n => n.reactions && n.reactions.length)
    .reduce((n, x) => n + x.reactions.length, 0), EXACT.prototypeEdges);
  cmpExact('颜色变量数', stub.CALLS.varColor, EXACT.colorVariables);
  cmpExact('数值变量数', stub.CALLS.varFloat, EXACT.scaleVariables);
  cmpExact('颜色集合模式数', stub.COLLECTIONS.find(c => c.name === 'Mosaic Color').modes.length, 2);
  cmpExact('文字样式数', stub.TEXT_STYLES.length, EXACT.textStyles);
  cmpExact('效果样式数', stub.EFFECT_STYLES.length, EXACT.effectStyles);

  Object.keys(EXACT_VARIANTS).forEach(setName => {
    const set = comps.children.find(c => c.name === setName);
    if (!set) { stats.exactFail.push(`变体集 ${setName} 不存在`); return; }
    const have = set.children.map(v => (v.name.split('=')[1] || '').trim()).sort().join(',');
    const want = EXACT_VARIANTS[setName].slice().sort().join(',');
    cmpExact(`${setName} 变体名`, have, want);
  });

  // ---- NUMERIC ----
  const rows = [];
  Object.keys(NUMERIC_COMPONENTS).forEach(key => {
    const [setName, variantName] = key.split('|');
    const set = comps.children.find(c => c.name === setName);
    const v = set && set.children.find(x => x.name === variantName);
    const real = NUMERIC_COMPONENTS[key];
    if (!v) { stats.numOut.push(`${key}: 节点不存在`); return; }
    rows.push([key, v.width, v.height, real[0], real[1], cmpNumeric(key, v.width, v.height, real[0], real[1])]);
  });
  Object.keys(NUMERIC_PLAIN).forEach(name => {
    const c = comps.children.find(x => x.name === name);
    const real = NUMERIC_PLAIN[name];
    if (!c) { stats.numOut.push(`${name}: 节点不存在`); return; }
    rows.push([name, c.width, c.height, real[0], real[1], cmpNumeric(name, c.width, c.height, real[0], real[1])]);
  });

  // ---- 输出 ----
  console.log('\n════════ 桩 vs 真实 Figma 校准 ════════\n');
  console.log('容差规则：');
  console.log(`  EXACT（计数/名称/绑定/原型目标）  tolerance = ${TOLERANCE.exact}`);
  console.log(`  宽度                              ±${TOLERANCE.width} pt`);
  console.log(`  高度                              ±${TOLERANCE.height} pt`);
  console.log(`  位置 x/y                          ±${TOLERANCE.position} pt`);
  console.log(`  浮点哨兵（<1pt 的零值）            ±${TOLERANCE.float}`);
  if (INJECT_H) console.log(`  ⚠️ 边界自检：对 "${INJECT_TARGET}" 注入高度偏移 ${INJECT_H} pt`);

  const outRows = rows.filter(r => r[5] === '超限');
  if (outRows.length) {
    console.log('\n超出容差的项：');
    stats.numOut.forEach(m => console.log('  ❌ ' + m));
  }
  if (stats.exactFail.length) {
    console.log('\nEXACT 不一致：');
    stats.exactFail.forEach(m => console.log('  ❌ ' + m));
  }

  // 待实读项：打印桩的当前值，供 MCP 实读时逐项核对
  if (NUMERIC_PENDING.length) {
    console.log('\n⏳ 待实读校准（' + PROVISIONAL + '）：');
    NUMERIC_PENDING.forEach(key => {
      const [setName, variantName] = key.split('|');
      const set = comps.children.find(c => c.name === setName);
      const v = set && set.children.find(x => x.name === variantName);
      console.log(v ? `  ⏳ ${key}  桩 ${v.width.toFixed(1)}×${v.height.toFixed(1)} —— 待 Figma 实读确认`
                    : `  ❌ ${key}: 节点不存在`);
      if (!v) stats.exactFail.push(`${key}: 节点不存在`);
    });
  }

  const numTotal = stats.numExact + stats.numWithin + stats.numOut.length;
  const exactTotal = stats.exactPass + stats.exactFail.length;
  console.log('\n结果：');
  console.log(`  EXACT              ${stats.exactPass} / ${exactTotal} 一致（容差 0）`);
  console.log(`  NUMERIC 精确相同    ${stats.numExact}`);
  console.log(`  NUMERIC 容差内      ${stats.numWithin}`);
  console.log(`  NUMERIC 超出容差    ${stats.numOut.length}`);
  console.log(`\n  合计 ${stats.exactPass + stats.numExact + stats.numWithin} / ${exactTotal + numTotal} 项在已定义容差范围内\n`);

  process.exit(stats.exactFail.length + stats.numOut.length ? 1 : 0);
}, 600);
