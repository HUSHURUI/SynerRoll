<script setup lang="ts">
import type {
  ComputeTask,
  ComputeTaskListResponse,
  DeviceFlexibilityResult,
  FlexibilityRequirementSource,
  FlexibilitySummaryResult,
  FlexibilityTaskConfig,
  FlexibilityValueSpec,
  TaskFlexibilityResponse
} from '~~/types/api'
import type { Project } from '~~/types/project'
import { useTaskApi } from '~~/composables/api/useTaskApi'
import { useTaskWebSocket } from '~~/composables/api/useTaskWebSocket'
import { useProjectApi } from '~~/composables/api/useProjectApi'
import { useToastCenter } from '~~/state/ui'
import { parseVariableKey, getVariableDisplayName } from '~~/config/component-meta'
import {
  FLEXIBILITY_REQUIREMENT_LABELS,
  FLEXIBILITY_REQUIREMENT_OPTIONS
} from '~~/config/flexibility'

definePageMeta({ title: '结果分析 - SynerRoll' })

/** "H:MM" → 分钟数 */
function tsToMinutes(ts: string): number {
  const parts = ts.split(':')
  if (parts.length < 2) return 0
  return parseInt(parts[0]!, 10) * 60 + parseInt(parts[1]!, 10)
}

function durationToMinutes(duration: string): number | null {
  const match = /^(\d+)(h|m|s)$/.exec(duration.trim())
  if (!match) return null
  const value = Number(match[1])
  if (match[2] === 'h') return value * 60
  if (match[2] === 'm') return value
  return value % 60 === 0 ? value / 60 : null
}

function minutesToTimestamp(minutes: number): string {
  const hour = Math.floor(minutes / 60)
  const minute = minutes % 60
  return `${hour}:${String(minute).padStart(2, '0')}`
}

const taskApi = useTaskApi()
const projectApi = useProjectApi()
const { connect } = useTaskWebSocket()
const { push } = useToastCenter()

// ───── 分析栏目 ─────
interface AnalysisSection {
  key: string
  label: string
  icon: string
}

const sections: AnalysisSection[] = [
  { key: 'overview', label: '运行总览', icon: '📊' },
  { key: 'energy-flow', label: '能流平衡分析', icon: '⚡' },
  { key: 'device-output', label: '设备出力分析', icon: '🔌' },
  { key: 'economy', label: '经济性分析', icon: '💰' },
  { key: 'carbon', label: '碳排放分析', icon: '🌱' },
  { key: 'stability', label: '稳定性分析', icon: '📈' },
  { key: 'flexibility', label: '系统灵活性量化评估', icon: '↕️' },
  { key: 'device-flexibility', label: '设备灵活性量化评估', icon: '⚙️' },
]

const activeSection = ref<string>('overview')

// ───── 当前选中的任务 ─────
const selectedTaskId = ref<string | null>(null)
const selectedTask = ref<ComputeTask | null>(null)
const currentProject = ref<Project | null>(null)

// ───── 任务列表弹窗 ─────
const showTaskListDialog = ref(false)

// ───── 新建任务弹窗 ─────
const showCreateDialog = ref(false)

// ───── 层名称映射 ─────
const layerNames = computed<Record<string, string>>(() => {
  if (!currentProject.value?.layerConfig?.layers) return {}
  const result: Record<string, string> = {}
  for (const layer of currentProject.value.layerConfig.layers) {
    result[layer.id] = layer.name
  }
  return result
})

// ───── 能流平衡分析 ─────
interface BusConnection {
  busLabel: string
  busCode: string
  variables: string[]
}

const connectionData = ref<BusConnection[]>([])

const loadConnectionData = async (taskId: string) => {
  try {
    const res = await taskApi.getConnection(taskId)
    connectionData.value = Array.isArray(res) ? res : []
  }
  catch (e) {
    console.warn('[EnergyFlow] loadConnectionData error:', e)
    connectionData.value = []
  }
}

// 时层选项（从 layerConfig 获取）
const layerOptions = computed(() => {
  if (!currentProject.value?.layerConfig?.layers) return []
  return currentProject.value.layerConfig.layers.map(l => ({
    value: l.id,
    label: l.name
  }))
})

// ───── 画布名称 ─────
const canvasName = computed(() => {
  if (!currentProject.value?.workspace?.canvases || !selectedTask.value) return ''
  const canvas = currentProject.value.workspace.canvases.find(c => c.id === selectedTask.value!.canvas_id)
  return canvas?.name ?? ''
})

// ───── code → 节点名称映射 ─────
// sourceId 格式: "WT_7e8a"，其中 7e8a 是节点 UUID 的前4位十六进制
const codeToLabel = computed<Record<string, string>>(() => {
  if (!currentProject.value?.workspace?.canvases) return {}
  const result: Record<string, string> = {}
  for (const canvas of currentProject.value.workspace.canvases) {
    for (const node of canvas.nodes) {
      if (node.data?.label && node.id) {
        // node.id = "node-7e8a9baa-..." → code = "7e8a"
        const code = node.id.replace('node-', '').slice(0, 4)
        result[code] = node.data.label
      }
    }
  }
  return result
})

// ───── 图表显示名称 ─────
const knownCodes = computed(() => Object.keys(codeToLabel.value))

const ELECTRIC_ENERGY_VARIABLES = new Set(['E_ES', 'E_PS', 'E_FS', 'E_CS'])

function getChartDisplayUnit(sourceId: string, varName: string, remark?: string): string {
  const sourceType = sourceId.split('_')[0] ?? ''
  if (remark === 'energy') return sourceType === 'HS' ? 'kg' : 'kWh'
  if (remark === 'hydrogen') return 'kg/h'
  if (remark === 'heat') return 'kW'
  if (remark === 'power') return sourceType === 'HS' ? 'kg/h' : 'kW'

  // 兼容后端尚未返回 remark 的历史接口响应。
  const { baseVarName } = parseVariableKey(`${sourceId}|${varName}`, knownCodes.value)
  if (ELECTRIC_ENERGY_VARIABLES.has(baseVarName)) return 'kWh'
  if (baseVarName === 'H_HS') return 'kg'
  if (baseVarName.startsWith('H_HS_') || baseVarName === 'H_HLOAD') return 'kg/h'
  return 'kW'
}

function getChartDisplayName(key: string): string {
  const { componentType, baseVarName } = parseVariableKey(key, knownCodes.value)
  const varDisplayName = getVariableDisplayName(componentType, baseVarName)

  // 从 varName 中匹配 codeToLabel 里已知的 code，获取节点名称
  const varName = key.split('|')[1] ?? ''
  let nodeName = ''
  for (const code of knownCodes.value) {
    if (varName.includes(code)) {
      nodeName = codeToLabel.value[code]!
      break
    }
  }

  if (nodeName && varDisplayName !== baseVarName) {
    return `${nodeName} - ${varDisplayName}`
  }
  if (varDisplayName !== baseVarName) {
    return varDisplayName
  }
  return key
}

// ───── 数据轮询 ─────
let wsHandle: { close: () => void; send: (m: object) => void } | null = null
const liveData = ref<Record<string, Record<string, { ts: string; value: number }[]>>>({})
const liveDataUnits = ref<Record<string, string>>({})
const liveStatus = ref<string>('')
const flexibilityData = ref<TaskFlexibilityResponse | null>(null)
const flexibilityLoading = ref(false)
const flexibilityError = ref('')

let refreshTimer: ReturnType<typeof setTimeout> | null = null
let pollingGeneration = 0

const flexibilityConfig = computed<FlexibilityTaskConfig | null>(() => {
  const config = flexibilityData.value?.config
  return config?.enabled ? config as FlexibilityTaskConfig : null
})

