import { raceTimeout } from './async.js'

export const GOALS = [
  { id: 'work', name: '腾出工作空间', hint: '优先清出能工作学习的区域' },
  { id: 'desk', name: '整理桌面', hint: '按用途把东西分一分、归个位' },
  { id: 'draw', name: '腾出绘图空间', hint: '优先保留能铺开画纸的区域' }
]

export const EXAMPLE_PLAN = {
  summary: '桌面中央堆着书本和纸张，右侧放着一只水杯。',
  uncertainties: [],
  steps: [
    { title: '清空中央', description: '把桌面中央的书本和纸张先搬到左边。' },
    { title: '给水杯挪位', description: '把水杯移到右上角，离开铺纸的位置。' },
    { title: '书本归拢', description: '把左边的书竖着叠整齐，靠边放。' }
  ]
}

const MAX_STEPS = 8
const MIN_STEPS = 1
const AVAILABILITY_TIMEOUT_MS = 8000
const ANALYZE_TIMEOUT_MS = 40000

const SYSTEM_PROMPT =
  '你是桌面整理助手，只能依据用户给的照片和整理目标给建议。规则：' +
  '一，只描述照片里看得见的东西，看不清的写进 uncertainties，不要猜。' +
  '二，不要假设用户有照片里没出现的收纳盒、抽屉或空位。' +
  '三，不建议丢弃任何物品，去留由用户自己决定。' +
  '四，每条步骤只做一件事，描述要具体到能立刻动手。' +
  '五，只输出 JSON，不要解释，不要用代码块包裹。'

function goalById(id) {
  for (let i = 0; i < GOALS.length; i++) {
    if (GOALS[i].id === id) return GOALS[i]
  }
  return GOALS[0]
}

function buildUserText(goal) {
  return (
    '整理目标：' + goal.name + '（' + goal.hint + '）。\n' +
    '请给出 3 到 5 条整理步骤，严格按下面格式输出 JSON：\n' +
    '{"summary":"一句话描述桌面现状",' +
    '"uncertainties":["看不清的东西"],' +
    '"steps":[{"title":"不超过 8 个字","description":"一句话动作，不超过 30 个字"}]}'
  )
}

function fail(stage, message) {
  const error = new Error(message)
  error.stage = stage
  return error
}

// 从模型输出里找出 JSON，容忍前后的多余文字和代码块围栏
export function parsePlanText(text) {
  if (!text) return null
  const trimmed = String(text).trim()
  const fenced = trimmed.replace(/^```(?:json)?/i, '').replace(/```$/, '').trim()
  try {
    return JSON.parse(fenced)
  } catch (e) {}
  const start = fenced.indexOf('{')
  const end = fenced.lastIndexOf('}')
  if (start >= 0 && end > start) {
    try {
      return JSON.parse(fenced.slice(start, end + 1))
    } catch (e) {}
  }
  return null
}

function nonEmptyString(value) {
  return typeof value === 'string' && value.trim().length > 0
}

// 结构校验：不合格就返回原因，不修补、不猜测
export function validatePlan(parsed) {
  if (!parsed || typeof parsed !== 'object') {
    return { ok: false, error: '返回的不是对象' }
  }
  if (!Array.isArray(parsed.steps)) {
    return { ok: false, error: '缺少 steps 数组' }
  }
  if (parsed.steps.length < MIN_STEPS) {
    return { ok: false, error: 'steps 是空的' }
  }
  if (parsed.steps.length > MAX_STEPS) {
    return { ok: false, error: 'steps 超过 ' + MAX_STEPS + ' 条' }
  }

  const steps = []
  for (let i = 0; i < parsed.steps.length; i++) {
    const step = parsed.steps[i]
    if (!step || typeof step !== 'object') {
      return { ok: false, error: '第 ' + (i + 1) + ' 条步骤不是对象' }
    }
    if (!nonEmptyString(step.title)) {
      return { ok: false, error: '第 ' + (i + 1) + ' 条缺少 title' }
    }
    if (!nonEmptyString(step.description)) {
      return { ok: false, error: '第 ' + (i + 1) + ' 条缺少 description' }
    }
    steps.push({
      title: step.title.trim(),
      description: step.description.trim()
    })
  }

  const uncertainties = []
  if (Array.isArray(parsed.uncertainties)) {
    for (let i = 0; i < parsed.uncertainties.length; i++) {
      if (nonEmptyString(parsed.uncertainties[i])) {
        uncertainties.push(parsed.uncertainties[i].trim())
      }
    }
  }

  return {
    ok: true,
    plan: {
      summary: nonEmptyString(parsed.summary) ? parsed.summary.trim() : '',
      uncertainties: uncertainties,
      steps: steps
    }
  }
}

// 主入口：dataUrl 为 data:image/...;base64,... 形式
// 失败时抛出的 error 带 stage 字段，页面直接显示这个阶段
export async function analyzeDesk(options) {
  const dataUrl = options && options.dataUrl
  if (!dataUrl) {
    throw fail('准备分析', '没有可分析的照片')
  }
  if (typeof LanguageModel === 'undefined') {
    throw fail('检查模型', '当前环境不支持语言模型')
  }

  const goal = goalById(options.goalId)
  const report = typeof options.onStage === 'function' ? options.onStage : function () {}

  report('检查模型')
  const availability = await raceTimeout(
    LanguageModel.availability(),
    AVAILABILITY_TIMEOUT_MS,
    '检查模型'
  )
  if (availability !== 'available') {
    throw fail('检查模型', '语言模型不可用')
  }

  report('初始化模型')
  const session = await raceTimeout(
    LanguageModel.create({
      initialPrompts: [{ role: 'system', content: SYSTEM_PROMPT }]
    }),
    ANALYZE_TIMEOUT_MS,
    '初始化模型'
  )

  let raw = ''
  try {
    report('分析照片')
    raw = await raceTimeout(
      session.prompt([
        {
          role: 'user',
          content: [
            { type: 'text', text: buildUserText(goal) },
            { type: 'image_url', image_url: { url: dataUrl } }
          ]
        }
      ]),
      ANALYZE_TIMEOUT_MS,
      '分析照片'
    )
  } finally {
    try {
      session.destroy()
    } catch (e) {}
  }

  report('解析结果')
  const parsed = parsePlanText(raw)
  if (!parsed) {
    throw fail('解析结果', '模型返回的内容不是有效 JSON')
  }

  const checked = validatePlan(parsed)
  if (!checked.ok) {
    throw fail('解析结果', '结果结构不对：' + checked.error)
  }

  return checked.plan
}
