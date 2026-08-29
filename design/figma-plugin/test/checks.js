/* ============================================================================
 * Mosaic 设计生成器 —— 自动检查套件
 * ----------------------------------------------------------------------------
 * 用法：node test/checks.js
 *
 * 检查项：
 *   1. runtime            生成流程无异常，从任意起始页均可运行
 *   2. overflow           手机框内无文本超出内容区
 *   3. clipping           无节点被裁切祖先截断
 *   4. instances          组件 / 实例计数与结构
 *   5. variant-arch       变体架构（笛卡尔积 · 重复 · 命名 · 嵌套属性暴露）
 *   6. naming             变体命名规范
 *   7. token-binding      数值是否绑定到 Token（排除豁免值）
 *   8. touch-target       可交互元素 hit area ≥ 44pt
 *
 * 每个检查器都必须能被「故意改坏的版本」触发 —— 见 test/selftest.js。
 * ========================================================================== */

const path = require('path');
const CODE = path.join(__dirname, '..', 'code.js');

// ---------------------------------------------------------------- 豁免规则

/** 微观视觉值：波形条宽、描边、圆点等，不进 Token。 */
const MICRO = new Set([0.5, 1, 1.5, 2, 2.5, 3, 5]);
/** 组件专属视觉锚点，需在 code.js 的 ANCHOR 表中登记。 */
/**
 * 组件专属视觉锚点豁免表 —— 当前为空。
 * 保持为空是有意的：任何往这里加数字的行为都在削弱这项检查，
 * 加之前必须先问「能不能改成 Token」。
 */
const ANCHOR = new Set([]);

const RESULTS = [];
function report(id, ok, detail) { RESULTS.push({ id, ok, detail }); }

// ---------------------------------------------------------------- 工具

function freshRun(startPage) {
  Object.keys(require.cache).forEach(k => { if (k.includes('figma-stub') || k === CODE) delete require.cache[k]; });
  const stub = require('./figma-stub.js');
  if (startPage) {
    const p = figma.root.children.find(x => x.name === startPage);
    if (p) figma.currentPage = p;
  }
  require(CODE);
  return stub;
}
function wait(ms) { return new Promise(r => setTimeout(r, ms)); }
function pages() { return figma.root.children; }
function pageBy(frag) { return pages().find(p => p.name.includes(frag)); }

// ---------------------------------------------------------------- 检查器

function checkRuntime(stub) {
  const err = stub.NOTIFIES.find(n => n.opts && n.opts.error);
  report('runtime', !err, err ? err.msg : stub.NOTIFIES.map(n => n.msg).join(' | '));
}

/** 文本溢出：与最近的「定宽祖先」的内宽比较，而不是与一个拍脑袋的常数比较。 */
function checkOverflow() {
  const board = pageBy('Screens').children[0];
  const screens = board.findAll(n => /^\d\d · /.test(n.name || ''));
  const bad = [];
  const walk = (n, avail, ownerName) => {
    let next = avail, owner = ownerName;
    if (n.layoutMode && n.layoutMode !== 'NONE') {
      const fixedW = n.layoutMode === 'HORIZONTAL'
        ? n.primaryAxisSizingMode === 'FIXED' : n.counterAxisSizingMode === 'FIXED';
      if (fixedW) {
        const inner = n.width - (n.paddingLeft || 0) - (n.paddingRight || 0);
        if (inner > 0 && (next === null || inner < next)) { next = inner; owner = n.name; }
      }
    }
    if (n.type === 'TEXT' && next !== null && n.width > next + 0.5) {
      bad.push(`"${n._chars.slice(0, 16)}" 宽${n.width.toFixed(0)} > 容器 "${owner}" 内宽${next.toFixed(0)}`);
    }
    (n.children || []).forEach(c => walk(c, next, owner));
  };
  screens.forEach(s => walk(s, null, null));
  const uniq = [...new Set(bad)];
  report('overflow', uniq.length === 0, uniq.length ? uniq.slice(0, 5).join(' ; ') : `扫描 ${screens.length} 屏，0 处溢出`);
}

