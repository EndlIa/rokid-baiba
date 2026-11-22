<script def>
{
  "navigationBarTitleText": "图像与标注测试"
}
</script>

<script setup>
import wx from 'wx'

const PHOTO_TIMEOUT_MS = 8000

export default {
  data: {
    phase: 'idle',
    selectedIdx: 0,
    showAnnotation: false,
    imageData: '',
    errorMsg: '',
    timeoutRemaining: 0,
    boundaryHint: '',
    buttons: []
  },

  onLoad() {
    this._armedAt = Date.now()
    this._cameraCtx = null
    this._timeoutTimer = null
    this._countdownTimer = null
    this._photoBitmap = null
    this._lastDirTime = 0
    this._lastDelta = 0
    this._refreshButtons()
  },

  onShow() {
    this._armedAt = Date.now()
    this.setData({ boundaryHint: '' })
  },

  onUnload() {
    this._clearTimers()
    if (this._photoBitmap) {
      try { this._photoBitmap.close() } catch (e) {}
      this._photoBitmap = null
    }
  },

  onKeyDown(event) {
    if (Date.now() - this._armedAt < 800) return
    const code = event.code
    if (code === 'ArrowUp' || code === 'ArrowLeft') {
      this._moveSelection(-1)
    } else if (code === 'ArrowDown' || code === 'ArrowRight') {
      this._moveSelection(1)
    }
  },

  onKeyUp(event) {
    if (Date.now() - this._armedAt < 800) return
    const code = event.code
    if (code === 'Enter') {
      event.preventDefault()
      this._activate()
    } else if (code === 'Backspace') {
      event.preventDefault()
      wx.navigateBack()
    }
    // ArrowUp/Down/Left/Right: 不 preventDefault，让运行时默认滚动行为生效
  },

  _refreshButtons() {
    const phase = this.data.phase
    let btns = []
    if (phase === 'idle') {
      btns = [{ key: 'capture', label: '拍照' }, { key: 'demo', label: '使用示例图' }]
    } else if (phase === 'captured') {
      btns = [{ key: 'retake', label: '重新拍摄' }, { key: 'annotation', label: '显示标注' }]
    } else if (phase === 'error') {
      btns = [{ key: 'retry', label: '重试拍照' }, { key: 'demo', label: '使用示例图' }]
    } else if (phase === 'no_camera') {
      btns = [{ key: 'demo', label: '使用示例图' }]
    } else if (phase === 'demo') {
      btns = [{ key: 'retake', label: '重新拍摄' }, { key: 'annotation', label: '显示标注' }]
    }
    this.setData({
      buttons: btns,
      selectedIdx: 0,
      showAnnotation: phase === 'captured' || phase === 'demo' ? this.data.showAnnotation : false
    })
  },

  _moveSelection(delta) {
    const now = Date.now()
    if (this._lastDirTime && now - this._lastDirTime < 1200 && this._lastDelta === delta) return
    this._lastDirTime = now
    this._lastDelta = delta

    const list = this.data.buttons
    if (list.length === 0) return
    const cur = this.data.selectedIdx
    const next = Math.min(list.length - 1, Math.max(0, cur + delta))
    if (next === cur) {
      const hint = delta < 0 ? '已经是第一个了' : '已经是最后一个了'
      this.setData({ boundaryHint: hint })
      return
    }
    this.setData({ selectedIdx: next, boundaryHint: '' })
  },

  _activate() {
    const btn = this.data.buttons[this.data.selectedIdx]
    if (!btn) return
    const key = btn.key
    if (key === 'capture' || key === 'retry') {
      this._startCapture()
    } else if (key === 'demo') {
      this._useDemoImage()
    } else if (key === 'retake') {
      this._retake()
    } else if (key === 'annotation') {
      this._toggleAnnotation()
    }
  },

  // ── 拍照 ──
  async _startCapture() {
    this._clearTimers()

    if (!this._cameraCtx) {
      try {
        this._cameraCtx = wx.media.createCameraContext()
      } catch (e) {
        this._cameraCtx = null
      }
    }
    if (!this._cameraCtx) {
      this.setData({ phase: 'no_camera', errorMsg: '' })
      this._refreshButtons()
      return
    }

    this.setData({ phase: 'requesting', errorMsg: '', timeoutRemaining: 8 })
    this._refreshButtons()

    // 倒计时显示
    let remaining = 8
    this._countdownTimer = setInterval(() => {
      remaining--
      if (remaining <= 0) remaining = 0
      this.setData({ timeoutRemaining: remaining })
    }, 1000)

    // 超时兜底
    let timeoutFired = false
    const timeoutPromise = new Promise((_, reject) => {
      this._timeoutTimer = setTimeout(() => {
        timeoutFired = true
        reject(new Error('拍照超时'))
      }, PHOTO_TIMEOUT_MS)
    })

    try {
      const photo = await Promise.race([
        this._cameraCtx.takePhoto({ quality: 'high', mode: 'default', enableSystemPreview: true }),
        timeoutPromise
      ])

      this._clearTimers()
      if (timeoutFired) return

      if (!photo || !photo.data) {
        this.setData({ phase: 'error', errorMsg: '拍照未返回图像数据' })
        this._refreshButtons()
        return
      }

      // 转换 ArrayBuffer → Blob → ImageBitmap → canvas 绘制
      const mimeType = photo.mimeType || 'image/webp'
      const blob = new Blob([photo.data], { type: mimeType })
      const bitmap = await createImageBitmap(blob)

      if (this._photoBitmap) {
        try { this._photoBitmap.close() } catch (e) {}
      }
      this._photoBitmap = bitmap

      this.setData({ phase: 'captured', imageData: 'captured', showAnnotation: false })
      this._refreshButtons()
      this._drawCanvas(bitmap)
    } catch (error) {
      this._clearTimers()
      const msg = (error && error.message) ? error.message : String(error)
      // 区分"无摄像头"与"拍照失败"
      if (msg.indexOf('Camera is unavailable') >= 0 || msg.indexOf('camera') >= 0) {
        this.setData({ phase: 'no_camera', errorMsg: msg })
      } else {
        this.setData({ phase: 'error', errorMsg: msg })
      }
      this._refreshButtons()
    }
  },

  // ── 示例图降级 ──
  _useDemoImage() {
    this._clearTimers()
    if (this._photoBitmap) {
      try { this._photoBitmap.close() } catch (e) {}
      this._photoBitmap = null
    }
    this.setData({ phase: 'demo', imageData: 'demo', showAnnotation: false })
    this._refreshButtons()
    this._drawDemoCanvas()
  },

  // ── 重新拍摄 ──
  _retake() {
    this._clearTimers()
    if (this._photoBitmap) {
      try { this._photoBitmap.close() } catch (e) {}
      this._photoBitmap = null
    }
    const ctx = wx.createCanvasContext('photoCanvas')
    if (ctx) {
      ctx.clearRect(0, 0, 448, 232)
    }
    this.setData({ phase: 'idle', imageData: '', showAnnotation: false, errorMsg: '' })
    this._refreshButtons()
  },

  // ── 标注切换 ──
  _toggleAnnotation() {
    this.setData({ showAnnotation: !this.data.showAnnotation })
  },

  // ── Canvas 绘制：真实照片 ──
  _drawCanvas(bitmap) {
    const ctx = wx.createCanvasContext('photoCanvas')
    if (!ctx) return
    ctx.clearRect(0, 0, 448, 232)
    // 居中等比缩放绘制
    const cw = 448
    const ch = 232
    const bw = bitmap.width
    const bh = bitmap.height
    const scale = Math.min(cw / bw, ch / bh)
    const dw = bw * scale
    const dh = bh * scale
    const dx = (cw - dw) / 2
    const dy = (ch - dh) / 2
    ctx.drawImage(bitmap, dx, dy, dw, dh)
  },

  // ── Canvas 绘制：示例图（简笔画：桌面 + 书本 + 收纳区） ──
  _drawDemoCanvas() {
    const ctx = wx.createCanvasContext('photoCanvas')
    if (!ctx) return
    const cw = 448
    const ch = 232
    ctx.clearRect(0, 0, cw, ch)

    // 背景
    ctx.fillStyle = 'rgba(64,255,94,0.06)'
    ctx.fillRect(0, 0, cw, ch)

    // 桌面线
    ctx.strokeStyle = 'rgba(64,255,94,0.24)'
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.moveTo(20, 180)
    ctx.lineTo(cw - 20, 180)
    ctx.stroke()

    // 书本（左下区域）
    ctx.strokeStyle = '#40ff5e'
    ctx.lineWidth = 2
    ctx.strokeRect(67, 90, 134, 80)
    // 书本封面纹理
    ctx.strokeStyle = 'rgba(64,255,94,0.48)'
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.moveTo(80, 110)
    ctx.lineTo(188, 110)
    ctx.moveTo(80, 130)
    ctx.lineTo(188, 130)
    ctx.moveTo(80, 150)
    ctx.lineTo(188, 150)
    ctx.stroke()
    // 书名标签
    ctx.fillStyle = 'rgba(64,255,94,0.72)'
    ctx.font = '11px sans-serif'
    ctx.fillText('书本', 110, 145)

    // 收纳区（右下区域，虚线框）
    ctx.strokeStyle = '#40ff5e'
    ctx.lineWidth = 2
    ctx.setLineDash([6, 4])
    ctx.strokeRect(246, 58, 134, 93)
    ctx.setLineDash([])
    // 收纳区标签
    ctx.fillStyle = 'rgba(64,255,94,0.72)'
    ctx.font = '11px sans-serif'
    ctx.fillText('收纳区', 280, 108)

    // "演示" 水印
    ctx.fillStyle = 'rgba(64,255,94,0.24)'
    ctx.font = '14px sans-serif'
    ctx.fillText('演示', cw - 50, ch - 10)
  },

  _clearTimers() {
    if (this._timeoutTimer) {
      clearTimeout(this._timeoutTimer)
      this._timeoutTimer = null
    }
    if (this._countdownTimer) {
      clearInterval(this._countdownTimer)
      this._countdownTimer = null
    }
  },

  // ── bindtap handler（指针输入路径，模拟器/预览可用） ──
  onTapButton(event) {
    const dataset = event.currentTarget && event.currentTarget.dataset
    if (!dataset) return
    const idx = dataset.idx
    const key = dataset.key
    if (typeof idx === 'number') {
      this.setData({ selectedIdx: idx })
    }
    if (key === 'capture' || key === 'retry') {
      this._startCapture()
    } else if (key === 'demo') {
      this._useDemoImage()
    } else if (key === 'retake') {
      this._retake()
    } else if (key === 'annotation') {
      this._toggleAnnotation()
    }
  }
}
</script>

