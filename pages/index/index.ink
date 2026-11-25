<script def>
{
  "navigationBarTitleText": "摆摆"
}
</script>

<script setup>
import wx from 'wx'
import { appInfo } from '../../utils/scenarioData.js'

const ACTIONS = [
  { key: 'organize', label: '开始整理' },
  { key: 'example', label: '查看示例' }
]

export default {
  data: {
    appName: appInfo.name,
    subtitle: appInfo.subtitle,
    description: appInfo.description,
    actions: ACTIONS,
    selectedIdx: 0,
    boundaryHint: ''
  },

  onLoad() {
    this._armedAt = Date.now()
    this._lastDirTime = 0
    this._lastDelta = 0
  },

  onShow() {
    this._armedAt = Date.now()
    this.setData({ boundaryHint: '' })
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
      // 根页面：不拦截，交给主机默认行为关闭应用
    } else if (
      code === 'ArrowUp' ||
      code === 'ArrowLeft' ||
      code === 'ArrowDown' ||
      code === 'ArrowRight'
    ) {
      event.preventDefault()
    }
  },

  _moveSelection(delta) {
    const stamp = Date.now()
    if (this._lastDirTime && stamp - this._lastDirTime < 1000 && this._lastDelta === delta) return
    this._lastDirTime = stamp
    this._lastDelta = delta

    const next = Math.min(ACTIONS.length - 1, Math.max(0, this.data.selectedIdx + delta))
    if (next === this.data.selectedIdx) {
      this.setData({ boundaryHint: delta < 0 ? '已经是第一个了' : '已经是最后一个了' })
      return
    }
    this.setData({ selectedIdx: next, boundaryHint: '' })
  },

  _activate() {
    const action = ACTIONS[this.data.selectedIdx]
    if (!action) return
    if (action.key === 'organize') {
      this.onStartOrganize()
    } else if (action.key === 'example') {
      this.onShowExample()
    }
  },

  onStartOrganize() {
    wx.navigateTo({ url: '/pages/organize/organize' })
  },

  onShowExample() {
    wx.navigateTo({ url: '/pages/organize/organize?mode=example' })
  },

  onTapOrganize() {
    this.setData({ selectedIdx: 0 })
    this.onStartOrganize()
  },

  onTapExample() {
    this.setData({ selectedIdx: 1 })
    this.onShowExample()
  }
}
</script>

<page>
  <view class="page-root">
    <view class="topbar">
      <text class="topbar-title">{{appName}}</text>
    </view>

    <view class="body">
      <text class="subtitle">{{subtitle}}</text>
      <text class="description">{{description}}</text>
    </view>

    <view class="action-band">
      <view class="btn-wrap" bindtap="onTapOrganize">
        <view class="btn-marker">
          <text class="marker-text" ink:if="{{selectedIdx === 0}}">●</text>
        </view>
        <text class="btn-label {{selectedIdx === 0 ? 'btn-label-active' : ''}}">开始整理</text>
      </view>
      <view class="btn-wrap" bindtap="onTapExample">
        <view class="btn-marker">
          <text class="marker-text" ink:if="{{selectedIdx === 1}}">●</text>
        </view>
        <text class="btn-label {{selectedIdx === 1 ? 'btn-label-active' : ''}}">查看示例</text>
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
  flex: 0 0 30px;
  display: flex;
  flex-direction: row;
  align-items: center;
  padding: 0 0 0 2px;
}

.topbar-title {
  font-size: 16px;
  font-weight: 500;
  color: rgba(64, 255, 94, 0.72);
}

.body {
  flex: 1 1 auto;
  min-height: 0;
  display: flex;
  flex-direction: column;
  justify-content: center;
  padding: 0 2px;
}

.subtitle {
  font-size: 14px;
  font-weight: 400;
  color: rgba(64, 255, 94, 0.72);
  line-height: 19px;
  margin-bottom: 8px;
}

.description {
  font-size: 12px;
  font-weight: 400;
  color: rgba(64, 255, 94, 0.48);
  line-height: 17px;
}

.action-band {
  flex: 0 0 48px;
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
  border: 1px solid rgba(64, 255, 94, 0.24);
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
  font-weight: 400;
  color: rgba(64, 255, 94, 0.48);
}
</style>
