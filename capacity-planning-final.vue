<script setup lang="ts">
import type {
  BoundaryDataset,
  BoundaryDatasetSummary,
  ApplyCapacityPlanningResult,
  CapacityPlanningResult,
  CapacityPlanningStatus,
  CapacityPlanningTask,
  CapacityPlanningFormSchema,
  CapacityVariableDraft,
  ScenarioPreviewResult
} from '~~/types/capacity-planning'
import type { Project } from '~~/types/project'
import { BOUNDARY_MEANING_LABELS } from '~~/types/boundary'

import { useCapacityPlanningApi } from '~~/composables/api/useCapacityPlanningApi'
import { useProjectApi } from '~~/composables/api/useProjectApi'
import { useToastCenter } from '~~/state/ui'
import PropertySwitch from '../../components/PropertySwitch.vue'
import PropertyNumber from '../../components/PropertyNumber.vue'
const CanvasWorkspace = defineAsyncComponent(() => import('../../components/CanvasWorkspace.vue'))
import * as echarts from 'echarts'

definePageMeta({ title: '容量规划 - SynerRoll' })

const route = useRoute()
const projectId = computed(() => String(route.params.projectId ?? ''))
const canvasId = computed(() => String(route.query.canvasId ?? ''))
const planningApi = useCapacityPlanningApi()
const projectApi = useProjectApi()
const { push } = useToastCenter()

const schema = ref<CapacityPlanningFormSchema | null>(null)
const project = ref<Project | null>(null)
const loading = ref(true)
const validating = ref(false)
const errorMessage = ref('')
const validatedAt = ref('')
const datasets = ref<BoundaryDatasetSummary[]>([])
const selectedDatasetId = ref('')
const activeDataset = ref<BoundaryDataset | null>(null)
const datasetLoading = ref(false)
const datasetError = ref('')
const scenarioPreview = ref<ScenarioPreviewResult | null>(null)
const planningTask = ref<CapacityPlanningTask | null>(null)
const planningResult = ref<CapacityPlanningResult | null>(null)
const planningBusy = ref(false)
const planningError = ref('')
const applyResult = ref<ApplyCapacityPlanningResult | null>(null)
const applyingResult = ref(false)
const currentStep = ref(1)
const objectiveConfirmed = ref(false)
const contentScroller = ref<HTMLElement | null>(null)
const selectedBoundaryId = ref('')
const boundaryPreviewChartRef = ref<HTMLDivElement | null>(null)
const convergenceChartRef = ref<HTMLDivElement | null>(null)
const capacityChangeChartRef = ref<HTMLDivElement | null>(null)
const planningLogRef = ref<HTMLDivElement | null>(null)
let planningPollTimer: ReturnType<typeof setInterval> | null = null
let planningPollPending = false
let boundaryPreviewChart: echarts.ECharts | null = null
let convergenceChart: echarts.ECharts | null = null
let capacityChangeChart: echarts.ECharts | null = null
const scenarioChartElements = new Map<string, HTMLDivElement>()
const scenarioCharts = new Map<string, echarts.ECharts>()
const selectedClusteringFeatureKey = ref('')
type PlanningLogState = 'done' | 'active' | 'pending' | 'error'
interface PlanningLogItem {
  id: string
  title: string
  detail: string
  state: PlanningLogState
  time: string
}
const planningLogFeed = ref<PlanningLogItem[]>([])
const planningLogIds = new Set<string>()
let planningLogSequenceTimer: ReturnType<typeof setTimeout> | null = null
let lastLoggedEvaluation = 0

const clustering = reactive({
  featureIds: [] as string[],
  clusterCount: 4,
  algorithm: 'kmeans' as 'kmeans' | 'kmedoids',
  normalize: 'zscore' as 'zscore' | 'minmax' | 'none',
  missingDayThreshold: 0.05,
  seed: 20260828
})

const optimizer = reactive({
  maxFuncEvals: 20,
  populationSize: 10,
  maxTimeSeconds: 3600,
  seed: 20260828,
  failurePenalty: 1e18
})

const planningSteps = [
  { id: 1, title: '容量变量配置', description: '确定参与规划的设备与容量范围' },
  { id: 2, title: '历史边界数据', description: '核对边界配置并预览时序数据' },
  { id: 3, title: '典型场景聚类', description: '配置聚类参数并预览代表性场景' },
  { id: 4, title: '规划目标设置', description: '确认规划目标并预留扩展结构' },
  { id: 5, title: '求解设置', description: '设置算法参数并观察求解过程' },
  { id: 6, title: '容量配置方案', description: '比较优化前后容量并应用最优方案' }
] as const

const variables = computed(() => schema.value?.variables ?? [])
const optimizedCount = computed(() => variables.value.filter(item => item.mode === 'optimize').length)
const fixedCount = computed(() => variables.value.length - optimizedCount.value)
const allOptimized = computed(() => variables.value.length > 0 && variables.value.every(item => item.mode === 'optimize'))
const toggleAllParticipation = () => {
  const target = allOptimized.value ? 'fixed' : 'optimize'
  for (const item of variables.value) {
    item.mode = target
    if (target === 'fixed') item.fixedValue = item.currentValue
  }
  validatedAt.value = ''
}
const handleSuggestedValueChange = (item: CapacityVariableDraft, value: number) => {
  item.suggestedValue = value
  validatedAt.value = ''
}
const handleBoundChange = (item: CapacityVariableDraft, field: 'lowerBound' | 'upperBound', value: number) => {
  if (!Number.isFinite(value)) return
  const gap = capacitySliderStep(item)
  if (field === 'lowerBound') {
    item.lowerBound = Math.max(capacitySchemaMin(item), Math.min(value, item.upperBound - gap))
    item.suggestedValue = Math.max(item.suggestedValue, item.lowerBound)
  } else {
    const schemaMaximum = capacitySchemaMax(item)
    item.upperBound = Math.max(value, item.lowerBound + gap)
    if (schemaMaximum !== undefined) item.upperBound = Math.min(item.upperBound, schemaMaximum)
    item.suggestedValue = Math.min(item.suggestedValue, item.upperBound)
  }
  validatedAt.value = ''
}
const configuredBoundaries = computed(() => project.value?.boundaries ?? [])
const canvasNodeNameById = computed(() => new Map(
  (project.value?.workspace.canvases.find(canvas => canvas.id === canvasId.value)?.nodes ?? [])
    .map(node => [node.id, node.data.label || node.id])
))
const activeCanvas = computed(() =>
  project.value?.workspace.canvases.find(canvas => canvas.id === canvasId.value) ?? null
)
const canvasPreviewRef = ref<InstanceType<typeof CanvasWorkspace> | null>(null)
const selectedBoundary = computed(() =>
  configuredBoundaries.value.find(boundary => boundary.id === selectedBoundaryId.value) ?? null
)
const clusteringFeatureOptions = computed(() => {
  const series = activeDataset.value?.series ?? []
  const singles = series.map((item) => {
    const label = item.meaning === 'wind_speed'
      ? '单风速'
      : item.meaning === 'irradiance'
        ? '单光伏'
        : `单${boundaryMeaningLabel(item.meaning) || item.name}`
    return {
      key: `single:${item.boundaryId}`,
      label,
      description: item.name,
      featureIds: [item.boundaryId]
    }
  })
  const wind = series.find(item => item.meaning === 'wind_speed')
  const photovoltaic = series.find(item => item.meaning === 'irradiance')
  if (!wind || !photovoltaic) return singles
  return [{
    key: `coupled:${wind.boundaryId}:${photovoltaic.boundaryId}`,
    label: '风光耦合',
    description: `${wind.name} + ${photovoltaic.name}`,
    featureIds: [wind.boundaryId, photovoltaic.boundaryId]
  }, ...singles]
})
const selectedBoundaryPreviewData = computed(() => {
  const boundary = selectedBoundary.value
  if (!boundary) return null
  if (boundary.rawData?.values.length) {
    return {
      values: boundary.rawData.values,
      timestamps: boundary.rawData.timestamps,
      xAxisLabel: boundary.rawData.xAxisLabel || '时间',
      yAxisLabel: boundary.rawData.yAxisLabel || BOUNDARY_MEANING_LABELS[boundary.meaning]
    }
  }

  const firstLayer = boundary.transformedData?.layers[0]
  if (!firstLayer?.values.length) return null
  return {
    values: firstLayer.values,
    timestamps: firstLayer.timestamps,
    xAxisLabel: '时间',
    yAxisLabel: BOUNDARY_MEANING_LABELS[boundary.meaning]
  }
})
const activeStep = computed(() => planningSteps.find(item => item.id === currentStep.value) ?? planningSteps[0])
const completedStepIds = computed(() => {
  const completed = new Set<number>()
  if (validatedAt.value) completed.add(1)
  if (activeDataset.value) completed.add(2)
  if (scenarioPreview.value) completed.add(3)
  if (objectiveConfirmed.value || planningTask.value) completed.add(4)
  if (planningResult.value) completed.add(5)
  if (applyResult.value?.projectApplied) completed.add(6)
  return completed
})

const boundaryPointCount = (boundary: Project['boundaries'][number]) =>
  boundary.rawData?.values.length
  ?? boundary.transformedData?.layers[0]?.values.length
  ?? 0

function boundaryMeaningLabel(meaning: string) {
  return BOUNDARY_MEANING_LABELS[meaning as keyof typeof BOUNDARY_MEANING_LABELS] || meaning
}

const boundaryRelatedDeviceNames = (boundary: Project['boundaries'][number]) => {
  const names = boundary.relatedComponents
    .map(componentId => canvasNodeNameById.value.get(componentId))
    .filter((name): name is string => Boolean(name))
  return names.length ? names.join('、') : '—'
}

const renderBoundaryPreview = () => {
  if (!boundaryPreviewChartRef.value || !selectedBoundaryPreviewData.value || !selectedBoundary.value) return
  boundaryPreviewChart?.dispose()
  boundaryPreviewChart = echarts.init(boundaryPreviewChartRef.value)
  boundaryPreviewChart.setOption({
    tooltip: { trigger: 'axis' },
    grid: {
      left: '3%',
      right: '3%',
      top: 24,
      bottom: 42,
      containLabel: true
    },
    xAxis: {
      type: 'category',
      data: selectedBoundaryPreviewData.value.timestamps,
      name: selectedBoundaryPreviewData.value.xAxisLabel,
      nameLocation: 'middle',
      nameGap: 30,
      axisLabel: { hideOverlap: true }
    },
    yAxis: {
      type: 'value',
      name: selectedBoundaryPreviewData.value.yAxisLabel,
      nameLocation: 'middle',
      nameGap: 48
    },
    series: [{
      name: selectedBoundary.value.name,
      data: selectedBoundaryPreviewData.value.values,
      type: 'line',
      smooth: true,
      symbol: 'none',
      sampling: 'lttb',
      lineStyle: { width: 2 },
      itemStyle: { color: '#165DFF' }
    }]
  })
  boundaryPreviewChart.resize()
}