<page>
  <view class="page-root">
    <!-- topbar -->
    <view class="topbar">
      <text class="topbar-title">图像与标注测试</text>
      <text class="status-chip" ink:if="{{phase === 'idle'}}">等待拍照</text>
      <text class="status-chip" ink:elif="{{phase === 'requesting'}}">请求中</text>
      <text class="status-chip" ink:elif="{{phase === 'captured'}}">拍照成功</text>
      <text class="status-chip" ink:elif="{{phase === 'error'}}">拍照失败</text>
      <text class="status-chip" ink:elif="{{phase === 'no_camera'}}">无摄像头</text>
      <text class="status-chip" ink:elif="{{phase === 'demo'}}">示例图</text>
    </view>

    <!-- image area (hero) -->
    <view class="image-area">
      <!-- idle 占位 -->
      <view class="placeholder" ink:if="{{phase === 'idle'}}">
        <text class="placeholder-text">等待拍照</text>
        <text class="placeholder-sub">按"拍照"按钮或使用示例图</text>
      </view>

      <!-- requesting loading -->
      <view class="placeholder" ink:elif="{{phase === 'requesting'}}">
        <text class="placeholder-text">相机初始化中…</text>
        <text class="placeholder-sub">请稍候… {{timeoutRemaining}}s</text>
      </view>

      <!-- no_camera -->
      <view class="placeholder" ink:elif="{{phase === 'no_camera'}}">
        <text class="placeholder-text">模拟器无摄像头</text>
        <text class="placeholder-sub">{{errorMsg || '摄像头不可用，请使用示例图'}}</text>
      </view>

      <!-- error -->
      <view class="placeholder" ink:elif="{{phase === 'error'}}">
        <text class="placeholder-text">拍照失败</text>
        <text class="placeholder-sub">{{errorMsg}}</text>
      </view>

      <!-- captured / demo: canvas + annotation overlay -->
      <view ink:elif="{{phase === 'captured' || phase === 'demo'}}" class="canvas-container">
        <canvas id="photoCanvas" class="photo-canvas" width="448" height="232"></canvas>

        <!-- 标注 overlay -->
        <view class="annotation-layer" ink:if="{{showAnnotation}}">
          <!-- 物品框 -->
          <view class="obj-box"></view>
          <view class="obj-label-wrap">
            <text class="obj-label">书本</text>
          </view>
          <!-- 编号 badge -->
          <view class="obj-badge">
            <text class="badge-text">1</text>
          </view>
          <!-- 目标区域框 -->
          <view class="target-box"></view>
          <view class="target-label-wrap">
            <text class="target-label">收纳区</text>
          </view>
          <!-- 箭头 -->
          <view class="arrow-wrap">
            <text class="arrow-text">→</text>
          </view>
          <!-- demo 标记 -->
          <view class="demo-mark" ink:if="{{phase === 'demo'}}">
            <text class="demo-mark-text">演示</text>
          </view>
        </view>
      </view>
    </view>

    <!-- action band -->
    <view class="action-band">
      <view ink:for="{{buttons}}" ink:key="key" class="btn-wrap" bindtap="onTapButton" data-key="{{item.key}}" data-idx="{{index}}">
        <view class="btn-marker">
          <view ink:if="{{selectedIdx === index}}" class="marker-dot"></view>
        </view>
        <text class="btn-label {{selectedIdx === index ? 'btn-label-active' : ''}}">{{item.label}}</text>
      </view>
    </view>

    <!-- hint bar -->
    <view class="hint-bar">
      <text class="hint-text">{{boundaryHint || '滑动切换 · 单击确认 · 双击返回'}}</text>
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
  padding: 12px 16px;
  box-sizing: border-box;
}

