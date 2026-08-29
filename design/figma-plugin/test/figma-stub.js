/* Figma Plugin API 桩 v2 —— 覆盖组件 / 变体 / 组件属性 / 数值变量 / 分页 / 原型。
   目的是在 Node 里真实执行 code.js，把运行时错误挡在进 Figma 之前。 */

let idc = 0;
const CALLS = {
  frame: 0, text: 0, rect: 0, svg: 0, component: 0, instance: 0,
  variantSets: 0, boundPaints: 0, boundNums: 0, compProps: 0, reactions: 0,
  textStyleApplied: 0, effectStyleApplied: 0, varColor: 0, varFloat: 0,
};
const COLLECTIONS = [], TEXT_STYLES = [], EFFECT_STYLES = [], PAGES = [], NOTIFIES = [];
const ALL_COMPONENTS = {};
const LOADED = global.__L = new Set();
let CLOSED = false;

const BINDABLE_NUM = new Set(['paddingLeft', 'paddingRight', 'paddingTop', 'paddingBottom',
  'itemSpacing', 'counterAxisSpacing', 'topLeftRadius', 'topRightRadius', 'bottomLeftRadius',
  'bottomRightRadius', 'width', 'height', 'minWidth', 'minHeight', 'maxWidth', 'maxHeight',
  'strokeWeight', 'opacity']);

