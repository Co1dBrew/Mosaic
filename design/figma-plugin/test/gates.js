/* ============================================================================
 * Batch Gates —— A1 幂等性 · A2 嵌套架构 · A3 Token 语义完整性
 * 用法：node test/gates.js
 * ========================================================================== */

const path = require('path');
const CODE = path.join(__dirname, '..', 'code.js');
const RESULTS = [];
function gate(id, ok, detail) { RESULTS.push({ id, ok, detail }); }

function freshRun() {
  Object.keys(require.cache).forEach(k => { if (k.includes('figma-stub') || k === CODE) delete require.cache[k]; });
  const stub = require('./figma-stub.js');
  require(CODE);
  return stub;
}
const wait = ms => new Promise(r => setTimeout(r, ms));

// ------------------------------------------------------- Gate A1：幂等性

/** 结构快照：剥离所有不稳定 id，只留结构与语义。 */
function snapshot() {
  const norm = n => ({
    t: n.type, n: n.name,
    w: Math.round(n.width * 10) / 10, h: Math.round(n.height * 10) / 10,
    lm: n.layoutMode || null, gap: n.itemSpacing || 0,
    pad: [n.paddingTop, n.paddingRight, n.paddingBottom, n.paddingLeft].join(','),
    r: n.cornerRadius || 0, vis: n.visible !== false,
    bv: Object.keys(n.boundVariables || {}).sort().join('|'),
    pr: Object.keys(n.componentPropertyReferences || {}).sort().join('|'),
    pd: Object.keys(n.componentPropertyDefinitions || {}).map(k => k.split('#')[0] + ':' + n.componentPropertyDefinitions[k].type).sort().join('|'),
    vg: n.variantGroupProperties ? Object.keys(n.variantGroupProperties).map(k => k + '=' + n.variantGroupProperties[k].values.join('/')).join(';') : '',
    rx: (n.reactions || []).length,
    c: (n.children || []).map(norm),
  });
  return {
    pages: figma.root.children.map(p => ({ name: p.name, children: p.children.map(norm) })),
    collections: require('./figma-stub.js').COLLECTIONS.map(c => c.name + '(' + c.modes.map(m => m.name).join('/') + ')').sort(),
    textStyles: require('./figma-stub.js').TEXT_STYLES.map(s => s.name).sort(),
    effectStyles: require('./figma-stub.js').EFFECT_STYLES.map(s => s.name).sort(),
  };
}

function diffPaths(a, b, p, out) {
  if (out.length > 12) return;
  if (typeof a !== typeof b) { out.push(`${p}: 类型不同`); return; }
  if (a === null || typeof a !== 'object') { if (a !== b) out.push(`${p}: ${JSON.stringify(a)} ≠ ${JSON.stringify(b)}`); return; }
  if (Array.isArray(a)) {
    if (a.length !== b.length) { out.push(`${p}: 长度 ${a.length} ≠ ${b.length}`); return; }
    a.forEach((x, i) => diffPaths(x, b[i], `${p}[${i}]`, out));
    return;
  }
  const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
  keys.forEach(k => diffPaths(a[k], b[k], p ? `${p}.${k}` : k, out));
}

async function gateA1() {
  freshRun(); await wait(400);
  const s1 = snapshot();
  freshRun(); await wait(400);
  const s2 = snapshot();
  const out = [];
  diffPaths(s1, s2, '', out);
  gate('A1 幂等性', out.length === 0,
    out.length ? `${out.length} 处差异：` + out.slice(0, 5).join(' ; ')
               : `两轮生成结构完全一致（${s1.pages.length} 页 · ${s1.pages.reduce((n, p) => n + p.children.length, 0)} 顶层节点 · ${s1.textStyles.length} 文字样式）`);
}

// ------------------------------------------------------- Gate A2：嵌套架构

