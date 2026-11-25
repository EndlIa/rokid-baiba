<script def>
{
  "navigationBarTitleText": "整理"
}
</script>

<script setup>
import wx from 'wx'
import { GOALS, EXAMPLE_PLAN, analyzeDesk } from '../../utils/organizer.js'

const ARM_MS = 800
const REPEAT_MS = 1000
const PHOTO_TIMEOUT_MS = 15000

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
  const guard = new Promise((resolve, reject) => {
    timer = setTimeout(function () {
      reject(new Error(label + '超时'))
    }, ms)
  })
  return Promise.race([promise, guard]).then(
    function (value) {
      if (timer) clearTimeout(timer)
      return value
    },
    function (error) {
      if (timer) clearTimeout(timer)
      throw error
    }
  )
}

export default {
  data: {
    mode: 'real',
    isExample: false,
    phase: 'goal',
    goals: GOALS,
    goalIdx: 0,
    goalId: GOALS[0].id,
    goalName: GOALS[0].name,
    statusText: '',
    stepIdx: 0,
    stepTotal: 0,
    title: '',
    description: '',
    errorMsg: '',
    hint: '',
    primaryLabel: '就用这个',
    showSecondary: false,
    topRight: ''
  },

  onLoad(query) {
    this._armedAt = Date.now()
    this._busy = false
    this._disposed = false
    this._cameraCtx = null
    this._plan = null
    this._dataUrl = ''
    this._lastDirTime = 0
    this._lastDelta = 0

    const isExample = query && query.mode === 'example'
    this.setData({ mode: isExample ? 'example' : 'real', isExample: isExample })

    if (isExample) {
      this._showPlan(EXAMPLE_PLAN)
    } else {
      this._updateChrome()
    }
  },

  onShow() {
    this._armedAt = Date.now()
  },

  onUnload() {
    this._disposed = true
    this._cameraCtx = null
    this._dataUrl = ''
  },

  onKeyDown(event) {
    if (Date.now() - this._armedAt < ARM_MS) return
    const code = event.code
    if (code === 'ArrowUp' || code === 'ArrowLeft') {
      this._moveByDirection(-1)
    } else if (code === 'ArrowDown' || code === 'ArrowRight') {
      this._moveByDirection(1)
    }
  },

  onKeyUp(event) {
    if (Date.now() - this._armedAt < ARM_MS) return
    const code = event.code
    if (code === 'Enter') {
      event.preventDefault()
      this._primary()
    } else if (code === 'Backspace') {
      this._back()
    } else if (
      code === 'ArrowUp' ||
      code === 'ArrowLeft' ||
      code === 'ArrowDown' ||
      code === 'ArrowRight'
    ) {
      event.preventDefault()
    }
  },

  _moveByDirection(delta) {
    const stamp = Date.now()
    if (this._lastDirTime && stamp - this._lastDirTime < REPEAT_MS && this._lastDelta === delta) return
    this._lastDirTime = stamp
    this._lastDelta = delta

    const phase = this.data.phase
    if (phase === 'goal') {
      this._moveGoal(delta)
    } else if (phase === 'guiding') {
      this._moveStep(delta)
    }
  },

  _moveGoal(delta) {
    const next = Math.min(GOALS.length - 1, Math.max(0, this.data.goalIdx + delta))
    if (next === this.data.goalIdx) return
    const goal = GOALS[next]
    this.setData({ goalIdx: next, goalId: goal.id, goalName: goal.name })
  },

  _moveStep(delta) {
    if (!this._plan) return
    const target = this.data.stepIdx + delta
    if (target < 0 || target >= this.data.stepTotal) return
    this._setStep(target)
  },

  _primary() {
    const phase = this.data.phase
    if (phase === 'goal') {
      this._confirmGoal()
    } else if (phase === 'ready') {
      this._startCapture()
    } else if (phase === 'guiding') {
      this._advanceStep()
    } else if (phase === 'done') {
      wx.navigateBack()
    } else if (phase === 'error') {
      this._retry()
    }
  },

  _back() {
    const phase = this.data.phase
    if (phase === 'goal') {
      // 初始状态，交给主机默认返回行为
      return
    }
    if (phase === 'ready') {
      this.setData({ phase: 'goal' })
      this._updateChrome()
      return
    }
    if (phase === 'capturing' || phase === 'analyzing') {
      // 请求进行中，不打断
      return
    }
    wx.navigateBack()
  },

  _confirmGoal() {
    this.setData({ phase: 'ready' })
    this._updateChrome()
  },

  _retry() {
    this.setData({ phase: 'ready', errorMsg: '' })
    this._updateChrome()
  },

  async _startCapture() {
    if (this._busy) return
    this._busy = true
    try {
      if (!this._cameraCtx) {
        try {
          this._cameraCtx = wx.media.createCameraContext()
        } catch (e) {
          this._cameraCtx = null
        }
      }
      if (!this._cameraCtx) {
        this._fail('这个设备没有可用摄像头')
        return
      }

      this.setData({ phase: 'capturing', statusText: '正在拍照' })
      this._updateChrome()

      // 必须在交互上下文里同步发起
      const pending = this._cameraCtx.takePhoto({})
      const photo = await raceTimeout(pending, PHOTO_TIMEOUT_MS, '拍照')

      if (this._disposed) return
      if (!photo || !photo.data) {
        this._fail('拍照没有取到图像数据')
        return
      }

      const mimeType = photo.mimeType || 'image/jpeg'
      this._dataUrl = 'data:' + mimeType + ';base64,' + bytesToBase64(photo.data)

      this.setData({ phase: 'analyzing', statusText: '正在分析桌面，请稍候' })
      this._updateChrome()

      const result = await analyzeDesk({ dataUrl: this._dataUrl, goalId: this.data.goalId })
      if (this._disposed) return
      this._showPlan(result.plan)
    } catch (error) {
      if (this._disposed) return
      this._fail(this._describe(error))
    } finally {
      this._busy = false
    }
  },

  _describe(error) {
    if (!error) return '未知错误'
    if (error.message) return error.message
    return String(error)
  },

  _fail(message) {
    this.setData({ phase: 'error', errorMsg: message, statusText: '' })
    this._updateChrome()
  },

  _showPlan(plan) {
    if (!plan || !Array.isArray(plan.steps) || plan.steps.length === 0) {
      this._fail('没有拿到可用的整理步骤')
      return
    }
    this._plan = plan
    const first = plan.steps[0]
    this.setData({
      phase: 'guiding',
      stepIdx: 0,
      stepTotal: plan.steps.length,
      title: first.title,
      description: first.description,
      errorMsg: ''
    })
    this._updateChrome()
  },

  _setStep(index) {
    const plan = this._plan
    if (!plan) return
    const clamped = Math.min(plan.steps.length - 1, Math.max(0, index))
    const step = plan.steps[clamped]
    this.setData({ stepIdx: clamped, title: step.title, description: step.description })
    this._updateChrome()
  },

  _advanceStep() {
    const next = this.data.stepIdx + 1
    if (next >= this.data.stepTotal) {
      this.setData({ phase: 'done' })
      this._updateChrome()
      return
    }
    this._setStep(next)
  },

  _updateChrome() {
    const phase = this.data.phase
    let hint = ''
    let primaryLabel = ''
    let showSecondary = false
    let topRight = this.data.isExample ? '示例' : ''

    if (phase === 'goal') {
      hint = '滑动选择 · 单击确认'
      primaryLabel = '就用这个'
    } else if (phase === 'ready') {
      hint = '单击拍照 · 双击换个目标'
      primaryLabel = '拍照'
    } else if (phase === 'capturing') {
      hint = '正在拍照'
      primaryLabel = '请稍候'
    } else if (phase === 'analyzing') {
      hint = '正在分析，请稍候'
      primaryLabel = '请稍候'
    } else if (phase === 'guiding') {
      const isLast = this.data.stepIdx >= this.data.stepTotal - 1
      topRight = (this.data.stepIdx + 1) + '/' + this.data.stepTotal
      hint = isLast ? '单击完成 · 滑动回看' : '单击下一步 · 滑动回看'
      primaryLabel = isLast ? '完成' : '下一步'
      showSecondary = this.data.stepIdx > 0
    } else if (phase === 'done') {
      hint = '单击返回'
      primaryLabel = '返回'
    } else if (phase === 'error') {
      hint = '单击重试'
      primaryLabel = '重试'
    }

    this.setData({ hint: hint, primaryLabel: primaryLabel, showSecondary: showSecondary, topRight: topRight })
  },

  onTapGoal(event) {
    const dataset = event.currentTarget && event.currentTarget.dataset
    const idx = dataset ? dataset.idx : 0
    const goal = GOALS[idx] || GOALS[0]
    this.setData({ goalIdx: idx, goalId: goal.id, goalName: goal.name })
    this._confirmGoal()
  },

  onTapPrimary() {
    this._primary()
  },

  onTapSecondary() {
    this._moveStep(-1)
  }
}
</script>