function baseNode(type) {
  const n = {
    id: 'n' + (++idc), type, name: type, x: 0, y: 0, width: 100, height: 100,
    visible: true, parent: null, children: [],
    fills: [], strokes: [], strokeWeight: 1, effects: [], effectStyleId: '', cornerRadius: 0,
    constraints: { horizontal: 'MIN', vertical: 'MIN' },
    layoutGrow: 0, layoutAlign: 'INHERIT', layoutPositioning: 'AUTO',
    _cpr: null, reactions: [],
    boundVariables: {},

    resize(w, h) {
      if (typeof w !== 'number' || !isFinite(w) || w <= 0) throw new Error(`${type} "${this.name}" resize 宽非法: ${w}`);
      if (typeof h !== 'number' || !isFinite(h) || h <= 0) throw new Error(`${type} "${this.name}" resize 高非法: ${h}`);
      const ow = this.width, oh = this.height;
      if (this.type === 'INSTANCE') this._sizeOverride = true;   // 记录显式尺寸覆盖
      this.width = w; this.height = h;
      // SCALE 约束的子节点随父级等比缩放（图标实例改尺寸时依赖此行为）
      if (ow > 0 && oh > 0 && (this.layoutMode === 'NONE' || !this.layoutMode)) {
        const sx = w / ow, sy = h / oh;
        (this.children || []).forEach(c => {
          if (c.constraints && c.constraints.horizontal === 'SCALE') {
            c.x = (c.x || 0) * sx; c.width = Math.max(0.01, c.width * sx);
            c.y = (c.y || 0) * sy; c.height = Math.max(0.01, c.height * sy);
          }
        });
      }
      if (this._relayout) this._relayout();
    },
    appendChild(c) {
      if (!c) throw new Error(`${type} "${this.name}" appendChild 收到空节点`);
      if (c === this) throw new Error('不能把节点加到自己里');
      // Figma 真实约束：实例的子树是只读的，不能增删/重排子节点
      if (this.type === 'INSTANCE' || this._inInstance)
        throw new Error(`不能往实例子树里 appendChild（目标 "${this.name}"）—— 实例内部只允许覆盖属性（fills/characters/可见性），增删子节点要改用组件属性（INSTANCE_SWAP / BOOLEAN）`);
      if (c.parent) c.parent.children = c.parent.children.filter(x => x !== c);
      c.parent = this; this.children.push(c); this._relayout();
    },
    insertChild(i, c) { this.appendChild(c); },
    remove() {
      if (this._inInstance)
        throw new Error(`不能删除实例子树里的节点（"${this.name}"）—— 应改用组件的 BOOLEAN 属性控制显隐`);
      if (this.parent) this.parent.children = this.parent.children.filter(x => x !== this);
      this.parent = null;
    },
    findOne(fn) {
      for (const c of this.children) { if (fn(c)) return c; const r = c.findOne ? c.findOne(fn) : null; if (r) return r; }
      return null;
    },
    findAll(fn) {
      let out = [];
      for (const c of this.children) { if (fn(c)) out.push(c); if (c.findAll) out = out.concat(c.findAll(fn)); }
      return out;
    },
    setExplicitVariableModeForCollection(col, mode) {
      if (!col || !mode) throw new Error('setExplicitVariableModeForCollection 参数缺失');
      const c = typeof col === 'string' ? COLLECTIONS.find(x => x.id === col) : col;
      if (!c) throw new Error('setExplicitVariableModeForCollection: 集合不存在');
      if (!c.modes.some(m => m.modeId === mode)) throw new Error('setExplicitVariableModeForCollection: modeId 不属于该集合');
      this._mode = mode;
    },
    setBoundVariable(field, variable) {
      if (!BINDABLE_NUM.has(field)) throw new Error(`setBoundVariable: 字段 "${field}" 不可绑定`);
      if (!variable || !variable.id) throw new Error(`setBoundVariable("${field}"): variable 非法`);
      if (variable._type !== 'FLOAT') throw new Error(`setBoundVariable("${field}"): 需要 FLOAT 变量，收到 ${variable._type}`);
      this.boundVariables[field] = { type: 'VARIABLE_ALIAS', id: variable.id };
      CALLS.boundNums++;
    },
    async setReactionsAsync(rs) {
      if (!Array.isArray(rs)) throw new Error('setReactionsAsync 需要数组');
      rs.forEach(r => {
        if (!r.trigger || !r.action) throw new Error('reaction 缺少 trigger/action');
        if (r.action.type === 'NODE' && !r.action.destinationId) throw new Error('NODE action 缺少 destinationId');
      });
      this.reactions = rs; CALLS.reactions += rs.length;
    },
    _relayout() {},
  };
  // Figma 会把组件属性的「默认值」应用到组件自身的渲染上，
  // 覆盖各变体里手动放置的内容。不建模这点会让桩系统性高估/低估尺寸。
  Object.defineProperty(n, 'componentPropertyReferences', {
    get() { return this._cpr; },
    set(v) {
      this._cpr = v;
      if (!v) return;
      let owner = this.parent;
      while (owner && owner.type !== 'COMPONENT' && owner.type !== 'COMPONENT_SET') owner = owner.parent;
      if (!owner) return;
      const defs = Object.assign({},
        (owner.parent && owner.parent.componentPropertyDefinitions) || {},
        owner.componentPropertyDefinitions || {});
      Object.keys(v).forEach(field => {
        const def = defs[v[field]];
        if (!def) return;
        if (field === 'characters' && def.type === 'TEXT' && this._reflow) {
          // 记住被默认值盖掉之前的文案。覆盖之后各变体看起来都一样，
          // 事后无法分辨「本来就该一样」和「本来不同、被默认值抹平了」——
          // checks.text-prop 靠这份原始文案做判定。
          if (this._authoredChars === undefined) this._authoredChars = this._chars;
          this._chars = String(def.defaultValue);
          this._natural = textWidth(this._chars, this.fontSize);
          this._reflow();
        } else if (field === 'visible' && def.type === 'BOOLEAN') {
          this.visible = !!def.defaultValue;
        } else if (field === 'mainComponent' && def.type === 'INSTANCE_SWAP') {
          // 显式 resize 过的实例（如按尺寸摆放的图标）保留自己的尺寸，
          // 只有沿用组件原始尺寸的实例才跟随替换目标变化。
          const target = ALL_COMPONENTS[def.defaultValue];
          if (target && target !== this && !this._sizeOverride) {
            this.width = target.width; this.height = target.height;
          }
        }
      });
      let up = this.parent;
      while (up) { if (up._relayout) up._relayout(); up = up.parent; }
    },
  });
  return n;
}