const previewBoundary = async (boundary: Project['boundaries'][number]) => {
  selectedBoundaryId.value = boundary.id
  await nextTick()
  renderBoundaryPreview()
}

const selectDefaultClusteringFeature = () => {
  const option = clusteringFeatureOptions.value[0]
  selectedClusteringFeatureKey.value = option?.key ?? ''
  clustering.featureIds = option ? [...option.featureIds] : []
}

const updateClusteringFeature = () => {
  const option = clusteringFeatureOptions.value.find(item => item.key === selectedClusteringFeatureKey.value)
  clustering.featureIds = option ? [...option.featureIds] : []
}

const disposeScenarioCharts = () => {
  scenarioCharts.forEach(chart => chart.dispose())
  scenarioCharts.clear()
}

const setScenarioChartRef = (scenarioId: string, element: unknown) => {
  if (element instanceof HTMLDivElement) {
    scenarioChartElements.set(scenarioId, element)
    return
  }
  scenarioChartElements.delete(scenarioId)
  scenarioCharts.get(scenarioId)?.dispose()
  scenarioCharts.delete(scenarioId)
}

const renderScenarioCharts = () => {
  disposeScenarioCharts()
  const preview = scenarioPreview.value
  if (!preview || currentStep.value !== 3) return

  const metadata = new Map(preview.dataset.series.map(item => [item.boundaryId, item]))
  const resolutionMinutes = preview.config.resolutionMinutes
  preview.scenarios.forEach((scenario, scenarioIndex) => {
    const element = scenarioChartElements.get(scenario.scenarioId)
    if (!element) return

    const entries = Object.entries(scenario.series)
    const pointCount = Math.max(0, ...entries.map(([, values]) => values.length))
    const timeLabels = Array.from({ length: pointCount }, (_, index) => {
      const totalMinutes = index * resolutionMinutes
      const hour = Math.floor(totalMinutes / 60).toString().padStart(2, '0')
      const minute = (totalMinutes % 60).toString().padStart(2, '0')
      return `${hour}:${minute}`
    })
    const units = [...new Set(entries.map(([featureId]) => metadata.get(featureId)?.unit || '数值'))]
    const chart = echarts.init(element)
    chart.setOption({
      animation: false,
      color: ['#165DFF', '#F59E0B', '#14B8A6', '#8B5CF6', '#EF4444'],
      tooltip: { trigger: 'axis' },
      legend: {
        type: 'scroll',
        top: 0,
        left: 8,
        right: 8
      },
      grid: {
        left: 16,
        right: units.length > 1 ? 70 : 24,
        top: 46,
        bottom: 30,
        containLabel: true
      },
      xAxis: {
        type: 'category',
        boundaryGap: false,
        data: timeLabels,
        axisLabel: { hideOverlap: true }
      },
      yAxis: units.map((unit, index) => ({
        type: 'value',
        name: unit,
        position: index === 0 ? 'left' : 'right',
        offset: index > 1 ? (index - 1) * 54 : 0,
        splitLine: { show: index === 0 }
      })),
      series: entries.map(([featureId, values]) => {
        const seriesMetadata = metadata.get(featureId)
        const unit = seriesMetadata?.unit || '数值'
        return {
          name: seriesMetadata?.name || featureId,
          data: values,
          type: 'line',
          smooth: true,
          showSymbol: false,
          yAxisIndex: Math.max(0, units.indexOf(unit)),
          lineStyle: { width: 2 }
        }
      }),
      aria: {
        enabled: true,
        description: `典型场景 ${scenarioIndex + 1} 的边界数据折线图`
      }
    })
    scenarioCharts.set(scenario.scenarioId, chart)
  })
}

const selectStep = (stepId: number) => {
  currentStep.value = Math.min(6, Math.max(1, stepId))
}

const confirmBoundaryData = () => {
  if (!activeDataset.value) {
    push({
      tone: 'warning',
      title: '尚无可用的历史边界数据快照',
      description: '请先在边界配置中完善并保存历史边界数据。'
    })
    return
  }
  currentStep.value = 3
}

const confirmTypicalScenarios = () => {
  if (!scenarioPreview.value) {
    push({ tone: 'warning', title: '请先生成并预览典型场景' })
    return
  }
  currentStep.value = 4
}

const confirmObjective = () => {
  objectiveConfirmed.value = true
  currentStep.value = 5
}

const formatNumber = (value: number) => new Intl.NumberFormat('zh-CN', {
  maximumFractionDigits: 4
}).format(value)

type CapacityBoundField = 'lowerBound' | 'upperBound'

const capacitySchemaMin = (item: CapacityVariableDraft) => {
  if (item.schemaMin === null || item.schemaMin === undefined) return 0
  const minimum = Number(item.schemaMin)
  return Number.isFinite(minimum) ? minimum : 0
}

const capacitySchemaMax = (item: CapacityVariableDraft) => {
  if (item.schemaMax === null || item.schemaMax === undefined) return undefined
  const maximum = Number(item.schemaMax)
  return Number.isFinite(maximum) ? maximum : undefined
}

const capacitySliderStep = (item: CapacityVariableDraft) => {
  const configuredStep = Number(item.step)
  if (Number.isFinite(configuredStep) && configuredStep > 0) return configuredStep
  return Math.max((Number(item.upperBound) - Number(item.lowerBound)) / 100, 0.0001)
}

const updateCapacityBound = (item: CapacityVariableDraft, field: CapacityBoundField, event: Event) => {
  const input = event.target as HTMLInputElement
  const inputValue = Number(input.value)
  if (!input.value.trim() || !Number.isFinite(inputValue)) {
    input.value = String(item[field])
    return
  }

  const gap = capacitySliderStep(item)
  if (field === 'lowerBound') {
    item.lowerBound = Math.max(capacitySchemaMin(item), Math.min(inputValue, item.upperBound - gap))
    item.suggestedValue = Math.max(item.suggestedValue, item.lowerBound)
  }
  else {
    const schemaMaximum = capacitySchemaMax(item)
    item.upperBound = Math.max(inputValue, item.lowerBound + gap)
    if (schemaMaximum !== undefined) item.upperBound = Math.min(item.upperBound, schemaMaximum)
    item.suggestedValue = Math.min(item.suggestedValue, item.upperBound)
  }

  input.value = String(item[field])
  validatedAt.value = ''
}

const updateCapacitySuggestion = (item: CapacityVariableDraft, event: Event) => {
  item.suggestedValue = Number((event.target as HTMLInputElement).value)
  validatedAt.value = ''
}

const updateParticipation = (item: CapacityVariableDraft, participates: boolean) => {
  item.mode = participates ? 'optimize' : 'fixed'
  if (!participates) item.fixedValue = item.currentValue
  validatedAt.value = ''
}

const variableError = (item: CapacityVariableDraft): string => {
  if (item.mode === 'fixed') {
    return Number.isFinite(Number(item.fixedValue)) && Number(item.fixedValue) >= 0
      ? ''
      : '固定容量必须是非负有限数值'
  }

  const lower = Number(item.lowerBound)
  const upper = Number(item.upperBound)
  const suggested = Number(item.suggestedValue)
  if (![lower, upper, suggested].every(Number.isFinite)) return '上下界和建议值必须是有限数值'
  if (lower < 0 || upper < 0 || suggested < 0) return '容量不能为负数'
  if (lower >= upper) return '下界必须小于上界'
  if (suggested < lower || suggested > upper) return '建议值必须位于上下界之间'
  return ''
}

const formValid = computed(() =>
  variables.value.length > 0
  && optimizedCount.value > 0
  && variables.value.every(item => !variableError(item))
)

const canPreviewScenarios = computed(() =>
  Boolean(activeDataset.value)
  && clustering.featureIds.length > 0
  && clustering.clusterCount >= 2
  && clustering.missingDayThreshold >= 0
  && clustering.missingDayThreshold <= 1
)

const activePlanningStatuses: CapacityPlanningStatus[] = [
  'queued',
  'validating',
  'clustering',
  'optimizing'
]
const planningActive = computed(() =>
  Boolean(planningTask.value && activePlanningStatuses.includes(planningTask.value.status))
)
const optimizerValid = computed(() =>
  Number.isInteger(Number(optimizer.maxFuncEvals))
  && optimizer.maxFuncEvals >= 2
  && optimizer.maxFuncEvals <= 10000
  && Number.isInteger(Number(optimizer.populationSize))
  && optimizer.populationSize >= 2
  && optimizer.populationSize <= 500
  && Number(optimizer.maxTimeSeconds) >= 1
  && Number(optimizer.failurePenalty) > 0
)
const planningPrerequisitesReady = computed(() =>
  Boolean(project.value && schema.value && activeDataset.value && scenarioPreview.value && objectiveConfirmed.value)
  && formValid.value
)
const canStartPlanning = computed(() =>
  planningPrerequisitesReady.value
  && optimizerValid.value
  && !planningActive.value
  && !planningBusy.value
)
const progressPercent = computed(() => {
  const progress = planningTask.value?.progress
  if (!progress?.maxFuncEvals) return 0
  return Math.min(100, Math.round(progress.completedEvaluations / progress.maxFuncEvals * 100))
})

const selectedClusteringFeatureOption = computed(() =>
  clusteringFeatureOptions.value.find(item => item.key === selectedClusteringFeatureKey.value) ?? null
)

const liveConvergencePoints = computed(() => {
  if (planningResult.value?.convergence.length) return planningResult.value.convergence
  return planningTask.value?.progress.convergence ?? []
})

const capacityChartItems = computed(() => {
  const resultById = new Map(
    (planningResult.value?.variables ?? []).map(item => [item.componentId, item])
  )
  const bestCandidate = planningTask.value?.progress.bestCandidate
  return variables.value
    .filter(item => item.mode === 'optimize')
    .map((item) => {
      const finalResult = resultById.get(item.componentId)
      const liveValue = bestCandidate?.[item.componentId]?.value
      return {
        componentId: item.componentId,
        name: item.componentName,
        unit: item.unit,
        currentValue: Number(item.currentValue),
        plannedValue: Number(finalResult?.optimalValue ?? liveValue ?? item.suggestedValue)
      }
    })
})

const solverIndicator = computed(() => {
  const status = planningTask.value?.status
  if (planningBusy.value || status === 'queued' || status === 'validating' || status === 'clustering') {
    return { label: '校验中', tone: 'checking' as const }
  }
  if (status === 'optimizing') return { label: '开始计算', tone: 'running' as const }
  if (status === 'completed') return { label: '计算完成', tone: 'completed' as const }
  if (status === 'failed') return { label: '计算失败', tone: 'failed' as const }
  if (status === 'cancelled') return { label: '已终止', tone: 'cancelled' as const }
  return { label: '等待启动', tone: 'ready' as const }
})