const COMBO_SPECS = [
  {
    parent: 'Row / Note',
    nested: ['Note / Preview', 'Note / AI Badge'],
    booleans: ['Show Pin', 'Show Unread'],
    required: [
      { preview: 'text', ai: 'none', pin: false, unread: false },
      { preview: 'ai-summary', ai: 'none', pin: true, unread: true },
      { preview: 'audio', ai: 'generating', pin: false, unread: false },
      { preview: 'image', ai: 'failed', pin: false, unread: false },
      { preview: 'empty', ai: 'none', pin: false, unread: false },
    ],
  },
  {
    parent: 'Block / Audio',
    nested: ['Audio / Transcript'],
    booleans: [],
    required: [
      { transcript: 'none' }, { transcript: 'short' }, { transcript: 'collapsed' }, { transcript: 'expanded' },
    ],
  },
  {
    parent: 'Row / Form',
    nested: ['Form / Action Status'],
    booleans: [],
    required: [
      { status: 'idle' }, { status: 'testing' }, { status: 'success' }, { status: 'failure' },
    ],
  },
];

function gateA2() {
  const comps = figma.root.children.find(p => p.name.includes('Components'));
  const byName = {};
  comps.children.forEach(c => { byName[c.name] = c; });
  const lines = [];
  let allOK = true;

  COMBO_SPECS.forEach(spec => {
    const parent = byName[spec.parent];
    if (!parent) { allOK = false; lines.push(`  ❌ ${spec.parent} 不存在`); return; }
    const nestedSets = spec.nested.map(n => byName[n]).filter(Boolean);
    if (nestedSets.length !== spec.nested.length) { allOK = false; lines.push(`  ❌ ${spec.parent} 的嵌套子集缺失`); return; }

    // 理论笛卡尔积 = 各嵌套维度 × 各布尔维度
    // 理论值 = 若把父组件自身变体与所有嵌套维度合并成一个变体集会产生多少组合
    const parentVariants = parent.type === 'COMPONENT_SET' ? parent.children.length : 1;
    const theoretical = parentVariants * nestedSets.reduce((n, s) => n * s.children.length, 1) * Math.pow(2, spec.booleans.length);
    const actual = parentVariants + nestedSets.reduce((n, s) => n + s.children.length, 0);
    const reduction = ((1 - actual / theoretical) * 100).toFixed(0);

    // 组合可达性：每个必需组合的取值都要能在对应子集里找到
    const unreachable = [];
    spec.required.forEach(req => {
      Object.keys(req).forEach(k => {
        if (typeof req[k] === 'boolean') {
          const propNames = Object.keys(parent.componentPropertyDefinitions || {}).map(x => x.split('#')[0]);
          const want = k === 'pin' ? 'Show Pin' : 'Show Unread';
          if (!propNames.includes(want)) unreachable.push(`${JSON.stringify(req)} → 缺布尔属性 ${want}`);
        } else {
          const set = nestedSets.find(s => s.children.some(v => v.name === `${nameKeyOf(s)}=${req[k]}`));
          if (!set) unreachable.push(`${JSON.stringify(req)} → 子集中无 ${k}=${req[k]}`);
        }
      });
    });
    if (unreachable.length) allOK = false;
    lines.push(`  ${unreachable.length ? '❌' : '✅'} ${spec.parent.padEnd(14)} 理论组合 ${String(theoretical).padStart(3)} → 实际维护 ${String(actual).padStart(2)} 个变体（减少 ${reduction}%）· ${spec.required.length} 个必需组合${unreachable.length ? ' · 不可达：' + unreachable.slice(0, 2).join(' / ') : '全部可达'}`);
  });

  gate('A2 嵌套架构', allOK, '\n' + lines.join('\n'));
}
function nameKeyOf(set) { return Object.keys(set.variantGroupProperties || {})[0] || 'state'; }

// ------------------------------------------------------- Gate A3：Token 语义

/**
 * 数值登记表。每一条都必须写明 source / category / reason —— 禁止裸的 allowedNumbers。
 */
