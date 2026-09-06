<script setup lang="ts">
import type { TaskDataRow, TaskTraceStep } from '~~/types/api'
import type { Project } from '~~/types/project'
import { useTaskApi } from '~~/composables/api/useTaskApi'
import {
  buildDeviceOutputCatalog,
  defaultDisplayUnit,
  timestampToMinutes,
  type DeviceOutputLiveData,
  type DeviceOutputVariable
} from '~~/utils/deviceOutputData'
import {
  readDeviceOutputAnalysisState,
  saveDeviceOutputAnalysisState
} from '~~/utils/deviceOutputState'
import DeviceOutputChart from './device-output/DeviceOutputChart.vue'
import DeviceParameterDrawer from './device-output/DeviceParameterDrawer.vue'
import PropertyMultiSelect from './PropertyMultiSelect.vue'
import DeviceVariableSelector from './device-output/DeviceVariableSelector.vue'

interface LayerOption {
  value: string
  label: string
}

interface DeviceChartState {
  id: string
  title: string
  selectedKeys: string[]
  units: Record<string, string>
  zoomStart: number
  zoomEnd: number
  analysisMode: 'range' | 'point'
  traceStep: number | null
  traceData: DeviceOutputLiveData
  traceLoading: boolean
  traceError: string
}

const props = defineProps<{
  taskId: string
  canvasId: string
  project: Project | null
  liveData: DeviceOutputLiveData
  liveDataUnits: Record<string, string>
  layerOptions: LayerOption[]
  simEndTime?: string | null
}>()

const selectedLayerIds = ref<string[]>([])
const charts = ref<DeviceChartState[]>([])
const taskApi = useTaskApi()
const traceSteps = ref<TaskTraceStep[]>([])
const traceStepsLoading = ref(false)
const traceStepsError = ref('')
const activeChartId = ref('')
const selectorOpen = ref(false)
const parameterOpen = ref(false)
const parameterDeviceId = ref('')
const defaultSelectionInitialized = ref(false)
const traceDataCache = new Map<number, DeviceOutputLiveData>()
let chartSequence = 0
let stateTaskId = props.taskId
let stateReady = false

function createChart(selectedKeys: string[] = [], displayIndex = charts.value.length + 1): DeviceChartState {
  chartSequence += 1
  return {
    id: `device-output-chart-${chartSequence}`,
    title: displayIndex === 1 ? '设备出力分析' : `设备出力分析 ${displayIndex}`,
    selectedKeys,
    units: {},
    zoomStart: 0,
    zoomEnd: 100,
    analysisMode: 'range',
    traceStep: null,
    traceData: {},
    traceLoading: false,
    traceError: ''
  }
}

function resetCharts(): void {
  chartSequence = 0
  const initial = createChart()
  charts.value = [initial]
  activeChartId.value = initial.id
  defaultSelectionInitialized.value = false
}

function restoreCharts(taskId: string): boolean {
  const stored = readDeviceOutputAnalysisState(taskId)
  if (!stored?.charts.length) return false

  selectedLayerIds.value = [...(stored.selectedLayerIds?.length
    ? stored.selectedLayerIds
    : stored.selectedLayerId
      ? [stored.selectedLayerId]
      : [])]
  charts.value = stored.charts.map(chart => ({
    ...chart,
    selectedKeys: [...chart.selectedKeys],
    units: { ...chart.units },
    traceData: {},
    traceLoading: false,
    traceError: ''
  }))
  activeChartId.value = charts.value.some(chart => chart.id === stored.activeChartId)
    ? stored.activeChartId
    : charts.value[0]!.id
  chartSequence = charts.value.reduce((maximum, chart) => {
    const sequence = Number(chart.id.match(/(\d+)$/)?.[1] ?? 0)
    return Math.max(maximum, sequence)
  }, charts.value.length)
  normalizeDefaultChartTitles()
  defaultSelectionInitialized.value = true
  return true
}