const planningPrerequisiteEntries = computed(() => {
  const algorithmLabel = clustering.algorithm === 'kmeans' ? 'K-means' : 'K-medoids'
  return [
    {
      title: '容量变量配置完毕',
      detail: `${optimizedCount.value} 个参与优化，${fixedCount.value} 个保持固定，容量上下界已确认`,
      state: (formValid.value ? 'done' : 'pending') as PlanningLogState
    },
    {
      title: '历史边界数据配置完毕',
      detail: activeDataset.value
        ? `${activeDataset.value.name}，${activeDataset.value.seriesCount} 条边界，${formatNumber(activeDataset.value.pointCount)} 个时序点`
        : '尚未选择历史边界数据',
      state: (activeDataset.value ? 'done' : 'pending') as PlanningLogState
    },
    {
      title: '典型场景聚类完毕',
      detail: scenarioPreview.value
        ? `${scenarioPreview.value.scenarios.length} 个场景，${algorithmLabel}，特征：${selectedClusteringFeatureOption.value?.label ?? '—'}`
        : '尚未生成典型场景',
      state: (scenarioPreview.value ? 'done' : 'pending') as PlanningLogState
    },
    {
      title: '规划目标配置完毕',
      detail: '年度典型场景加权运行目标最小',
      state: (objectiveConfirmed.value ? 'done' : 'pending') as PlanningLogState
    }
  ]
})

const solverThinkingText = computed(() => {
  if (solverIndicator.value.tone === 'checking') return '正在理解配置并执行一致性校验'
  if (solverIndicator.value.tone === 'running') return '正在搜索容量组合并推演更优解'
  if (solverIndicator.value.tone === 'completed') return '推演完成，已生成最优容量方案'
  if (solverIndicator.value.tone === 'failed') return '推演中断，正在整理错误信息'
  if (solverIndicator.value.tone === 'cancelled') return '任务已终止，等待新的求解指令'
  return '配置已载入，等待启动求解'
})

const planningLogTime = () => new Date().toLocaleTimeString('zh-CN', {
  hour12: false,
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit'
})

const appendPlanningLog = (item: Omit<PlanningLogItem, 'time'>) => {
  if (planningLogIds.has(item.id)) return
  planningLogIds.add(item.id)
  planningLogFeed.value.push({ ...item, time: planningLogTime() })
  if (planningLogFeed.value.length > 80) planningLogFeed.value.splice(0, planningLogFeed.value.length - 80)
  void nextTick(() => {
    if (planningLogRef.value) planningLogRef.value.scrollTop = planningLogRef.value.scrollHeight
  })
}

const appendCurrentPlanningStatus = () => {
  const task = planningTask.value
  if (planningBusy.value && !task) {
    appendPlanningLog({
      id: 'creating-task',
      title: '正在创建容量规划任务',
      detail: '冻结项目、容量变量与典型场景快照',
      state: 'active'
    })
    return
  }
  if (!task) {
    appendPlanningLog(planningPrerequisitesReady.value
      ? {
          id: 'ready-to-solve',
          title: '全部前置条件完成',
          detail: 'AI 规划引擎已就绪，等待开始求解',
          state: 'done'
        }
      : {
          id: 'prerequisite-missing',
          title: '前置条件尚未完成',
          detail: '请返回对应步骤补充配置和确认',
          state: 'pending'
        })
    return
  }

  if (task.status === 'queued') {
    appendPlanningLog({ id: 'task-queued', title: '规划任务已进入计算队列', detail: `任务 ${task.id.slice(0, 12)}，等待分配求解资源`, state: 'active' })
  }
  else if (task.status === 'validating') {
    appendPlanningLog({ id: 'task-validating', title: '正在校验容量规划配置', detail: '检查项目快照、容量上下界和求解参数', state: 'active' })
  }
  else if (task.status === 'clustering') {
    appendPlanningLog({ id: 'task-clustering', title: '正在复核典型场景', detail: '冻结聚类结果并检查场景权重一致性', state: 'active' })
  }
  else if (task.status === 'optimizing') {
    appendPlanningLog({ id: 'task-optimizing', title: '全部前置条件完成，开始求解', detail: '黑箱优化器正在搜索可行容量组合', state: 'active' })
  }
  else if (task.status === 'completed') {
    appendPlanningLog({
      id: 'task-completed',
      title: '容量规划求解完成',
      detail: `完成 ${task.progress.completedEvaluations} 次评价，最优目标 ${task.progress.bestFitness === null ? '—' : formatNumber(task.progress.bestFitness)}`,
      state: 'done'
    })
  }
  else if (task.status === 'failed') {
    appendPlanningLog({ id: 'task-failed', title: '容量规划求解失败', detail: planningError.value || task.errorMessage || '求解器返回异常', state: 'error' })
  }
  else if (task.status === 'cancelled') {
    appendPlanningLog({ id: 'task-cancelled', title: '容量规划已终止', detail: '已停止后续候选容量评价', state: 'error' })
  }

  const completedEvaluations = task.progress.completedEvaluations
  if (completedEvaluations > lastLoggedEvaluation) {
    lastLoggedEvaluation = completedEvaluations
    appendPlanningLog({
      id: `evaluation-${completedEvaluations}`,
      title: `求解中 · 第 ${completedEvaluations} 次评价完成`,
      detail: task.progress.bestFitness === null
        ? '当前候选方案不可行，继续搜索新的容量组合'
        : `当前最优目标 ${formatNumber(task.progress.bestFitness)}，正在生成下一组候选参数`,
      state: task.status === 'completed' ? 'done' : 'active'
    })
  }
}

const startPlanningLogSequence = () => {
  if (planningLogSequenceTimer) clearTimeout(planningLogSequenceTimer)
  planningLogSequenceTimer = null
  planningLogFeed.value = []
  planningLogIds.clear()
  lastLoggedEvaluation = 0
  const entries = [...planningPrerequisiteEntries.value]
  let index = 0
  const revealNext = () => {
    if (currentStep.value !== 5) return
    const entry = entries[index]
    if (!entry) {
      appendCurrentPlanningStatus()
      planningLogSequenceTimer = null
      return
    }
    appendPlanningLog({ id: `prerequisite-${index}`, ...entry })
    index += 1
    planningLogSequenceTimer = setTimeout(revealNext, 520)
  }
  planningLogSequenceTimer = setTimeout(revealNext, 180)
}

const compactChartNumber = (value: number) => {
  const absolute = Math.abs(value)
  if (absolute >= 1e9) return `${(value / 1e9).toFixed(1)}G`
  if (absolute >= 1e6) return `${(value / 1e6).toFixed(1)}M`
  if (absolute >= 1e3) return `${(value / 1e3).toFixed(1)}k`
  return Number(value.toFixed(2)).toString()
}

const renderConvergenceChart = () => {
  if (!convergenceChartRef.value || currentStep.value !== 5) return
  if (!convergenceChart) convergenceChart = echarts.init(convergenceChartRef.value)
  const points = liveConvergencePoints.value
  const currentFitness = points
    .filter(point => point.feasible && Number.isFinite(point.fitness))
    .map(point => [point.ordinal, point.fitness])
  const bestFitness = points
    .filter(point => point.bestSoFar !== null && Number.isFinite(point.bestSoFar))
    .map(point => [point.ordinal, point.bestSoFar as number])

  convergenceChart.setOption({
    animationDuration: 250,
    animationDurationUpdate: 250,
    tooltip: { trigger: 'axis' },
    legend: {
      top: 2,
      right: 8,
      itemWidth: 14,
      itemHeight: 8,
      textStyle: { fontSize: 10 }
    },
    grid: { left: 54, right: 22, top: 38, bottom: 44 },
    xAxis: {
      type: 'value',
      minInterval: 1,
      name: '评价次数',
      nameLocation: 'middle',
      nameGap: 28,
      axisLabel: { fontSize: 10 },
      splitLine: { show: false }
    },
    yAxis: {
      type: 'value',
      scale: true,
      axisLabel: { fontSize: 10, formatter: compactChartNumber },
      splitLine: { lineStyle: { type: 'dashed', color: '#e8edf4' } }
    },
    dataZoom: points.length > 30
      ? [{ type: 'inside', startValue: Math.max(1, points.length - 29), endValue: points.length }]
      : [],
    graphic: points.length
      ? []
      : [{
          type: 'text',
          left: 'center',
          top: 'middle',
          style: { text: '等待黑箱评价数据…', fill: '#8a94a6', fontSize: 13 }
        }],
    series: [
      {
        name: '本次目标',
        type: 'line',
        data: currentFitness,
        showSymbol: true,
        symbolSize: 5,
        lineStyle: { width: 1.5, color: '#93B4E8' },
        itemStyle: { color: '#5B8FF9' }
      },
      {
        name: '当前最优',
        type: 'line',
        data: bestFitness,
        showSymbol: false,
        step: 'end',
        lineStyle: { width: 2.5, color: '#165DFF' },
        areaStyle: { color: 'rgba(22, 93, 255, 0.10)' }
      }
    ]
  }, true)
}

const renderCapacityChangeChart = () => {
  if (!capacityChangeChartRef.value || currentStep.value !== 5) return
  if (!capacityChangeChart) capacityChangeChart = echarts.init(capacityChangeChartRef.value)
  const items = capacityChartItems.value
  capacityChangeChart.setOption({
    animationDuration: 300,
    animationDurationUpdate: 300,
    tooltip: {
      trigger: 'axis',
      axisPointer: { type: 'shadow' },
      formatter: (params: unknown) => {
        const rows = Array.isArray(params) ? params as Array<{ dataIndex?: number; seriesName?: string; value?: number; color?: string }> : []
        const index = rows[0]?.dataIndex ?? 0
        const item = items[index]
        if (!item) return ''
        return [
          `<b>${item.name}</b>`,
          ...rows.map(row => `<span style="color:${row.color ?? ''}">●</span> ${row.seriesName ?? ''}：${formatNumber(Number(row.value ?? 0))} ${item.unit}`)
        ].join('<br/>')
      }
    },
    legend: {
      top: 2,
      right: 8,
      itemWidth: 14,
      itemHeight: 8,
      textStyle: { fontSize: 10 }
    },
    grid: { left: 54, right: 18, top: 38, bottom: items.length > 5 ? 66 : 44 },
    xAxis: {
      type: 'category',
      data: items.map(item => item.name),
      axisLabel: {
        fontSize: 10,
        interval: 0,
        rotate: items.length > 5 ? 28 : 0,
        formatter: (value: string) => value.length > 8 ? `${value.slice(0, 8)}…` : value
      }
    },
    yAxis: {
      type: 'value',
      scale: true,
      axisLabel: { fontSize: 10, formatter: compactChartNumber },
      splitLine: { lineStyle: { type: 'dashed', color: '#e8edf4' } }
    },
    graphic: items.length
      ? []
      : [{
          type: 'text',
          left: 'center',
          top: 'middle',
          style: { text: '暂无参与规划的容量参数', fill: '#8a94a6', fontSize: 13 }
        }],
    series: [
      {
        name: '当前容量',
        type: 'bar',
        data: items.map(item => item.currentValue),
        barMaxWidth: 30,
        itemStyle: { color: '#B8C4D6', borderRadius: [4, 4, 0, 0] }
      },
      {
        name: planningTask.value?.progress.bestCandidate ? '实时最优容量' : '推荐初值',
        type: 'bar',
        data: items.map(item => item.plannedValue),
        barMaxWidth: 30,
        itemStyle: { color: '#165DFF', borderRadius: [4, 4, 0, 0] }
      }
    ]
  }, true)
}