/* topbar */
.topbar {
  flex: 0 0 28px;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
  padding: 0 2px;
}

.topbar-title {
  font-size: 14px;
  font-weight: 500;
  color: rgba(64,255,94,0.72);
}

.status-chip {
  font-size: 10px;
  font-weight: 400;
  color: rgba(64,255,94,0.72);
  border: 1px solid rgba(64,255,94,0.24);
  border-radius: 4px;
  padding: 1px 8px;
}

/* image area (hero) */
.image-area {
  flex: 1 1 auto;
  min-height: 0;
  display: flex;
  flex-direction: column;
  margin: 4px 0;
}

.placeholder {
  flex: 1 1 auto;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  border: 1px solid rgba(64,255,94,0.24);
  border-radius: 4px;
}

.placeholder-text {
  font-size: 14px;
  font-weight: 500;
  color: rgba(64,255,94,0.72);
  margin-bottom: 6px;
}

.placeholder-sub {
  font-size: 10px;
  font-weight: 400;
  color: rgba(64,255,94,0.48);
}

.canvas-container {
  position: relative;
  flex: 1 1 auto;
  display: flex;
  flex-direction: column;
}

.photo-canvas {
  width: 448px;
  height: 232px;
  border: 1px solid rgba(64,255,94,0.24);
  border-radius: 4px;
}

