/* ============================================================================
 * 校准容差的边界变异测试
 * ----------------------------------------------------------------------------
 * 证明「高度容差 ±2pt」是 calibration.js 里真实生效的判定，而不是文档里的口头规则。
 * 对一个已知精确匹配的节点注入偏移，验证判定在边界两侧的行为。
 * 用法：node test/tolerance.js
 * ========================================================================== */
const { execFileSync } = require('child_process');
const path = require('path');
const DIR = path.join(__dirname, '..');
const TARGET = 'Bar / Status';   // 精确匹配项（393×54），注入偏移不会牵连其它项

const CASES = [
  { delta: 0,    expect: 'pass', desc: '无偏移' },
  { delta: 1,    expect: 'pass', desc: '1pt（容差内）' },
  { delta: 2,    expect: 'pass', desc: '2pt（正好等于容差上界）' },
  { delta: 2.1,  expect: 'fail', desc: '2.1pt（刚超出容差）' },
  { delta: 3,    expect: 'fail', desc: '3pt（明显超出）' },
  { delta: -2,   expect: 'pass', desc: '-2pt（负方向边界）' },
  { delta: -2.1, expect: 'fail', desc: '-2.1pt（负方向超出）' },
];

console.log('\n════════ 校准容差边界自检 ════════');
console.log(`  目标节点：${TARGET}   高度容差：±2pt\n`);
let pass = 0, fail = 0;
CASES.forEach(c => {
  let ok;
  try {
    execFileSync('node', [path.join('test', 'calibration.js')],
      { cwd: DIR, encoding: 'utf8', env: Object.assign({}, process.env,
        { CALIB_INJECT_H: String(c.delta), CALIB_INJECT_TARGET: TARGET }) });
    ok = 'pass';
  } catch (e) { ok = 'fail'; }
  const good = ok === c.expect;
  if (good) pass++; else fail++;
  console.log(`  ${good ? '✅' : '❌'} Δ=${String(c.delta).padStart(5)}  期望 ${c.expect.toUpperCase().padEnd(4)} 实际 ${ok.toUpperCase().padEnd(4)}  ${c.desc}`);
});
console.log(`\n════════ ${pass} / ${CASES.length} 边界用例通过 ════════\n`);
process.exit(fail ? 1 : 0);