// Figma 真实行为：create* 出来的节点会先挂到 figma.currentPage 上。
// 克隆实例子树时要关掉，否则子节点会被挂到页面上而不是留在实例里。
let AUTOPARENT = true;
function adopt(n) {
  if (AUTOPARENT && figma.currentPage && n.type !== 'PAGE') {
    n.parent = figma.currentPage; figma.currentPage.children.push(n);
  }
  return n;
}
// 中文全角字符宽度≈1倍字号，西文≈0.55倍。之前统一按 0.62 会严重低估中文宽度。
function textWidth(str, fs) {
  let w = 0;
  for (const ch of str) w += /[\u2e80-\u9fff\uff00-\uffef\u3000-\u303f]/.test(ch) ? fs : fs * 0.55;
  return w;
}
function pageOf(n) { while (n && n.type !== 'PAGE') n = n.parent; return n; }

function makeFrameLike(type) {
  const f = baseNode(type);
  f.layoutMode = 'NONE'; f.itemSpacing = 0;
  f.primaryAxisSizingMode = 'AUTO'; f.counterAxisSizingMode = 'AUTO';
  f.primaryAxisAlignItems = 'MIN'; f.counterAxisAlignItems = 'MIN';
  f.paddingTop = f.paddingRight = f.paddingBottom = f.paddingLeft = 0;
  f.clipsContent = false; f.width = 0.01; f.height = 0.01;
  f._relayout = function () {
    if (this.layoutMode === 'NONE') return;
    const flow = this.children.filter(c => c.layoutPositioning !== 'ABSOLUTE' && c.visible !== false);
    const horiz = this.layoutMode === 'HORIZONTAL';
    const padAlong = horiz ? this.paddingLeft + this.paddingRight : this.paddingTop + this.paddingBottom;
    const gaps = Math.max(0, flow.length - 1) * this.itemSpacing;

    // layoutGrow：主轴固定时，把剩余空间均分给 grow 子节点（真 Figma 的 Fill container）
    // 主轴尺寸「已由外部决定」的三种情况：自身 FIXED、被父级 STRETCH 拉伸、被父级 grow 撑开
    const alongFixed = this.primaryAxisSizingMode === 'FIXED' || this._extAlong === true;
    const growers = flow.filter(c => c.layoutGrow === 1);
    if (alongFixed && growers.length) {
      const avail = (horiz ? this.width : this.height) - padAlong - gaps;
      const usedFixed = flow.filter(c => c.layoutGrow !== 1).reduce((s, c) => s + (horiz ? c.width : c.height), 0);
      const each = Math.max(1, (avail - usedFixed) / growers.length);
      growers.forEach(c => {
        if (horiz) {
          c.width = each; if (c._reflow) c._reflow();
          if (c.layoutMode === 'HORIZONTAL') { c._extAlong = true; if (c._relayout) c._relayout(); }
        } else {
          c.height = each;
          if (c.layoutMode === 'VERTICAL') { c._extAlong = true; if (c._relayout) c._relayout(); }
        }
      });
    }
    // layoutAlign = STRETCH：交叉轴固定时，拉伸到容器内宽/内高
    const crossFixed = this.counterAxisSizingMode === 'FIXED';
    if (crossFixed) {
      const padAcross = horiz ? this.paddingTop + this.paddingBottom : this.paddingLeft + this.paddingRight;
      const availCross = (horiz ? this.height : this.width) - padAcross;
      flow.filter(c => c.layoutAlign === 'STRETCH').forEach(c => {
        if (horiz) {
          c.height = Math.max(1, availCross);
          if (c.layoutMode === 'VERTICAL') { c._extAlong = true; if (c._relayout) c._relayout(); }
        } else {
          c.width = Math.max(1, availCross);
          if (c._reflow) c._reflow();
          if (c.layoutMode === 'HORIZONTAL') { c._extAlong = true; if (c._relayout) c._relayout(); }
        }
      });
    }

    let along = flow.reduce((s, c) => s + (horiz ? c.width : c.height), 0) + Math.max(0, flow.length - 1) * this.itemSpacing;
    let across = flow.reduce((m, c) => Math.max(m, horiz ? c.height : c.width), 0);
    along += horiz ? this.paddingLeft + this.paddingRight : this.paddingTop + this.paddingBottom;
    across += horiz ? this.paddingTop + this.paddingBottom : this.paddingLeft + this.paddingRight;
    let wAuto = horiz ? this.primaryAxisSizingMode === 'AUTO' : this.counterAxisSizingMode === 'AUTO';
    let hAuto = horiz ? this.counterAxisSizingMode === 'AUTO' : this.primaryAxisSizingMode === 'AUTO';
    // 主轴尺寸已由外部决定（STRETCH / grow）时不得按内容重算，否则会把父级给的宽度覆盖掉
    if (this._extAlong) { if (horiz) wAuto = false; else hAuto = false; }
    // 交叉轴被父级 STRETCH 决定时同理
    if (this.layoutAlign === 'STRETCH') { if (horiz) hAuto = false; else wAuto = false; }
    if (wAuto) this.width = Math.max(0.01, horiz ? along : across);
    if (hAuto) this.height = Math.max(0.01, horiz ? across : along);

    // 计算子节点坐标（真 Figma 的 auto layout 会排布位置；不算的话
    // 「宽度合法但 x 偏移导致右溢出」这类问题完全测不出来）
    const innerStart = horiz ? this.paddingLeft : this.paddingTop;
    const contentAlong = flow.reduce((s2, c) => s2 + (horiz ? c.width : c.height), 0) + gaps;
    const availAlong = (horiz ? this.width : this.height) - padAlong;
    let cursor = innerStart;
    let extraGap = this.itemSpacing;
    if (this.primaryAxisAlignItems === 'CENTER') cursor += Math.max(0, (availAlong - contentAlong) / 2);
    else if (this.primaryAxisAlignItems === 'MAX') cursor += Math.max(0, availAlong - contentAlong);
    else if (this.primaryAxisAlignItems === 'SPACE_BETWEEN' && flow.length > 1) {
      const bare = flow.reduce((s2, c) => s2 + (horiz ? c.width : c.height), 0);
      extraGap = Math.max(this.itemSpacing, (availAlong - bare) / (flow.length - 1));
    }
    const crossStart = horiz ? this.paddingTop : this.paddingLeft;
    const availCross2 = (horiz ? this.height : this.width) - (horiz ? this.paddingTop + this.paddingBottom : this.paddingLeft + this.paddingRight);
    flow.forEach(c => {
      const cAlong = horiz ? c.width : c.height;
      const cCross = horiz ? c.height : c.width;
      let cross = crossStart;
      if (this.counterAxisAlignItems === 'CENTER') cross += Math.max(0, (availCross2 - cCross) / 2);
      else if (this.counterAxisAlignItems === 'MAX') cross += Math.max(0, availCross2 - cCross);
      if (horiz) { c.x = cursor; c.y = cross; } else { c.y = cursor; c.x = cross; }
      cursor += cAlong + extraGap;
    });
  };
  return f;
}