function saveCurrentState(taskId = stateTaskId): void {
  if (!stateReady || !taskId || !charts.value.length) return
  saveDeviceOutputAnalysisState(taskId, {
    selectedLayerIds: [...selectedLayerIds.value],
    activeChartId: activeChartId.value,
    charts: charts.value.map(chart => ({
      id: chart.id,
      title: chart.title,
      selectedKeys: [...chart.selectedKeys],
      units: { ...chart.units },
      zoomStart: chart.zoomStart,
      zoomEnd: chart.zoomEnd,
      analysisMode: chart.analysisMode,
      traceStep: chart.traceStep
    }))
  })
}

const catalog = computed(() => buildDeviceOutputCatalog(
  props.liveData,
  props.liveDataUnits,
  props.project,
  props.canvasId
))

const allVariables = computed(() => catalog.value.flatMap(device => device.variables))
const variableByKey = computed(() => new Map(allVariables.value.map(variable => [variable.key, variable])))
const activeChart = computed(() => charts.value.find(chart => chart.id === activeChartId.value) ?? charts.value[0])
const selectedLayerLabels = computed(() => selectedLayerIds.value.map(layerOptionsLabel))
const selectedLayerSummary = computed(() => selectedLayerLabels.value.join('；') || '请选择时间层')
const layerLabelMap = computed(() => Object.fromEntries(props.layerOptions.map(option => [option.value, option.label])))
const activeVariableSummary = computed(() => {
  const labels = (activeChart.value?.selectedKeys ?? [])
    .map(key => variableByKey.value.get(key)?.displayName)
    .filter((label): label is string => Boolean(label))
  return labels.join('；') || '选择设备变量'
})

const maximumMinute = computed<number | undefined>(() => {
  const raw = props.simEndTime?.trim()
  if (!raw) return undefined
  const match = /^(\d{1,3}):(\d{2})/.exec(raw)
  if (!match) return undefined
  const minute = Number(match[1]) * 60 + Number(match[2])
  return minute > 0 ? minute : undefined
})

function preferredVariables(): DeviceOutputVariable[] {
  const available = allVariables.value.filter(variable => (
    variable.layerIds.some(layerId => selectedLayerIds.value.includes(layerId))
    && variable.componentType !== 'BUS'
  ))
  const preferredNames = [
    'E_GP', 'E_CHP', 'E_HYDRO', 'E_WT', 'E_PV', 'E_ES_out', 'E_PS_out',
    'E_GRID_in', 'E_GRID_out'
  ]
  const preferred = preferredNames
    .map(name => available.find(variable => variable.baseVarName === name))
    .filter((variable): variable is DeviceOutputVariable => Boolean(variable))
  return [...new Map([...preferred, ...available].map(variable => [variable.key, variable])).values()].slice(0, 3)
}

function seedUnits(chart: DeviceChartState): void {
  for (const key of chart.selectedKeys) {
    const variable = variableByKey.value.get(key)
    if (!variable || chart.units[variable.dimension]) continue
    chart.units[variable.dimension] = defaultDisplayUnit(variable.dimension, variable.originalUnit)
  }
}

function layerOptionsLabel(layerId: string): string {
  return props.layerOptions.find(option => option.value === layerId)?.label ?? `时层${layerId}`
}

function normalizeDefaultChartTitles(): void {
  charts.value.forEach((chart, index) => {
    if (!/^设备出力分析(?:\s+\d+)?$/.test(chart.title.trim())) return
    chart.title = index === 0 ? '设备出力分析' : `设备出力分析 ${index + 1}`
  })
}

function resetChartContents(chart: DeviceChartState): void {
  chart.title = '设备出力分析'
  chart.selectedKeys = []
  chart.units = {}
  chart.zoomStart = 0
  chart.zoomEnd = 100
  chart.analysisMode = 'range'
  chart.traceStep = null
  chart.traceData = {}
  chart.traceLoading = false
  chart.traceError = ''
}

function rowsToLiveData(rows: TaskDataRow[]): DeviceOutputLiveData {
  const merged: DeviceOutputLiveData = {}
  for (const row of rows) {
    const value = Number(row.value)
    if (!Number.isFinite(value)) continue
    const key = `${row.sourceId}|${row.varName}`
    const layerId = String(row.layerId)
    merged[key] ??= {}
    merged[key]![layerId] ??= []
    merged[key]![layerId]!.push({
      ts: String(row.ts),
      value: Math.abs(value)
    })
  }
  for (const layers of Object.values(merged)) {
    for (const points of Object.values(layers)) {
      points.sort((left, right) => timestampToMinutes(left.ts) - timestampToMinutes(right.ts))
    }
  }
  return merged
}