const FLEXIBILITY_DIRECTIONS = ['up', 'down'] as const
const FLEXIBILITY_DIRECTION_LABELS: Record<typeof FLEXIBILITY_DIRECTIONS[number], string> = {
  up: '上调',
  down: '下调'
}
const FLEXIBILITY_DIRECTION_ORDER: Record<typeof FLEXIBILITY_DIRECTIONS[number], number> = {
  up: 0,
  down: 1
}

const flexibilityPeriods = computed(() =>
  (flexibilityData.value?.periods ?? [])
    .slice()
    .sort((a, b) => {
      const timeDiff = tsToMinutes(a.timestamp) - tsToMinutes(b.timestamp)
      return timeDiff || FLEXIBILITY_DIRECTION_ORDER[a.direction] - FLEXIBILITY_DIRECTION_ORDER[b.direction]
    })
)

interface DeviceFlexibilityGroup {
  key: string
  deviceId: string
  deviceType: string
  label: string
  boundary: boolean
  rows: DeviceFlexibilityResult[]
}

const DEVICE_TYPE_LABELS: Record<string, string> = {
  WT: '风机',
  PV: '光伏',
  CP: '燃煤机组',
  GP: '气电机组',
  CHP: '热电联产',
  ET: '电解槽',
  ELOAD: '电负荷',
  HLOAD: '氢负荷',
  QLOAD: '热负荷',
  ES: '电化学储能',
  HS: '储氢设备',
  FS: '飞轮储能',
  CS: '压缩空气储能',
  PS: '抽水蓄能',
  HYDRO: '常规水电',
  GRID: '电网'
}

const deviceFlexibilityGroups = computed<DeviceFlexibilityGroup[]>(() => {
  const groups = new Map<string, DeviceFlexibilityGroup>()

  const addRow = (row: DeviceFlexibilityResult, boundary = false) => {
    const key = `${row.device_type}:${row.device_id}`
    let group = groups.get(key)
    if (!group) {
      const nodeLabel = codeToLabel.value[row.device_id]
      group = {
        key,
        deviceId: row.device_id,
        deviceType: row.device_type,
        label: nodeLabel || DEVICE_TYPE_LABELS[row.device_type] || `${row.device_type} ${row.device_id}`,
        boundary,
        rows: []
      }
      groups.set(key, group)
    }
    group.rows.push(row)
  }

  for (const period of flexibilityPeriods.value) {
    for (const row of period.device_results ?? []) addRow(row)
    if (period.boundary_result) addRow(period.boundary_result, true)
  }

  const canvas = currentProject.value?.workspace.canvases.find(
    item => item.id === selectedTask.value?.canvas_id
  )
  const order = new Map<string, number>()
  for (const [index, node] of (canvas?.nodes ?? []).entries()) {
    const code = node.id.replace('node-', '').slice(0, 4)
    order.set(`${node.data.componentKey}:${code}`, index)
  }

  return [...groups.values()]
    .map(group => ({
      ...group,
      rows: group.rows.slice().sort((a, b) => {
        const timeDiff = tsToMinutes(a.timestamp) - tsToMinutes(b.timestamp)
        return timeDiff || a.direction.localeCompare(b.direction)
      })
    }))
    .sort((a, b) => (order.get(a.key) ?? Number.MAX_SAFE_INTEGER) - (order.get(b.key) ?? Number.MAX_SAFE_INTEGER)
      || a.key.localeCompare(b.key))
})

const flexibilityPoiLimits = computed(() => {
  const upward = flexibilityPeriods.value.find(row => row.direction === 'up')
  const downward = flexibilityPeriods.value.find(row => row.direction === 'down')
  const maximum = upward?.poi_power_limit == null ? Number.NaN : Number(upward.poi_power_limit)
  const minimum = downward?.poi_power_limit == null ? Number.NaN : Number(downward.poi_power_limit)
  return {
    maximum: Number.isFinite(maximum) ? maximum : null,
    minimum: Number.isFinite(minimum) ? minimum : null
  }
})

const directionSummary = (direction: 'up' | 'down'): FlexibilitySummaryResult | undefined =>
  flexibilityData.value?.summaries.find(row => row.direction === direction)

const formatFlexValue = (value: unknown, digits = 2): string => {
  const numeric = Number(value)
  return Number.isFinite(numeric) ? numeric.toFixed(digits) : '--'
}

const formatFlexPercent = (value: unknown): string => {
  const numeric = Number(value)
  return Number.isFinite(numeric) ? `${(numeric * 100).toFixed(1)}%` : '--'
}

const reloadFlexibility = async (taskId: string, options: { silent?: boolean } = {}) => {
  if (!options.silent) {
    flexibilityLoading.value = true
    flexibilityError.value = ''
  }
  try {
    const data = await taskApi.getFlexibility(taskId)
    if (selectedTaskId.value !== taskId) return
    flexibilityData.value = data
    flexibilityError.value = ''
  }
  catch (error) {
    if (selectedTaskId.value !== taskId) return
    if (!options.silent || !flexibilityData.value) {
      flexibilityData.value = null
      flexibilityError.value = error instanceof Error ? error.message : String(error)
    }
    else {
      console.warn('[Poll] reloadFlexibility error:', error)
    }
  }
  finally {
    if (!options.silent && selectedTaskId.value === taskId) {
      flexibilityLoading.value = false
    }
  }
}

const reloadLiveData = async (taskId: string) => {
  try {
    const data = await taskApi.getData(taskId)
    const rows = data?.rows ?? []
    if (rows.length) {
      const merged: Record<string, Record<string, { ts: string; value: number }[]>> = {}
      const units: Record<string, string> = {}
      for (const row of rows) {
        const key = `${row.sourceId}|${row.varName}`
        units[key] = getChartDisplayUnit(row.sourceId, row.varName, row.remark)
        const lid = row.layerId ?? '1'
        if (!merged[key]) merged[key] = {}
        if (!merged[key][lid]) merged[key][lid] = []
        merged[key][lid]!.push({ ts: String(row.ts), value: Math.abs(Number(row.value)) })
      }
      for (const key of Object.keys(merged)) {
        for (const lid of Object.keys(merged[key]!)) {
          merged[key]![lid]!.sort((a, b) => tsToMinutes(a.ts) - tsToMinutes(b.ts))
        }
      }
      liveData.value = merged
      liveDataUnits.value = units
    }
  }
  catch (e) { console.warn('[Poll] reloadLiveData error:', e) }
}

const startPolling = (taskId: string) => {
  stopPolling()
  const generation = pollingGeneration
  let pending = false
  const reloadResults = () => Promise.all([
    reloadLiveData(taskId),
    reloadFlexibility(taskId, { silent: true })
  ])
  const poll = async () => {
    if (pending) return
    pending = true
    let shouldStop = false
    try {
      await reloadResults()
      try {
        const task = await taskApi.getState(taskId)
        if (task) {
          liveStatus.value = task.status
          if (selectedTaskId.value === taskId) selectedTask.value = task
          if (['completed', 'failed', 'cancelled'].includes(task.status)) {
            // 状态与结果写入可能恰好跨过本轮请求，再拉一次确保最终结果完整。
            await reloadResults()
            shouldStop = true
            return
          }
        }
      }
      catch { /* 静默 */ }
    }
    catch { /* 静默 */ }
    finally {
      pending = false
      if (!shouldStop && generation === pollingGeneration && selectedTaskId.value === taskId) {
        refreshTimer = setTimeout(poll, 500) // 前端刷新渲染速度
      }
    }
  }
  void poll()
}

const stopPolling = () => {
  pollingGeneration += 1
  if (refreshTimer) {
    clearTimeout(refreshTimer)
    refreshTimer = null
  }
}

const unsubscribeTask = () => {
  stopPolling()
  if (wsHandle) {
    wsHandle.close()
    wsHandle = null
  }
}