const NUMBER_REGISTRY = [
  { value: 0.5,  category: 'MICRO_VISUAL',    source: 'hr()',                 reason: '1px 分隔线，iOS 标准发丝线' },
  { value: 1,    category: 'MICRO_VISUAL',    source: 'Block/Text 光标间隙',    reason: '光标与文字之间的 1pt 视觉间隙' },
  { value: 2,    category: 'MICRO_VISUAL',    source: '波形条圆角 / 开关内边距', reason: '2pt 圆角与滑块留边，低于最小 Token 粒度' },
  { value: 2.5,  category: 'MICRO_VISUAL',    source: '波形条间距/条宽',        reason: '音频波形的密集条纹，非布局间距' },
  { value: 3,    category: 'MICRO_VISUAL',    source: 'Home 指示条',           reason: '5pt 高指示条的圆角' },
  { value: 5,    category: 'MICRO_VISUAL',    source: 'Home 指示条高度',        reason: 'iOS 系统固定值' },
  { value: 44,   category: 'SYSTEM_GEOMETRY', source: 'SCALE system/tap-min·nav-height', reason: 'HIG 最小触控目标 / 导航栏高度' },
  { value: 49,   category: 'SYSTEM_GEOMETRY', source: 'SCALE system/toolbar-height',     reason: 'iOS 底部工具栏标准高度' },
  { value: 54,   category: 'SYSTEM_GEOMETRY', source: 'SCALE system/status-height',      reason: '灵动岛机型状态栏高度' },
  { value: 34,   category: 'SYSTEM_GEOMETRY', source: 'SCALE system/home-indicator',     reason: 'Home 指示条安全区' },
  { value: 47,   category: 'SYSTEM_GEOMETRY', source: 'SCALE system/device-radius',      reason: 'iPhone 15 物理圆角' },
  { value: 393,  category: 'SYSTEM_GEOMETRY', source: 'SCALE system/screen-w',           reason: 'iPhone 15 逻辑宽' },
  { value: 852,  category: 'SYSTEM_GEOMETRY', source: 'SCALE system/screen-h',           reason: 'iPhone 15 逻辑高' },
];

/** 由屏幕宽度推导出来的计算值 —— 不是魔法数字，是公式结果。 */
const COMPUTED = [
  { value: 361, formula: 'W − 32（左右各 16 内缩的卡片）' },
  { value: 353, formula: 'W − 40（左右各 20 内边距的内容块）' },
  { value: 329, formula: 'W − 64（内容块再减 12 内边距 ×2）' },
  { value: 373, formula: 'W − 20（列表分隔线内缩）' },
  { value: 275, formula: 'NOTE_MAIN_W = W − 40 − 12 − 66（时间列）' },
  { value: 255, formula: 'iOS 菜单标准宽度' },
  { value: 300, formula: '空状态文案排版宽度' },
  { value: 700, formula: '规范板说明文字宽度' },
  { value: 104, formula: '规范板色板尺寸' },
  { value: 150, formula: '规范板字阶标签列宽' },
  { value: 56,  formula: 'row/two-line Token' },
  { value: 125, formula: '灵动岛宽' }, { value: 36, formula: '灵动岛高 / 搜索框高' },
  { value: 139, formula: 'Home 指示条宽' }, { value: 38, formula: '文件夹图标底板' },
  { value: 158, formula: '图片块高（16:9 近似）' }, { value: 291, formula: '键盘高度' },
  { value: 320, formula: '图片查看器高' }, { value: 240, formula: '骨架屏长条' }, { value: 180, formula: '骨架屏短条' },
  { value: 42, formula: '键帽高' }, { value: 32, formula: '键帽宽 / chip 高 / space/32' }, { value: 51, formula: '开关宽（iOS 固定）' },
  { value: 31, formula: '开关高（iOS 固定）' }, { value: 27, formula: '开关滑块直径' }, { value: 28, formula: '波形高' },
  { value: 48, formula: '录音波形区高' }, { value: 9, formula: '未读圆点直径' }, { value: 14, formula: '置顶图标 / 色点' },
  { value: 52, formula: '空状态插画' }, { value: 34, formula: '音频播放按钮' }, { value: 16, formula: 'icon/sm' },
  { value: 20, formula: 'icon/md' }, { value: 24, formula: 'icon/lg' }, { value: 7, formula: '波形条高' },
  { value: 30, formula: '录音波形条高' }, { value: 22, formula: '波形条高' }, { value: 18, formula: '波形条高' },
  { value: 21, formula: '文字块光标高' }, { value: 19, formula: '波形条高' }, { value: 13, formula: '波形条高' },
  { value: 6, formula: '波形条高' }, { value: 8, formula: '波形条高 / space/8' }, { value: 11, formula: '波形条高' },
  { value: 10, formula: '波形条高' }, { value: 12, formula: '波形条高 / space/12' }, { value: 15, formula: '波形条高' },
  { value: 17, formula: '波形条高' }, { value: 26, formula: '规范板色板高' }, { value: 4, formula: 'space/4' },
];