const renderSolverCharts = () => {
  renderConvergenceChart()
  renderCapacityChangeChart()
}

const disposeSolverCharts = () => {
  convergenceChart?.dispose()
  capacityChangeChart?.dispose()
  convergenceChart = null
  capacityChangeChart = null
}

const scrollPlanningLogToEnd = () => {
  if (planningLogRef.value) planningLogRef.value.scrollTop = planningLogRef.value.scrollHeight
}

const loadSchema = async () => {
  loading.value = true
  errorMessage.value = ''
  validatedAt.value = ''
  try {
    if (!projectId.value || !canvasId.value) {
      throw new Error('缺少项目或画布参数，请从编辑器的“容量规划”入口进入')
    }
    schema.value = await planningApi.getFormSchema(projectId.value, canvasId.value)
  }
  catch (error) {
    errorMessage.value = error instanceof Error ? error.message : String(error)
  }
  finally {
    loading.value = false
  }
}

const loadDataset = async (datasetId: string) => {
  selectedDatasetId.value = datasetId
  scenarioPreview.value = null
  if (!datasetId) {
    activeDataset.value = null
    selectedClusteringFeatureKey.value = ''
    clustering.featureIds = []
    return
  }

  datasetLoading.value = true
  datasetError.value = ''
  try {
    activeDataset.value = await planningApi.getDataset(projectId.value, datasetId)
    clustering.featureIds = []
    selectDefaultClusteringFeature()
  }
  catch (error) {
    datasetError.value = error instanceof Error ? error.message : String(error)
  }
  finally {
    datasetLoading.value = false
  }
}

const loadDatasetContext = async () => {
  datasetError.value = ''
  try {
    const [projectResult, listResult] = await Promise.all([
      projectApi.getProject(projectId.value),
      planningApi.listDatasets(projectId.value)
    ])
    project.value = projectResult.project
    datasets.value = listResult.datasets
    if (datasets.value[0]) {
      await loadDataset(datasets.value[0].id)
    }
  }
  catch (error) {
    datasetError.value = error instanceof Error ? error.message : String(error)
  }
}

const previewTypicalDays = async () => {
  if (!activeDataset.value || !canPreviewScenarios.value) return
  datasetLoading.value = true
  datasetError.value = ''
  scenarioPreview.value = null
  try {
    scenarioPreview.value = await planningApi.previewScenarios({
      projectId: projectId.value,
      datasetId: activeDataset.value.id,
      featureIds: [...clustering.featureIds],
      clusterCount: Number(clustering.clusterCount),
      algorithm: clustering.algorithm,
      normalize: clustering.normalize,
      missingDayThreshold: Number(clustering.missingDayThreshold),
      seed: Number(clustering.seed),
      representative: 'nearest-observation'
    })
    push({
      tone: 'success',
      title: '典型场景聚类完成',
      description: `${scenarioPreview.value.scenarios.length} 个场景，覆盖 ${scenarioPreview.value.quality.validDayCount} 个有效日`
    })
  }
  catch (error) {
    datasetError.value = error instanceof Error ? error.message : String(error)
  }
  finally {
    datasetLoading.value = false
  }
}

const validateForm = async () => {
  if (!schema.value || !formValid.value) {
    push({ tone: 'warning', title: '请先修正容量变量配置' })
    return false
  }

  validating.value = true
  errorMessage.value = ''
  try {
    const result = await planningApi.validateVariables({
      projectId: projectId.value,
      canvasId: canvasId.value,
      variables: schema.value.variables
    })
    schema.value.variables = result.variables
    validatedAt.value = new Date().toLocaleTimeString('zh-CN')
    push({
      tone: 'success',
      title: '容量变量配置已通过服务端校验',
      description: `共 ${optimizedCount.value} 个优化变量、${fixedCount.value} 个固定变量`
    })
    return true
  }
  catch (error) {
    errorMessage.value = error instanceof Error ? error.message : String(error)
    return false
  }
  finally {
    validating.value = false
  }
}

const validateAndContinue = async () => {
  if (await validateForm()) currentStep.value = 2
}

const clearPlanningPoll = () => {
  if (planningPollTimer) clearInterval(planningPollTimer)
  planningPollTimer = null
}

const refreshPlanning = async () => {
  if (!planningTask.value || planningPollPending) return
  planningPollPending = true
  try {
    planningTask.value = await planningApi.getPlanning(planningTask.value.id)
    if (planningTask.value.status === 'completed') {
      planningResult.value = await planningApi.getPlanningResult(planningTask.value.id)
      currentStep.value = 6
      clearPlanningPoll()
      push({
        tone: 'success',
        title: '容量规划完成',
        description: `${planningResult.value.evaluationCount} 次评价，最优目标 ${formatNumber(planningResult.value.fitness)}`
      })
    }
    else if (planningTask.value.status === 'failed' || planningTask.value.status === 'cancelled') {
      clearPlanningPoll()
      planningError.value = planningTask.value.errorMessage
        || (planningTask.value.status === 'cancelled' ? '容量规划已取消' : '容量规划失败')
    }
  }
  catch (error) {
    planningError.value = error instanceof Error ? error.message : String(error)
  }
  finally {
    planningPollPending = false
  }
}

const startPlanningPoll = () => {
  clearPlanningPoll()
  planningPollTimer = setInterval(refreshPlanning, 500)
  void refreshPlanning()
}

const createAndStartPlanning = async () => {
  if (!canStartPlanning.value || !schema.value || !activeDataset.value) return
  planningBusy.value = true
  planningError.value = ''
  planningResult.value = null
  try {
    const validated = await planningApi.validateVariables({
      projectId: projectId.value,
      canvasId: canvasId.value,
      variables: schema.value.variables
    })
    schema.value.variables = validated.variables
    validatedAt.value = new Date().toLocaleTimeString('zh-CN')

    const created = await planningApi.createPlanning({
      projectId: projectId.value,
      canvasId: canvasId.value,
      name: `${schema.value.projectName}容量规划`,
      variables: schema.value.variables,
      planningLayerId: '1',
      clustering: {
        datasetId: activeDataset.value.id,
        featureIds: [...clustering.featureIds],
        clusterCount: Number(clustering.clusterCount),
        algorithm: clustering.algorithm,
        normalize: clustering.normalize,
        missingDayThreshold: Number(clustering.missingDayThreshold),
        seed: Number(clustering.seed),
        representative: 'nearest-observation'
      },
      optimizer: {
        method: 'adaptive_de_rand_1_bin_radiuslimited',
        maxFuncEvals: Number(optimizer.maxFuncEvals),
        populationSize: Number(optimizer.populationSize),
        maxTimeSeconds: Number(optimizer.maxTimeSeconds),
        seed: Number(optimizer.seed),
        failurePenalty: Number(optimizer.failurePenalty)
      },
      economics: {
        evaluator: 'operating-objective-v1',
        currency: 'CNY'
      }
    })
    planningTask.value = await planningApi.startPlanning(created.id)
    currentStep.value = 5
    push({
      tone: 'success',
      title: '容量规划任务已启动',
      description: `任务 ${created.id.slice(0, 12)}，建议容量将首先被评价`
    })
    startPlanningPoll()
  }
  catch (error) {
    planningError.value = error instanceof Error ? error.message : String(error)
  }
  finally {
    planningBusy.value = false
  }
}

const cancelPlanning = async () => {
  if (!planningTask.value || !planningActive.value) return
  planningBusy.value = true
  try {
    planningTask.value = await planningApi.cancelPlanning(planningTask.value.id)
    await refreshPlanning()
  }
  catch (error) {
    planningError.value = error instanceof Error ? error.message : String(error)
  }
  finally {
    planningBusy.value = false
  }
}

const applyAndSimulate = async () => {
  if (!planningTask.value || !planningResult.value || applyingResult.value) return
  applyingResult.value = true
  planningError.value = ''
  try {
    applyResult.value = await planningApi.applyAndSimulate(planningTask.value.id, {
      expectedProjectUpdatedAt: planningResult.value.projectUpdatedAt,
      mode: 'offline',
      name: `${schema.value?.projectName ?? '容量规划'}最优解全历史仿真`
    })
    push({
      tone: applyResult.value.taskCreated ? 'success' : 'warning',
      title: applyResult.value.taskCreated ? '最优容量已应用，全历史仿真已启动' : '最优容量已应用',
      description: applyResult.value.taskCreated
        ? `仿真任务 ${applyResult.value.taskId?.slice(0, 12) ?? ''}，边界源为未聚类历史数据`
        : applyResult.value.message
    })
  }
  catch (error) {
    planningError.value = error instanceof Error ? error.message : String(error)
  }
  finally {
    applyingResult.value = false
  }
}

watch(
  () => [
    selectedDatasetId.value,
    [...clustering.featureIds].sort().join(','),
    clustering.clusterCount,
    clustering.algorithm,
    clustering.normalize,
    clustering.missingDayThreshold,
    clustering.seed
  ],
  () => {
    scenarioPreview.value = null
  }
)

watch(scenarioPreview, async (preview) => {
  disposeScenarioCharts()
  if (!preview || currentStep.value !== 3) return
  await nextTick()
  renderScenarioCharts()
})

watch(
  () => JSON.stringify({
    convergence: liveConvergencePoints.value,
    capacities: capacityChartItems.value,
    status: planningTask.value?.status,
    busy: planningBusy.value
  }),
  async () => {
    if (currentStep.value !== 5) return
    await nextTick()
    renderSolverCharts()
    scrollPlanningLogToEnd()
  }
)

watch(
  () => [
    planningBusy.value,
    planningTask.value?.status,
    planningTask.value?.progress.completedEvaluations,
    planningTask.value?.progress.bestFitness,
    planningError.value
  ],
  () => {
    if (currentStep.value === 5) appendCurrentPlanningStatus()
  }
)

watch(currentStep, async (step) => {
  await nextTick()
  contentScroller.value?.scrollTo({ top: 0, behavior: 'smooth' })
  if (step === 2 && selectedBoundaryId.value) renderBoundaryPreview()
  else if (step !== 2) {
    boundaryPreviewChart?.dispose()
    boundaryPreviewChart = null
  }
  if (step === 3 && scenarioPreview.value) renderScenarioCharts()
  else if (step !== 3) disposeScenarioCharts()
  if (step === 5) {
    renderSolverCharts()
    startPlanningLogSequence()
  }
  else {
    if (planningLogSequenceTimer) clearTimeout(planningLogSequenceTimer)
    planningLogSequenceTimer = null
    disposeSolverCharts()
  }
})

const resizePlanningCharts = () => {
  boundaryPreviewChart?.resize()
  scenarioCharts.forEach(chart => chart.resize())
  convergenceChart?.resize()
  capacityChangeChart?.resize()
}