const subscribeTask = (taskId: string) => {
  unsubscribeTask()
  liveData.value = {}
  liveDataUnits.value = {}
  liveStatus.value = ''
  flexibilityData.value = null
  flexibilityError.value = ''

  wsHandle = connect(taskId, (evt) => {
    if (evt.type === 'status') {
      liveStatus.value = evt.status
      if (selectedTask.value?.id === taskId) {
        selectedTask.value = { ...selectedTask.value, status: evt.status as ComputeTask['status'] }
      }
    }
    else if (evt.type === 'flexibility' || evt.type === 'flexibility_summary') {
      void reloadFlexibility(taskId, { silent: true })
    }
    else if (evt.type === 'completed' || evt.type === 'failed' || evt.type === 'cancelled') {
      if (selectedTask.value?.id === taskId) {
        selectedTask.value = { ...selectedTask.value, status: evt.type }
      }
      void reloadLiveData(taskId)
      void reloadFlexibility(taskId, { silent: true })
      stopPolling()
    }
  })
}

// ───── 加载项目详情 ─────
const loadProject = async (projectId: string) => {
  try {
    const res = await projectApi.getProject(projectId)
    currentProject.value = res.project
  }
  catch (e) {
    console.warn('[Result] loadProject error:', e)
    currentProject.value = null
  }
}

// ───── 选中任务 ─────
const selectTask = async (taskId: string) => {
  selectedTaskId.value = taskId
  showTaskListDialog.value = false

  // 获取任务详情
  try {
    selectedTask.value = await taskApi.getState(taskId)
    if (selectedTask.value?.project_id) {
      await loadProject(selectedTask.value.project_id)
    }
  }
  catch (e) {
    console.warn('[Result] get task state error:', e)
    selectedTask.value = null
  }

  // 加载总线连接数据（能流平衡分析用）
  await loadConnectionData(taskId)

  subscribeTask(taskId)
  await reloadFlexibility(taskId)
  startPolling(taskId)
}

watch(activeSection, (section) => {
  if ((section === 'flexibility' || section === 'device-flexibility') && selectedTaskId.value) {
    void reloadFlexibility(selectedTaskId.value)
  }
})

onBeforeUnmount(() => unsubscribeTask())

// ───── 任务列表数据 ─────
const { data: taskListData, refresh: refreshTaskList } = await useAsyncData<ComputeTaskListResponse>(
  'task-list',
  () => taskApi.listTasks()
)
const taskList = computed(() => taskListData.value?.tasks ?? [])

const refreshList = async () => { await refreshTaskList() }

// ───── 状态展示辅助 ─────
const STATUS_LABEL: Record<string, string> = {
  pending: '待启动',
  parsing: '解析中',
  building: '构建中',
  solving: '求解中',
  completed: '已完成',
  failed: '失败',
  cancelled: '已取消'
}

const STATUS_TONE: Record<string, string> = {
  pending: 'neutral',
  parsing: 'primary',
  building: 'primary',
  solving: 'primary',
  completed: 'success',
  failed: 'danger',
  cancelled: 'warning'
}

const showActions = (t: ComputeTask) => ({
  cancel: ['pending', 'parsing', 'building', 'solving'].includes(t.status),
  cleanup: ['completed', 'failed', 'cancelled'].includes(t.status)
})

const doAction = async (action: 'cancel' | 'cleanup', taskId: string) => {
  try {
    if (action === 'cleanup') {
      if (!confirm('确认清理该任务？数据将被永久删除。')) return
      await taskApi.cleanup(taskId)
      push({ tone: 'success', title: '任务已清理' })
      if (selectedTaskId.value === taskId) {
        unsubscribeTask()
        selectedTaskId.value = null
        selectedTask.value = null
      }
    }
    else if (action === 'cancel') {
      if (!confirm('确认取消该任务？')) return
      await taskApi.cancel(taskId)
      push({ tone: 'success', title: '已发送取消信号' })
    }
    await refreshList()
  }
  catch (err) {
    push({ tone: 'danger', title: `${action} 失败`, description: String(err) })
  }
}

// ───── 新建任务 ─────
const route = useRoute()
const initialProjectId = (route.query.projectId as string) || ''
const initialCanvasId = (route.query.canvasId as string) || ''

type FlexibilityValueMode = 'constant' | 'manual' | 'file' | 'boundary'

interface CreationBoundarySeriesOption {
  value: string
  label: string
  timestamps: string[]
  values: number[]
  source: 'database' | 'project'
}

const newTask = reactive({
  projectId: initialProjectId,
  canvasId: initialCanvasId,
  layerId: '1',
  mode: 'offline' as 'offline' | 'online',
  simStartTime: '0:00',
  simEndTime: '24:00',
  name: '',
  poiId: '',
  requirementSource: 'net_load_change' as FlexibilityRequirementSource,
  flexibilityValueMode: 'constant' as FlexibilityValueMode,
  targetPoiPowerKw: 0,
  upwardRequirementKw: 0,
  downwardRequirementKw: 0,
  targetPoiPowerSeries: { default: 0 } as Record<string, number>,
  upwardRequirementSeries: { default: 0 } as Record<string, number>,
  downwardRequirementSeries: { default: 0 } as Record<string, number>
})

const creationProject = ref<Project | null>(null)
const creationProjectLoading = ref(false)
const creationProjectError = ref('')
const boundarySeriesOptions = ref<CreationBoundarySeriesOption[]>([])
const boundarySeriesLoading = ref(false)
const boundarySeriesWarning = ref('')
const seriesValidationErrors = reactive({ target: '', upward: '', downward: '' })

const creationCanvasOptions = computed(() => creationProject.value?.workspace.canvases ?? [])
const creationLayerOptions = computed(() => creationProject.value?.layerConfig.layers ?? [])
const creationCanvas = computed(() =>
  creationCanvasOptions.value.find(canvas => canvas.id === newTask.canvasId) ?? creationCanvasOptions.value[0]
)

const finiteGridNumber = (value: unknown, fallback: number): number => {
  const numeric = Number(value)
  return Number.isFinite(numeric) ? numeric : fallback
}

const creationGridOptions = computed(() =>
  (creationCanvas.value?.nodes ?? [])
    .filter(node => node.data?.componentKey === 'GRID')
    .map(node => {
      const params = node.data?.business?.commonTechParams ?? {}
      const capacityKw = Math.max(0, finiteGridNumber(params.capacity, 0))
      const sellRatio = Math.max(0, finiteGridNumber(params.sell_ratio, 1))
      const buyRatio = Math.max(0, finiteGridNumber(params.buy_ratio, 1))
      const code = node.id.replace(/^node-/, '').slice(0, 4)
      return {
        value: code,
        label: `${node.data?.label ?? '电网接口'} (${code})`,
        capacityKw,
        sellRatio,
        buyRatio,
        maximumPoiPowerKw: capacityKw * sellRatio,
        minimumPoiPowerKw: -capacityKw * buyRatio
      }
    })
)

const selectedGridOption = computed(() =>
  creationGridOptions.value.find(option => option.value === newTask.poiId) ?? creationGridOptions.value[0] ?? null
)

const isIslandedFlexibility = computed(() => creationGridOptions.value.length === 0)

// 灵活性评价固定采用项目配置中的最底层时层。
const flexibilityEvaluationLayer = computed(() =>
  creationLayerOptions.value[creationLayerOptions.value.length - 1]
)
const flexibilityEvaluationLayerId = computed(() =>
  flexibilityEvaluationLayer.value?.id ?? newTask.layerId
)

