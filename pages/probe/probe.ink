<script def>
{
  "navigationBarTitleText": "自检"
}
</script>

<script setup>
import wx from 'wx'
import { probeStore } from '../../utils/probeStore.js'

const PHOTO_TIMEOUT_MS = 12000
const MODEL_TIMEOUT_MS = 30000

const VISION_PROMPT =
  '看这张图，找出画面里最明显的 3 件物品。只输出 JSON，不要任何解释。' +
  '格式：{"items":[{"name":"物品名","bbox":[x0,y0,x1,y1],"confidence":0.0}]}' +
  '。bbox 用相对图片宽高的比例表示，四个数都在 0 到 1 之间，顺序是左上 x、左上 y、右下 x、右下 y。'

const CHECKS = [
  { key: 'env', label: '环境' },
  { key: 'llm', label: '语言模型' },
  { key: 'camera', label: '相机' },
  { key: 'vision', label: '看图坐标' },
  { key: 'voice', label: '语音' },
  { key: 'esm', label: '模块共享' }
]

function now() {
  return Date.now()
}

function bytesToBase64(buffer) {
  const bytes = new Uint8Array(buffer)
  const CHUNK = 4096
  let binary = ''
  for (let i = 0; i < bytes.length; i += CHUNK) {
    const end = Math.min(i + CHUNK, bytes.length)
    binary += String.fromCharCode.apply(null, bytes.subarray(i, end))
  }
  return window.btoa(binary)
}

function raceTimeout(promise, ms, label) {
  let timer = null
  const guard = new Promise((_, reject) => {
    timer = setTimeout(() => {
      reject(new Error('超时：' + label + '（' + ms + 'ms）'))
    }, ms)
  })
  return Promise.race([promise, guard]).then(
    (value) => {
      if (timer) clearTimeout(timer)
      return value
    },
    (err) => {
      if (timer) clearTimeout(timer)
      throw err
    }
  )
}

function shorten(text, max) {
  if (!text) return ''
  const flat = String(text).replace(/\s+/g, ' ')
  return flat.length <= max ? flat : flat.slice(0, max) + '…'
}

function extractJson(text) {
  if (!text) return null
  const trimmed = String(text).trim()
  try {
    return JSON.parse(trimmed)
  } catch (e) {}
  const start = trimmed.indexOf('{')
  const end = trimmed.lastIndexOf('}')
  if (start >= 0 && end > start) {
    try {
      return JSON.parse(trimmed.slice(start, end + 1))
    } catch (e) {}
  }
  return null
}

