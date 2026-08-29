/* 全量验证：checks → gates → calibration → selftest。用法：node test/all.js */
const { execFileSync } = require('child_process');
const path = require('path');
const DIR = path.join(__dirname, '..');
const SUITES = [['checks.js', '自动检查'], ['gates.js', 'Batch Gates'], ['calibration.js', '桩校准'], ['tolerance.js', '容差边界'], ['selftest.js', '变异自检']];
let fail = 0;
SUITES.forEach(([f, label]) => {
  try {
    const out = execFileSync('node', [path.join('test', f)], { cwd: DIR, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
    const last = out.trim().split('\n').filter(l => l.includes('════') || l.includes('合计')).pop() || '';
    console.log(`  ✅ ${label.padEnd(12)} ${last.replace(/═/g, '').trim()}`);
  } catch (e) {
    fail++;
    console.log(`  ❌ ${label.padEnd(12)} 失败`);
    console.log((e.stdout || '').split('\n').filter(l => l.trim().startsWith('❌') || l.includes('| ❌')).slice(0, 5).map(l => '       ' + l.trim()).join('\n'));
  }
});
process.exit(fail ? 1 : 0);
