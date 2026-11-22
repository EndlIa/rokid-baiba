// 摆摆 — 示例数据模块
// 纯本地示意数据，未接入摄像头、空间定位或 AI 识别

export const appInfo = {
  name: '摆摆',
  subtitle: '你的 AI 空间整理搭子',
  description: '看一眼，说一声，和摆摆一起给生活重新找位置。'
};

export const scenarios = [
  { id: 'desk', name: '杂乱书桌', hint: '书桌台面' },
  { id: 'shelf', name: '书架整理', hint: '书架分层' },
  { id: 'nightstand', name: '床头柜整理', hint: '床头收纳' }
];

export const steps = [
  { id: 'clear', name: '清空台面', desc: '把桌面上的东西全部移到一边，腾出操作空间。' },
  { id: 'sort', name: '分类物品', desc: '按用途分成几堆：文具、书本、电子设备、杂物。' },
  { id: 'store', name: '归位收纳', desc: '按使用频率放回固定位置，常用的在手边，不常用的靠里。' }
];

export const layoutData = {
  title: '布局示意',
  items: [
    { from: '书本', fromLabel: '台面散放', to: '书架左侧', toLabel: '竖排放齐' },
    { from: '水杯', fromLabel: '台面右侧', to: '桌面右上角', toLabel: '远离电子设备' }
  ],
  disclaimer: '位置仅供参考，不代表真实空间锚定',
  note: '示意数据 · 待接入视觉识别'
};

export const doneMessage = {
  title: '整理完成',
  desc: '台面清爽了，下次找东西不用翻。'
};

export const scenarioMap = {
  desk: { name: '杂乱书桌' },
  shelf: { name: '书架整理' },
  nightstand: { name: '床头柜整理' }
};