function cloneTree(node, map) {
  const c = node.type === 'TEXT' ? figma.createText()
    : node.type === 'RECTANGLE' ? figma.createRectangle()
    : makeFrameLike('FRAME');
  ['name', 'width', 'height', 'x', 'y', 'visible', 'layoutMode', 'itemSpacing', 'clipsContent',
   'primaryAxisSizingMode', 'counterAxisSizingMode', 'primaryAxisAlignItems', 'counterAxisAlignItems',
   'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft', 'layoutGrow', 'layoutAlign',
   'layoutPositioning', 'cornerRadius', 'componentPropertyReferences', 'fontSize', 'textStyleId',
   'textAutoResize'].forEach(k => { if (node[k] !== undefined) c[k] = node[k]; });
  c.fills = node.fills; c.strokes = node.strokes; c.effects = node.effects;
  c.boundVariables = Object.assign({}, node.boundVariables);   // 实例继承主组件的变量绑定
  if (node.type === 'TEXT') { c.fontName = node.fontName; c._chars = node._chars; }
  map.set(node, c);
  node.children.forEach(ch => { const cc = cloneTree(ch, map); cc.parent = c; c.children.push(cc); });
  return c;
}

function addComponentProperty(propName, type, defaultValue) {
  const ok = ['BOOLEAN', 'TEXT', 'INSTANCE_SWAP', 'VARIANT'];
  if (ok.indexOf(type) < 0) throw new Error(`addComponentProperty: 类型 "${type}" 非法`);
  if (type === 'TEXT' && typeof defaultValue !== 'string') throw new Error(`属性 ${propName}: TEXT 默认值必须是字符串`);
  if (type === 'BOOLEAN' && typeof defaultValue !== 'boolean') throw new Error(`属性 ${propName}: BOOLEAN 默认值必须是布尔`);
  if (type === 'INSTANCE_SWAP' && typeof defaultValue !== 'string') throw new Error(`属性 ${propName}: INSTANCE_SWAP 默认值必须是组件 id`);
  const pid = propName + '#' + (++idc) + ':0';
  this.componentPropertyDefinitions[pid] = { type, defaultValue };
  CALLS.compProps++;
  return pid;
}