onMounted(() => {
  window.addEventListener('resize', resizePlanningCharts)
})
onBeforeUnmount(() => {
  clearPlanningPoll()
  if (planningLogSequenceTimer) clearTimeout(planningLogSequenceTimer)
  window.removeEventListener('resize', resizePlanningCharts)
  boundaryPreviewChart?.dispose()
  disposeScenarioCharts()
  disposeSolverCharts()
})

await Promise.all([loadSchema(), loadDatasetContext()])

useHead(() => ({
  title: schema.value ? `${schema.value.projectName} - 容量规划` : '容量规划 - SynerRoll'
}))
</script>

<template>
  <div class="h-screen min-h-[720px] bg-app-bg">
    <header class="flex h-14 items-center border-b border-blue-900/40 bg-primary px-4 shadow-sm">
      <button
        class="inline-flex h-9 items-center gap-2 rounded-md px-3 text-sm font-medium text-white transition hover:bg-white/10"
        type="button"
        @click="navigateTo('/editor/' + projectId)"
      >
        <span class="text-lg leading-none">←</span>
        <span>返回</span>
      </button>
      <div class="ml-4 hidden h-5 w-px bg-white/25 sm:block" />
      <div class="ml-4 hidden min-w-0 truncate text-sm font-medium text-white sm:block">
        {{ schema?.projectName || project?.name || '项目模型' }} - 容量规划
      </div>
    </header>

    <div class="flex h-[calc(100vh-56px)] min-h-0 gap-2 p-2">
      <div v-if="loading" class="panel-card flex flex-1 items-center justify-center text-sm text-app-muted">
        正在分析画布中的容量设备...
      </div>

      <div v-else-if="errorMessage && !schema" class="panel-card flex flex-1 flex-col items-center justify-center p-8 text-center">
        <div class="text-base font-semibold text-app-danger">容量规划表单加载失败</div>
        <p class="mt-2 max-w-3xl text-sm text-app-muted">{{ errorMessage }}</p>
        <AppButton class="mt-5" label="重试" tone="primary" @click="loadSchema" />
      </div>

      <template v-else-if="schema">
        <aside class="panel-card flex w-72 shrink-0 flex-col overflow-hidden">
          <div class="border-b border-app-border px-5 py-3">
            <h1 class="text-lg font-bold text-app-text">容量规划流程</h1>
          </div>

          <nav class="flex-1 overflow-y-auto px-6 py-6" aria-label="容量规划步骤">
            <template v-for="step in planningSteps" :key="step.id">
              <button
                type="button"
                class="h-[72px] w-full rounded-lg border px-4 py-2.5 text-left transition"
                :class="currentStep === step.id
                  ? 'border-primary bg-primary text-white shadow-md'
                  : completedStepIds.has(step.id)
                    ? 'border-green-200 bg-green-50 text-app-text hover:border-green-300'
                    : 'border-app-border bg-white text-app-text hover:border-primary/40 hover:bg-blue-50/50'"
                :aria-current="currentStep === step.id ? 'step' : undefined"
                @click="selectStep(step.id)"
              >
                <div class="flex h-full items-center gap-3">
                  <span
                    class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-xs font-bold"
                    :class="currentStep === step.id
                      ? 'bg-white text-primary'
                      : completedStepIds.has(step.id)
                        ? 'bg-green-500 text-white'
                        : 'bg-app-panel-soft text-app-muted'"
                  >
                    {{ completedStepIds.has(step.id) && currentStep !== step.id ? '✓' : step.id }}
                  </span>
                  <span class="min-w-0 flex-1">
                    <span class="block truncate text-base">步骤{{ ['一', '二', '三', '四', '五', '六'][step.id - 1] }}：{{ step.title }}</span>
                  </span>
                </div>
              </button>
              <div v-if="step.id < 6" class="flex h-12 items-center justify-center text-3xl font-black leading-none text-primary/45">
                ↓
              </div>
            </template>
          </nav>

          <div class="border-t border-app-border bg-app-panel-soft px-4 py-3">
            <div class="text-xs text-app-muted">当前：<span class="font-semibold text-primary">{{ activeStep.title }}</span></div>
            <div class="mt-1 text-xs text-app-muted">{{ activeStep.description }}</div>
          </div>
        </aside>

        <main class="panel-card flex min-w-0 flex-1 flex-col overflow-hidden">
          <div class="flex items-center justify-between gap-5 border-b border-app-border bg-white px-6 py-4">
            <div>
              <div class="text-xs font-semibold text-primary">步骤 {{ currentStep }} / 6</div>
              <h2 class="mt-0.5 text-xl font-bold text-app-text">{{ activeStep.title }}</h2>
            </div>
          </div>

          <div ref="contentScroller" class="min-h-0 flex-1 overflow-y-auto bg-app-surface p-5">
            <div v-if="errorMessage" class="mb-4 rounded-lg border border-app-danger/30 bg-red-50 px-4 py-3 text-sm text-app-danger">
              {{ errorMessage }}
            </div>
            <div v-if="datasetError && currentStep >= 2 && currentStep <= 3" class="mb-4 rounded-lg border border-app-danger/30 bg-red-50 px-4 py-3 text-sm text-app-danger">
              {{ datasetError }}
            </div>
            <div v-if="planningError && currentStep >= 5" class="mb-4 rounded-lg border border-app-danger/30 bg-red-50 px-4 py-3 text-sm text-app-danger">
              {{ planningError }}
            </div>

            <section v-if="currentStep === 1" class="space-y-4">
              <div v-for="warning in schema.warnings" :key="warning" class="rounded-lg border border-app-warning/30 bg-orange-50 px-4 py-3 text-sm text-app-warning">
                {{ warning }}
              </div>
              <div class="flex items-center justify-between rounded-lg border border-app-border bg-white px-4 py-3">
                <div class="text-xs text-app-muted">
                  <span v-if="validatedAt" class="font-semibold text-app-success">✓ 服务端校验通过（{{ validatedAt }}）</span>
                  <span v-else>容量按设备及物理单位分别优化，修改后需要重新校验。</span>
                </div>
                <div class="flex gap-2">
                  <AppButton label="初步校验配置可行性" tone="neutral" :disabled="loading" @click="loadSchema" />
                  <AppButton label="校验并进入下一步" tone="primary" :disabled="validating || !formValid" @click="validateAndContinue" />
                </div>
              </div>
              <div class="overflow-hidden rounded-lg border border-app-border bg-white">
                <div class="flex items-center justify-between border-b border-app-border px-5 py-4">
                  <div>
                    <h3 class="font-semibold text-app-text">可选设备列表</h3>
                  </div>
                  <span class="text-xs text-app-muted">参与规划 / 可规划设备：<span class="font-bold text-primary">{{ optimizedCount }} / {{ variables.length }}</span></span>
                </div>
                <div class="overflow-x-auto">
                  <table class="w-full min-w-[860px] text-left text-sm">
                    <thead class="bg-app-panel-soft text-sm text-center">
                      <tr>
                        <th class="px-4 py-3 font-medium">设备名称</th>
                        <th class="px-4 py-3 font-medium">设备类型</th>
                        <th class="px-4 py-3 font-medium">变量设置</th>
                        <th class="px-4 py-3 font-medium">参考容量值</th>
                        <th class="px-4 py-3 text-center font-medium">
                          <span class="inline-flex items-center gap-2">
                            参与优化
                            <input
                              type="checkbox"
                              class="h-4 w-4 cursor-pointer accent-primary"
                              :checked="allOptimized"
                              @change="toggleAllParticipation"
                            >
                          </span>
                        </th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr
                        v-for="item in variables"
                        :key="item.componentId"
                        class="border-t transition-colors border-app-border hover:bg-app-panel-soft/70"
                      >
                        <td class="px-4 py-3 text-center">{{ item.componentName }}</td>
                        <td class="px-4 py-3 text-center">{{ item.componentKey }}</td>
                        <td class="px-4 py-3 w-1/3">
                          <template v-if="item.mode === 'optimize'">
                            <div class="flex items-center gap-3 min-w-[360px]">
                              <div class="shrink-0 w-max">
                                <PropertyNumber
                                  :model-value="item.lowerBound"
                                  :unit="item.unit"
                                  :min="capacitySchemaMin(item)"
                                  :max="item.upperBound - capacitySliderStep(item)"
                                  :step="capacitySliderStep(item)"
                                  @update:model-value="handleBoundChange(item, 'lowerBound', $event)"
                                />
                              </div>
                              <div class="flex-1 min-w-[160px]">
                                <div class="variable-slider">
                                  <div class="variable-slider__track">
                                    <div
                                      class="variable-slider__fill"
                                      :style="{
                                        width: ((item.upperBound - item.lowerBound) > 0
                                          ? ((item.suggestedValue - item.lowerBound) / (item.upperBound - item.lowerBound)) * 100
                                          : 0) + '%'
                                      }"
                                    />
                                    <input
                                      type="range"
                                      class="variable-slider__range"
                                      :value="item.suggestedValue"
                                      :min="item.lowerBound"
                                      :max="item.upperBound"
                                      :step="capacitySliderStep(item)"
                                      aria-label="容量推荐值"
                                      @input="updateCapacitySuggestion(item, $event)"
                                    >
                                  </div>
                                </div>
                              </div>
                              <div class="shrink-0 w-max">
                                <PropertyNumber
                                  :model-value="item.upperBound"
                                  :unit="item.unit"
                                  :min="item.lowerBound + capacitySliderStep(item)"
                                  :max="capacitySchemaMax(item)"
                                  :step="capacitySliderStep(item)"
                                  @update:model-value="handleBoundChange(item, 'upperBound', $event)"
                                />
                              </div>
                            </div>
                            <p v-if="variableError(item)" class="mt-1 text-xs text-app-danger">{{ variableError(item) }}</p>
                          </template>
                          <span v-else class="text-xs text-[#86909c]">—</span>
                        </td>
                        <td class="px-4 py-3 w-1/6">
                          <div class="w-max mx-auto">
                            <PropertyNumber
                              :model-value="item.suggestedValue"
                              :unit="item.unit"
                              :min="item.mode === 'optimize' ? item.lowerBound : 0"
                              :max="item.mode === 'optimize' ? item.upperBound : undefined"
                              :step="capacitySliderStep(item)"
                              @update:model-value="handleSuggestedValueChange(item, $event)"
                            />
                          </div>
                        </td>
                        <td class="px-4 py-3 text-center">
                          <PropertySwitch
                            :model-value="item.mode === 'optimize'"
                            @update:model-value="updateParticipation(item, $event)"
                          />
                        </td>
                      </tr>
                    </tbody>
                  </table>
                  <div v-if="!variables.length" class="px-6 py-12 text-center text-sm text-app-muted">当前画布没有可规划容量的设备。</div>
                </div>
              </div>

              <div v-if="activeCanvas" class="overflow-hidden rounded-lg border border-app-border bg-white">
                <div class="flex items-center justify-between border-b border-app-border px-5 py-3">
                  <div>
                    <h3 class="font-semibold text-app-text">画布拓扑预览</h3>
                  </div>
                </div>
                <div class="flex h-[400px] w-full">
                  <ClientOnly>
                    <CanvasWorkspace
                      ref="canvasPreviewRef"
                      :canvas="activeCanvas"
                      readonly
                    />
                  </ClientOnly>
                </div>
              </div>

              
            </section>

            <section v-else-if=”currentStep === 2” class=”space-y-4”>
              <div class=”overflow-hidden rounded-lg border border-app-border bg-white”>
                <div class=”flex items-center justify-between border-b border-app-border px-5 py-4”>
                  <div>
                    <h3 class=”font-semibold text-app-text”>边界配置数据</h3>
                  </div>
                  <span class=”text-xs text-app-muted”>共 <span class=”font-bold text-primary”>{{ configuredBoundaries.length }}</span> 项</span>
                </div>
                <div class=”overflow-x-auto”>
                  <table class=”w-full min-w-[860px] text-left text-sm”>
                    <thead class=”bg-app-panel-soft text-sm text-center”>
                      <tr>
                        <th class=”px-4 py-3 font-medium”>边界名称</th>
                        <th class=”px-4 py-3 font-medium”>物理含义</th>
                        <th class=”px-4 py-3 font-medium”>数据列</th>
                        <th class=”px-4 py-3 font-medium”>时间步长</th>
                        <th class=”px-4 py-3 font-medium”>关联设备</th>
                        <th class=”px-4 py-3 font-medium”>状态</th>
                        <th class=”px-4 py-3 text-center font-medium”>操作</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr
                        v-for=”boundary in configuredBoundaries”
                        :key=”boundary.id”
                        class=”border-t transition-colors border-app-border hover:bg-app-panel-soft/70”
                      >
                        <td class=”px-4 py-3 text-center”>{{ boundary.name }}</td>
                        <td class=”px-4 py-3 text-center”>{{ BOUNDARY_MEANING_LABELS[boundary.meaning] }}</td>
                        <td class=”px-4 py-3 text-center text-app-muted”>{{ boundary.columnName || '—' }}</td>
                        <td class=”px-4 py-3 text-center text-app-muted”>{{ boundary.timeStep || '—' }}</td>
                        <td class=”max-w-72 px-4 py-3 text-center text-app-muted”>
                          <span class=”line-clamp-2” :title=”boundaryRelatedDeviceNames(boundary)”>{{ boundaryRelatedDeviceNames(boundary) }}</span>
                        </td>
                        <td class=”px-4 py-3 text-center”>
                          <span class=”rounded-full px-2.5 py-1 text-xs” :class=”boundaryPointCount(boundary) ? 'bg-green-50 text-app-success' : 'bg-app-panel-soft text-app-muted'”>
                            {{ boundaryPointCount(boundary) ? '已配置' : '待完善' }}
                          </span>
                        </td>
                        <td class=”px-4 py-3 text-center”>
                          <AppButton
                            label=”预览”
                            tone=”primary”
                            size=”sm”
                            :disabled=”!boundaryPointCount(boundary)”
                            @click=”previewBoundary(boundary)”
                          />
                        </td>
                      </tr>
                    </tbody>
                  </table>
                  <div v-if=”!configuredBoundaries.length” class=”px-6 py-12 text-center text-sm text-app-muted”>当前项目还没有边界配置。</div>
                </div>
              </div>

              <div class=”rounded-lg border border-app-border bg-white”>
                <div class=”flex items-center justify-between border-b border-app-border px-5 py-4”>
                  <div>
                    <h3 class=”font-semibold text-app-text”>数据预览</h3>
                  </div>
                  <span v-if=”selectedBoundary” class=”rounded-full bg-primary-soft px-3 py-1 text-xs font-medium text-primary”>
                    正在预览：{{ selectedBoundary.name }}
                  </span>
                </div>

                <div v-if=”selectedBoundary && selectedBoundaryPreviewData” class=”p-4”>
                  <div ref=”boundaryPreviewChartRef” class=”h-72 w-full” />
                </div>

                <div v-else class=”flex h-72 flex-col items-center justify-center px-6 text-center text-app-muted”>
                  <svg class=”mb-3 h-10 w-10” viewBox=”0 0 24 24” fill=”none” stroke=”currentColor” stroke-width=”1.5” aria-hidden=”true”>
                    <path d=”M3 3v18h18M7 16l4-4 4 4 5-6” stroke-linecap=”round” stroke-linejoin=”round” />
                  </svg>
                  <div class=”text-sm font-medium”>{{ selectedBoundary ? '该边界暂无可预览数据' : '数据预览为空' }}</div>
                  <p class=”mt-1 text-xs”>{{ selectedBoundary ? '请返回边界配置导入并保存数据。' : '点击上方边界数据行中的”预览”查看曲线。' }}</p>
                </div>
              </div>

              <div class=”flex items-center justify-between”>
                <AppButton label=”返回边界配置” tone=”neutral” @click=”navigateTo('/boundary/' + projectId)” />
                <AppButton label=”确认数据，进入典型场景聚类” tone=”primary” :disabled=”!activeDataset” @click=”confirmBoundaryData” />
              </div>
            </section>

            <section v-else-if="currentStep === 3" class="space-y-4">
              <div class="rounded-lg border border-app-border bg-white">
                <div class="border-b border-app-border px-5 py-4">
                  <h3 class="font-semibold text-app-text">聚类配置</h3>
                  <p class="mt-1 text-xs text-app-muted">选择典型场景数量、聚类算法和参与聚类的边界特征。</p>
                </div>
                <div class="p-5">
                  <div class="grid grid-cols-[180px_240px_minmax(0,1fr)] items-start gap-4">
                    <label class="block"><span class="field-label">典型场景数量</span><input v-model.number="clustering.clusterCount" class="field-input" type="number" min="2" max="30"></label>
                    <label class="block">
                      <span class="field-label">聚类算法</span>
                      <select v-model="clustering.algorithm" class="field-select">
                        <option value="kmeans">K-means</option>
                        <option value="kmedoids">K-medoids</option>
                      </select>
                    </label>
                    <label class="block">
                      <span class="field-label">聚类特征</span>
                      <select v-model="selectedClusteringFeatureKey" class="field-select" :disabled="!clusteringFeatureOptions.length" @change="updateClusteringFeature">
                        <option v-if="!clusteringFeatureOptions.length" value="">暂无可用特征</option>
                        <option v-for="option in clusteringFeatureOptions" :key="option.key" :value="option.key">
                          {{ option.label }}（{{ option.description }}）
                        </option>
                      </select>
                    </label>
                  </div>

                  <div class="mt-5 flex items-center justify-between border-t border-app-border pt-4">
                    <p class="text-xs text-app-muted">点击后执行 {{ clustering.algorithm === 'kmeans' ? 'K-means' : 'K-medoids' }} 聚类，并停留在本页查看结果。</p>
                    <AppButton label="开始聚类并预览" tone="primary" :disabled="datasetLoading || !canPreviewScenarios" @click="previewTypicalDays" />
                  </div>
                </div>
              </div>

              <div class="rounded-lg border border-app-border bg-white">
                <div class="flex items-center justify-between border-b border-app-border px-5 py-4">
                  <div><h3 class="font-semibold text-app-text">典型场景结果预览</h3><p class="mt-1 text-xs text-app-muted">每个场景展示所选边界的日内曲线及其全年加权。</p></div>
                  <span v-if="scenarioPreview" class="rounded-full bg-green-50 px-3 py-1 text-xs font-medium text-app-success">聚类完成</span>
                </div>

                <div v-if="scenarioPreview" class="p-5">
                  <div class="grid grid-cols-4 gap-3">
                    <div class="rounded-lg bg-app-panel-soft p-3"><div class="text-xs text-app-muted">有效自然日</div><div class="mt-1 text-lg font-bold text-app-text">{{ scenarioPreview.quality.validDayCount }}</div></div>
                    <div class="rounded-lg bg-app-panel-soft p-3"><div class="text-xs text-app-muted">排除自然日</div><div class="mt-1 text-lg font-bold text-app-text">{{ scenarioPreview.quality.excludedDayCount }}</div></div>
                    <div class="rounded-lg bg-app-panel-soft p-3"><div class="text-xs text-app-muted">聚类迭代</div><div class="mt-1 text-lg font-bold text-app-text">{{ scenarioPreview.quality.iterations }}</div></div>
                    <div class="rounded-lg bg-app-panel-soft p-3"><div class="text-xs text-app-muted">收敛状态</div><div class="mt-1 text-lg font-bold" :class="scenarioPreview.quality.converged ? 'text-app-success' : 'text-app-warning'">{{ scenarioPreview.quality.converged ? '已收敛' : '未收敛' }}</div></div>
                  </div>
                  <div class="mt-5 grid grid-cols-2 gap-4">
                    <article v-for="(scenario, scenarioIndex) in scenarioPreview.scenarios" :key="scenario.scenarioId" class="overflow-hidden rounded-lg border border-app-border bg-white">
                      <div class="flex items-center justify-between gap-4 border-b border-app-border bg-app-panel-soft px-4 py-3">
                        <div>
                          <div class="text-sm font-semibold text-app-text">典型场景 {{ scenarioIndex + 1 }}</div>
                          <div class="mt-0.5 text-xs text-app-muted">代表日期 {{ scenario.representativeDate }} · 覆盖 {{ scenario.memberDates.length }} 个自然日</div>
                        </div>
                        <div class="shrink-0 text-right">
                          <div class="rounded-full bg-primary px-3 py-1 text-xs font-semibold text-white">场景加权 {{ (scenario.probability * 100).toFixed(1) }}%</div>
                          <div class="mt-1 text-xs text-app-muted">权重 {{ formatNumber(scenario.weightDays) }} 天</div>
                        </div>
                      </div>
                      <div :ref="element => setScenarioChartRef(scenario.scenarioId, element)" class="h-64 w-full px-2 py-1" />
                    </article>
                  </div>
                  <div v-for="warning in scenarioPreview.quality.warnings" :key="warning" class="mt-4 rounded-lg border border-app-warning/30 bg-orange-50 px-4 py-3 text-xs text-app-warning">{{ warning }}</div>
                </div>

                <div v-else class="flex min-h-56 flex-col items-center justify-center px-6 py-10 text-center">
                  <div class="flex h-12 w-12 items-center justify-center rounded-full bg-app-panel-soft text-2xl text-primary">◌</div>
                  <div class="mt-3 font-medium text-app-text">等待生成典型场景</div>
                  <p class="mt-1 text-sm text-app-muted">完成上方配置后，聚类结果和场景权重会在这里预览。</p>
                </div>
              </div>

              <div class="flex items-center justify-between rounded-lg border border-app-border bg-white px-5 py-4">
                <p class="text-xs text-app-muted">请先核对各场景曲线和加权，确认后再进入下一步。</p>
                <AppButton label="确认典型场景，进入规划目标设置" tone="primary" :disabled="!scenarioPreview" @click="confirmTypicalScenarios" />
              </div>
            </section>

            <section v-else-if="currentStep === 4" class="space-y-4">
              <div class="rounded-lg border border-primary/25 bg-blue-50 px-5 py-4">
                <div class="font-semibold text-app-text">当前阶段采用运行目标最小化</div>
                <p class="mt-1 text-sm leading-6 text-app-muted">容量方案根据典型场景权重汇总真实运行优化目标，避免使用尚未确认口径的经济性占位数字。</p>
              </div>

              <div class="grid grid-cols-2 gap-4">
                <div class="rounded-lg border-2 border-primary bg-white p-5 shadow-sm">
                  <div class="flex items-start justify-between gap-3">
                    <div><div class="text-xs font-semibold text-primary">当前启用目标</div><h3 class="mt-2 text-lg font-bold text-app-text">年度加权运行目标最小</h3></div>
                    <span class="rounded-full bg-primary px-3 py-1 text-xs font-semibold text-white">已启用</span>
                  </div>
                  <p class="mt-4 text-sm leading-6 text-app-muted">使用每个典型场景的求解目标乘以其年度权重，取总目标最小的容量组合。</p>
                  <div class="mt-4 rounded-md bg-app-panel-soft px-3 py-2 text-xs text-app-muted">评价器：<code class="text-app-text">operating-objective-v1</code></div>
                </div>
                <div class="rounded-lg border border-dashed border-app-border bg-white p-5">
                  <div class="text-xs font-semibold text-app-muted">后续优化预留</div><h3 class="mt-2 text-lg font-bold text-app-text">全生命周期经济性</h3>
                  <p class="mt-4 text-sm leading-6 text-app-muted">待设备投资、维护、折旧、残值和能源价格口径确认后开放。</p><span class="mt-4 inline-flex rounded-full bg-app-panel-soft px-3 py-1 text-xs text-app-muted">暂未启用</span>
                </div>
                <div class="rounded-lg border border-dashed border-app-border bg-white p-5">
                  <div class="text-xs font-semibold text-app-muted">指标结构预留</div><h3 class="mt-2 text-lg font-bold text-app-text">NPV / IRR</h3>
                  <p class="mt-4 text-sm leading-6 text-app-muted">预留净现值与内部收益率的参数、结果和约束展示区域。</p><span class="mt-4 inline-flex rounded-full bg-app-panel-soft px-3 py-1 text-xs text-app-muted">待定义</span>
                </div>
                <div class="rounded-lg border border-dashed border-app-border bg-white p-5">
                  <div class="text-xs font-semibold text-app-muted">指标结构预留</div><h3 class="mt-2 text-lg font-bold text-app-text">LCOE / 综合成本</h3>
                  <p class="mt-4 text-sm leading-6 text-app-muted">预留平准化成本、多目标权重和约束边界的配置区域。</p><span class="mt-4 inline-flex rounded-full bg-app-panel-soft px-3 py-1 text-xs text-app-muted">待定义</span>
                </div>
              </div>

              <div class="flex items-center justify-between rounded-lg border border-app-border bg-white px-5 py-4">
                <p class="text-xs text-app-muted">后续扩展不会改变六步流程，只会在本步骤补充指标和经济参数。</p>
                <AppButton label="确认当前目标，进入求解设置" tone="primary" @click="confirmObjective" />
              </div>
            </section>

            <section v-else-if="currentStep === 5" class="space-y-4">
              <div class="rounded-lg border border-app-border bg-white px-4 py-3">
                <div class="grid grid-cols-[repeat(5,minmax(0,1fr))_auto] items-end gap-3">
                  <label class="block"><span class="field-label">最大评价次数</span><input v-model.number="optimizer.maxFuncEvals" class="field-input" type="number" min="2" max="10000"></label>
                  <label class="block"><span class="field-label">种群规模</span><input v-model.number="optimizer.populationSize" class="field-input" type="number" min="2" max="500"></label>
                  <label class="block"><span class="field-label">最长时间（秒）</span><input v-model.number="optimizer.maxTimeSeconds" class="field-input" type="number" min="1"></label>
                  <label class="block"><span class="field-label">随机种子</span><input v-model.number="optimizer.seed" class="field-input" type="number"></label>
                  <label class="block"><span class="field-label">失败惩罚</span><input v-model.number="optimizer.failurePenalty" class="field-input" type="number" min="1"></label>
                  <AppButton class="mb-px whitespace-nowrap" label="创建并启动容量规划" tone="primary" :disabled="!canStartPlanning" @click="createAndStartPlanning" />
                </div>
              </div>

              <div class="grid grid-cols-[330px_minmax(0,1fr)] items-stretch gap-4">
                <div class="flex min-h-0 flex-col gap-3">
                  <div class="flex min-h-0 flex-1 flex-col overflow-hidden rounded-lg border border-app-border bg-white">
                    <div class="flex items-start justify-between gap-3 border-b border-app-border px-4 py-3">
                      <div class="min-w-0">
                        <h3 class="text-sm font-semibold text-app-text">容量规划运行日志</h3>
                        <p class="mt-0.5 text-xs leading-5 text-app-muted">依次核对前置配置，并持续展示求解状态。</p>
                      </div>
                      <div
                        class="inline-flex shrink-0 items-center gap-2 rounded-full px-2.5 py-1 text-xs font-semibold"
                        :class="{
                          'bg-orange-50 text-app-warning': solverIndicator.tone === 'checking',
                          'bg-blue-50 text-primary': solverIndicator.tone === 'running',
                          'bg-green-50 text-app-success': solverIndicator.tone === 'completed',
                          'bg-red-50 text-app-danger': solverIndicator.tone === 'failed',
                          'bg-app-panel-soft text-app-muted': solverIndicator.tone === 'ready' || solverIndicator.tone === 'cancelled'
                        }"
                      >
                        <span
                          class="h-2 w-2 rounded-full"
                          :class="{
                            'animate-pulse bg-app-warning': solverIndicator.tone === 'checking',
                            'animate-pulse bg-primary': solverIndicator.tone === 'running',
                            'bg-app-success': solverIndicator.tone === 'completed',
                            'bg-app-danger': solverIndicator.tone === 'failed',
                            'bg-app-muted': solverIndicator.tone === 'ready' || solverIndicator.tone === 'cancelled'
                          }"
                        />
                        {{ solverIndicator.label }}
                      </div>
                    </div>

                    <div ref="planningLogRef" class="planning-log-surface min-h-0 flex-1 overflow-y-auto px-4 py-2 font-mono text-xs">
                      <TransitionGroup name="planning-log" tag="div" class="relative z-10">
                        <div v-for="(entry, index) in planningLogFeed" :key="entry.id" class="planning-log-line flex gap-3 border-b border-app-border/70 py-3 last:border-b-0">
                          <span
                            class="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-[10px] font-bold shadow-sm"
                            :class="entry.state === 'done' ? 'bg-emerald-500 text-white' : entry.state === 'active' ? 'planning-log-active-dot bg-blue-500 text-white' : entry.state === 'error' ? 'bg-red-500 text-white' : 'bg-gray-300 text-gray-600'"
                          >{{ entry.state === 'done' ? '✓' : entry.state === 'active' ? '›' : entry.state === 'error' ? '!' : index + 1 }}</span>
                          <div class="min-w-0 flex-1">
                            <div class="flex items-start justify-between gap-2">
                              <div class="font-medium" :class="entry.state === 'error' ? 'text-app-danger' : entry.state === 'pending' ? 'text-app-muted' : 'text-app-text'">{{ entry.title }}</div>
                              <time class="shrink-0 text-[10px] text-app-muted/75">{{ entry.time }}</time>
                            </div>
                            <div class="mt-1 leading-5 text-app-muted">{{ entry.detail }}</div>
                          </div>
                        </div>
                      </TransitionGroup>
                      <div class="planning-thinking relative z-10 mt-2 flex items-center gap-2 rounded-md border border-primary/15 bg-white/70 px-3 py-2 text-primary shadow-sm backdrop-blur-sm">
                        <span class="planning-thinking-dot" />
                        <span class="planning-thinking-dot" />
                        <span class="planning-thinking-dot" />
                        <span class="ml-1 min-w-0 flex-1 truncate">{{ solverThinkingText }}</span>
                        <span class="planning-log-cursor">▍</span>
                      </div>
                      <div v-if="planningError && planningTask?.status !== 'failed' && planningTask?.status !== 'cancelled'" class="relative z-10 mt-2 border-t border-app-danger/20 py-3 text-app-danger">[错误] {{ planningError }}</div>
                    </div>

                    <div class="border-t border-app-border px-4 py-3">
                      <div class="h-1.5 overflow-hidden rounded-full bg-app-panel-soft">
                        <div class="h-full rounded-full bg-primary transition-all duration-300" :style="{ width: progressPercent + '%' }" />
                      </div>
                      <div class="mt-2 text-right text-xs text-app-muted">{{ planningTask?.progress.completedEvaluations ?? 0 }} / {{ planningTask?.progress.maxFuncEvals ?? optimizer.maxFuncEvals }} 次评价 · {{ progressPercent }}%</div>
                    </div>
                  </div>
                  <AppButton class="w-full justify-center" label="终止容量规划" tone="danger" :disabled="!planningActive || planningBusy" @click="cancelPlanning" />
                </div>

                <div class="space-y-4">
                  <div class="overflow-hidden rounded-lg border border-app-border bg-white">
                  <div class="flex items-center justify-between border-b border-app-border px-4 py-3">
                    <div>
                      <h3 class="text-sm font-semibold text-app-text">黑箱求解收敛曲线</h3>
                      <p class="mt-0.5 text-xs text-app-muted">随每次评价滚动更新，本次目标与当前最优同步展示。</p>
                    </div>
                    <div class="text-right text-xs">
                      <div class="text-app-muted">当前最优</div>
                      <div class="mt-0.5 font-bold text-primary">{{ planningTask?.progress.bestFitness === null || planningTask?.progress.bestFitness === undefined ? '—' : formatNumber(planningTask.progress.bestFitness) }}</div>
                    </div>
                  </div>
                  <div ref="convergenceChartRef" class="h-72 w-full px-2 py-1" />
                  </div>

                  <div class="overflow-hidden rounded-lg border border-app-border bg-white">
                    <div class="flex items-center justify-between border-b border-app-border px-4 py-3">
                      <div>
                        <h3 class="text-sm font-semibold text-app-text">容量规划参数变化</h3>
                        <p class="mt-0.5 text-xs text-app-muted">对比当前容量与黑箱求解中的实时最优容量。</p>
                      </div>
                      <span class="rounded-full bg-primary-soft px-3 py-1 text-xs font-medium text-primary">{{ capacityChartItems.length }} 个参数</span>
                    </div>
                    <div ref="capacityChangeChartRef" class="h-72 w-full px-2 py-1" />
                  </div>
                </div>
              </div>
            </section>

            <section v-else class="space-y-4">
              <template v-if="planningResult">
                <div class="flex items-start justify-between gap-6 rounded-lg border border-primary/25 bg-blue-50 px-5 py-4">
                  <div>
                    <div class="text-xs font-semibold text-primary">当前最优方案依据</div>
                    <h3 class="mt-1 text-lg font-bold text-app-text">年度典型场景加权运行目标最小</h3>
                    <p class="mt-1 text-xs leading-5 text-app-muted">综合 {{ scenarioPreview?.scenarios.length ?? 0 }} 个典型场景的全年权重，从 {{ planningResult.evaluationCount }} 次候选评价中选出。</p>
                  </div>
                  <span class="rounded-full bg-primary px-3 py-1 text-xs font-semibold text-white">最优方案</span>
                </div>

                <div class="grid grid-cols-3 gap-3">
                  <div class="rounded-lg border border-primary/25 bg-white p-4"><div class="text-xs text-app-muted">最优运行目标</div><div class="mt-1 text-2xl font-bold text-primary">{{ formatNumber(planningResult.fitness) }}</div></div>
                  <div class="rounded-lg border border-app-border bg-white p-4"><div class="text-xs text-app-muted">候选评价</div><div class="mt-1 text-2xl font-bold text-app-text">{{ planningResult.evaluationCount }}</div></div>
                  <div class="rounded-lg border border-app-border bg-white p-4"><div class="text-xs text-app-muted">失败评价</div><div class="mt-1 text-2xl font-bold" :class="planningResult.failedEvaluationCount ? 'text-app-warning' : 'text-app-success'">{{ planningResult.failedEvaluationCount }}</div></div>
                </div>

                <div v-for="warning in planningResult.warnings" :key="warning" class="rounded-lg border border-app-warning/30 bg-orange-50 px-4 py-3 text-xs text-app-warning">{{ warning }}</div>

                <div class="overflow-x-auto rounded-lg border border-app-border bg-white">
                  <div class="flex items-center justify-between border-b border-app-border px-5 py-4"><div><h3 class="font-semibold text-app-text">优化前后容量对比</h3><p class="mt-1 text-xs text-app-muted">蓝色列为将要写入模型的最优容量。</p></div></div>
                  <table class="w-full min-w-[850px] text-left text-sm">
                    <thead class="bg-app-panel-soft text-xs text-app-muted">
                      <tr><th class="px-4 py-3 font-medium">设备</th><th class="px-4 py-3 font-medium">设备类型</th><th class="px-4 py-3 font-medium">优化前</th><th class="bg-blue-50 px-4 py-3 font-semibold text-primary">优化后</th><th class="px-4 py-3 font-medium">容量变化</th><th class="px-4 py-3 font-medium">变化率</th><th class="px-4 py-3 font-medium">规划方式</th></tr>
                    </thead>
                    <tbody>
                      <tr v-for="item in planningResult.variables" :key="item.componentId" class="border-t border-app-border">
                        <td class="px-4 py-4 font-semibold text-app-text">{{ item.componentName }}</td>
                        <td class="px-4 py-4 text-app-muted">{{ item.componentKey }}</td>
                        <td class="px-4 py-4 text-app-text">{{ formatNumber(item.currentValue) }} {{ item.unit }}</td>
                        <td class="bg-blue-50/60 px-4 py-4 text-base font-bold text-primary">{{ formatNumber(item.optimalValue) }} {{ item.unit }}</td>
                        <td class="px-4 py-4" :class="item.optimalValue > item.currentValue ? 'text-app-success' : item.optimalValue < item.currentValue ? 'text-app-warning' : 'text-app-muted'">{{ item.optimalValue >= item.currentValue ? '+' : '' }}{{ formatNumber(item.optimalValue - item.currentValue) }} {{ item.unit }}</td>
                        <td class="px-4 py-4" :class="(item.changeRate ?? 0) > 0 ? 'text-app-success' : (item.changeRate ?? 0) < 0 ? 'text-app-warning' : 'text-app-muted'">{{ item.changeRate === null ? '基准为 0' : ((item.changeRate >= 0 ? '+' : '') + (item.changeRate * 100).toFixed(2) + '%') }}</td>
                        <td class="px-4 py-4 text-app-muted">{{ item.mode === 'optimize' ? '参与优化' : '保持固定' }}</td>
                      </tr>
                    </tbody>
                  </table>
                </div>

                <div class="rounded-lg border border-green-200 bg-green-50 p-5">
                  <div class="flex items-end justify-between gap-8">
                    <div>
                      <h3 class="font-semibold text-app-text">应用最优容量并启动滚动优化求解</h3>
                      <p class="mt-1 max-w-3xl text-xs leading-5 text-app-muted">系统会校验项目版本，一次性把上表最优容量写回模型，再使用完整历史边界数据启动多时间尺度滚动求解。</p>
                      <div v-if="applyResult" class="mt-3 rounded-md border border-green-200 bg-white px-4 py-3 text-sm">
                        <div class="font-semibold" :class="applyResult.taskCreated ? 'text-app-success' : 'text-app-warning'">{{ applyResult.taskCreated ? '最优容量已配置，滚动求解任务已创建' : '最优容量已配置，但任务创建失败' }}</div>
                        <div class="mt-1 text-xs text-app-muted">{{ applyResult.simStartTime }} 至 {{ applyResult.simEndTime }}</div><p v-if="applyResult.message" class="mt-1 text-xs text-app-warning">{{ applyResult.message }}</p>
                      </div>
                    </div>
                    <div class="flex shrink-0 flex-col items-end gap-2">
                      <AppButton label="配置最优容量并启动滚动求解" tone="green" :disabled="applyingResult || Boolean(applyResult?.projectApplied)" @click="applyAndSimulate" />
                      <button v-if="applyResult?.taskCreated" type="button" class="text-xs font-medium text-primary hover:underline" @click="navigateTo('/tasks')">查看滚动求解任务 →</button>
                    </div>
                  </div>
                </div>
              </template>

              <div v-else class="flex min-h-[480px] flex-col items-center justify-center rounded-lg border border-dashed border-app-border bg-white px-8 text-center">
                <div class="flex h-14 w-14 items-center justify-center rounded-full bg-app-panel-soft text-3xl text-primary">◇</div>
                <h3 class="mt-4 text-lg font-semibold text-app-text">尚未生成容量配置方案</h3>
                <p class="mt-2 max-w-xl text-sm leading-6 text-app-muted">完成求解后，这里会显示最优指标、优化前后容量对比，以及将方案应用到模型的操作。</p>
                <AppButton class="mt-5" label="前往求解设置" tone="primary" @click="selectStep(5)" />
              </div>
            </section>
          </div>
        </main>
      </template>
    </div>
  </div>
