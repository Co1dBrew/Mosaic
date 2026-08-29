/* ============================================================================
 * 检查器自检（变异测试）
 * ----------------------------------------------------------------------------
 * 用法：node test/selftest.js
 *
 * 对 code.js 做「定向破坏」，验证对应的检查器确实会报警。
 * 没有这一步，checks.js 报「0 问题」是没有说服力的 —— 可能只是检查器坏了。
 * ========================================================================== */

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const DIR = path.join(__dirname, '..');
const SRC = path.join(DIR, 'code.js');
const TMP = path.join(DIR, 'test', '_mutant.js');
const CHECKS = path.join(DIR, 'test', 'checks.js');
const GATES = path.join(DIR, 'test', 'gates.js');
const original = fs.readFileSync(SRC, 'utf8');

/** 每个变异体：改坏一处，期望某个检查项从 ✅ 变 ❌。 */
const MUTANTS = [
  {
    id: 'clipping',
    desc: 'Row / Folder 宽度改回 393（会被 361 宽的裁切卡片截断）',
    apply: s => s.replace("name: 'Folder Row', dir: 'h', gap: 'space/12', w: W - 32,",
                          "name: 'Folder Row', dir: 'h', gap: 'space/12', w: W,"),
  },
  {
    id: 'multiline-width',
    desc: 'Search Result 的 excerpt 退回 grow（复刻 2026-08-07 的裁字事故）',
    apply: s => s.replace("width: W - 64, name: 'Excerpt Text' }),",
                          "grow: 1, name: 'Excerpt Text' }),"),
  },
  {
    id: 'text-prop',
    desc: 'Bar / Search Status 重新加回 Message TEXT 属性（复刻 degraded 显示 building 文案的事故）',
    apply: s => s.replace('  // 刻意**不给** Message / CTA Label 加 TEXT 组件属性。',
      "  P.barSearchStatus = { Message: C.barSearchStatus.addComponentProperty('Message', 'TEXT', SEARCH_STATUS_SPEC.building.msg) };\n" +
      "  bindPropAll(C.barSearchStatus, 'Message', 'characters', P.barSearchStatus.Message);\n" +
      '  // 刻意**不给** Message / CTA Label 加 TEXT 组件属性。'),
  },
  {
    id: 'token-binding',
    desc: 'Chip / Tag 的 padding 改成裸数字 7',
    apply: s => s.replace("name: 'Tag', dir: 'h', pad: ['space/4', 'space/8', 'space/4', 'space/8'],",
                          "name: 'Tag', dir: 'h', pad: [7, 7, 7, 7],"),
  },
  {
    id: 'touch-target',
    desc: 'Tappable 容器从 44pt 缩到 24pt',
    apply: s => s.replace("name: name || 'Tappable', w: 'system/tap-min', h: 'system/tap-min',",
                          "name: name || 'Tappable', w: 24, h: 24,"),
  },
  {
    id: 'variant-arch',
    desc: 'Chip / Tag 改成 3 个变体维度（笛卡尔积）',
    apply: s => s.replace(
      "  C.chipTag = variantSet('Chip / Tag', ['state'],\n    [{ state: 'default' }, { state: 'selected' }],",
      "  C.chipTag = variantSet('Chip / Tag', ['state', 'size', 'tone'],\n    [{ state: 'default', size: 'sm', tone: 'a' }, { state: 'selected', size: 'lg', tone: 'b' }],"),
  },
  {
    id: 'variant-arch',
    desc: '声明 INSTANCE_SWAP 属性但不接线',
    apply: s => s.replace("  bindProp(C.rowNote.findOne(n => n.name === 'Preview'), 'mainComponent', P.rowNote.Preview);", ''),
  },
  {
    id: 'overflow',
    desc: '摘要面板正文宽度超出容器内宽',
    apply: s => s.replace("          { s: 'iOS/Subheadline', width: W - 32 }),",
                          "          { s: 'iOS/Subheadline', width: W + 40 }),"),
  },
  {
    id: 'A1 幂等性', runner: 'gates',
    desc: '组件名引入随机数（破坏可重复生成）',
    apply: s => s.replace("  C.blockImage = variantSet('Block / Image', ['state'],",
                          "  C.blockImage = variantSet('Block / Image ' + Math.floor(Math.random()*1e6), ['state'],"),
  },
  {
    id: 'B1 状态覆盖', runner: 'gates',
    desc: '删掉 Block / Link 的 failed 状态',
    apply: s => s.replace("[{ state: 'preview' }, { state: 'url-only' }, { state: 'loading' }, { state: 'failed' }],",
                          "[{ state: 'preview' }, { state: 'url-only' }, { state: 'loading' }],"),
  },
  {
    id: 'B2 入口可达', runner: 'gates',
    desc: '移除 ⋯ 菜单里的「导出为 Markdown」',
    apply: s => s.replace("mi('导出为 Markdown', 'share'), ", "mi('占位', 'doc'), "),
  },
  {
    id: 'B4 架构稳定', runner: 'gates',
    desc: '在屏内放一个裸 frame 冒充 Note Row 实例（detached）',
    apply: s => s.replace("      iNoteRow({ title: '现场照片', preview: 'image', time: '10月14日' }),",
                          "      iNoteRow({ title: '现场照片', preview: 'image', time: '10月14日' }),\n      F({ name: 'Note Row / 假的', w: 'system/screen-w', h: 40 }),"),
  },
  {
    id: 'C1 原型完整', runner: 'gates',
    desc: '把一条连线指向不存在的目标（死链）',
    apply: s => s.replace("action: { type: 'NODE', destinationId: to.id,",
                          "action: { type: 'NODE', destinationId: (f.flow === 7 ? 'BOGUS' : to.id),"),
  },
  {
    id: 'clipping',
    desc: '屏 20 标签宽度改回 393（在 x=20 处右溢出 20pt）',
    apply: s => s.replace("const label = t => F({ name: 'Block State Label', dir: 'v', w: 353,",
                          "const label = t => F({ name: 'Block State Label', dir: 'v', w: 'system/screen-w',"),
  },
  {
    id: 'runtime',
    desc: '往实例子树里 appendChild（真 Figma 会抛错）',
    apply: s => s.replace("  const badge = inst.findOne(n => n.name === 'Badge');\n  if (badge) badge.fills = [paint(color)];",
                          "  const badge = inst.findOne(n => n.name === 'Badge');\n  if (badge) { badge.fills = [paint(color)]; badge.appendChild(ic('doc', 16)); }"),
  },
];