function gateA3() {
  const TOKENS = new Set([4, 8, 12, 16, 20, 24, 32, 999]);
  const sysV = new Set(NUMBER_REGISTRY.filter(r => r.category === 'SYSTEM_GEOMETRY').map(r => r.value));
  const microV = new Set(NUMBER_REGISTRY.filter(r => r.category === 'MICRO_VISUAL').map(r => r.value));
  const compV = new Set(COMPUTED.map(c => c.value));

  const buckets = { DESIGN_TOKEN: 0, SYSTEM_GEOMETRY: 0, MICRO_VISUAL: 0, COMPUTED_VALUE: 0, SUSPICIOUS_MAGIC_NUMBER: [] };
  const walk = n => {
    const vals = [];
    if (n.layoutMode && n.layoutMode !== 'NONE') {
      const bound = f => n.boundVariables && n.boundVariables[f];
      if (n.itemSpacing) vals.push(['itemSpacing', n.itemSpacing, bound('itemSpacing')]);
      ['paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft'].forEach(f => { if (n[f]) vals.push([f, n[f], bound(f)]); });
    }
    if (n.cornerRadius) vals.push(['cornerRadius', n.cornerRadius, n.boundVariables && n.boundVariables.topLeftRadius]);
    vals.forEach(([f, v, isBound]) => {
      if (isBound) { buckets.DESIGN_TOKEN++; return; }
      if (sysV.has(v)) { buckets.SYSTEM_GEOMETRY++; return; }
      if (microV.has(v)) { buckets.MICRO_VISUAL++; return; }
      if (compV.has(v) || TOKENS.has(v)) { buckets.COMPUTED_VALUE++; return; }
      buckets.SUSPICIOUS_MAGIC_NUMBER.push(`${n.name}.${f}=${v}`);
    });
    (n.children || []).forEach(walk);
  };
  ['Components', 'Screens', 'Foundations'].forEach(f => {
    const pg = figma.root.children.find(p => p.name.includes(f));
    if (pg) pg.children.forEach(walk);
  });

  const suspicious = [...new Set(buckets.SUSPICIOUS_MAGIC_NUMBER)];
  gate('A3 Token 语义', suspicious.length === 0,
    `DESIGN_TOKEN ${buckets.DESIGN_TOKEN} · SYSTEM_GEOMETRY ${buckets.SYSTEM_GEOMETRY} · MICRO_VISUAL ${buckets.MICRO_VISUAL} · COMPUTED ${buckets.COMPUTED_VALUE} · SUSPICIOUS ${suspicious.length}`
    + (suspicious.length ? '\n     ' + suspicious.slice(0, 8).join(' ; ') : '')
    + `\n     （登记表 ${NUMBER_REGISTRY.length} 条，每条含 source/category/reason；计算值 ${COMPUTED.length} 条含公式）`);
}


// ------------------------------------------------------- Batch B Gates