// 与 simulation_runner._flexibility_evaluation_timestamps 保持一致：周前层按 length，
// 其他层按 forward 形成评价窗口，并受任务结束时间截断。
const expectedFlexibilityTimestamps = computed<string[]>(() => {
  const layer = flexibilityEvaluationLayer.value
  if (!layer) return []
  const startMatch = /^(\d+):(\d{1,2})$/.exec(newTask.simStartTime.trim())
  if (!startMatch || Number(startMatch[2]) >= 60) return []
  const startMinutes = Number(startMatch[1]) * 60 + Number(startMatch[2])
  const stepMinutes = durationToMinutes(layer.step)
  const durationMinutes = durationToMinutes(String(layer.id) === '1' ? layer.length : layer.forward)
  if (!stepMinutes || !durationMinutes || durationMinutes % stepMinutes !== 0) return []

  const endMatch = /^(\d+):(\d{1,2})$/.exec(newTask.simEndTime.trim())
  const endMinutes = endMatch && Number(endMatch[2]) < 60
    ? Number(endMatch[1]) * 60 + Number(endMatch[2])
    : null
  const timestamps: string[] = []
  for (let offset = 0; offset < durationMinutes; offset += stepMinutes) {
    const timestampMinutes = startMinutes + offset
    if (endMinutes !== null && timestampMinutes + stepMinutes > endMinutes) break
    timestamps.push(minutesToTimestamp(timestampMinutes))
  }
  return timestamps
})

const expectedRequirementTimestamps = computed(() => {
  if (newTask.requirementSource !== 'agc_or_schedule') return expectedFlexibilityTimestamps.value
  const stepMinutes = durationToMinutes(flexibilityEvaluationLayer.value?.step ?? '')
  if (!stepMinutes) return []
  return expectedFlexibilityTimestamps.value.map(timestamp =>
    minutesToTimestamp(tsToMinutes(timestamp) + stepMinutes)
  )
})

const availableRequirementOptions = computed(() =>
  isIslandedFlexibility.value
    ? FLEXIBILITY_REQUIREMENT_OPTIONS.filter(option => option.value !== 'agc_or_schedule')
    : FLEXIBILITY_REQUIREMENT_OPTIONS
)

const formatBoundaryPower = (value: number): string =>
  `${new Intl.NumberFormat('zh-CN', { maximumFractionDigits: 2 }).format(value)} kW`

const openGridConfiguration = () => {
  if (!newTask.projectId) return
  showCreateDialog.value = false
  void navigateTo(`/editor/${newTask.projectId}`)
}

const syncCreationSelections = () => {
  if (creationCanvasOptions.value.length && !creationCanvasOptions.value.some(canvas => canvas.id === newTask.canvasId)) {
    newTask.canvasId = creationCanvasOptions.value[0]!.id
  }
  if (creationLayerOptions.value.length && !creationLayerOptions.value.some(layer => layer.id === newTask.layerId)) {
    newTask.layerId = creationLayerOptions.value[0]!.id
  }
  if (!creationGridOptions.value.some(option => option.value === newTask.poiId)) {
    newTask.poiId = creationGridOptions.value[0]?.value ?? ''
  }
}

const loadCreationProject = async (projectId: string) => {
  creationProject.value = null
  creationProjectError.value = ''
  if (!projectId.trim()) return
  creationProjectLoading.value = true
  try {
    const response = await projectApi.getProject(projectId.trim())
    creationProject.value = response.project
    syncCreationSelections()
  }
  catch (error) {
    creationProjectError.value = error instanceof Error ? error.message : String(error)
  }
  finally {
    creationProjectLoading.value = false
  }
}

const boundarySeriesCandidates = computed(() =>
  (creationProject.value?.boundaries ?? []).filter(boundary =>
    boundary.meaning === 'power' || /计划|AGC|目标|调度/i.test(boundary.name)
  )
)

const cachedBoundarySeriesOptions = (): CreationBoundarySeriesOption[] => {
  const layerId = flexibilityEvaluationLayerId.value
  const options: CreationBoundarySeriesOption[] = []
  for (const boundary of boundarySeriesCandidates.value) {
    const layer = boundary.transformedData?.layers.find(item => String(item.layerId) === String(layerId))
    if (!layer?.timestamps.length || layer.timestamps.length !== layer.values.length) continue
    options.push({
      value: `${boundary.id}:${layerId}`,
      label: `${boundary.name} · ${layer.layerName}（项目缓存）`,
      timestamps: layer.timestamps.map(String),
      values: layer.values.map(Number),
      source: 'project'
    })
  }
  return options
}

const refreshBoundarySeriesOptions = async () => {
  const projectId = newTask.projectId.trim()
  const layerId = flexibilityEvaluationLayerId.value
  const candidates = boundarySeriesCandidates.value
  boundarySeriesOptions.value = cachedBoundarySeriesOptions()
  boundarySeriesWarning.value = ''
  if (!projectId || !layerId || !candidates.length) return

  boundarySeriesLoading.value = true
  try {
    const response = await $fetch<{
      success: boolean
      data?: {
        boundaries: Array<{
          boundaryId?: string
          layerId: string
          found: boolean
          values?: number[]
          timestamps?: string[]
        }>
      }
    }>('/api/v1/boundary/load', {
      method: 'POST',
      body: {
        projectId,
        boundaries: candidates.map(boundary => ({
          layerId,
          meaning: boundary.meaning,
          boundaryId: boundary.id
        }))
      }
    })
    const databaseOptions: CreationBoundarySeriesOption[] = []
    for (let index = 0; index < (response.data?.boundaries ?? []).length; index++) {
      const item = response.data!.boundaries[index]!
      if (!item.found || !item.timestamps?.length || item.timestamps.length !== item.values?.length) continue
      const boundaryId = item.boundaryId || candidates[index]?.id
      const boundary = candidates.find(candidate => candidate.id === boundaryId)
      if (!boundary || !boundaryId) continue
      databaseOptions.push({
        value: `${boundaryId}:${layerId}`,
        label: `${boundary.name} · ${creationLayerOptions.value.find(layer => String(layer.id) === String(layerId))?.name ?? `时层${layerId}`}（边界数据库）`,
        timestamps: item.timestamps.map(String),
        values: item.values!.map(Number),
        source: 'database'
      })
    }
    const databaseIds = new Set(databaseOptions.map(option => option.value))
    boundarySeriesOptions.value = [
      ...databaseOptions,
      ...boundarySeriesOptions.value.filter(option => !databaseIds.has(option.value))
    ]
  }
  catch {
    if (boundarySeriesOptions.value.length) {
      boundarySeriesWarning.value = '边界数据库暂不可用，当前使用项目中保存的同层缓存。'
    }
    else {
      boundarySeriesWarning.value = '边界数据库暂不可用，且项目中没有该时层的缓存曲线。'
    }
  }
  finally {
    boundarySeriesLoading.value = false
  }
}

watch(() => newTask.canvasId, () => {
  if (!creationGridOptions.value.some(option => option.value === newTask.poiId)) {
    newTask.poiId = creationGridOptions.value[0]?.value ?? ''
  }
})

watch(isIslandedFlexibility, (isIslanded) => {
  if (!isIslanded) return
  newTask.poiId = ''
  if (newTask.requirementSource === 'agc_or_schedule') newTask.requirementSource = 'net_load_change'
})

watch(
  [() => newTask.flexibilityValueMode, () => flexibilityEvaluationLayerId.value],
  ([mode]) => {
    if (mode === 'boundary') void refreshBoundarySeriesOptions()
  }
)

watch(showCreateDialog, async (open) => {
  if (open) {
    newTask.projectId = initialProjectId || selectedTask.value?.project_id || newTask.projectId
    newTask.canvasId = initialCanvasId || selectedTask.value?.canvas_id || newTask.canvasId
    await loadCreationProject(newTask.projectId)
  }
})

onMounted(async () => {
  if (route.query.create === '1') {
    showCreateDialog.value = true
  }
  // 如果有 initialProjectId，预加载项目信息（用于返回按钮）
  if (initialProjectId && !currentProject.value) {
    await loadProject(initialProjectId)
  }
})