function runAgainst(file, runner) {
  const backup = fs.readFileSync(SRC, 'utf8');
  fs.writeFileSync(SRC, fs.readFileSync(file, 'utf8'));
  let out;
  try {
    out = execFileSync('node', [runner], { cwd: DIR, encoding: 'utf8' });
  } catch (e) {
    out = (e.stdout || '') + (e.stderr || '');
  } finally {
    fs.writeFileSync(SRC, backup);
  }
  return out;
}

console.log('\n════════ 检查器自检（变异测试）════════\n');
let pass = 0, fail = 0;

MUTANTS.forEach((m, i) => {
  const mutated = m.apply(original);
  if (mutated === original) {
    console.log(`  ⚠️  #${i + 1} [${m.id}] 变异未生效（源码已变？）— ${m.desc}`);
    fail++;
    return;
  }
  fs.writeFileSync(TMP, mutated);
  const out = runAgainst(TMP, m.runner === 'gates' ? GATES : CHECKS);
  const line = out.split('\n').find(l => l.includes(m.id));
  const caught = line && line.trim().startsWith('❌');
  if (caught) { pass++; console.log(`  ✅ #${i + 1} [${m.id}] 被抓到 — ${m.desc}`); }
  else { fail++; console.log(`  ❌ #${i + 1} [${m.id}] 漏检 — ${m.desc}\n       实际: ${(line || '(无该检查项输出)').trim()}`); }
});

try { fs.unlinkSync(TMP); } catch (e) { }
console.log(`\n════════ ${pass} / ${MUTANTS.length} 个变异被抓到 ════════\n`);
process.exit(fail ? 1 : 0);