export default {
  data: {
    idx: 0,
    total: CHECKS.length,
    currentLabel: CHECKS[0].label,
    running: false,
    lines: [],
    seq: 0
  },

  onLoad() {
    this._armedAt = now()
    this._cameraCtx = null
    this._photo = null
    this._photoDataUrl = ''
    this._vision1 = null
    this._lastDirTime = 0
    this._lastDelta = 0
    this._log('info', '自检页就绪。上下切换，回车运行。')
  },

  onShow() {
    this._armedAt = now()
  },

  onKeyDown(event) {
    if (now() - this._armedAt < 600) return
    const code = event.code
    if (code === 'ArrowUp' || code === 'ArrowLeft') {
      this._move(-1)
    } else if (code === 'ArrowDown' || code === 'ArrowRight') {
      this._move(1)
    }
  },

  onKeyUp(event) {
    if (now() - this._armedAt < 600) return
    const code = event.code
    if (code === 'Enter') {
      event.preventDefault()
      this._runCurrent()
    } else if (code === 'Backspace') {
      event.preventDefault()
      wx.navigateBack()
    } else if (
      code === 'ArrowUp' ||
      code === 'ArrowLeft' ||
      code === 'ArrowDown' ||
      code === 'ArrowRight'
    ) {
      event.preventDefault()
    }
  },

  _move(delta) {
    const stamp = now()
    if (this._lastDirTime && stamp - this._lastDirTime < 1000 && this._lastDelta === delta) return
    this._lastDirTime = stamp
    this._lastDelta = delta
    const next = Math.min(CHECKS.length - 1, Math.max(0, this.data.idx + delta))
    if (next === this.data.idx) return
    this.setData({ idx: next, currentLabel: CHECKS[next].label })
  },

  _log(level, text) {
    const cls = level === 'ok' ? 'line-ok' : level === 'err' ? 'line-err' : 'line-info'
    const flat = String(text == null ? '' : text)
    const segments = []
    for (let i = 0; i < flat.length; i += 40) {
      segments.push(flat.slice(i, i + 40))
    }
    if (segments.length === 0) segments.push('')

    let seq = this.data.seq
    const added = []
    for (let k = 0; k < segments.length; k++) {
      seq += 1
      added.push({ id: seq, cls: cls, text: segments[k] })
    }
    const lines = this.data.lines.concat(added)
    const trimmed = lines.length > 200 ? lines.slice(lines.length - 200) : lines
    this.setData({ lines: trimmed, seq: seq })
  },

  _setRunning(running) {
    this.setData({ running: running })
  },

  onTapPrev() {
    this._move(-1)
  },

  onTapNext() {
    this._move(1)
  },

  onTapRun() {
    this._runCurrent()
  },

  async _runCurrent() {
    if (this.data.running) {
      this._log('info', '还在跑，等这一项结束')
      return
    }
    const check = CHECKS[this.data.idx]
    this._setRunning(true)
    this._log('info', '—— 开始：' + check.label + ' ——')
    try {
      if (check.key === 'env') await this._checkEnv()
      else if (check.key === 'llm') await this._checkLlm()
      else if (check.key === 'camera') await this._checkCamera()
      else if (check.key === 'vision') await this._checkVision()
      else if (check.key === 'voice') await this._checkVoice()
      else if (check.key === 'esm') await this._checkEsm()
    } catch (error) {
      const msg = error && error.message ? error.message : String(error)
      this._log('err', '未捕获异常：' + shorten(msg, 180))
    }
    this._setRunning(false)
  },

  // ── 环境 ──
  async _checkEnv() {
    this._log('info', '视口 ' + window.innerWidth + '×' + window.innerHeight)
    this._log('info', 'LanguageModel: ' + (typeof LanguageModel !== 'undefined' ? '有' : '没有'))
    this._log('info', 'SpeechRecognition: ' + (typeof SpeechRecognition !== 'undefined' ? '有' : '没有'))
    this._log('info', 'speechSynthesis: ' + (typeof speechSynthesis !== 'undefined' ? '有' : '没有'))
    this._log('info', 'SpeechSynthesisUtterance: ' + (typeof SpeechSynthesisUtterance !== 'undefined' ? '有' : '没有'))
    this._log('info', 'window.btoa: ' + (typeof window.btoa === 'function' ? '有' : '没有'))
    this._log('info', 'wx.media: ' + (wx && wx.media ? '有' : '没有'))
    this._log('info', 'wx.navigateTo: ' + (wx && typeof wx.navigateTo === 'function' ? '有' : '没有'))
    this._log('ok', '环境探测完成')
  },

  // ── 语言模型（纯文本） ──
  async _checkLlm() {
    if (typeof LanguageModel === 'undefined') {
      this._log('err', 'LanguageModel 不存在')
      return
    }
    const availability = await raceTimeout(LanguageModel.availability(), MODEL_TIMEOUT_MS, 'availability')
    this._log('info', 'availability: ' + availability)
    if (availability !== 'available') {
      this._log('err', '模型不可用，后续全部依赖它的检查都跑不了')
      return
    }

    const createStart = now()
    const session = await raceTimeout(
      LanguageModel.create({
        initialPrompts: [{ role: 'system', content: '你只输出一个词，不要标点。' }]
      }),
      MODEL_TIMEOUT_MS,
      'create'
    )
    this._log('info', 'create 耗时 ' + (now() - createStart) + 'ms')

    const promptStart = now()
    const answer = await raceTimeout(
      session.prompt('用两个字回答：你好'),
      MODEL_TIMEOUT_MS,
      'prompt'
    )
    const elapsed = now() - promptStart
    this._log('info', '纯文本 prompt 耗时 ' + elapsed + 'ms')
    this._log('ok', '返回：' + shorten(answer, 40))

    try {
      session.destroy()
    } catch (e) {}
  },

  // ── 相机 ──
  async _checkCamera() {
    if (!wx || !wx.media || typeof wx.media.createCameraContext !== 'function') {
      this._log('err', 'wx.media.createCameraContext 不存在')
      return
    }

    if (!this._cameraCtx) {
      this._cameraCtx = wx.media.createCameraContext()
    }
    if (!this._cameraCtx) {
      this._log('err', 'createCameraContext 返回空，模拟器可能没有摄像头')
      return
    }
    this._log('info', 'CameraContext 已获取')

    let photo = null
    const start = now()
    try {
      photo = await raceTimeout(this._cameraCtx.takePhoto({}), PHOTO_TIMEOUT_MS, 'takePhoto')
    } catch (error) {
      const msg = error && error.message ? error.message : String(error)
      this._log('err', 'takePhoto 失败：' + shorten(msg, 160))
      this._log('info', '耗时 ' + (now() - start) + 'ms')
      return
    }
    const elapsed = now() - start

    if (!photo) {
      this._log('err', 'takePhoto 没返回对象')
      return
    }
    if (!photo.data) {
      this._log('err', '返回里没有 data 字段，实际字段：' + Object.keys(photo).join(', '))
      return
    }

    const byteLength = photo.data.byteLength || (photo.data.length || 0)
    this._log('ok', '拍照成功 ' + elapsed + 'ms，' + byteLength + ' 字节')
    this._log('info', 'mimeType: ' + (photo.mimeType || '(空)'))
    this._log('info', '字段：' + Object.keys(photo).join(', '))

    try {
      const base64 = bytesToBase64(photo.data)
      this._photo = photo.data
      this._photoDataUrl =
        'data:' + (photo.mimeType || 'image/jpeg') + ';base64,' + base64
      probeStore.photoBase64 = base64
      probeStore.photoMime = photo.mimeType || 'image/jpeg'
      this._log('info', 'base64 编码完成，长度 ' + base64.length)
    } catch (error) {
      const msg = error && error.message ? error.message : String(error)
      this._log('err', 'base64 编码失败：' + shorten(msg, 160))
    }
  },

  // ── 看图取坐标 ──
  async _checkVision() {
    if (typeof LanguageModel === 'undefined') {
      this._log('err', 'LanguageModel 不存在')
      return
    }
    if (!this._photoDataUrl) {
      this._log('err', '还没有照片，先跑一下「相机」')
      return
    }

    const first = await this._visionOnce('第 1 次')
    if (!first) return
    const second = await this._visionOnce('第 2 次')

    if (second && first.names.join('|') === second.names.join('|')) {
      this._log('ok', '两次物品顺序一致')
    } else if (second) {
      this._log('info', '两次结果有差异，标注层要按置信度过滤')
    }
  },

  async _visionOnce(tag) {
    const start = now()
    let raw = ''
    try {
      const session = await raceTimeout(
        LanguageModel.create({
          initialPrompts: [{ role: 'system', content: '你只输出 JSON，不输出任何解释。' }]
        }),
        MODEL_TIMEOUT_MS,
        'vision-create'
      )
      try {
        raw = await raceTimeout(
          session.prompt([
            {
              role: 'user',
              content: [
                { type: 'text', text: VISION_PROMPT },
                { type: 'image_url', image_url: { url: this._photoDataUrl } }
              ]
            }
          ]),
          MODEL_TIMEOUT_MS,
          'vision-prompt'
        )
      } finally {
        try {
          session.destroy()
        } catch (e) {}
      }
    } catch (error) {
      const msg = error && error.message ? error.message : String(error)
      this._log('err', tag + ' 调用失败：' + shorten(msg, 160))
      return null
    }

    const elapsed = now() - start
    probeStore.visionRaw = raw
    this._log('info', tag + ' 耗时 ' + elapsed + 'ms')
    this._log('info', tag + ' 原文：' + shorten(raw, 150))

    const parsed = extractJson(raw)
    if (!parsed) {
      this._log('err', tag + ' 解析不出 JSON')
      return null
    }
    const items = Array.isArray(parsed.items) ? parsed.items : []
    if (items.length === 0) {
      this._log('err', tag + ' JSON 里没有 items')
      return null
    }

    let maxCoord = 0
    const names = []
    for (let i = 0; i < items.length; i++) {
      const item = items[i]
      names.push(String(item.name || '?'))
      const box = item.bbox
      if (Array.isArray(box)) {
        for (let k = 0; k < box.length; k++) {
          const value = Number(box[k])
          if (!isNaN(value) && Math.abs(value) > Math.abs(maxCoord)) maxCoord = value
        }
      }
    }

    this._log('ok', tag + ' 解析到 ' + items.length + ' 件：' + shorten(names.join('、'), 60))
    this._log(
      'info',
      tag + ' 坐标绝对值最大 ' + maxCoord + '，' +
        (maxCoord <= 1 ? '是 0–1 归一化' : maxCoord <= 100 ? '像百分比 0–100' : '像像素或 0–1000')
    )

    return { names: names, items: items }
  },

  // ── 语音 ──
  async _checkVoice() {
    if (typeof speechSynthesis !== 'undefined' && typeof SpeechSynthesisUtterance !== 'undefined') {
      try {
        const utterance = new SpeechSynthesisUtterance('自检，听到这句话说明播报可用')
        speechSynthesis.speak(utterance)
        this._log('ok', '已发起语音播报，注意听')
      } catch (error) {
        const msg = error && error.message ? error.message : String(error)
        this._log('err', '播报失败：' + shorten(msg, 160))
      }
    } else {
      this._log('err', 'speechSynthesis 不可用')
    }

    if (typeof SpeechRecognition === 'undefined') {
      this._log('err', 'SpeechRecognition 不可用')
      return
    }

    try {
      const recognition = new SpeechRecognition()
      recognition.lang = 'zh-CN'
      recognition.interimResults = false
      recognition.onresult = (event) => {
        const result = event.results[event.resultIndex][0]
        this._log('ok', '识别到：' + shorten(result.transcript, 60))
        this._log('info', '置信度 ' + (result.confidence != null ? result.confidence : '未提供'))
      }
      recognition.onerror = (event) => {
        this._log('err', '识别错误：' + (event.error || '') + ' ' + shorten(event.message || '', 100))
      }
      recognition.onend = () => {
        this._log('info', '识别会话结束')
      }
      recognition.start()
      this._log('info', '识别已启动，现在说一句话')
    } catch (error) {
      const msg = error && error.message ? error.message : String(error)
      this._log('err', '启动识别失败：' + shorten(msg, 160))
    }
  },

  // ── 模块共享 ──
  async _checkEsm() {
    const stamp = now()
    probeStore.stamp = stamp
    probeStore.note = '探针写入@' + stamp
    this._log('ok', '已写入 probeStore：' + probeStore.note)
    this._log('info', '返回首页看是否显示同一句话')
  }
}
</script>

