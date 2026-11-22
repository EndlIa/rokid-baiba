<script def>
{
  "navigationBarTitleText": "示例场景"
}
</script>

<script setup>
import wx from 'wx'
import { scenarios } from '../../utils/scenarioData.js'

export default {
  data: {
    scenarios: scenarios,
    selectedIdx: 0,
    boundaryHint: ''
  },

  onLoad() {
    this._armedAt = Date.now()
  },

  onShow() {
    this._armedAt = Date.now()
    this.setData({ boundaryHint: '', selectedIdx: 0 })
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
    } else if (code === 'ArrowUp' || code === 'ArrowLeft') {
      event.preventDefault()
    } else if (code === 'ArrowDown' || code === 'ArrowRight') {
      event.preventDefault()
    }
  },

  _moveSelection(delta) {
    const now = Date.now()
    if (this._lastDirTime && now - this._lastDirTime < 1200 && this._lastDelta === delta) return
    this._lastDirTime = now
    this._lastDelta = delta

    const list = this.data.scenarios
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
    const item = this.data.scenarios[this.data.selectedIdx]
    if (item) {
      wx.navigateTo({ url: '/pages/steps/steps?scenario=' + item.id })
    }
  },

  onTapScenario(e) {
    const idx = e.currentTarget.dataset.idx
    if (typeof idx === 'number') {
      this.setData({ selectedIdx: idx })
      const item = this.data.scenarios[idx]
      if (item) {
        wx.navigateTo({ url: '/pages/steps/steps?scenario=' + item.id })
      }
    }
  },

  onTapBack() {
    wx.navigateBack()
  }
}
</script>

<page>
  <view class="page-root">
    <view class="topbar">
      <text class="topbar-title">示例场景</text>
    </view>
    <view class="divider"></view>

    <view class="body">
      <view class="row" ink:for="{{scenarios}}" ink:key="id" data-idx="{{index}}" bindtap="onTapScenario">
        <view class="row-marker">
          <text class="marker-dot" ink:if="{{selectedIdx === index}}">●</text>
        </view>
        <view class="row-content">
          <text class="row-name {{selectedIdx === index ? 'row-name-active' : ''}}">{{item.name}}</text>
          <text class="row-hint">{{item.hint}}</text>
        </view>
        <text class="row-arrow {{selectedIdx === index ? 'row-arrow-active' : ''}}">›</text>
      </view>
    </view>

    <view class="divider"></view>

    <view class="action-band">
      <view class="btn-back" bindtap="onTapBack">
        <text class="btn-back-label">返回</text>
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
  padding: 0 0 0 2px;
}

.topbar-title {
  font-size: 16px;
  font-weight: 500;
  color: rgba(64,255,94,0.72);
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

.row {
  display: flex;
  flex-direction: row;
  align-items: center;
  min-height: 44px;
  padding: 0 12px;
  border: 1px solid rgba(64,255,94,0.12);
  border-radius: 4px;
  margin-bottom: 6px;
}

.row-marker {
  width: 16px;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  flex: 0 0 16px;
}

.marker-dot {
  font-size: 10px;
  color: #40ff5e;
}

.row-content {
  flex: 1 1 auto;
  min-width: 0;
  display: flex;
  flex-direction: column;
  padding: 0 8px;
}

.row-name {
  font-size: 13px;
  font-weight: 500;
  color: rgba(64,255,94,0.48);
  line-height: 18px;
}

.row-name-active {
  color: #40ff5e;
}

.row-hint {
  font-size: 10px;
  font-weight: 400;
  color: rgba(64,255,94,0.48);
  line-height: 14px;
}

.row-arrow {
  font-size: 14px;
  color: rgba(64,255,94,0.24);
  flex: 0 0 14px;
}

.row-arrow-active {
  color: rgba(64,255,94,0.72);
}

.action-band {
  flex: 0 0 40px;
  display: flex;
  flex-direction: row;
  align-items: center;
  padding: 0 2px;
}

.btn-back {
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  min-height: 32px;
  padding: 0 24px;
  border: 1px solid rgba(64,255,94,0.24);
  border-radius: 4px;
}

.btn-back-label {
  font-size: 11px;
  font-weight: 500;
  color: rgba(64,255,94,0.72);
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
