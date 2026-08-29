/* 万象记 Mosaic —— 旧 IA 对照屏生成代码（已归档，不参与生产）
 * 对应 D-08：①现状首页 / ③现状卡片列表内摘要 / ⑦现状编辑器＋菜单
 * 保留目的：留存论证依据。这些函数已从 code.js 移除，不再生成到 Screens 页。
 * 如需重现：把本文件的函数拷回 code.js 并加入 SCREENS 数组。
 */

function scOldHome() {
  return screen('① 现状 · 首页 = 文件夹列表', [
    iStatus(),
    iNav({ title: '', leading: 'gear', trailing: 'plus', trailing2: 'search' }),
    F({ name: 'Large Title', dir: 'v', w: W, pad: ['space/4', 'space/16', 'space/8', 'space/16'],
        children: [T('万象记', { s: 'iOS/LargeTitle' })] }),
    F({ name: 'Body', dir: 'v', gap: 'space/14', w: W, grow: 1, cross: 'CENTER', pad: ['space/10', 0, 0, 0], clip: true, children: [
      F({ name: 'List', dir: 'v', w: W - 32, radius: 'radius/10', fill: 'bg/card', clip: true, children: [
        iFolderRow('工作', '12 张卡片', FOLDER_COLORS.work, 'briefcase'), hr(W - 32),
        iFolderRow('读书', '8 张卡片', FOLDER_COLORS.book, 'book'), hr(W - 32),
        iFolderRow('灵感', '3 张卡片', FOLDER_COLORS.idea, 'bulb'), hr(W - 32),
        iFolderRow('旅行', '5 张卡片', FOLDER_COLORS.trip, 'folder')] }),
      T('还要再点一次\n才能看到任何一条笔记的内容',
        { s: 'iOS/Footnote', c: 'text/tertiary', align: 'CENTER', width: 300 })] }),
    iHome(),
  ]);
}

function scOldCardList() {
  const bullet = txt => F({ name: 'Point', dir: 'h', gap: 'space/6',
    children: [T('•', { s: 'iOS/Subheadline', c: 'text/secondary' }), T(txt, { s: 'iOS/Subheadline' })] });
  const sbtn = (label, iconName, del) => F({
    name: 'Legacy Button / ' + label, dir: 'h', gap: 'space/6', h: 44, cross: 'CENTER',
    pad: [0, 'space/12', 0, 'space/12'], radius: 'radius/12', fill: del ? 'accent/red-bg' : 'accent/blue-bg',
    children: [ic(iconName, 14, del ? 'accent/red' : 'accent/blue'),
               T(label, { s: 'iOS/Subheadline Emphasized', c: del ? 'accent/red' : 'accent/blue' })] });

  const sticker = F({ name: 'Legacy Sticker', dir: 'v', gap: 'space/10', w: 297, pad: ['space/12', 0, 0, 0], children: [
    hr(297), T('初始总结', { s: 'iOS/Caption1 Emphasized', c: 'text/secondary' }),
    F({ name: 'Badge', dir: 'h', pad: ['space/2', 'space/8', 'space/2', 'space/8'], radius: 'radius/full',
        fill: 'accent/blue-bg', children: [T('会议记录', { s: 'iOS/Caption2 Emphasized', c: 'accent/blue' })] }),
    F({ name: 'Topics', dir: 'h', gap: 'space/4', children: [iTag('排期'), iTag('分工'), iTag('上线')] }),
    sbtn('把主题加为标签', 'tag'),
    bullet('确定下周三上线'), bullet('新增三位负责人'), bullet('设计先行，后端跟进'),
    T('围绕 Q3 排期展开，明确了上线时间与分工…', { s: 'iOS/Subheadline', width: 297 }),
    T('kimi · kimi-k2.6 · 2026-08-06 14:30', { s: 'iOS/Caption2', c: 'text/tertiary' }),
    hr(297), T('更新记录', { s: 'iOS/Caption1 Emphasized', c: 'text/secondary' }),
    F({ name: 'Log', dir: 'v', gap: 'space/4', w: 297, pad: ['space/8', 'space/8', 'space/8', 'space/8'],
        radius: 'radius/8', fill: 'bg/fill', children: [
      T('补充了预算部分', { s: 'iOS/Subheadline Emphasized' }),
      T('· 新增一段录音转写', { s: 'iOS/Caption1', c: 'text/secondary' }),
      T('2026-08-06 16:02', { s: 'iOS/Caption2', c: 'text/tertiary' })] }),
    F({ name: 'Actions', dir: 'h', gap: 'space/8', children: [
      sbtn('立即更新', 'refresh'), sbtn('重新生成', 'sparkle'), sbtn('清除', 'trash', true)] }),
  ] });

  const chev = F({ name: 'Disclosure', w: 44, h: 44, main: 'CENTER', cross: 'CENTER',
                   children: [ic('chevronD', 15, 'text/secondary')] });
  abs(chev, R(9, 9, 'accent/red', 5), 30, 8).name = 'Unread Dot';

  const card = F({ name: 'Legacy Card', dir: 'h', gap: 'space/10', w: W - 24,
    pad: ['space/12', 'space/12', 'space/12', 'space/12'], radius: 'radius/14', fill: 'bg/card', children: [
    F({ name: 'Main', dir: 'v', gap: 'space/6', grow: 1, children: [
      F({ name: 'Title', dir: 'h', gap: 'space/5', cross: 'CENTER',
          children: [ic('pin', 'size/icon-sm', 'accent/orange'), T('Q3 产品评审会', { s: 'iOS/Headline' })] }),
      T('确定了排期与三位负责人，下周三上线', { s: 'iOS/Subheadline', c: 'text/secondary', stretch: true }),
      F({ name: 'Kind Icons', dir: 'h', gap: 'space/10', cross: 'CENTER', stretch: true, children: [
        ic('doc', 'size/icon-sm', 'text/secondary'), ic('photo', 'size/icon-sm', 'text/secondary'),
        ic('wave', 'size/icon-sm', 'text/secondary'), ic('link', 'size/icon-sm', 'text/secondary'),
        spacer(), T('3小时前', { s: 'iOS/Caption2', c: 'text/tertiary' })] }),
      F({ name: 'Tags', dir: 'h', gap: 'space/4', children: [iTag('排期'), iTag('评审')] }),
      sticker] }),
    chev] });

  return screen('③ 现状 · 摘要在列表行内展开', [
    iStatus(), iNav({ title: '工作', leading: 'back', trailing: 'pencil' }),
    F({ name: 'Tag Filter', dir: 'h', gap: 'space/8', w: W,
        pad: ['space/8', 'space/16', 'space/12', 'space/16'], clip: true,
        children: [iChip('排期', true), iChip('评审'), iChip('Q3')] }),
    F({ name: 'Body', dir: 'v', w: W, grow: 1, cross: 'CENTER', clip: true, children: [card] }),
    iHome(),
  ]);
}