function traceTimelineOptions(): TaskTraceStep[] {
  const selected = new Set(selectedLayerIds.value)
  const representativeByTime = new Map<string, TaskTraceStep>()
  const layerOrder = new Map(selectedLayerIds.value.map((layerId, index) => [layerId, index]))
  for (const step of traceSteps.value) {
    if (!selected.has(step.layerId)) continue
    const current = representativeByTime.get(step.simTime)
    if (!current || (layerOrder.get(step.layerId) ?? Infinity) < (layerOrder.get(current.layerId) ?? Infinity)) {
      representativeByTime.set(step.simTime, step)
    }
  }
  return [...representativeByTime.values()]
    .sort((left, right) => timestampToMinutes(left.simTime) - timestampToMinutes(right.simTime) || left.step - right.step)
}

function currentTraceTime(chart: DeviceChartState): string | undefined {
  return traceSteps.value.find(step => step.step === chart.traceStep)?.simTime
}

function mergeLiveData(target: DeviceOutputLiveData, source: DeviceOutputLiveData): void {
  for (const [key, layers] of Object.entries(source)) {
    target[key] ??= {}
    for (const [layerId, points] of Object.entries(layers)) {
      target[key]![layerId] = points
    }
  }
}

async function loadTraceData(chart: DeviceChartState): Promise<void> {
  const simTime = currentTraceTime(chart)
  if (!simTime) {
    chart.traceData = {}
    chart.traceLoading = false
    return
  }

  const selected = new Set(selectedLayerIds.value)
  const matchingSteps = traceSteps.value.filter(step => selected.has(step.layerId) && step.simTime === simTime)
  const requestSignature = `${simTime}|${selectedLayerIds.value.join('|')}`

  const requestTaskId = props.taskId
  chart.traceLoading = true
  chart.traceError = ''
  try {
    const snapshots = await Promise.all(matchingSteps.map(async (step) => {
      const cached = traceDataCache.get(step.step)
      if (cached) return cached
      const response = await taskApi.getTraceData(requestTaskId, step.step)
      const traceData = rowsToLiveData(response.rows ?? [])
      traceDataCache.set(step.step, traceData)
      return traceData
    }))
    const currentSignature = `${currentTraceTime(chart) ?? ''}|${selectedLayerIds.value.join('|')}`
    if (props.taskId !== requestTaskId || currentSignature !== requestSignature) return
    const merged: DeviceOutputLiveData = {}
    for (const snapshot of snapshots) mergeLiveData(merged, snapshot)
    chart.traceData = merged
  }
  catch (error) {
    const currentSignature = `${currentTraceTime(chart) ?? ''}|${selectedLayerIds.value.join('|')}`
    if (props.taskId !== requestTaskId || currentSignature !== requestSignature) return
    chart.traceData = {}
    chart.traceError = error instanceof Error ? error.message : String(error)
  }
  finally {
    const currentSignature = `${currentTraceTime(chart) ?? ''}|${selectedLayerIds.value.join('|')}`
    if (props.taskId === requestTaskId && currentSignature === requestSignature) {
      chart.traceLoading = false
    }
  }
}

function alignTraceStep(chart: DeviceChartState, preferredTime?: string): void {
  const options = traceTimelineOptions()
  if (!options.length) {
    chart.traceStep = null
    chart.traceData = {}
    chart.traceLoading = false
    return
  }

  const current = options.find(option => option.step === chart.traceStep)
  const sameTime = preferredTime
    ? options.find(option => option.simTime === preferredTime)
    : undefined
  const selected = current ?? sameTime ?? options[options.length - 1]!
  chart.traceStep = selected.step
  void loadTraceData(chart)
}