const parseFlexibilityValueSpec = (
  constantValue: number,
  seriesValue: Record<string, number>,
  fieldLabel: string,
  nonnegative: boolean
): FlexibilityValueSpec => {
  if (newTask.flexibilityValueMode === 'constant') {
    const value = Number(constantValue)
    if (!Number.isFinite(value) || (nonnegative && value < 0)) {
      throw new Error(`${fieldLabel}必须是${nonnegative ? '非负' : ''}有限数值`)
    }
    return value
  }

  if (!seriesValue || Object.keys(seriesValue).length === 0) {
    throw new Error(`${fieldLabel}的分时数据必须是非空的时间戳对象`)
  }

  const result: Record<string, number> = {}
  for (const [timestamp, rawValue] of Object.entries(seriesValue)) {
    const value = Number(rawValue)
    if (!Number.isFinite(value) || (nonnegative && value < 0)) {
      throw new Error(`${fieldLabel}在 ${timestamp} 的值必须是${nonnegative ? '非负' : ''}有限数值`)
    }
    result[timestamp] = value
  }
  return result
}

const buildFlexibilityTaskConfig = (): FlexibilityTaskConfig => {
  const islanded = isIslandedFlexibility.value
  if (!islanded && creationGridOptions.value.length > 1 && !newTask.poiId) {
    throw new Error('当前画布存在多个电网接口，请选择本次评价使用的并网点')
  }
  if (islanded && newTask.requirementSource === 'agc_or_schedule') {
    throw new Error('离网系统没有并网点，不能使用计划/AGC目标作为需求来源')
  }

  const config: FlexibilityTaskConfig = {
    enabled: true,
    layerId: flexibilityEvaluationLayerId.value,
    // 后端兼容字段；当前优化模型始终采用经济运行基准，不再向用户暴露无效选项。
    operationMode: 'economic_operation',
    networkMode: islanded ? 'islanded' : 'grid_connected',
    boundaryCondition: islanded ? 'islanded_local_balance' : 'grid_component_limits',
    poiId: islanded ? null : (newTask.poiId || null),
    requirementSource: newTask.requirementSource
  }

  if (newTask.requirementSource === 'agc_or_schedule') {
    if (newTask.flexibilityValueMode !== 'constant' && seriesValidationErrors.target) {
      throw new Error(seriesValidationErrors.target)
    }
    config.targetPoiPowerKw = parseFlexibilityValueSpec(
      newTask.targetPoiPowerKw,
      newTask.targetPoiPowerSeries,
      '目标并网功率',
      false
    )
  }
  else if (newTask.requirementSource === 'user_defined') {
    if (newTask.flexibilityValueMode !== 'constant') {
      if (seriesValidationErrors.upward) throw new Error(seriesValidationErrors.upward)
      if (seriesValidationErrors.downward) throw new Error(seriesValidationErrors.downward)
    }
    config.upwardRequirementKw = parseFlexibilityValueSpec(
      newTask.upwardRequirementKw,
      newTask.upwardRequirementSeries,
      '上调需求',
      true
    )
    config.downwardRequirementKw = parseFlexibilityValueSpec(
      newTask.downwardRequirementKw,
      newTask.downwardRequirementSeries,
      '下调需求',
      true
    )
  }
  return config
}

const createTask = async () => {
  if (!newTask.projectId) {
    push({ tone: 'warning', title: '请填写 projectId' })
    return
  }
  try {
    const flexibility = buildFlexibilityTaskConfig()
    const res = await taskApi.createTask({
      projectId: newTask.projectId,
      canvasId: newTask.canvasId,
      layerId: newTask.layerId,
      mode: newTask.mode,
      simStartTime: newTask.simStartTime,
      simEndTime: newTask.simEndTime || null,
      name: newTask.name || null,
      flexibility
    })
    push({ tone: 'success', title: '任务已创建' })
    showCreateDialog.value = false
    await refreshList()
    await selectTask(res.id)
    activeSection.value = 'flexibility'
  }
  catch (err) {
    push({ tone: 'danger', title: '创建任务失败', description: String(err) })
  }
}
</script>