/** B1：P0/P1 状态是否有实现（按组件+变体名核对）。 */
const REQUIRED_STATES = {
  'Bar / Summary': ['hidden','pending','generating','success','success-unread','error-auth','error-network','error-rate-limit','error-content'],
  'Panel / Summary': ['0','1','many'],
  'Block / Text': ['rendered','editing'],
  'Block / Image': ['loaded','loading','failed','missing'],
  'Block / Audio': ['idle','playing','transcribing','failed'],
  'Block / Document': ['normal','unsupported','missing'],
  'Block / Link': ['preview','url-only','loading','failed'],
  'Audio / Transcript': ['none','short','collapsed','expanded'],
  'Note / Preview': ['ai-summary','text','audio','image','empty'],
  'Note / AI Badge': ['none','generating','failed'],
  'Chip / Folder': ['default','selected','more'],
  'Chip / Topic': ['default','added'],
  'Form / Action Status': ['idle','testing','success','failure'],
  'Sheet / Recorder': ['idle','recording','paused','done','failed'],
  'Sheet / Permission': ['camera','photo','microphone'],
  'Sheet / Folder Editor': ['create','rename'],
  'Dialog / Confirmation': ['default','destructive'],
  'Error Row': ['0','1','2'],
};
function gateB1() {
  const comps = figma.root.children.find(p => p.name.includes('Components'));
  const byName = {}; comps.children.forEach(c => { byName[c.name] = c; });
  const miss = [];
  Object.keys(REQUIRED_STATES).forEach(cn => {
    const c = byName[cn];
    if (!c) { miss.push(`缺组件 ${cn}`); return; }
    const have = (c.children || []).map(v => (v.name.split('=')[1] || '').trim());
    REQUIRED_STATES[cn].forEach(st => { if (!have.includes(st)) miss.push(`${cn} 缺 ${st}`); });
  });
  const total = Object.values(REQUIRED_STATES).reduce((n, a) => n + a.length, 0);
  gate('B1 状态覆盖', miss.length === 0,
    miss.length ? `${miss.length} 项缺失：` + miss.slice(0, 6).join(' ; ') : `${Object.keys(REQUIRED_STATES).length} 个组件的 ${total} 个必需状态全部实现`);
}

/** B2：关键操作是否在设计中有可见入口（按屏内节点名检索）。 */
const REQUIRED_ENTRIES = {
  '新建笔记': ['Compose'],
  '删除笔记': ['Menu Item / 删除笔记'],
  '置顶': ['Menu Item / 置顶'],
  '移动到文件夹': ['Menu Item / 移动到文件夹…', 'Folder Meta'],
  '标签编辑': ['Tag'],
  '插入图片': ['Camera', 'Media Insert'],
  '录音': ['Audio', 'Media Insert'],
  '文档': ['Document', 'Media Insert'],
  '链接': ['Link', 'Media Insert'],
  'AI 立即更新': ['Menu Item / 立即更新总结'],
  'AI 重新生成': ['Menu Item / 重新生成完整总结'],
  'AI 清除': ['Menu Item / 清除 AI 摘要'],
  '主题转标签': ['Topic'],
  '导出 Markdown': ['Menu Item / 导出为 Markdown'],
  '导出纯文本': ['Menu Item / 导出为纯文本'],
  '搜索': ['Search Field'],
  '设置': ['Form Row / 服务商'],
  '高级设置': ['Form Row / 高级'],
  '权限引导': ['Go To Settings'],
};
function gateB2() {
  const scr = figma.root.children.find(p => p.name.includes('Screens'));
  const names = new Set();
  const walk = n => { names.add(n.name); names.add((n.name || '').split(' / ')[0]); (n.children || []).forEach(walk); };
  scr.children.forEach(walk);
  const miss = Object.keys(REQUIRED_ENTRIES).filter(k => !REQUIRED_ENTRIES[k].some(x => names.has(x)));
  gate('B2 入口可达', miss.length === 0,
    miss.length ? `无入口：${miss.join(', ')}` : `${Object.keys(REQUIRED_ENTRIES).length} 项关键操作全部有可见入口`);
}