</template>

<style scoped>
.variable-slider {
  display: flex;
  align-items: center;
  gap: 8px;
  width: 100%;
}

.variable-slider__track {
  position: relative;
  flex: 1;
  height: 4px;
  background: #dde1e6;
  border-radius: 2px;
  overflow: visible;
}

.variable-slider__fill {
  position: absolute;
  left: 0;
  top: 0;
  height: 100%;
  background: #0a4da2;
  border-radius: 2px;
  pointer-events: none;
}

.variable-slider__range {
  position: absolute;
  top: 50%;
  left: 0;
  width: 100%;
  height: 20px;
  transform: translateY(-50%);
  background: transparent;
  cursor: pointer;
  margin: 0;
  -webkit-appearance: none;
  appearance: none;
}

.variable-slider__range::-webkit-slider-thumb {
  width: 12px;
  height: 12px;
  border-radius: 50%;
  background: #ffffff;
  border: 2px solid #0a4da2;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.15);
  cursor: pointer;
  -webkit-appearance: none;
  transition: transform 0.15s ease;
}

.variable-slider__range::-webkit-slider-thumb:hover {
  transform: scale(1.15);
}

.variable-slider__range::-moz-range-thumb {
  width: 12px;
  height: 12px;
  border-radius: 50%;
  background: #ffffff;
  border: 2px solid #0a4da2;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.15);
  cursor: pointer;
}