<template>
  <div class="h-screen flex flex-col bg-app-bg">
    <!-- 头部 -->
    <header class="flex items-center h-14 px-4 bg-primary text-white">
      <button
        class="inline-flex items-center gap-1 px-3 h-8 rounded text-sm hover:bg-white/10"
        @click="() => {
          const pid = currentProject?.id || selectedTask?.project_id || initialProjectId
          navigateTo(pid ? `/editor/${pid}` : '/project')
        }"
      >← 返回</button>
      <h1 class="ml-4 text-base font-medium">结果分析</h1>
      <div class="ml-auto flex items-center gap-2">
        <AppButton
          label="任务列表"
          tone="ghost"
          size="sm"
          @click="showTaskListDialog = true"
        />
        <AppButton
          label="新建任务"
          tone="neutral"
          size="sm"
          @click="showCreateDialog = true"
        />
      </div>
    </header>

    <div class="flex-1 min-h-0 flex gap-2 p-2">
      <!-- 左：分析栏目导航 -->
      <aside class="panel-card w-56 flex flex-col">
        <div class="flex items-center px-3 h-12 border-b border-app-border">
          <span class="text-sm font-medium">仿真结果分析</span>
        </div>

        <div class="flex-1 overflow-y-auto">
          <div
            v-for="section in sections"
            :key="section.key"
            class="flex items-center px-3 h-11 cursor-pointer transition-colors"
            :class="activeSection === section.key ? 'bg-primary-soft' : 'hover:bg-app-panel-soft'"
            @click="activeSection = section.key"
          >
            <span class="mr-2 text-sm">{{ section.icon }}</span>
            <span class="flex-1 text-sm truncate">{{ section.label }}</span>
          </div>
        </div>
      </aside>

      <!-- 右：内容区 -->
      <main class="flex-1 panel-card flex flex-col min-h-0 p-3">
        <!-- 未选中任务 -->
        <div v-if="!selectedTask" class="flex-1 flex flex-col items-center justify-center text-app-muted text-sm gap-4">
          <div>请先选择一个计算任务</div>
          <AppButton label="选择任务" tone="primary" size="sm" @click="showTaskListDialog = true" />
        </div>

        <!-- 已选中任务 -->
        <div v-else class="flex-1 flex flex-col min-h-0">
          <!-- 任务信息栏 -->
          <div class="flex items-center justify-between mb-3 pb-3 border-b border-app-border">
            <div>
              <div class="text-sm font-medium">
                {{ currentProject?.name ?? selectedTask.project_id }}
                <span v-if="canvasName" class="text-app-muted"> - {{ canvasName }}</span>
              </div>
              <div class="text-xs mt-1 text-app-muted">
                任务: {{ selectedTask.name ?? selectedTask.id.slice(0, 8) }}
                <span class="ml-2">模式: {{ selectedTask.mode === 'offline' ? '离线' : '在线' }}</span>
              </div>
            </div>
            <div class="flex items-center gap-2">
              <span
                class="px-2 py-0.5 rounded text-xs"
                :class="`bg-${STATUS_TONE[selectedTask.status]}-soft text-${STATUS_TONE[selectedTask.status]}`"
              >{{ STATUS_LABEL[selectedTask.status] }}</span>
              <AppButton
                v-if="showActions(selectedTask).cancel"
                label="取消"
                size="sm"
                tone="danger"
                @click="doAction('cancel', selectedTask!.id)"
              />
              <AppButton
                v-if="showActions(selectedTask).cleanup"
                label="清理"
                size="sm"
                tone="ghost"
                @click="doAction('cleanup', selectedTask!.id)"
              />
            </div>
          </div>

          <!-- 运行总览 -->
          <div v-if="activeSection === 'overview'" class="flex-1 min-h-0 overflow-y-auto">
            <div
              v-if="Object.keys(liveData).length === 0"
              class="flex items-center justify-center h-full text-app-muted text-sm"
            >
              等待任务数据...
            </div>
            <div v-else class="grid grid-cols-2 gap-3">
              <div
                v-for="(layers, key) in liveData"
                :key="key"
                class="border border-app-border rounded p-2"
              >
                <TaskSeriesChart
                  :layers="layers"
                  :title="getChartDisplayName(String(key))"
                  :unit="liveDataUnits[String(key)] ?? 'kW'"
                  :layer-names="layerNames"
                />
              </div>
            </div>
          </div>

          <!-- 系统灵活性量化评估 -->
          <div v-else-if="activeSection === 'flexibility'" class="flex-1 min-h-0 overflow-y-auto">
            <div v-if="flexibilityLoading" class="flex h-full items-center justify-center text-sm text-app-muted">
              正在加载灵活性评价结果...
            </div>

            <div v-else-if="flexibilityError" class="flex h-full flex-col items-center justify-center gap-3 text-sm">
              <div class="max-w-xl rounded-[12px] border border-app-danger/30 bg-red-50 px-5 py-4 text-app-danger">
                {{ flexibilityError }}
              </div>
              <AppButton label="重新加载" tone="primary" size="sm" @click="reloadFlexibility(selectedTask!.id)" />
            </div>

            <div v-else-if="!flexibilityConfig" class="flex h-full flex-col items-center justify-center gap-2 text-center">
              <div class="inline-flex h-12 w-12 items-center justify-center rounded-full bg-app-panel-soft text-2xl">↕️</div>
              <p class="text-sm font-medium text-app-text">该历史任务未包含灵活性量化评估</p>
              <p class="max-w-md text-xs leading-5 text-app-muted">
                请新建计算任务；新任务将默认执行灵活性量化评估。
              </p>
            </div>

            <div v-else class="space-y-3">
              <section class="rounded-[12px] border border-app-border bg-app-panel-soft/60 px-4 py-3">
                <div class="flex flex-wrap items-center justify-between gap-2">
                  <div>
                    <h2 class="text-sm font-semibold text-app-text">评价口径</h2>
                    <p class="mt-0.5 text-xs text-app-muted">任务配置会随结果保存，便于复核不同算例口径。</p>
                  </div>
                  <span class="rounded-full bg-green-50 px-3 py-1 text-xs font-medium text-green-700">已启用</span>
                </div>
                <div class="mt-2 grid gap-2 text-xs sm:grid-cols-2 xl:grid-cols-3">
                  <div class="rounded-lg bg-white px-3 py-1.5">
                    <div class="text-app-muted">需求来源</div>
                    <div class="mt-0.5 font-medium text-app-text">{{ FLEXIBILITY_REQUIREMENT_LABELS[flexibilityConfig.requirementSource] ?? flexibilityConfig.requirementSource }}</div>
                  </div>
                  <div class="rounded-lg bg-white px-3 py-1.5">
                    <div class="text-app-muted">网络口径</div>
                    <div class="mt-0.5 font-medium text-app-text">{{ flexibilityConfig.networkMode === 'islanded' ? '离网本地平衡' : '并网 POI' }}</div>
                  </div>
                  <div class="rounded-lg bg-white px-3 py-1.5">
                    <div class="text-app-muted">{{ flexibilityConfig.networkMode === 'islanded' ? '系统边界' : 'GRID功率边界' }}</div>
                    <div v-if="flexibilityConfig.networkMode === 'islanded'" class="mt-0.5 font-medium text-app-text">无外部交换，内部资源承担平衡</div>
                    <div v-else class="mt-0.5 font-medium text-app-text">
                      {{ flexibilityPoiLimits.minimum == null ? '--' : formatBoundaryPower(flexibilityPoiLimits.minimum) }}
                      ～
                      {{ flexibilityPoiLimits.maximum == null ? '--' : formatBoundaryPower(flexibilityPoiLimits.maximum) }}
                    </div>
                  </div>
                </div>
              </section>

              <section v-if="flexibilityData?.summaries.length" class="grid gap-3 xl:grid-cols-2">
                <div
                  v-for="direction in FLEXIBILITY_DIRECTIONS"
                  :key="direction"
                  class="rounded-[12px] border border-app-border bg-white p-4"
                >
                  <div class="mb-3 flex items-center justify-between">
                    <h3 class="text-sm font-semibold text-app-text">{{ FLEXIBILITY_DIRECTION_LABELS[direction] }}全时域指标</h3>
                    <span
                      class="rounded-full px-2 py-1 text-[11px]"
                      :class="(directionSummary(direction)?.adequate_period_ratio ?? 0) >= 1 ? 'bg-green-50 text-green-700' : 'bg-orange-50 text-orange-700'"
                    >
                      达标 {{ formatFlexPercent(directionSummary(direction)?.adequate_period_ratio) }}
                    </span>
                  </div>
                  <div class="grid grid-cols-2 gap-2 lg:grid-cols-4">
                    <div class="rounded-lg bg-app-panel-soft px-3 py-3">
                      <div class="text-[11px] text-app-muted">全时域最小裕度</div>
                      <div class="mt-1 text-base font-semibold text-app-text">{{ formatFlexValue(directionSummary(direction)?.minimum_margin) }} <span class="text-[10px] font-normal text-app-muted">kW</span></div>
                    </div>
                    <div class="rounded-lg bg-app-panel-soft px-3 py-3">
                      <div class="text-[11px] text-app-muted">最大缺额</div>
                      <div class="mt-1 text-base font-semibold text-app-text">{{ formatFlexValue(directionSummary(direction)?.maximum_deficit) }} <span class="text-[10px] font-normal text-app-muted">kW</span></div>
                    </div>
                    <div class="rounded-lg bg-app-panel-soft px-3 py-3">
                      <div class="text-[11px] text-app-muted">缺额电量</div>
                      <div class="mt-1 text-base font-semibold text-app-text">{{ formatFlexValue(directionSummary(direction)?.deficit_energy) }} <span class="text-[10px] font-normal text-app-muted">kWh</span></div>
                    </div>
                    <div class="rounded-lg bg-app-panel-soft px-3 py-3">
                      <div class="text-[11px] text-app-muted">达标时段比例</div>
                      <div class="mt-1 text-base font-semibold text-app-text">{{ formatFlexPercent(directionSummary(direction)?.adequate_period_ratio) }}</div>
                    </div>
                  </div>
                </div>
              </section>

              <div v-if="flexibilityPeriods.length" class="grid gap-3">
                <FlexibilitySeriesChart
                  :rows="flexibilityPeriods"
                  :device-labels="codeToLabel"
                  direction="up"
                />
                <FlexibilitySeriesChart
                  :rows="flexibilityPeriods"
                  :device-labels="codeToLabel"
                  direction="down"
                />
              </div>

              <div v-if="!flexibilityPeriods.length" class="flex min-h-52 items-center justify-center rounded-[12px] border border-dashed border-app-border text-sm text-app-muted">
                {{ selectedTask.status === 'completed' ? '任务已完成，但暂无灵活性评价结果。' : '任务运行中，正在等待灵活性逐时段结果...' }}
              </div>
            </div>
          </div>

          <!-- 设备灵活性量化评估 -->
          <div v-else-if="activeSection === 'device-flexibility'" class="flex-1 min-h-0 overflow-y-auto">
            <div v-if="flexibilityLoading" class="flex h-full items-center justify-center text-sm text-app-muted">
              正在加载设备灵活性评价结果...
            </div>

            <div v-else-if="flexibilityError" class="flex h-full flex-col items-center justify-center gap-3 text-sm">
              <div class="max-w-xl rounded-[12px] border border-app-danger/30 bg-red-50 px-5 py-4 text-app-danger">
                {{ flexibilityError }}
              </div>
              <AppButton label="重新加载" tone="primary" size="sm" @click="reloadFlexibility(selectedTask!.id)" />
            </div>

            <div v-else-if="!flexibilityConfig" class="flex h-full flex-col items-center justify-center gap-2 text-center">
              <div class="inline-flex h-12 w-12 items-center justify-center rounded-full bg-app-panel-soft text-2xl">⚙️</div>
              <p class="text-sm font-medium text-app-text">该历史任务未包含灵活性量化评估</p>
              <p class="max-w-md text-xs leading-5 text-app-muted">
                新任务会默认生成系统汇总和各设备灵活性明细。
              </p>
            </div>

            <div v-else-if="deviceFlexibilityGroups.length" class="space-y-3">
              <DeviceFlexibilityChart
                v-for="device in deviceFlexibilityGroups"
                :key="device.key"
                :title="device.label"
                :device-type="device.deviceType"
                :rows="device.rows"
                :boundary="device.boundary"
              />
            </div>

            <div v-else class="flex min-h-52 items-center justify-center rounded-[12px] border border-dashed border-app-border text-sm text-app-muted">
              {{ selectedTask.status === 'completed' ? '任务已完成，但暂无设备灵活性评价结果。' : '任务运行中，正在等待设备灵活性结果...' }}
            </div>
          </div>

          <!-- 能流平衡分析 -->
          <div v-else-if="activeSection === 'energy-flow'" class="flex-1 min-h-0 flex flex-col">
            <div
              v-if="connectionData.length === 0"
              class="flex-1 flex items-center justify-center text-app-muted text-sm"
            >
              等待任务数据...
            </div>
            <div v-else class="flex-1 min-h-0 overflow-y-auto space-y-6">
              <div
                v-for="bus in connectionData"
                :key="bus.busCode"
                class="space-y-3"
              >
                <div
                  v-for="layer in layerOptions"
                  :key="layer.value"
                  class="border border-app-border rounded p-3"
                >
                  <EnergyFlowChart
                    :bus-label="`${bus.busLabel} · ${layer.label}`"
                    :variables="bus.variables"
                    :live-data="liveData"
                    :layer-id="layer.value"
                    :code-to-label="codeToLabel"
                  />
                </div>
              </div>
            </div>
          </div>

          <!-- 其他栏目占位 -->
          <div v-else class="flex-1 flex items-center justify-center text-app-muted text-sm">
            {{ sections.find(s => s.key === activeSection)?.label ?? '' }} - 开发中...
          </div>
        </div>
      </main>
    </div>

    <!-- 任务列表弹窗 -->
    <AppModal
      :open="showTaskListDialog"
      title="计算任务列表"
      size="lg"
      @close="showTaskListDialog = false"
    >
      <div class="px-2 py-1">
        <div class="max-h-96 overflow-y-auto">
          <div v-if="taskList.length === 0" class="p-4 text-center text-sm text-app-muted">
            暂无任务
          </div>
          <table v-else class="w-full text-sm">
            <thead>
              <tr class="text-left text-xs text-app-muted border-b border-app-border">
                <th class="pb-2 pr-4">任务名称</th>
                <th class="pb-2 pr-4">项目ID</th>
                <th class="pb-2 pr-4">模式</th>
                <th class="pb-2 pr-4">状态</th>
                <th class="pb-2">操作</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="t in taskList"
                :key="t.id"
                class="border-b border-app-border cursor-pointer hover:bg-app-panel-soft"
                @click="selectTask(t.id)"
              >
                <td class="py-2 pr-4 truncate max-w-[10rem]">{{ t.name ?? t.id.slice(0, 8) }}</td>
                <td class="py-2 pr-4 font-mono text-xs text-app-muted truncate max-w-[8rem]">{{ t.project_id }}</td>
                <td class="py-2 pr-4">{{ t.mode === 'offline' ? '离线' : '在线' }}</td>
                <td class="py-2 pr-4">
                  <span
                    class="px-1.5 py-0.5 rounded text-[10px]"
                    :class="`bg-${STATUS_TONE[t.status]}-soft text-${STATUS_TONE[t.status]}`"
                  >{{ STATUS_LABEL[t.status] }}</span>
                </td>
                <td class="py-2">
                  <div class="flex gap-1">
                    <AppButton
                      v-if="showActions(t).cancel"
                      label="取消"
                      size="sm"
                      tone="danger"
                      @click.stop="doAction('cancel', t.id)"
                    />
                    <AppButton
                      v-if="showActions(t).cleanup"
                      label="清理"
                      size="sm"
                      tone="ghost"
                      @click.stop="doAction('cleanup', t.id)"
                    />
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
      <template #footer>
        <AppButton label="刷新" tone="ghost" size="sm" @click="refreshList" />
        <AppButton label="关闭" tone="neutral" size="sm" @click="showTaskListDialog = false" />
      </template>
    </AppModal>

    <!-- 新建任务弹窗 -->
    <AppModal
      :open="showCreateDialog"
      title="新建仿真计算任务"
      size="lg"
      @close="showCreateDialog = false"
    >
      <div class="space-y-4 px-2 py-1">
        <section class="rounded-[12px] border border-app-border p-4">
          <div class="mb-3">
            <h3 class="text-sm font-semibold text-app-text">仿真任务设置</h3>
            <p class="mt-1 text-xs text-app-muted">选择当前建模画布、计算时层和仿真时间范围。</p>
          </div>

          <div class="grid gap-3 sm:grid-cols-2">
            <label class="space-y-1 text-xs text-app-muted">
              <span>项目 ID</span>
              <input
                v-model="newTask.projectId"
                class="field-input h-8 text-xs"
                @change="loadCreationProject(newTask.projectId)"
              >
            </label>
            <label class="space-y-1 text-xs text-app-muted">
              <span>任务名称</span>
              <input v-model="newTask.name" class="field-input h-8 text-xs" placeholder="可选">
            </label>
            <label class="space-y-1 text-xs text-app-muted">
              <span>建模画布</span>
              <select v-if="creationCanvasOptions.length" v-model="newTask.canvasId" class="field-input h-8 text-xs">
                <option v-for="canvas in creationCanvasOptions" :key="canvas.id" :value="canvas.id">{{ canvas.name }}</option>
              </select>
              <input v-else v-model="newTask.canvasId" class="field-input h-8 text-xs" placeholder="canvasId">
            </label>
            <label class="space-y-1 text-xs text-app-muted">
              <span>仿真时层</span>
              <select v-model="newTask.layerId" class="field-input h-8 text-xs">
                <option v-for="layer in creationLayerOptions" :key="layer.id" :value="layer.id">{{ layer.name }}（{{ layer.step }}）</option>
                <option v-if="!creationLayerOptions.length" value="1">时层 1</option>
              </select>
            </label>
            <label class="space-y-1 text-xs text-app-muted">
              <span>运行方式</span>
              <select v-model="newTask.mode" class="field-input h-8 text-xs">
                <option value="offline">离线计算（尽快求解）</option>
                <option value="online">在线计算（按真实时间推进）</option>
              </select>
            </label>
            <div class="grid grid-cols-2 gap-2">
              <label class="space-y-1 text-xs text-app-muted">
                <span>开始时间</span>
                <input v-model="newTask.simStartTime" class="field-input h-8 text-xs" placeholder="0:00">
              </label>
              <label class="space-y-1 text-xs text-app-muted">
                <span>结束时间</span>
                <input v-model="newTask.simEndTime" class="field-input h-8 text-xs" placeholder="24:00">
              </label>
            </div>
          </div>

          <p v-if="creationProjectLoading" class="mt-2 text-xs text-app-muted">正在读取项目配置...</p>
          <p v-else-if="creationProjectError" class="mt-2 text-xs text-app-danger">{{ creationProjectError }}</p>
        </section>

        <section class="rounded-[12px] border border-primary/40 bg-primary-soft/35 p-4">
          <div>
            <div>
              <div class="flex items-center gap-2">
                <span class="inline-flex h-8 w-8 items-center justify-center rounded-lg bg-white text-lg">↕️</span>
                <div>
                  <h3 class="text-sm font-semibold text-app-text">灵活性量化评估</h3>
                  <p class="mt-0.5 text-xs text-app-muted">在基准仿真后，自动使用项目最底层时层计算上下调供给、需求、裕度和全时域指标。</p>
                </div>
              </div>
            </div>
          </div>

          <div class="mt-4 space-y-3 border-t border-primary/15 pt-4">
            <div class="grid gap-3 sm:grid-cols-2">
              <label class="space-y-1 text-xs text-app-muted">
                <span>并网点 POI</span>
                <select v-model="newTask.poiId" class="field-input h-8 text-xs" :disabled="isIslandedFlexibility">
                  <option v-if="isIslandedFlexibility" value="">离网系统（无 GRID / POI）</option>
                  <option v-for="option in creationGridOptions" :key="option.value" :value="option.value">{{ option.label }}</option>
                </select>
              </label>
              <label class="space-y-1 text-xs text-app-muted">
                <span>灵活性需求来源</span>
                <select v-model="newTask.requirementSource" class="field-input h-8 text-xs">
                  <option v-for="option in availableRequirementOptions" :key="option.value" :value="option.value">{{ option.label }}</option>
                </select>
              </label>
            </div>

            <div
              v-if="selectedGridOption"
              data-testid="poi-boundary-summary"
              class="rounded-[10px] border border-primary/20 bg-white p-3"
            >
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <div class="text-xs font-semibold text-app-text">POI功率边界</div>
                </div>
                <button type="button" class="text-xs font-medium text-primary hover:underline" @click="openGridConfiguration">
                  返回建模页修改GRID参数
                </button>
              </div>
              <div class="mt-3 grid gap-2 text-xs sm:grid-cols-2 xl:grid-cols-4">
                <div class="rounded-lg bg-app-panel-soft px-3 py-2">
                  <div class="text-app-muted">接口容量</div>
                  <div class="mt-1 font-medium text-app-text">{{ formatBoundaryPower(selectedGridOption.capacityKw) }}</div>
                </div>
                <div class="rounded-lg bg-app-panel-soft px-3 py-2">
                  <div class="text-app-muted">上送上限</div>
                  <div class="mt-1 font-medium text-app-text">{{ formatBoundaryPower(selectedGridOption.maximumPoiPowerKw) }}</div>
                </div>
                <div class="rounded-lg bg-app-panel-soft px-3 py-2">
                  <div class="text-app-muted">购入下限</div>
                  <div class="mt-1 font-medium text-app-text">{{ formatBoundaryPower(selectedGridOption.minimumPoiPowerKw) }}</div>
                </div>
                <div class="rounded-lg bg-app-panel-soft px-3 py-2">
                  <div class="text-app-muted">上送 / 购入比例</div>
                  <div class="mt-1 font-medium text-app-text">{{ (selectedGridOption.sellRatio * 100).toFixed(0) }}% / {{ (selectedGridOption.buyRatio * 100).toFixed(0) }}%</div>
                </div>
              </div>
            </div>
            <div
              v-else
              data-testid="islanded-boundary-summary"
              class="rounded-[10px] border border-emerald-200 bg-emerald-50 p-3"
            >
              <div class="text-xs font-semibold text-emerald-800">离网本地平衡口径</div>
              <div class="mt-1 text-[11px] leading-5 text-emerald-700">
                当前画布没有 GRID，系统外部交换功率固定为 0。系统供给由内部可调设备灵活性合计形成，不再经过 POI 剩余空间截断。
              </div>
              <div class="mt-2 text-[11px] text-emerald-700">离网模式支持“净负荷变化”和“用户直接给定”；计划/AGC目标因不存在 POI 而不可用。</div>
            </div>

            <div class="rounded-lg bg-white px-3 py-2 text-xs leading-5 text-app-muted">
              {{ availableRequirementOptions.find(option => option.value === newTask.requirementSource)?.description }}
            </div>

            <template v-if="newTask.requirementSource !== 'net_load_change'">
              <div class="flex flex-wrap items-center gap-x-4 gap-y-2 text-xs">
                <span class="text-app-muted">数值输入方式</span>
                <label class="inline-flex items-center gap-1.5">
                  <input v-model="newTask.flexibilityValueMode" type="radio" value="constant" class="accent-primary">
                  全时域常数
                </label>
                <label class="inline-flex items-center gap-1.5">
                  <input v-model="newTask.flexibilityValueMode" type="radio" value="manual" class="accent-primary">
                  表格编辑
                </label>
                <label class="inline-flex items-center gap-1.5">
                  <input v-model="newTask.flexibilityValueMode" type="radio" value="file" class="accent-primary">
                  导入文件
                </label>
                <label class="inline-flex items-center gap-1.5">
                  <input v-model="newTask.flexibilityValueMode" type="radio" value="boundary" class="accent-primary">
                  项目边界数据库
                </label>
              </div>

              <div v-if="newTask.requirementSource === 'agc_or_schedule'">
                <label class="space-y-1 text-xs text-app-muted">
                  <span>目标并网功率（kW，正值表示上送、负值表示购入）</span>
                  <input v-if="newTask.flexibilityValueMode === 'constant'" v-model.number="newTask.targetPoiPowerKw" type="number" step="100" class="field-input h-8 text-xs">
                </label>
                <FlexibilityTimeSeriesEditor
                  v-if="newTask.flexibilityValueMode !== 'constant'"
                  v-model="newTask.targetPoiPowerSeries"
                  :mode="newTask.flexibilityValueMode"
                  label="目标并网功率"
                  :boundary-options="boundarySeriesOptions"
                  :expected-timestamps="expectedRequirementTimestamps"
                  @validation="seriesValidationErrors.target = $event"
                />
              </div>

              <div v-else class="grid gap-3 sm:grid-cols-2">
                <div class="space-y-1 text-xs text-app-muted">
                  <span>上调需求（kW）</span>
                  <input v-if="newTask.flexibilityValueMode === 'constant'" v-model.number="newTask.upwardRequirementKw" type="number" min="0" step="100" class="field-input h-8 text-xs">
                  <FlexibilityTimeSeriesEditor
                    v-else
                    v-model="newTask.upwardRequirementSeries"
                    :mode="newTask.flexibilityValueMode"
                    label="上调需求"
                    :nonnegative="true"
                    :boundary-options="boundarySeriesOptions"
                    :expected-timestamps="expectedRequirementTimestamps"
                    @validation="seriesValidationErrors.upward = $event"
                  />
                </div>
                <div class="space-y-1 text-xs text-app-muted">
                  <span>下调需求（kW）</span>
                  <input v-if="newTask.flexibilityValueMode === 'constant'" v-model.number="newTask.downwardRequirementKw" type="number" min="0" step="100" class="field-input h-8 text-xs">
                  <FlexibilityTimeSeriesEditor
                    v-else
                    v-model="newTask.downwardRequirementSeries"
                    :mode="newTask.flexibilityValueMode"
                    label="下调需求"
                    :nonnegative="true"
                    :boundary-options="boundarySeriesOptions"
                    :expected-timestamps="expectedRequirementTimestamps"
                    @validation="seriesValidationErrors.downward = $event"
                  />
                </div>
              </div>

              <p v-if="newTask.flexibilityValueMode === 'boundary' && boundarySeriesLoading" class="text-xs text-app-muted">正在读取项目边界数据库...</p>
              <p v-else-if="newTask.flexibilityValueMode === 'boundary' && boundarySeriesWarning" class="rounded-lg bg-orange-50 px-3 py-2 text-xs text-orange-700">{{ boundarySeriesWarning }}</p>
            </template>
          </div>
        </section>
      </div>
      <template #footer>
        <AppButton label="取消" tone="neutral" @click="showCreateDialog = false" />
        <AppButton label="创建" tone="primary" @click="createTask" />
      </template>
    </AppModal>
  </div>
</template>