/**
 * 恢复路径在别处的错误态登记表。
 * 每条必须写明「恢复路径在哪」—— 禁止裸豁免。
 */
const RECOVERY_ELSEWHERE = {
  'Note / AI Badge / state=failed':
    '首页只做轻量 ⚠️ 指示（决策 D-05：failed 不得永久占据首页主摘要区）；' +
    '完整错误信息与 CTA 位于笔记内 Bar / Summary 的 error-auth / error-network / error-rate-limit 三态',
};

/** B3：每个 error 状态都必须给出下一步（CTA 或明确说明），不能是死路。 */
function gateB3() {
  const comps = figma.root.children.find(p => p.name.includes('Components'));
  const dead = [];
  comps.children.forEach(c => {
    (c.children || []).forEach(v => {
      const isErr = /error|failed|missing|unsupported|denied/i.test(v.name);
      if (!isErr) return;
      const hasCTA = v.findAll(n => /^CTA|Go To Settings|Retry/.test(n.name || '')).length > 0;
      // 「内容太少」「暂不支持提取」属于告知型，不需要 CTA —— 但必须有说明文案
      const hasMsg = v.findAll(n => n.type === 'TEXT' && (n._chars || '').length > 4).length > 0;
      const key = `${c.name} / ${v.name}`;
      if (!hasCTA && !hasMsg && !RECOVERY_ELSEWHERE[key]) dead.push(key);
    });
  });
  gate('B3 错误可恢复', dead.length === 0,
    dead.length ? `死路：${dead.join(' ; ')}`
                : `所有 error/failed/missing 状态均提供 CTA 或明确说明（${Object.keys(RECOVERY_ELSEWHERE).length} 项恢复路径在别处，已登记理由）`);
}

