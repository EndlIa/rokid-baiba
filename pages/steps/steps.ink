<script def>
{
  "navigationBarTitleText": "整理步骤"
}
</script>

<script setup>
import wx from 'wx'
import { steps, layoutData, doneMessage, scenarioMap } from '../../utils/scenarioData.js'

export default {
  data: {
    phase: 'step',
    scenarioName: '',
    stepIdx: 0,
    stepTotal: steps.length,
    currentStep: steps[0],
    steps: steps,
    layoutData: layoutData,
    doneMessage: doneMessage,
    selectedActionIdx: 2,
    actions: ['prev', 'layout', 'next'],
    boundaryHint: ''
  },

  onLoad(query) {
    this._armedAt = Date.now()
    const sid = (query && query.scenario) || 'desk'
    const sObj = scenarioMap[sid] || scenarioMap['desk']
    this.setData({
      scenarioName: sObj.name,
      stepIdx: 0,
      selectedActionIdx: 2,
      boundaryHint: '',
      phase: 'step',
      currentStep: steps[0]
    })
  },

  onShow() {
    this._armedAt = Date.now()
  },

  onKeyDown(event) {
    if (Date.now() - this._armedAt < 800) return
    const code = event.code
    if (code === 'ArrowUp' || code === 'ArrowLeft') {
      this._handleDir(-1)
    } else if (code === 'ArrowDown' || code === 'ArrowRight') {
      this._handleDir(1)
    }
  },

  onKeyUp(event) {
    if (Date.now() - this._armedAt < 800) return
    const code = event.code
    if (code === 'Enter') {
      event.preventDefault()
      this._activate()
    } else if (code === 'Backspace') {
      if (this.data.phase === 'layout') {
        event.preventDefault()
        this.setData({ phase: 'step', boundaryHint: '' })
      } else if (this.data.phase === 'done') {
        event.preventDefault()
        this.setData({ phase: 'step', stepIdx: 0, selectedActionIdx: 2, boundaryHint: '', currentStep: steps[0] })
      } else {
        event.preventDefault()
        wx.navigateBack()
      }
    } else if (code === 'ArrowUp' || code === 'ArrowLeft') {
      event.preventDefault()
    } else if (code === 'ArrowDown' || code === 'ArrowRight') {
      event.preventDefault()
    }
  },

  _handleDir(delta) {
    const now = Date.now()
    if (this._lastDirTime && now - this._lastDirTime < 1200 && this._lastDelta === delta) return
    this._lastDirTime = now
    this._lastDelta = delta

    const phase = this.data.phase
    if (phase === 'step') {
      this._moveAction(delta)
    } else if (phase === 'layout') {
      this.setData({ phase: 'step', boundaryHint: '' })
    } else if (phase === 'done') {
      const hint = delta < 0 ? '已完成' : '已完成'
      this.setData({ boundaryHint: hint })
    }
  },

  _moveAction(delta) {
    const list = this.data.actions
    const cur = this.data.selectedActionIdx
    const next = Math.min(list.length - 1, Math.max(0, cur + delta))
    if (next === cur) {
      const hint = delta < 0 ? '已是第一个操作' : '已是最后一个操作'
      this.setData({ boundaryHint: hint })
      return
    }
    this.setData({ selectedActionIdx: next, boundaryHint: '' })
  },

  _activate() {
    const phase = this.data.phase
    if (phase === 'step') {
      const action = this.data.actions[this.data.selectedActionIdx]
      if (action === 'prev') {
        this._prevStep()
      } else if (action === 'next') {
        this._nextStep()
      } else if (action === 'layout') {
        this.setData({ phase: 'layout', boundaryHint: '' })
      }
    } else if (phase === 'layout') {
      this.setData({ phase: 'step', boundaryHint: '' })
    } else if (phase === 'done') {
      wx.navigateBack()
    }
  },

  _prevStep() {
    const cur = this.data.stepIdx
    if (cur <= 0) {
      this.setData({ boundaryHint: '已经是第一步了' })
      return
    }
    const next = cur - 1
    this.setData({
      stepIdx: next,
      currentStep: steps[next],
      selectedActionIdx: 2,
      boundaryHint: ''
    })
  },

  _nextStep() {
    const cur = this.data.stepIdx
    if (cur >= steps.length - 1) {
      this.setData({ phase: 'done', boundaryHint: '' })
      return
    }
    const next = cur + 1
    this.setData({
      stepIdx: next,
      currentStep: steps[next],
      selectedActionIdx: 2,
      boundaryHint: ''
    })
  },

  onTapPrev() {
    this.setData({ selectedActionIdx: 0 })
    this._prevStep()
  },

  onTapLayout() {
    this.setData({ selectedActionIdx: 1 })
    this.setData({ phase: 'layout', boundaryHint: '' })
  },

  onTapNext() {
    this.setData({ selectedActionIdx: 2 })
    this._nextStep()
  },

  onTapBackToStep() {
    this.setData({ phase: 'step', boundaryHint: '' })
  },

  onTapDoneBack() {
    wx.navigateBack()
  },

  onTapBack() {
    wx.navigateBack()
  }
}
</script>