function scOldEditor() {
  const p = screen('⑦ 现状 · 编辑器 ＋添加内容', [
    iStatus(), iNav({ title: '未命名笔记', leading: 'back', trailing: 'pin' }),
    F({ name: 'Body', dir: 'v', w: W, grow: 1, clip: true, children: [
      F({ name: 'Title', dir: 'v', w: W, pad: ['space/14', 'space/20', 0, 'space/20'],
          children: [T('标题（可留空，由 AI 生成）', { s: 'iOS/Title3', c: 'text/tertiary' })] }),
      F({ name: 'Legacy Tag Section', dir: 'v', gap: 'space/6', w: W, pad: ['space/22', 'space/20', 0, 'space/20'], children: [
        T('标签', { s: 'iOS/Footnote Emphasized', c: 'text/secondary' }),
        F({ name: 'Add', dir: 'h', gap: 'space/8', cross: 'CENTER', children: [
          ic('tag', 'size/icon-md', 'text/secondary'), T('添加标签', { s: 'iOS/Body', c: 'text/tertiary' })] })] }),
      F({ name: 'Hint', dir: 'v', w: W, pad: ['space/26', 'space/20', 0, 'space/20'], children: [
        T('点击下方「添加内容」，把文字、录音、图片、文档、链接塞进这张卡片。',
          { s: 'iOS/Subheadline', c: 'text/secondary', width: 353 })] }),
    ] }),
    F({ name: 'Legacy Bottom Bar', dir: 'h', w: W, h: 52, main: 'SPACE_BETWEEN', cross: 'CENTER',
        pad: [0, 'space/16', 0, 'space/16'], fill: 'bg/card', children: [
      F({ name: 'Add Content', dir: 'h', gap: 'space/6', cross: 'CENTER', children: [
        ic('plus', 'size/icon-lg'), T('添加内容', { s: 'iOS/Headline', c: 'accent/blue' })] }),
      ic('share', 'size/icon-lg')] }),
    iHome(),
  ]);
  scrim(p);
  abs(p, menuOf([[iMenuItem('文字', 'doc'), iMenuItem('从相册选图', 'photo'), iMenuItem('拍照', 'camera'),
                  iMenuItem('录音', 'mic'), iMenuItem('导入文档', 'doc'), iMenuItem('添加链接', 'link')]]), 16, 488);
  return p;
}