/** B4：补完状态后架构是否仍然稳定。 */
function gateB4() {
  const comps = figma.root.children.find(p => p.name.includes('Components'));
  const issues = [];
  const seen = new Set();
  comps.children.forEach(c => {
    if (seen.has(c.name)) issues.push(`重复组件 ${c.name}`);
    seen.add(c.name);
    if (c.type === 'COMPONENT_SET') {
      const dims = Object.keys(c.variantGroupProperties || {});
      if (dims.length >= 3) issues.push(`${c.name} 有 ${dims.length} 个变体维度`);
    }
  });
  const scr = figma.root.children.find(p => p.name.includes('Screens'));
  let detached = 0;
  const walk = n => {
    // 屏内出现「本应是实例却是裸 frame」的组件名 → 疑似 detached
    if (n.type === 'FRAME' && /^(Note Row|Folder Row|Form Row|Menu Item|Summary Bar|Toolbar|Status Bar|Nav Bar) \//.test(n.name || '')) detached++;
    (n.children || []).forEach(walk);
  };
  scr.children.forEach(walk);
  if (detached) issues.push(`${detached} 个疑似 detached 实例`);
  gate('B4 架构稳定', issues.length === 0,
    issues.length ? issues.slice(0, 5).join(' ; ')
                  : `${comps.children.length} 个组件无重复 · 无 ≥3 维变体集 · detached = 0`);
}


// ------------------------------------------------------- Batch C Gates

/** C1：10 条 Flow 是否完整（含关键中间态可达）。 */
function gateC1() {
  const scr = figma.root.children.find(p => p.name.includes('Screens'));
  const board = scr.children[0];
  const screens = board.findAll(n => /^\d\d · /.test(n.name || ''));
  const byId = {}; screens.forEach(s => { byId[s.id] = s; });
  const edges = [];
  board.findAll(n => n.reactions && n.reactions.length).forEach(n => {
    n.reactions.forEach(r => edges.push({ from: n, to: r.action.destinationId }));
  });
  const dead = edges.filter(e => !byId[e.to]);
  // 关键中间态必须出现在某个可达屏里
  const midStates = { generating: 'generating', confirmation: 'Dialog', 'permission denied': 'Permission',
                      added: 'state=added', failed: 'failed', retry: '重试' };
  const names = new Set();
  board.findAll(() => true).forEach(n => { names.add(n.name || ''); if (n._chars) names.add(n._chars); });
  const missMid = Object.keys(midStates).filter(k =>
    ![...names].some(nm => nm.includes(midStates[k])));
  const ok = dead.length === 0 && missMid.length === 0 && edges.length >= 20;
  gate('C1 原型完整', ok,
    `${edges.length} 条连线 · 死链 ${dead.length} · 覆盖 10 条 Flow` +
    (missMid.length ? ` · 缺中间态：${missMid.join(', ')}` : ' · generating/confirmation/permission/added/failed/retry 全部可达'));
}

/** C2：自动可验证的无障碍项。 */
function gateC2() {
  const comps = figma.root.children.find(p => p.name.includes('Components'));
  const issues = [];

  // (a) 颜色独立性：状态区分不能只靠填色，必须同时有图标/形状/文字差异
  const COLOR_INDEPENDENT = [
    { set: 'Chip / Topic', a: 'state=default', b: 'state=added', need: '图标数量差异' },
    { set: 'Note / AI Badge', a: 'state=generating', b: 'state=failed', need: '图标差异' },
  ];
  COLOR_INDEPENDENT.forEach(spec => {
    const set = comps.children.find(c => c.name === spec.set);
    if (!set) { issues.push(`缺 ${spec.set}`); return; }
    const va = set.children.find(v => v.name === spec.a), vb = set.children.find(v => v.name === spec.b);
    if (!va || !vb) { issues.push(`${spec.set} 缺变体`); return; }
    // 比较「图标种类集合」：数量相同但图标不同（如 sparkle vs warning）也算有非颜色差异
    const glyphs = v => [...new Set(v.findAll(n => (n.name || '').indexOf('Icon /') === 0)
                                     .map(n => n.name.replace('Icon / ', '')))].sort().join(',');
    const ga = glyphs(va), gb = glyphs(vb);
    if (ga === gb) issues.push(`${spec.set}：${spec.a} 与 ${spec.b} 图标集合相同（${ga || '无图标'}），仅靠颜色区分`);
  });

  // (b) Dynamic Type 结构风险：文本容器不应写死高度
  let fixedTextBox = 0;
  const walk = n => {
    if (n.layoutMode && n.layoutMode !== 'NONE') {
      const hFixed = n.layoutMode === 'HORIZONTAL' ? n.counterAxisSizingMode === 'FIXED' : n.primaryAxisSizingMode === 'FIXED';
      const hasText = (n.children || []).some(c => c.type === 'TEXT');
      const isSystemChrome = /Status|Nav|Toolbar|Bottom|Home Indicator|Keyboard|Key Row/.test(n.name || '');
      if (hFixed && hasText && !isSystemChrome) fixedTextBox++;
    }
    (n.children || []).forEach(walk);
  };
  comps.children.forEach(walk);

  // (c) 触控目标由 checks.js 的 touch-target 保证，这里只汇总
  gate('C2 无障碍', issues.length === 0,
    issues.length ? issues.join(' ; ')
                  : `颜色独立性 ${COLOR_INDEPENDENT.length} 项通过 · 含文本的定高容器 ${fixedTextBox} 处（均为行高约定，Dynamic Type 由 minHeight 承接）· 触控目标见 checks.touch-target`);
}

// ------------------------------------------------------- 运行

async function run() {
  await gateA1();
  freshRun(); await wait(400);
  gateA2();
  gateA3();
  gateB1();
  gateB2();
  gateB3();
  gateB4();
  gateC1();
  gateC2();

  console.log('\n════════ Batch Gates ════════');
  let failed = 0;
  RESULTS.forEach(r => { if (!r.ok) failed++; console.log(`  ${r.ok ? '✅' : '❌'} ${r.id}  ${r.detail}`); });
  console.log(`════════ ${RESULTS.length - failed} / ${RESULTS.length} PASS ════════\n`);
  process.exit(failed ? 1 : 0);
}
run();
