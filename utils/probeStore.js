// 探针用的跨页暂存
// 目的不是业务功能，是验证页面之间是否共享同一个模块实例
export const probeStore = {
  note: '',
  stamp: 0,
  photoBase64: '',
  photoMime: 'image/jpeg',
  visionRaw: ''
}