<page>
  <view class="page-root">
    <view class="topbar">
      <text class="topbar-title">{{isExample ? '示例流程' : '摆摆'}}</text>
      <text class="topbar-right" ink:if="{{topRight}}">{{topRight}}</text>
    </view>
    <view class="divider"></view>

    <view class="body" ink:if="{{phase === 'goal'}}">
      <text class="prompt">你想先做什么</text>
      <view
        class="goal-row {{goalIdx === index ? 'goal-row-active' : ''}}"
        ink:for="{{goals}}"
        ink:key="id"
        bindtap="onTapGoal"
        data-idx="{{index}}"
      >
        <text class="goal-name {{goalIdx === index ? 'goal-name-active' : ''}}">{{item.name}}</text>
        <text class="goal-hint">{{item.hint}}</text>
      </view>
    </view>

    <view class="body" ink:if="{{phase === 'ready'}}">
      <text class="prompt">{{goalName}}</text>
      <text class="hero">看向书桌</text>
      <text class="desc">把桌面整体放进画面，单击拍照</text>
    </view>

    <view class="body" ink:if="{{phase === 'capturing'}}">
      <text class="hero">{{statusText}}</text>
      <text class="desc">保持不动，很快就好</text>
    </view>

    <view class="body" ink:if="{{phase === 'analyzing'}}">
      <text class="hero">{{statusText}}</text>
      <text class="desc">正在看照片里有什么，稍等一下</text>
    </view>

    <view class="body" ink:if="{{phase === 'guiding'}}">
      <text class="progress">{{stepIdx + 1}} / {{stepTotal}}</text>
      <text class="hero">{{title}}</text>
      <text class="desc">{{description}}</text>
    </view>

    <view class="body" ink:if="{{phase === 'done'}}">
      <text class="hero">这一步走完了</text>
      <text class="desc">桌面是你最清楚的，觉得差不多就可以收工</text>
    </view>

    <view class="body" ink:if="{{phase === 'error'}}">
      <text class="hero">没能完成</text>
      <text class="desc">{{errorMsg}}</text>
    </view>

    <view class="divider"></view>

    <view class="action-band">
      <view class="btn btn-ghost" ink:if="{{showSecondary}}" bindtap="onTapSecondary">
        <text class="btn-label">上一步</text>
      </view>
      <view class="btn btn-primary" bindtap="onTapPrimary">
        <text class="btn-label btn-label-active">{{primaryLabel}}</text>
      </view>
    </view>

    <view class="hint-bar">
      <text class="hint-text">{{hint}}</text>
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