<page>
  <view class="page-root">
    <view class="topbar">
      <text class="topbar-title">自检</text>
      <text class="status-chip">{{running ? '运行中' : '就绪'}}</text>
    </view>

    <view class="check-bar">
      <text class="check-label">{{currentLabel}}</text>
      <text class="check-idx">{{idx + 1}}/{{total}}</text>
    </view>

    <scroll-view class="log" scroll-y="true">
      <view class="line" ink:for="{{lines}}" ink:key="id">
        <text class="line-text {{item.cls}}">{{item.text}}</text>
      </view>
    </scroll-view>

    <view class="action-band">
      <view class="btn" bindtap="onTapPrev">
        <text class="btn-label">上一条</text>
      </view>
      <view class="btn btn-primary" bindtap="onTapRun">
        <text class="btn-label btn-label-active">运行</text>
      </view>
      <view class="btn" bindtap="onTapNext">
        <text class="btn-label">下一条</text>
      </view>
    </view>

    <view class="hint-bar">
      <text class="hint-text">上下切换 · 回车运行 · 双击返回</text>
    </view>
  </view>
</page>

<style>
.page-root {
  width: 480px;
  height: 352px;
  background-color: #000000;
  display: flex;
  flex-direction: column;
  padding: 10px 14px;
  box-sizing: border-box;
}