function checkClipping() {
  const hits = [];
  const walk = (n, clipW, clipName, offX) => {
    const right = (offX || 0) + n.width;
    if (clipW && n.width > clipW + 0.5)
      hits.push(`"${n.name}" 宽${n.width.toFixed(0)} > 裁切容器 "${clipName}" 宽${clipW.toFixed(0)}`);
    else if (clipW && right > clipW + 0.5)
      hits.push(`"${n.name}" 右边缘 ${right.toFixed(0)} 超出裁切容器 "${clipName}" 宽${clipW.toFixed(0)}（x 偏移 ${(offX || 0).toFixed(0)}）`);
    const nw = n.clipsContent ? Math.min(clipW || Infinity, n.width) : clipW;
    const nn = n.clipsContent && (!clipW || n.width <= clipW) ? n.name : clipName;
    const reset = n.clipsContent;
    (n.children || []).forEach(c => walk(c, nw === Infinity ? null : nw, nn, reset ? (c.x || 0) : (offX || 0) + (c.x || 0)));
  };
  ['Components', 'Screens'].forEach(f => pageBy(f).children.forEach(c => walk(c, null, null, 0)));
  const uniq = [...new Set(hits)];
  report('clipping', uniq.length === 0, uniq.length ? uniq.slice(0, 5).join(' ; ') : '0 处被截断');
}

function checkInstances(stub) {
  const comps = pageBy('Components');
  const sets = comps.children.filter(c => c.type === 'COMPONENT_SET').length;
  const plain = comps.children.filter(c => c.type === 'COMPONENT').length;
  report('instances', comps.children.length > 0,
    `${comps.children.length} 个顶层组件节点（${sets} 变体集 + ${plain} 单组件）· ${stub.CALLS.instance} 个实例 · ${stub.CALLS.compProps} 个组件属性`);
}

/**
 * 变体架构检查。
 * 不设机械的统一变体数上限 —— 只找结构性问题：
 *   a) 多个独立布尔维度被乘成完整笛卡尔积
 *   b) 组合数远超真实业务状态数（>=3 维即高度可疑）
 *   c) 重复变体名
 *   d) 变体命名不符合 `属性=值`
 *   e) 声明了 INSTANCE_SWAP / BOOLEAN 属性却没有节点引用它（接口没接上）
 */
function checkVariantArchitecture() {
  const comps = pageBy('Components');
  const issues = [];
  comps.children.forEach(c => {
    if (c.type === 'COMPONENT_SET') {
      const dims = Object.keys(c.variantGroupProperties || {});
      // a/b：多维笛卡尔积
      if (dims.length >= 3) {
        issues.push(`[笛卡尔积] "${c.name}" 有 ${dims.length} 个变体维度 (${dims.join('×')})，应改用嵌套组件或布尔属性`);
      } else if (dims.length === 2) {
        const sizes = dims.map(d => c.variantGroupProperties[d].values.length);
        if (sizes[0] * sizes[1] === c.children.length && sizes.every(s => s >= 2) && c.children.length > 6) {
          issues.push(`[笛卡尔积] "${c.name}" 是 ${sizes.join('×')} 的完整组合共 ${c.children.length} 变体，考虑拆为嵌套`);
        }
      }
      // c：重复
      const names = c.children.map(v => v.name);
      if (new Set(names).size !== names.length) issues.push(`[重复变体] "${c.name}" 存在同名变体`);
      // d：命名
      c.children.forEach(v => {
        if (!/^[^=]+=[^=]*(,\s*[^=]+=[^=]*)*$/.test(v.name)) issues.push(`[命名] "${c.name}" 的变体 "${v.name}" 不符合 属性=值`);
      });
    }
    // e：属性接口是否接上
    const defs = c.componentPropertyDefinitions || {};
    Object.keys(defs).forEach(pid => {
      const type = defs[pid].type;
      if (type !== 'INSTANCE_SWAP' && type !== 'BOOLEAN' && type !== 'TEXT') return;
      const field = type === 'INSTANCE_SWAP' ? 'mainComponent' : type === 'BOOLEAN' ? 'visible' : 'characters';
      const scope = c.type === 'COMPONENT_SET' ? c.children : [c];
      const wired = scope.some(v => v.findAll(n => n.componentPropertyReferences &&
        n.componentPropertyReferences[field] === pid).length > 0);
      if (!wired) issues.push(`[接口未接] "${c.name}" 的属性 "${pid.split('#')[0]}"(${type}) 没有任何节点引用`);
    });
  });
  report('variant-arch', issues.length === 0, issues.length ? issues.slice(0, 6).join(' ; ') :
    `${comps.children.filter(c => c.type === 'COMPONENT_SET').length} 个变体集架构合规，属性接口全部接上`);
}

function checkNaming() {
  const comps = pageBy('Components');
  const bad = [];
  comps.children.forEach(c => {
    if (!/^[A-Z]/.test(c.name)) bad.push(`组件名 "${c.name}" 未以大写开头`);
    if (/Variant \d|New Variant|Frame \d/.test(c.name)) bad.push(`组件名 "${c.name}" 疑似默认命名`);
  });
  report('naming', bad.length === 0, bad.length ? bad.join(' ; ') : `${comps.children.length} 个组件命名规范`);
}

