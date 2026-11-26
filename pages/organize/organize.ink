<script def>
{
  "navigationBarTitleText": "整理"
}
</script>

<script setup>
import wx from 'wx'
import { GOALS, EXAMPLE_PLAN, analyzeDesk } from '../../utils/organizer.js'
import { capturePhoto } from '../../utils/camera.js'
import {
  PHASE,
  intentFor,
  chromeFor,
  stepAfterAdvance,
  clampStep,
  moveIndex
} from '../../utils/flow.js'

const ARM_MS = 800
const REPEAT_MS = 1000

export default {
  data: {
    isExample: false,
    phase: PHASE.GOAL,
    goals: GOALS,
    goalIdx: 0,
    stepIdx: 0,
    stepTotal: 0,
    title: '',
    description: '',
    errorStage: '',
    errorMsg: '',
    hint: '',
    primaryLabel: '',
    topRight: '',
    showSecondary: false
  },

  onLoad(query) {
    this._armedAt = Date.now()
    this._busy = false
    this._disposed = false
    this._cameraCtx = null
    this._plan = null
    this._lastDirTime = 0
    this._lastDelta = 0

    const isExample = !!(query && query.mode === 'example')
    this._state = {
      phase: PHASE.GOAL,
      stepIdx: 0,
      stepTotal: 0,
      isExample: isExample
    }

    if (isExample) {
      this._showPlan(EXAMPLE_PLAN)
    } else {
      this.setData({ isExample: isExample })
      this._render()
    }
  },

  onShow() {
    this._armedAt = Date.now()
  },

  onUnload() {
    this._disposed = true
    this._cameraCtx = null
    this._plan = null
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
    } else if (
      code === 'ArrowUp' ||
      code === 'ArrowLeft' ||
      code === 'ArrowDown' ||
      code === 'ArrowRight'
    ) {
      event.preventDefault()
    }
    // Backspace 不做拦截，保留宿主默认返回
  },

  // 段落状态和界面文案一起更新，避免读到旧的 data
  _render(patch) {
    this._state = Object.assign({}, this._state, patch || {})
    const chrome = chromeFor(this._state)
    const data = Object.assign({}, patch || {}, chrome)
    data.phase = this._state.phase
    data.isExample = this._state.isExample
    this.setData(data)
  },

  _primary() {
    const intent = intentFor(this.data.phase)
    if (intent === 'confirm') {
      this._render({ phase: PHASE.READY })
    } else if (intent === 'capture') {
      this._startCapture()
    } else if (intent === 'advance') {
      this._advanceStep()
    } else if (intent === 'exit') {
      wx.navigateBack()
    } else if (intent === 'retry') {
      this._render({ phase: PHASE.READY, errorStage: '', errorMsg: '' })
    }
  },

  _moveByDirection(delta) {
    const stamp = Date.now()
    if (this._lastDirTime && stamp - this._lastDirTime < REPEAT_MS && this._lastDelta === delta) return
    this._lastDirTime = stamp
    this._lastDelta = delta

    const phase = this.data.phase
    if (phase === PHASE.GOAL) {
      const next = moveIndex(this.data.goalIdx, delta, GOALS.length)
      if (next !== this.data.goalIdx) this.setData({ goalIdx: next })
    } else if (phase === PHASE.GUIDING) {
      this._moveStep(delta)
    }
  },

  _moveStep(delta) {
    if (!this._plan) return
    const target = moveIndex(this.data.stepIdx, delta, this.data.stepTotal)
    if (target === this.data.stepIdx) return
    this._setStep(target)
  },

  _setStep(index) {
    if (!this._plan) return
    const position = clampStep(index, this.data.stepTotal)
    const step = this._plan.steps[position]
    this._render({
      stepIdx: position,
      title: step.title,
      description: step.description
    })
  },

  _advanceStep() {
    const next = stepAfterAdvance(this.data.stepIdx, this.data.stepTotal)
    if (next < 0) {
      this._render({ phase: PHASE.DONE })
      return
    }
    this._setStep(next)
  },

  async _startCapture() {
    if (this._busy) return
    this._busy = true
    this._stage = '打开相机'
    this._render({ phase: PHASE.CAPTURING, errorStage: '', errorMsg: '' })
    try {
      if (!this._cameraCtx) {
        this._cameraCtx = wx.media.createCameraContext()
      }
      const reportStage = (stage) => { this._stage = stage }
      const photo = await capturePhoto(this._cameraCtx, reportStage)
      if (this._disposed) return

      this._render({ phase: PHASE.ANALYZING })
      const plan = await analyzeDesk({
        dataUrl: photo.dataUrl,
        goalId: GOALS[this.data.goalIdx].id,
        onStage: reportStage
      })
      if (this._disposed) return
      this._showPlan(plan)
    } catch (error) {
      if (this._disposed) return
      this._fail(error)
    } finally {
      this._busy = false
    }
  },

  _showPlan(plan) {
    if (!plan || !Array.isArray(plan.steps) || plan.steps.length === 0) {
      this._fail({ stage: '解析结果', message: '没有拿到可用的整理步骤' })
      return
    }
    this._plan = plan
    const first = plan.steps[0]
    this._state.stepTotal = plan.steps.length
    this._render({
      phase: PHASE.GUIDING,
      stepIdx: 0,
      stepTotal: plan.steps.length,
      title: first.title,
      description: first.description,
      errorStage: '',
      errorMsg: ''
    })
  },

  _fail(error) {
    const stage = (error && error.stage) || this._stage || '整理流程'
    const message = (error && error.message) || String(error)
    console.error('[摆摆] ' + stage + '：' + message)
    this._render({ phase: PHASE.ERROR, errorStage: stage, errorMsg: message })
  },

  onTapGoal(event) {
    const dataset = event.currentTarget && event.currentTarget.dataset
    const index = dataset ? Number(dataset.idx) : 0
    const goalIdx = clampStep(index, GOALS.length)
    this.setData({ goalIdx: goalIdx })
    this._render({ phase: PHASE.READY })
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
      <text class="prompt">{{goals[goalIdx].name}}</text>
      <text class="hero">看向书桌</text>
      <text class="desc">把桌面整体放进画面，单击拍照</text>
    </view>

    <view class="body" ink:if="{{phase === 'capturing'}}">
      <text class="hero">正在拍照</text>
      <text class="desc">保持不动，很快就好</text>
    </view>

    <view class="body" ink:if="{{phase === 'analyzing'}}">
      <text class="hero">正在分析桌面</text>
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
      <text class="desc">失败环节：{{errorStage}}</text>
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