const figma = {
  mixed: Symbol('mixed'),
  root: null,
  currentPage: null,
  viewport: { scrollAndZoomIntoView(ns) { if (!Array.isArray(ns)) throw new Error('scrollAndZoomIntoView 需要数组'); } },

  createPage() {
    // 真实 Figma 的 createPage() 会把新页挂到 document root 下
    const p = baseNode('PAGE'); p.selection = []; p.name = 'Page';
    PAGES.push(p);
    if (figma.root) { p.parent = figma.root; figma.root.children.push(p); }
    return p;
  },
  createFrame() { CALLS.frame++; return adopt(makeFrameLike('FRAME')); },
  createComponent() {
    CALLS.component++;
    const c = makeFrameLike('COMPONENT');
    ALL_COMPONENTS[c.id] = c;
    c.componentPropertyDefinitions = {};
    c.addComponentProperty = addComponentProperty;
    adopt(c);
    c.createInstance = function () {
      CALLS.instance++;
      const map = new Map();
      AUTOPARENT = false;
      const inst = cloneTree(this, map);
      AUTOPARENT = true;
      adopt(inst);
      inst.type = 'INSTANCE'; inst.mainComponent = this;
      // 标记整棵子树属于实例内部，后续 appendChild/remove 会被拒绝
      (function mark(n) { n.children.forEach(c => { c._inInstance = true; mark(c); }); })(inst);
      inst._defs = this.componentPropertyDefinitions;
      inst._applyProp = function (key, val) {
        const defs = Object.assign({},
          (this.mainComponent.parent && this.mainComponent.parent.componentPropertyDefinitions) || {},
          this.mainComponent.componentPropertyDefinitions || {});
        const def = defs[key];
        if (!def) return;
        const field = def.type === 'INSTANCE_SWAP' ? 'mainComponent'
                    : def.type === 'BOOLEAN' ? 'visible' : 'characters';
        const targets = this.findAll(n => n.componentPropertyReferences && n.componentPropertyReferences[field] === key);
        targets.forEach(t => {
          if (def.type === 'TEXT') { t._propSet = true; t._chars = String(val); if (t._reflow) { t._natural = textWidth(String(val), t.fontSize); t._reflow(); } }
          else if (def.type === 'BOOLEAN') { t.visible = !!val; }
          else if (def.type === 'INSTANCE_SWAP') {
            const target = ALL_COMPONENTS[val];
            if (target) {
              // 用目标组件的子树替换（近似 Figma 的 instance swap）
              t.children.slice().forEach(c => { c.parent = null; });
              t.children = [];
              AUTOPARENT = false;
              const map = new Map();
              const clone = cloneTree(target, map);
              AUTOPARENT = true;
              clone.children.forEach(c => { c.parent = t; t.children.push(c); });
              // 换进来的子树同样属于实例内部 —— 不标记的话，后续对它直接改文案
              // 不会被记成「显式覆写」，checks.text-prop 会误报
              (function mark(n) { n.children.forEach(c => { c._inInstance = true; mark(c); }); })(t);
              t.width = target.width; t.height = target.height;
              t.layoutMode = target.layoutMode; t.itemSpacing = target.itemSpacing;
              t.primaryAxisSizingMode = target.primaryAxisSizingMode;
              t.counterAxisSizingMode = target.counterAxisSizingMode;
              ['paddingTop','paddingRight','paddingBottom','paddingLeft'].forEach(k2 => { t[k2] = target[k2]; });
            }
          }
        });
        // 自底向上重排
        let up = targets[0] && targets[0].parent;
        while (up) { if (up._relayout) up._relayout(); up = up.parent; }
      };
      inst.setProperties = function (props) {
        Object.keys(props).forEach(k => { this._applyProp(k, props[k]); });
        Object.keys(props).forEach(k => {
          const isVariant = this.mainComponent.parent && this.mainComponent.parent.type === 'COMPONENT_SET'
            && this.mainComponent.parent.variantGroupProperties
            && this.mainComponent.parent.variantGroupProperties[k];
          if (isVariant) {
            const vals = this.mainComponent.parent.variantGroupProperties[k].values;
            if (vals.indexOf(String(props[k])) < 0)
              throw new Error(`setProperties: 变体属性 "${k}" 没有取值 "${props[k]}"（可选: ${vals.join('/')}）`);
            return;
          }
          const defs = this._defs || {};
          const setDefs = this.mainComponent.parent && this.mainComponent.parent.componentPropertyDefinitions;
          if (!defs[k] && !(setDefs && setDefs[k]))
            throw new Error(`setProperties: 未知属性 "${k}"`);
        });
      };
      return inst;
    };
    return c;
  },
  createRectangle() { CALLS.rect++; return adopt(baseNode('RECTANGLE')); },
  createText() {
    CALLS.text++;
    const t = baseNode('TEXT');
    t.fontName = null; t.fontSize = 12; t.lineHeight = null; t.letterSpacing = null;
    t._tar = 'WIDTH_AND_HEIGHT'; t.textAlignHorizontal = 'LEFT';
    Object.defineProperty(t, 'textAutoResize', {
      get() { return this._tar; },
      set(v) { this._tar = v; if (this._reflow) this._reflow(); },
    });
    t.maxLines = null; t.textTruncation = 'DISABLED';
    t._chars = ''; t._styleId = ''; t._natural = 1;
    // 分段着色（Matched Excerpt 的命中高亮）。不影响排版，只记录区间供检查器读取。
    t._rangeFills = [];
    t.setRangeFills = function (start, end, fills) {
      if (typeof start !== 'number' || typeof end !== 'number') throw new Error('setRangeFills: 区间必须是数字');
      if (start < 0 || end > this._chars.length || start >= end)
        throw new Error(`setRangeFills: 区间 [${start},${end}) 越界（文本长度 ${this._chars.length}）`);
      this._rangeFills.push({ start: start, end: end, fills: fills });
    };
    t.getRangeFills = function (start, end) {
      const hit = this._rangeFills.find(r => r.start === start && r.end === end);
      return hit ? hit.fills : this.fills;
    };
    t._reflow = function () {
      const lh = (this.lineHeight && this.lineHeight.value) || this.fontSize * 1.35;
      if (this.textAutoResize === 'WIDTH_AND_HEIGHT') { this.width = Math.max(1, this._natural); this.height = lh; return; }
      const hard = String(this._chars || '').split('\n');
      let lines = hard.reduce((sum, seg) =>
        sum + Math.max(1, Math.ceil(textWidth(seg, this.fontSize) / Math.max(1, this.width))), 0);
      if (this.maxLines) lines = Math.min(lines, this.maxLines);
      if (this.textAutoResize !== 'NONE') this.height = lines * lh;
    };
    const _resize = t.resize.bind(t);
    // Figma 真实行为：对文本调 resize(w, h) 会把 textAutoResize 重置为 NONE，
    // 高度从此固定，不再随换行增长。这正是「摘要永远只有一行」的根因。
    t.resize = function (w, h) { _resize(w, h); this.textAutoResize = 'NONE'; };
    Object.defineProperty(t, 'textStyleId', {
      get() { return this._styleId; },
      set(v) {
        if (v && !TEXT_STYLES.some(s => s.id === v)) throw new Error('textStyleId 指向不存在的样式: ' + v);
        if (v) CALLS.textStyleApplied++;
        this._styleId = v;
      },
    });
    Object.defineProperty(t, 'characters', {
      get() { return this._chars; },
      set(v) {
        if (typeof v !== 'string') throw new Error('characters 必须是字符串');
        if (!this.fontName) throw new Error('设置 characters 前必须先设置 fontName');
        if (!LOADED.has(this.fontName.family + '|' + this.fontName.style))
          throw new Error('字体未加载: ' + JSON.stringify(this.fontName));
        // 实例内的直接赋值也算「显式覆写」（生成器里有几处绕开 setProperties 直接改文案）
        if (this._inInstance) this._propSet = true;
        this._chars = v;
        this._natural = Math.max(1, textWidth(v, this.fontSize));
        if (this.textAutoResize === 'WIDTH_AND_HEIGHT') this.width = this._natural;
        this._reflow();
      },
    });
    return t;
  },
  createNodeFromSvg(svg) {
    if (typeof svg !== 'string' || svg.indexOf('<svg') !== 0) throw new Error('createNodeFromSvg 需要 svg 字符串');
    const m = svg.match(/width="([\d.]+)"\s+height="([\d.]+)"/);
    if (!m) throw new Error('svg 缺少 width/height');
    CALLS.svg++;
    const f = makeFrameLike('FRAME');
    f.width = parseFloat(m[1]); f.height = parseFloat(m[2]);
    f.primaryAxisSizingMode = 'FIXED'; f.counterAxisSizingMode = 'FIXED';
    const v = baseNode('VECTOR'); v.name = 'Vector';
    v.width = f.width; v.height = f.height;   // 矢量填满外框（真 Figma 导入即如此）
    v.constraints = { horizontal: 'SCALE', vertical: 'SCALE' };
    v.strokes = svg.indexOf('stroke="none"') === -1 ? [{ type: 'SOLID', color: { r: 0, g: 0, b: 0 } }] : [];
    v.fills = svg.indexOf('fill="none"') === -1 ? [{ type: 'SOLID', color: { r: 0, g: 0, b: 0 } }] : [];
    v.parent = f; f.children.push(v);
    return adopt(f);
  },
  combineAsVariants(comps, parent) {
    if (!Array.isArray(comps) || !comps.length) throw new Error('combineAsVariants 需要非空组件数组');
    comps.forEach(c => {
      if (c.type !== 'COMPONENT') throw new Error('combineAsVariants: 只接受 COMPONENT，收到 ' + c.type);
      if (!/^[^=]+=[^=]*(,\s*[^=]+=[^=]*)*$/.test(c.name))
        throw new Error(`combineAsVariants: 变体命名必须是 "属性=值" 格式，收到 "${c.name}"`);
    });
    const keysOf = c => c.name.split(',').map(s => s.split('=')[0].trim());
    const first = keysOf(comps[0]).join('|');
    comps.forEach(c => {
      if (keysOf(c).join('|') !== first)
        throw new Error(`combineAsVariants: 各变体属性名不一致（"${comps[0].name}" vs "${c.name}"）`);
    });
    const names = new Set(comps.map(c => c.name));
    if (names.size !== comps.length) throw new Error('combineAsVariants: 存在重复的变体组合');
    if (!parent) throw new Error('combineAsVariants: 缺少 parent');
    const pp = pageOf(parent);
    comps.forEach(c => {
      if (pageOf(c) !== pp)
        throw new Error(`in combineAsVariants: Grouped nodes must be in the same page as the parent（"${c.name}" 在 "${(pageOf(c)||{}).name}"，parent 在 "${(pp||{}).name}"）—— 建组件前要先把 figma.currentPage 设成目标页`);
    });

    CALLS.variantSets++;
    const set = makeFrameLike('COMPONENT_SET');
    set.componentPropertyDefinitions = {};
    set.addComponentProperty = addComponentProperty;
    set.variantGroupProperties = {};
    keysOf(comps[0]).forEach(k => {
      set.variantGroupProperties[k] = {
        values: Array.from(new Set(comps.map(c =>
          c.name.split(',').map(s => s.trim()).find(s => s.split('=')[0].trim() === k).split('=')[1].trim()))),
      };
    });
    // 归组时要先把组件从原父级（通常是 currentPage）摘掉，否则页面上会留下重复引用
    comps.forEach(c => {
      if (c.parent) c.parent.children = c.parent.children.filter(x => x !== c);
      c.parent = set; set.children.push(c);
    });
    set.defaultVariant = comps[0];
    parent.appendChild(set);
    return set;
  },

  createTextStyle() {
    const s = { id: 'S' + (++idc), type: 'TEXT_STYLE', name: '', fontName: null, fontSize: 12, lineHeight: null, letterSpacing: null, remove() { const i = TEXT_STYLES.indexOf(s); if (i >= 0) TEXT_STYLES.splice(i, 1); } };
    TEXT_STYLES.push(s); return s;
  },
  getLocalTextStyles() { return TEXT_STYLES.slice(); },
  createEffectStyle() {
    const s = { id: 'E' + (++idc), type: 'EFFECT_STYLE', name: '', effects: [], remove() { const i = EFFECT_STYLES.indexOf(s); if (i >= 0) EFFECT_STYLES.splice(i, 1); } };
    EFFECT_STYLES.push(s); return s;
  },
  getLocalEffectStyles() { return EFFECT_STYLES.slice(); },

  variables: {
    getLocalVariableCollections() { return COLLECTIONS.slice(); },
    createVariableCollection(name) {
      const modes = [{ modeId: 'm' + (++idc), name: 'Mode 1' }];
      const col = {
        id: 'C' + (++idc), name, modes,
        renameMode(id, n) { const m = modes.find(x => x.modeId === id); if (!m) throw new Error('renameMode: 未知 modeId'); m.name = n; },
        addMode(n) { const id = 'm' + (++idc); modes.push({ modeId: id, name: n }); return id; },
        remove() { const i = COLLECTIONS.indexOf(col); if (i >= 0) COLLECTIONS.splice(i, 1); },
      };
      COLLECTIONS.push(col); return col;
    },
    createVariable(name, col, type) {
      if (!col || !col.modes) throw new Error('createVariable: collection 非法');
      if (['COLOR', 'FLOAT', 'STRING', 'BOOLEAN'].indexOf(type) < 0) throw new Error('createVariable: 类型非法 ' + type);
      const known = new Set(col.modes.map(m => m.modeId));
      if (type === 'COLOR') CALLS.varColor++; else if (type === 'FLOAT') CALLS.varFloat++;
      return {
        id: 'V' + (++idc), name, _type: type,
        setValueForMode(modeId, val) {
          if (!known.has(modeId)) throw new Error(`变量 ${name}: 未知 modeId`);
          if (type === 'COLOR') {
            ['r', 'g', 'b', 'a'].forEach(k => {
              if (typeof val[k] !== 'number' || !isFinite(val[k]) || val[k] < 0 || val[k] > 1)
                throw new Error(`变量 ${name} 的 ${k} 通道非法: ${val[k]}`);
            });
          } else if (type === 'FLOAT') {
            if (typeof val !== 'number' || !isFinite(val)) throw new Error(`变量 ${name}: FLOAT 值非法 ${val}`);
          }
        },
      };
    },
    setBoundVariableForPaint(paint, field, variable) {
      if (!paint || paint.type !== 'SOLID') throw new Error('setBoundVariableForPaint: paint 非法');
      if (field !== 'color') throw new Error('setBoundVariableForPaint: field 应为 color');
      if (!variable || !variable.id) throw new Error('setBoundVariableForPaint: variable 非法');
      if (variable._type !== 'COLOR') throw new Error('setBoundVariableForPaint: 需要 COLOR 变量');
      CALLS.boundPaints++;
      return Object.assign({}, paint, { boundVariables: { color: { type: 'VARIABLE_ALIAS', id: variable.id } } });
    },
  },

  async loadFontAsync(f) {
    if (f.family !== (global.__ONLY_FONT || 'PingFang SC')) throw new Error('字体不可用: ' + f.family);
    LOADED.add(f.family + '|' + f.style);
  },
  notify(msg, opts) { NOTIFIES.push({ msg, opts }); },
  closePlugin() { CLOSED = true; },
};

figma.root = baseNode('DOCUMENT');
figma.root.appendChild = function (p) { p.parent = this; this.children.push(p); };
const p0 = figma.createPage(); p0.name = 'Page 1';
figma.root.children = [p0]; p0.parent = figma.root;
figma.currentPage = p0;

global.figma = figma;
module.exports = { figma, CALLS, NOTIFIES, COLLECTIONS, TEXT_STYLES, EFFECT_STYLES, PAGES, isClosed: () => CLOSED };