/** Token 绑定检查：找未绑定变量的 spacing / radius，排除豁免值。 */
function checkTokenBinding() {
  const bad = [];
  const seen = new Set();
  const walk = n => {
    if (n.layoutMode && n.layoutMode !== 'NONE') {
      const check = (field, val) => {
        if (!val) return;
        if (MICRO.has(val) || ANCHOR.has(val)) return;
        if (n.boundVariables && n.boundVariables[field]) return;
        const key = `${field}=${val}@${n.name}`;
        if (seen.has(key)) return;
        seen.add(key);
        bad.push(`"${n.name}" ${field}=${val} 未绑定 Token`);
      };
      check('itemSpacing', n.itemSpacing);
      ['paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft'].forEach(f => check(f, n[f]));
    }
    if (n.cornerRadius && !MICRO.has(n.cornerRadius) && !ANCHOR.has(n.cornerRadius)) {
      const bound = n.boundVariables && n.boundVariables.topLeftRadius;
      if (!bound) {
        const key = `radius=${n.cornerRadius}@${n.name}`;
        if (!seen.has(key)) { seen.add(key); bad.push(`"${n.name}" cornerRadius=${n.cornerRadius} 未绑定 Token`); }
      }
    }
    (n.children || []).forEach(walk);
  };
  ['Components', 'Screens'].forEach(f => pageBy(f).children.forEach(walk));
  report('token-binding', bad.length === 0, bad.length ? `${bad.length} 处：` + bad.slice(0, 6).join(' ; ') : '全部数值已绑定 Token 或属豁免值');
}

/**
 * 触控目标：独立可点控件必须物理 ≥44pt。
 *
 * 行内 chip 是**有据可查的例外**：在一行里横排的 chip 若都做成 44pt 高，
 * 视觉上会变成一排厚按钮，不符合 iOS。这类元素靠 `.contentShape` 在实现层
 * 撑开 hit area（允许纵向重叠），设计稿只在组件说明中标注。
 */
const TAP_EXEMPT = {
  'Chip': '行内 chip，hit area 由 contentShape 撑开',
  'Tag': '行内 chip，同上',
  'Topic': '行内 chip，同上',
  'Folder Meta': '行内 chip，同上',
  'Trailing Icon': '菜单行内的装饰图标，整行 44pt 已是点击区',
  'Topics': '容器，非可点元素',
  'Insert Actions': '容器，其子项各自 44pt',
  'Editing Actions': '容器，其子项各自 44pt',
};
/** 必须物理满足 44pt 的独立控件（精确匹配）。 */
const TAP_STRICT = new Set(['Tappable', 'Leading', 'Trailing', 'Compose', 'Camera', 'Audio', 'Document',
  'Link', 'Media Insert', 'Bold', 'Italic', 'More Format', 'Record', 'Menu Item', 'Form Row',
  'CTA', 'Cancel', 'Confirm', 'Go To Settings']);

function checkTouchTarget() {
  const comps = pageBy('Components');
  const bad = [];
  const walk = n => {
    const nm = (n.name || '').split(' / ')[0];
    if (TAP_EXEMPT[n.name] || TAP_EXEMPT[nm]) return;
    if (TAP_STRICT.has(n.name) || TAP_STRICT.has(nm)) {
      if (n.width < 43.5 || n.height < 43.5) bad.push(`"${n.name}" ${n.width.toFixed(0)}×${n.height.toFixed(0)}`);
      return;
    }
    (n.children || []).forEach(walk);
  };
  // 变体集本身是容器，不参与判定；下钻到各变体
  comps.children.forEach(c => (c.type === 'COMPONENT_SET' ? c.children : [c]).forEach(walk));
  const uniq = [...new Set(bad)];
  report('touch-target', uniq.length === 0,
    uniq.length ? `${uniq.length} 处 < 44pt：` + uniq.slice(0, 8).join(' ; ')
                : `独立控件 hit area 全部 ≥44pt（${Object.keys(TAP_EXEMPT).length} 类行内元素为登记豁免）`);
}

/**
 * 多行文本必须显式定宽。
 *
 * 2026-08-07 MCP 实读的真实事故：`Row / Search Result` 的 excerpt 写成
 * `T(..., { lines: 2, grow: 1 })`，指望 auto-layout 的 grow 去约束宽度。
 * Figma 的实际行为是**不换行** —— 文本拉成一条长行，被屏幕的 clipsContent 裁掉，
 * 用户看到的是半句话。桩当时也估成一行，于是两边"一致地错"，calibration 全绿。
 *
 * 结论：`maxLines >= 2` 必须配 `width`（走 resize，textAutoResize='NONE'），
 * 不能靠 grow / stretch。这条规则在源码层面就能判定，不依赖桩的排版保真度。
 */
