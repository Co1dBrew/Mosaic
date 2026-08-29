/* ============================================================================
 * Dev Tools 线框 —— 结构冒烟测试（Track B）
 * ----------------------------------------------------------------------------
 * 用法：node test/run.js
 *
 * 复用 Production 那套 figma-stub，但**只借运行环境**，不共享任何基准：
 * Track B 不进 calibration、不做 ±1pt 校验。
 *
 * 这里只回答四个问题：
 *   1. 生成器能不能跑完（字体 / API 用法有没有错）
 *   2. 屏数、屏尺寸对不对
 *   3. 内容有没有溢出 852pt（低保真也不能画到屏外）
 *   4. 三条 Flow 的连线是不是都接上了（死链 = 0）
 * ========================================================================== */

require('../../figma-plugin/test/figma-stub.js');
require('../code.js');

const EXPECT = { screens: 10, w: 393, h: 852, edges: 11 };
const RESULTS = [];
const ok = (id, pass, detail) => RESULTS.push({ id, pass, detail });

setTimeout(() => {
  const page = figma.root.children.find(p => p.name.indexOf('Dev Tools') >= 0);
  if (!page) {
    console.log('❌ 没有生成 🔧 Dev Tools 页');
    process.exit(1);
  }
  const board = page.children[0];
  const cols = board.children;
  const screens = cols.map(c => c.children[c.children.length - 1]);

  ok('screens', screens.length === EXPECT.screens, `${screens.length} 屏（期望 ${EXPECT.screens}）`);

  const wrongSize = screens.filter(s => s.width !== EXPECT.w || s.height !== EXPECT.h)
    .map(s => `${s.name} ${s.width}×${s.height}`);
  ok('size', wrongSize.length === 0, wrongSize.length ? wrongSize.join(' ; ') : `全部 ${EXPECT.w}×${EXPECT.h}`);

  // Body 内容累计高度不得超过可用高度（852 − navBar 44）
  const overflow = [];
  screens.forEach(s => {
    const b = s.children.find(c => c.name === 'Body');
    if (!b) return;
    const used = b.children.reduce((n, c) => n + c.height, 0);
    if (used > b.height + 0.5) overflow.push(`${s.name} 内容 ${used.toFixed(0)} > Body ${b.height.toFixed(0)}`);
  });
  ok('overflow', overflow.length === 0, overflow.length ? overflow.join(' ; ') : '无内容溢出');

  const edges = board.findAll(n => n.reactions && n.reactions.length)
    .reduce((n, x) => n + x.reactions.length, 0);
  ok('prototype', edges === EXPECT.edges, `${edges} 条连线（期望 ${EXPECT.edges}）`);

  // Track B 边界：不得创建任何 Variable / Text Style / Effect Style
  const stub = require('../../figma-plugin/test/figma-stub.js');
  const leaked = [];
  if (stub.CALLS.varColor || stub.CALLS.varFloat) leaked.push('创建了 Variable');
  if (stub.TEXT_STYLES.length) leaked.push(`创建了 ${stub.TEXT_STYLES.length} 个 Text Style`);
  if (stub.EFFECT_STYLES.length) leaked.push(`创建了 ${stub.EFFECT_STYLES.length} 个 Effect Style`);
  ok('track-b', leaked.length === 0, leaked.length ? leaked.join(' ; ') : '未创建任何 Variable / Style，未触碰 Production 页');

  const touched = figma.root.children.filter(p => /Foundations|Components|Screens/.test(p.name) && p.children.length === 0);
  ok('production-untouched', touched.length === 0,
    touched.length ? `清空了 Production 页：${touched.map(p => p.name).join(', ')}` : 'Production 三页未被触碰');

  console.log('\n════════ Dev Tools 线框冒烟测试 ════════');
  let bad = 0;
  RESULTS.forEach(r => { if (!r.pass) bad++; console.log(`  ${r.pass ? '✅' : '❌'} ${r.id.padEnd(20)} ${r.detail}`); });
  console.log(`════════ ${RESULTS.length - bad} / ${RESULTS.length} 通过 ════════\n`);
  process.exit(bad ? 1 : 0);
}, 600);