async function loadTraceSteps(taskId: string): Promise<void> {
  traceStepsLoading.value = true
  traceStepsError.value = ''
  try {
    const response = await taskApi.getTraceSteps(taskId)
    if (props.taskId !== taskId) return
    traceSteps.value = response.steps ?? []
    for (const chart of charts.value) {
      if (chart.analysisMode === 'point') alignTraceStep(chart)
    }
  }
  catch (error) {
    if (props.taskId !== taskId) return
    traceSteps.value = []
    traceStepsError.value = error instanceof Error ? error.message : String(error)
  }
  finally {
    if (props.taskId === taskId) traceStepsLoading.value = false
  }
}

watch(() => props.taskId, (taskId, previousTaskId) => {
  if (stateReady && previousTaskId) saveCurrentState(previousTaskId)
  stateTaskId = taskId
  stateReady = false
  traceSteps.value = []
  traceStepsError.value = ''
  traceDataCache.clear()
  if (!restoreCharts(taskId)) {
    selectedLayerIds.value = props.layerOptions[0]?.value ? [props.layerOptions[0].value] : []
    resetCharts()
  }
  stateReady = true
  void loadTraceSteps(taskId)
}, { immediate: true })

watch(() => props.layerOptions.map(option => option.value).join('|'), () => {
  const available = new Set(props.layerOptions.map(option => option.value))
  const validSelection = selectedLayerIds.value.filter(layerId => available.has(layerId))
  if (!validSelection.length && props.layerOptions[0]?.value) validSelection.push(props.layerOptions[0].value)
  if (validSelection.join('|') !== selectedLayerIds.value.join('|')) {
    selectedLayerIds.value = validSelection
  }
}, { immediate: true })

watch(() => selectedLayerIds.value.join('|'), () => {
  for (const chart of charts.value) {
    if (chart.analysisMode !== 'point') continue
    const previousTime = currentTraceTime(chart)
    alignTraceStep(chart, previousTime)
  }
})

watch(catalog, () => {
  if (defaultSelectionInitialized.value || !catalog.value.length || !activeChart.value) return
  activeChart.value.selectedKeys = preferredVariables().map(variable => variable.key)
  seedUnits(activeChart.value)
  defaultSelectionInitialized.value = true
}, { immediate: true })

watch(() => JSON.stringify({
  selectedLayerIds: selectedLayerIds.value,
  activeChartId: activeChartId.value,
  charts: charts.value.map(chart => ({
    id: chart.id,
    title: chart.title,
    selectedKeys: chart.selectedKeys,
    units: chart.units,
    zoomStart: chart.zoomStart,
    zoomEnd: chart.zoomEnd,
    analysisMode: chart.analysisMode,
    traceStep: chart.traceStep
  }))
}), () => saveCurrentState(), { flush: 'sync' })

onBeforeUnmount(() => {
  saveCurrentState()
})

function openVariableSelector(chartId?: string): void {
  if (chartId) activeChartId.value = chartId
  selectorOpen.value = true
}

function applyVariables(keys: string[]): void {
  if (!activeChart.value) return
  activeChart.value.selectedKeys = keys.filter(key => variableByKey.value.has(key))
  seedUnits(activeChart.value)
}

function addChart(): void {
  const emptyChart = charts.value.find(chart => chart.selectedKeys.length === 0)
  if (emptyChart) {
    activeChartId.value = emptyChart.id
    selectorOpen.value = true
    return
  }
  const chart = createChart([], charts.value.length + 1)
  charts.value.push(chart)
  normalizeDefaultChartTitles()
  activeChartId.value = chart.id
  selectorOpen.value = true
}

function deleteChart(chartId: string): void {
  const index = charts.value.findIndex(chart => chart.id === chartId)
  if (index < 0) return
  if (charts.value.length === 1) {
    resetChartContents(charts.value[0]!)
    activeChartId.value = charts.value[0]!.id
    defaultSelectionInitialized.value = true
    return
  }
  charts.value.splice(index, 1)
  normalizeDefaultChartTitles()
  if (activeChartId.value === chartId) {
    activeChartId.value = charts.value[Math.max(0, index - 1)]?.id ?? charts.value[0]!.id
  }
}

function updateUnit(chart: DeviceChartState, payload: { dimension: string; unit: string }): void {
  chart.units[payload.dimension] = payload.unit
}

function updateZoom(chart: DeviceChartState, payload: { start: number; end: number }): void {
  chart.zoomStart = payload.start
  chart.zoomEnd = payload.end
}