/* annotation overlay */
.annotation-layer {
  position: absolute;
  top: 0;
  left: 0;
  width: 448px;
  height: 232px;
  pointer-events: none;
}

.obj-box {
  position: absolute;
  left: 15%;
  top: 30%;
  width: 30%;
  height: 35%;
  border: 2px solid #40ff5e;
}

.obj-label-wrap {
  position: absolute;
  left: 15%;
  top: 64%;
}

.obj-label {
  font-size: 10px;
  font-weight: 500;
  color: #40ff5e;
  background-color: rgba(64,255,94,0.12);
  padding: 1px 4px;
  border-radius: 2px;
}

.obj-badge {
  position: absolute;
  left: 13%;
  top: 27%;
  width: 18px;
  height: 18px;
  background-color: #40ff5e;
  border-radius: 9px;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
}

.badge-text {
  font-size: 10px;
  font-weight: 700;
  color: #000000;
}

.target-box {
  position: absolute;
  left: 55%;
  top: 25%;
  width: 30%;
  height: 40%;
  border: 2px solid #40ff5e;
}

.target-label-wrap {
  position: absolute;
  left: 55%;
  top: 64%;
}

.target-label {
  font-size: 10px;
  font-weight: 500;
  color: #40ff5e;
  background-color: rgba(64,255,94,0.12);
  padding: 1px 4px;
  border-radius: 2px;
}

.arrow-wrap {
  position: absolute;
  left: 45%;
  top: 45%;
}

.arrow-text {
  font-size: 16px;
  font-weight: 700;
  color: #40ff5e;
}

.demo-mark {
  position: absolute;
  right: 4px;
  bottom: 4px;
}

.demo-mark-text {
  font-size: 9px;
  font-weight: 400;
  color: rgba(64,255,94,0.48);
}

/* action band */
.action-band {
  flex: 0 0 40px;
  display: flex;
  flex-direction: row;
  align-items: center;
  gap: 12px;
  padding: 0 2px;
}

.btn-wrap {
  flex: 1 1 0;
  min-width: 0;
  display: flex;
  flex-direction: row;
  align-items: center;
  min-height: 32px;
  padding: 0 12px;
  border: 1px solid rgba(64,255,94,0.24);
  border-radius: 4px;
}

.btn-marker {
  width: 16px;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
}

.marker-text {
  font-size: 11px;
  color: #40ff5e;
}

.btn-label {
  font-size: 11px;
  font-weight: 500;
  color: rgba(64,255,94,0.48);
}

.btn-label-active {
  color: #40ff5e;
}

/* hint bar */
.hint-bar {
  flex: 0 0 18px;
  display: flex;
  flex-direction: row;
  align-items: center;
  padding: 0 2px;
}

.hint-text {
  font-size: 10px;
  font-weight: 400;
  color: rgba(64,255,94,0.48);
}
</style>