.planning-log-surface {
  position: relative;
  isolation: isolate;
  background:
    radial-gradient(circle at 12% 0%, rgb(22 93 255 / 10%), transparent 34%),
    linear-gradient(180deg, #f8fafc 0%, #eef2f7 100%);
}

.planning-log-surface::before {
  position: absolute;
  z-index: 0;
  inset: 0;
  background: linear-gradient(180deg, transparent 0%, rgb(22 93 255 / 6%) 48%, transparent 100%);
  content: '';
  pointer-events: none;
  transform: translateY(-100%);
  animation: planning-log-scan 4s linear infinite;
}

.planning-log-line {
  transition: background-color 180ms ease;
}

.planning-log-line:hover {
  background-color: rgb(255 255 255 / 55%);
}

.planning-log-enter-active {
  transition:
    opacity 360ms ease,
    transform 360ms cubic-bezier(0.22, 1, 0.36, 1),
    filter 360ms ease;
}

.planning-log-enter-from {
  opacity: 0;
  filter: blur(4px);
  transform: translateY(12px) scale(0.985);
}

.planning-log-active-dot {
  box-shadow: 0 0 0 0 rgb(59 130 246 / 42%);
  animation: planning-log-pulse 1.45s ease-out infinite;
}

.planning-thinking {
  overflow: hidden;
}

.planning-thinking::after {
  position: absolute;
  inset: 0;
  background: linear-gradient(105deg, transparent 30%, rgb(22 93 255 / 8%) 50%, transparent 70%);
  content: '';
  pointer-events: none;
  transform: translateX(-100%);
  animation: planning-thinking-sheen 2.8s ease-in-out infinite;
}

.planning-thinking-dot {
  z-index: 1;
  width: 5px;
  height: 5px;
  flex: none;
  border-radius: 999px;
  background: #165dff;
  animation: planning-thinking-bounce 1.2s ease-in-out infinite;
}

.planning-thinking-dot:nth-child(2) {
  animation-delay: 160ms;
}

.planning-thinking-dot:nth-child(3) {
  animation-delay: 320ms;
}

.planning-log-cursor {
  animation: planning-log-cursor 850ms steps(1) infinite;
}

@keyframes planning-log-scan {
  to {
    transform: translateY(100%);
  }
}

@keyframes planning-log-pulse {
  70% {
    box-shadow: 0 0 0 7px rgb(59 130 246 / 0%);
  }

  100% {
    box-shadow: 0 0 0 0 rgb(59 130 246 / 0%);
  }
}

@keyframes planning-thinking-sheen {
  55%,
  100% {
    transform: translateX(100%);
  }
}

@keyframes planning-thinking-bounce {
  0%,
  60%,
  100% {
    opacity: 0.35;
    transform: translateY(0);
  }

  30% {
    opacity: 1;
    transform: translateY(-3px);
  }
}

@keyframes planning-log-cursor {
  0%,
  48% {
    opacity: 1;
  }

  49%,
  100% {
    opacity: 0;
  }
}

@media (prefers-reduced-motion: reduce) {
  .planning-log-surface::before,
  .planning-log-active-dot,
  .planning-thinking::after,
  .planning-thinking-dot,
  .planning-log-cursor {
    animation: none;
  }

  .planning-log-enter-active {
    transition: none;
  }
}
</style>