.topbar {
  flex: 0 0 26px;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
}

.topbar-title {
  font-size: 14px;
  font-weight: 500;
  color: rgba(64, 255, 94, 0.72);
}

.status-chip {
  font-size: 10px;
  color: rgba(64, 255, 94, 0.72);
  border: 1px solid rgba(64, 255, 94, 0.24);
  border-radius: 4px;
  padding: 1px 8px;
}

.check-bar {
  flex: 0 0 24px;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
  border-bottom: 1px solid rgba(64, 255, 94, 0.24);
}

.check-label {
  font-size: 13px;
  font-weight: 500;
  color: #40ff5e;
}

.check-idx {
  font-size: 10px;
  color: rgba(64, 255, 94, 0.48);
}

.log {
  flex: 1 1 auto;
  min-height: 0;
  margin: 4px 0;
  border: 1px solid rgba(64, 255, 94, 0.16);
  border-radius: 4px;
  padding: 4px 6px;
  box-sizing: border-box;
}

.line {
  display: flex;
  flex-direction: row;
  padding: 1px 0;
}

.line-text {
  font-size: 10px;
  line-height: 14px;
  white-space: nowrap;
  overflow: hidden;
  color: rgba(64, 255, 94, 0.48);
}

.line-info {
  color: rgba(64, 255, 94, 0.72);
}

.line-ok {
  color: #40ff5e;
}

.line-err {
  color: #ff6b6b;
}

.action-band {
  flex: 0 0 34px;
  display: flex;
  flex-direction: row;
  align-items: center;
  gap: 8px;
}

.btn {
  flex: 1 1 0;
  min-width: 0;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  min-height: 28px;
  border: 1px solid rgba(64, 255, 94, 0.24);
  border-radius: 4px;
}

.btn-primary {
  border-color: rgba(64, 255, 94, 0.72);
}

.btn-label {
  font-size: 11px;
  font-weight: 500;
  color: rgba(64, 255, 94, 0.48);
}

.btn-label-active {
  color: #40ff5e;
}

.hint-bar {
  flex: 0 0 16px;
  display: flex;
  flex-direction: row;
  align-items: center;
}

.hint-text {
  font-size: 9px;
  color: rgba(64, 255, 94, 0.48);
}
</style>