<page>
  <view class="page-root">
    <view class="topbar">
      <text class="topbar-title">{{scenarioName}}</text>
      <text class="topbar-progress">{{stepIdx + 1}}/{{stepTotal}}</text>
    </view>
    <view class="divider"></view>

    <view class="body" ink:if="{{phase === 'step'}}">
      <text class="step-hero">{{currentStep.name}}</text>
      <text class="step-desc">{{currentStep.desc}}</text>
    </view>

    <view class="body" ink:if="{{phase === 'layout'}}">
      <text class="layout-title">{{layoutData.title}} · 示意图</text>
      <view class="layout-row" ink:for="{{layoutData.items}}" ink:key="from">
        <view class="box from-box">
          <text class="box-title">{{item.from}}</text>
          <text class="box-label">{{item.fromLabel}}</text>
        </view>
        <view class="arrow-col">
          <text class="arrow-text">→</text>
        </view>
        <view class="box to-box">
          <text class="box-title">{{item.to}}</text>
          <text class="box-label">{{item.toLabel}}</text>
        </view>
      </view>
      <view class="disclaimer-box">
        <text class="disclaimer-text">{{layoutData.disclaimer}}</text>
      </view>
      <text class="chip">{{layoutData.note}}</text>
    </view>

    <view class="body" ink:if="{{phase === 'done'}}">
      <text class="step-hero">{{doneMessage.title}}</text>
      <text class="step-desc">{{doneMessage.desc}}</text>
    </view>

    <view class="divider"></view>

    <view class="action-band" ink:if="{{phase === 'step'}}">
      <view class="btn-wrap {{selectedActionIdx === 0 ? 'btn-active' : ''}}" bindtap="onTapPrev">
        <text class="marker" ink:if="{{selectedActionIdx === 0}}">●</text>
        <text class="btn-label {{selectedActionIdx === 0 ? 'btn-label-active' : ''}}">上一步</text>
      </view>
      <view class="btn-wrap {{selectedActionIdx === 1 ? 'btn-active' : ''}}" bindtap="onTapLayout">
        <text class="marker" ink:if="{{selectedActionIdx === 1}}">●</text>
        <text class="btn-label {{selectedActionIdx === 1 ? 'btn-label-active' : ''}}">示意</text>
      </view>
      <view class="btn-wrap {{selectedActionIdx === 2 ? 'btn-active' : ''}}" bindtap="onTapNext">
        <text class="marker" ink:if="{{selectedActionIdx === 2}}">●</text>
        <text class="btn-label {{selectedActionIdx === 2 ? 'btn-label-active' : ''}}">下一步</text>
      </view>
    </view>

    <view class="action-band" ink:if="{{phase === 'layout'}}">
      <view class="btn-wrap btn-active" bindtap="onTapBackToStep">
        <text class="marker">●</text>
        <text class="btn-label btn-label-active">返回步骤</text>
      </view>
    </view>

    <view class="action-band" ink:if="{{phase === 'done'}}">
      <view class="btn-wrap btn-active" bindtap="onTapDoneBack">
        <text class="marker">●</text>
        <text class="btn-label btn-label-active">返回</text>
      </view>
    </view>

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