function updateAnalysisMode(chart: DeviceChartState, mode: 'range' | 'point'): void {
  chart.analysisMode = mode
  if (mode === 'point') alignTraceStep(chart)
}

function updateTraceStep(chart: DeviceChartState, step: number): void {
  if (!traceTimelineOptions().some(option => option.step === step)) return
  chart.traceStep = step
  void loadTraceData(chart)
}

function openParameters(): void {
  const firstVariable = activeChart.value?.selectedKeys
    .map(key => variableByKey.value.get(key))
    .find(Boolean)
  parameterDeviceId.value = firstVariable?.deviceId ?? catalog.value[0]?.id ?? ''
  parameterOpen.value = true
}
</script>

<template>
  <div class="flex h-full min-h-0 flex-col">
    <div
      v-if="catalog.length"
      class="mb-3 flex items-center gap-3 bg-app-panel-soft/60 px-4 py-2 text-sm"
    >
      <span class="shrink-0 text-app-muted">时层选择：</span>
      <div class="min-w-30 shrink-0">
      <PropertyMultiSelect
        v-model="selectedLayerIds"
        :options="layerOptions"
        placeholder="请选择时层"
        class=""
      />
      </div>

      <span class="shrink-0 text-app-muted">当前数据包含 {{ catalog.length }} 个设备或总线，{{ allVariables.length }} 个可查看变量</span>

      <div class="ml-auto flex shrink-0 items-center gap-2">
        <AppButton label="查看设备参数" size="md" tone="neutral" @click="openParameters" />
        <AppButton label="新增视图" size="md" tone="neutral" @click="addChart" />
      </div>
    </div>

    <div v-if="catalog.length" class="flex-1 min-h-0 overflow-y-auto pr-1">
      <div class="min-h-full space-y-4 pb-2">
        <DeviceOutputChart
          v-for="chart in charts"
          :key="chart.id"
          :chart-id="chart.id"
          :title="chart.title"
          :selected-keys="chart.selectedKeys"
          :variables="allVariables"
          :live-data="chart.analysisMode === 'point' ? chart.traceData : liveData"
          :layer-ids="selectedLayerIds"
          :layer-labels="layerLabelMap"
          :unit-selections="chart.units"
          :zoom-start="chart.zoomStart"
          :zoom-end="chart.zoomEnd"
          :analysis-mode="chart.analysisMode"
          :trace-step="chart.traceStep"
          :trace-options="traceTimelineOptions()"
          :trace-loading="traceStepsLoading || chart.traceLoading"
          :trace-error="chart.traceError || traceStepsError"
          :maximum-minute="maximumMinute"
          :class="charts.length === 1 ? 'min-h-full' : ''"
          @delete="deleteChart(chart.id)"
          @edit-variables="openVariableSelector(chart.id)"
          @update:title="chart.title = $event"
          @update:unit="updateUnit(chart, $event)"
          @update:zoom="updateZoom(chart, $event)"
          @update:mode="updateAnalysisMode(chart, $event)"
          @update:trace-step="updateTraceStep(chart, $event)"
        />
      </div>
    </div>

    <div v-else class="flex flex-1 flex-col items-center justify-center gap-2 text-center">
      <div class="flex h-12 w-12 items-center justify-center rounded-full bg-app-panel-soft text-2xl">🔌</div>
      <p class="text-sm font-medium text-app-text">暂无设备出力结果</p>
      <p class="max-w-md text-xs leading-5 text-app-muted">任务运行后，本页会从已有结果中识别设备和可查看变量，不会触发新的求解计算。</p>
    </div>

    <DeviceVariableSelector
      :open="selectorOpen"
      :devices="catalog"
      :selected-keys="activeChart?.selectedKeys ?? []"
      :layer-ids="selectedLayerIds"
      @close="selectorOpen = false"
      @apply="applyVariables"
    />

    <DeviceParameterDrawer
      :open="parameterOpen"
      :project="project"
      :canvas-id="canvasId"
      :devices="catalog"
      :selected-device-id="parameterDeviceId"
      @close="parameterOpen = false"
    />
  </div>
</template>
