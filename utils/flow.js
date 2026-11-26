// 页面的纯状态逻辑：不碰 DOM、不碰相机、不碰模型，方便单独测试
// organize.ink 只负责把这里的结果渲染出来

export const PHASE = {
  GOAL: 'goal',
  READY: 'ready',
  CAPTURING: 'capturing',
  ANALYZING: 'analyzing',
  GUIDING: 'guiding',
  DONE: 'done',
  ERROR: 'error'
}

// 单击要做什么，由当前阶段决定
export function intentFor(phase) {
  if (phase === PHASE.GOAL) return 'confirm'
  if (phase === PHASE.READY) return 'capture'
  if (phase === PHASE.GUIDING) return 'advance'
  if (phase === PHASE.DONE) return 'exit'
  if (phase === PHASE.ERROR) return 'retry'
  return 'wait'
}

// 拍照和分析进行中不接受新操作
export function isBusy(phase) {
  return phase === PHASE.CAPTURING || phase === PHASE.ANALYZING
}

// 推进到下一步；已经到最后一步返回 -1，表示该结束了
export function stepAfterAdvance(stepIdx, stepTotal) {
  const next = stepIdx + 1
  return next >= stepTotal ? -1 : next
}

export function clampStep(index, total) {
  if (total <= 0) return 0
  return Math.min(total - 1, Math.max(0, index))
}

export function moveIndex(index, delta, total) {
  if (total <= 0) return 0
  return Math.min(total - 1, Math.max(0, index + delta))
}

// 顶栏、提示条、主按钮文案
export function chromeFor(state) {
  const phase = state.phase
  const stepIdx = state.stepIdx || 0
  const stepTotal = state.stepTotal || 0
  const tag = state.isExample ? '示例' : ''

  if (phase === PHASE.GOAL) {
    return {
      hint: '滑动选择 · 单击确认',
      primaryLabel: '就用这个',
      topRight: tag,
      showSecondary: false
    }
  }

  if (phase === PHASE.READY) {
    return {
      hint: '单击拍照 · 双击返回',
      primaryLabel: '拍照',
      topRight: tag,
      showSecondary: false
    }
  }

  if (phase === PHASE.CAPTURING) {
    return {
      hint: '正在拍照，请稍候',
      primaryLabel: '请稍候',
      topRight: tag,
      showSecondary: false
    }
  }

  if (phase === PHASE.ANALYZING) {
    return {
      hint: '正在分析，请稍候',
      primaryLabel: '请稍候',
      topRight: tag,
      showSecondary: false
    }
  }

  if (phase === PHASE.GUIDING) {
    const isLast = stepIdx >= stepTotal - 1
    const progress = stepIdx + 1 + '/' + stepTotal
    return {
      hint: isLast ? '单击完成 · 滑动回看' : '单击下一步 · 滑动回看',
      primaryLabel: isLast ? '完成' : '下一步',
      topRight: tag ? tag + ' ' + progress : progress,
      showSecondary: stepIdx > 0
    }
  }

  if (phase === PHASE.DONE) {
    return {
      hint: '单击返回',
      primaryLabel: '返回',
      topRight: tag,
      showSecondary: false
    }
  }

  if (phase === PHASE.ERROR) {
    return {
      hint: '单击重试',
      primaryLabel: '重试',
      topRight: tag,
      showSecondary: false
    }
  }

  return { hint: '', primaryLabel: '', topRight: tag, showSecondary: false }
}