.topbar {
  flex: 0 0 28px;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
  padding: 0 2px;
}

.topbar-title {
  font-size: 15px;
  font-weight: 500;
  color: rgba(64,255,94,0.72);
}

.topbar-progress {
  font-size: 12px;
  font-weight: 500;
  color: rgba(64,255,94,0.48);
}

.divider {
  height: 1px;
  background-color: rgba(64,255,94,0.24);
  flex: 0 0 1px;
}

.body {
  flex: 1 1 auto;
  min-height: 0;
  display: flex;
  flex-direction: column;
  justify-content: center;
  padding: 0 2px;
}

.step-hero {
  font-size: 22px;
  font-weight: 700;
  color: #40ff5e;
  line-height: 28px;
  margin-bottom: 10px;
}

.step-desc {
  font-size: 13px;
  font-weight: 400;
  color: rgba(64,255,94,0.72);
  line-height: 18px;
}

.layout-title {
  font-size: 14px;
  font-weight: 500;
  color: rgba(64,255,94,0.72);
  margin-bottom: 8px;
}

.layout-row {
  display: flex;
  flex-direction: row;
  align-items: center;
  margin-bottom: 6px;
}

.box {
  flex: 1 1 0;
  min-width: 0;
  display: flex;
  flex-direction: column;
  border: 1px solid rgba(64,255,94,0.24);
  border-radius: 4px;
  padding: 4px 6px;
}

.from-box {
  border-color: rgba(64,255,94,0.24);
}

.to-box {
  border-color: rgba(64,255,94,0.48);
}

.box-title {
  font-size: 11px;
  font-weight: 500;
  color: rgba(64,255,94,0.72);
  line-height: 15px;
}

.box-label {
  font-size: 9px;
  font-weight: 400;
  color: rgba(64,255,94,0.48);
  line-height: 13px;
}

.arrow-col {
  flex: 0 0 28px;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
}

.arrow-text {
  font-size: 16px;
  font-weight: 700;
  color: #40ff5e;
}

.disclaimer-box {
  border: 1px solid rgba(64,255,94,0.24);
  border-radius: 4px;
  padding: 4px 8px;
  margin-top: 4px;
  margin-bottom: 4px;
}

.disclaimer-text {
  font-size: 10px;
  font-weight: 400;
  color: rgba(64,255,94,0.48);
  line-height: 14px;
}

.chip {
  font-size: 9px;
  font-weight: 400;
  color: rgba(64,255,94,0.48);
  border: 1px solid rgba(64,255,94,0.24);
  border-radius: 3px;
  padding: 1px 6px;
}

.action-band {
  flex: 0 0 40px;
  display: flex;
  flex-direction: row;
  align-items: center;
  gap: 8px;
  padding: 0 2px;
}

.btn-wrap {
  flex: 1 1 0;
  min-width: 0;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  min-height: 32px;
  padding: 0 6px;
  border: 1px solid rgba(64,255,94,0.24);
  border-radius: 4px;
}

.btn-active {
  border-color: rgba(64,255,94,0.72);
}

.marker {
  font-size: 10px;
  color: #40ff5e;
  margin-right: 4px;
}

.btn-label {
  font-size: 11px;
  font-weight: 500;
  color: rgba(64,255,94,0.48);
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
  font-weight: 400;
  color: rgba(64,255,94,0.48);
}
</style>
