import { raceTimeout } from './async.js'

export const PHOTO_TIMEOUT_MS = 15000

// 与已验证可用的拍照参数保持一致
const PHOTO_OPTIONS = {
  quality: 'high',
  mode: 'default',
  enableSystemPreview: true
}

export function bytesToBase64(buffer) {
  const bytes = new Uint8Array(buffer)
  const CHUNK = 4096
  let binary = ''
  for (let i = 0; i < bytes.length; i += CHUNK) {
    const end = Math.min(i + CHUNK, bytes.length)
    binary += String.fromCharCode.apply(null, bytes.subarray(i, end))
  }
  return window.btoa(binary)
}

// 必须在交互上下文里同步调用：
// 函数体在第一个 await 之前就会执行 takePhoto，交互门禁才能通过
export async function capturePhoto(cameraCtx, onStage) {
  const report = typeof onStage === 'function' ? onStage : function () {}
  if (!cameraCtx) {
    const error = new Error('这个设备没有可用摄像头')
    error.stage = '打开相机'
    throw error
  }

  report('发起拍照')
  let pending
  try {
    pending = cameraCtx.takePhoto(PHOTO_OPTIONS)
  } catch (error) {
    if (!error.stage) error.stage = '发起拍照'
    throw error
  }

  report('等待相机返回')
  const photo = await raceTimeout(pending, PHOTO_TIMEOUT_MS, '等待相机返回')
  if (!photo || !photo.data) {
    const error = new Error('相机没有返回图像数据')
    error.stage = '读取照片'
    throw error
  }

  report('编码照片')
  const mimeType = photo.mimeType || 'image/jpeg'
  return {
    dataUrl: 'data:' + mimeType + ';base64,' + bytesToBase64(photo.data),
    mimeType: mimeType,
    bytes: photo.data.byteLength || photo.data.length || 0
  }
}