.topbar {
  flex: 0 0 26px;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
  padding: 0 2px;
}

.topbar-title {
  font-size: 14px;
  font-weight: 500;
  color: rgba(64, 255, 94, 0.72);
}

.topbar-right {
  font-size: 11px;
  font-weight: 500;
  color: rgba(64, 255, 94, 0.48);
}

.divider {
  flex: 0 0 1px;
  height: 1px;
  background-color: rgba(64, 255, 94, 0.24);
}

.body {
  flex: 1 1 auto;
  min-height: 0;
  display: flex;
  flex-direction: column;
  justify-content: center;
  padding: 0 2px;
}

.prompt {
  font-size: 12px;
  color: rgba(64, 255, 94, 0.48);
  margin-bottom: 8px;
}

.hero {
  font-size: 22px;
  font-weight: 700;
  color: #40ff5e;
  line-height: 28px;
  margin-bottom: 8px;
}

.desc {
  font-size: 13px;
  color: rgba(64, 255, 94, 0.72);
  line-height: 19px;
}

.progress {
  font-size: 11px;
  font-weight: 500;
  color: rgba(64, 255, 94, 0.48);
  margin-bottom: 6px;
}

.goal-row {
  display: flex;
  flex-direction: column;
  border: 1px solid rgba(64, 255, 94, 0.24);
  border-radius: 4px;
  padding: 5px 8px;
  margin-bottom: 6px;
}

.goal-row-active {
  border-color: rgba(64, 255, 94, 0.72);
}

.goal-name {
  font-size: 13px;
  font-weight: 500;
  color: rgba(64, 255, 94, 0.48);
  line-height: 18px;
}

.goal-name-active {
  color: #40ff5e;
}

.goal-hint {
  font-size: 10px;
  color: rgba(64, 255, 94, 0.48);
  line-height: 14px;
}

.action-band {
  flex: 0 0 40px;
  display: flex;
  flex-direction: row;
  align-items: center;
  gap: 8px;
  padding: 0 2px;
}

.btn {
  flex: 1 1 0;
  min-width: 0;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  min-height: 32px;
  border: 1px solid rgba(64, 255, 94, 0.24);
  border-radius: 4px;
}

.btn-primary {
  border-color: rgba(64, 255, 94, 0.72);
}

.btn-ghost {
  flex: 0 0 96px;
}

.btn-label {
  font-size: 12px;
  font-weight: 500;
  color: rgba(64, 255, 94, 0.48);
}

.btn-label-active {
  color: #40ff5e;
}

.hint-bar {
  flex: 0 0 18px;
  display: flex;
  flex-direction: row;
  align-items: center;
  padding: 0 2px;
}

.hint-text {
  font-size: 10px;
  color: rgba(64, 255, 94, 0.48);
}
</style>