function checkMultilineWidth() {
  const bad = [];
  const walk = n => {
    if (n.type === 'TEXT' && n.maxLines >= 2 && n.textAutoResize !== 'NONE')
      bad.push(`"${n.name}" maxLines=${n.maxLines} 却未显式定宽（textAutoResize=${n.textAutoResize}）`);
    (n.children || []).forEach(walk);
  };
  ['Components', 'Screens'].forEach(f => pageBy(f).children.forEach(walk));
  const uniq = [...new Set(bad)];
  report('multiline-width', uniq.length === 0,
    uniq.length ? `${uniq.length} 处多行文本未定宽（Figma 不会换行，会被裁掉）：` + uniq.slice(0, 5).join(' ; ')
                : '多行文本全部显式定宽');
}

/**
 * TEXT 组件属性不得跨「文案本就不同」的变体共用。
 *
 * 2026-08-07 第 3 轮实读的真实事故：`Bar / Search Status` 的四个变体各有各的文案，
 * 却共用一个 Message TEXT 属性。Figma 的 TEXT 属性**全变体共用一个默认值**，
 * 切换变体不换文案 —— 于是 degraded 变体在屏上显示成了 building 的「正在准备智能搜索…」。
 * 四个变体里三个在说谎，而结构检查、gate、校准全绿。
 *
 * 判定用的是**被默认值盖掉之前**的文案（桩记在 `_authoredChars` 里）——
 * 覆盖之后各变体看起来都一样，事后无法分辨「本来就该一样」和「本来不同、被抹平了」。
 * 修法二选一：把属性去掉（文案属于状态定义），或让每个实例都显式赋值。
 */
function checkTextPropConsistency() {
  const bad = [];
  const risky = {};   // pid → 属性名，仅收「各变体文案本就不同」的属性

  pageBy('Components').children.filter(c => c.type === 'COMPONENT_SET').forEach(set => {
    const defs = set.componentPropertyDefinitions || {};
    Object.keys(defs).filter(pid => defs[pid].type === 'TEXT').forEach(pid => {
      const texts = new Set();
      set.children.forEach(v => v.findAll(n => n.componentPropertyReferences &&
        n.componentPropertyReferences.characters === pid)
        .forEach(n => texts.add(n._authoredChars !== undefined ? n._authoredChars : n.characters)));
      if (texts.size > 1) risky[pid] = set.name + ' / ' + pid.split('#')[0];
    });
  });

  // 变体间文案不同本身不是错 —— 错的是**实例没有显式赋值**，那样它只会拿到默认值。
  const walk = (n, screenName) => {
    if (n.componentPropertyReferences && n.componentPropertyReferences.characters) {
      const pid = n.componentPropertyReferences.characters;
      if (risky[pid] && !n._propSet)
        bad.push(`${screenName}：实例未给 "${risky[pid]}" 赋值，只会显示默认文案 ` +
                 `${JSON.stringify(String(n.characters).slice(0, 16))}`);
    }
    (n.children || []).forEach(c => walk(c, screenName));
  };
  pageBy('Screens').children.forEach(board =>
    board.children.forEach(col => walk(col, (col.name || '').replace('Column / ', ''))));

  const uniq = [...new Set(bad)];
  report('text-prop', uniq.length === 0,
    uniq.length ? `${uniq.length} 处：` + uniq.slice(0, 4).join(' ; ')
                : `${Object.keys(risky).length} 个异文案 TEXT 属性，全部实例均已显式赋值`);
}

// ---------------------------------------------------------------- 运行

async function run() {
  const stub = freshRun();
  await wait(400);
  checkRuntime(stub);
  checkOverflow();
  checkClipping();
  checkInstances(stub);
  checkVariantArchitecture();
  checkNaming();
  checkTokenBinding();
  checkTouchTarget();
  checkMultilineWidth();
  checkTextPropConsistency();

  // 起始页健壮性
  const names = pages().map(p => p.name);
  const fails = [];
  for (const n of names) {
    const s = freshRun(n);
    await wait(300);
    if (s.NOTIFIES.find(x => x.opts && x.opts.error)) fails.push(n);
  }
  report('start-page', fails.length === 0, fails.length ? '失败于：' + fails.join(', ') : `${names.length} 个起始页全部通过`);

  console.log('\n════════ 自动检查结果 ════════');
  let failed = 0;
  RESULTS.forEach(r => {
    if (!r.ok) failed++;
    console.log(`  ${r.ok ? '✅' : '❌'} ${r.id.padEnd(16)} ${r.detail}`);
  });
  console.log(`════════ ${RESULTS.length - failed} / ${RESULTS.length} 通过 ════════\n`);
  process.exit(failed ? 1 : 0);
}
run();
