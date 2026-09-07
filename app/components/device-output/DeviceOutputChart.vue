<script setup lang="ts">
import * as echarts from 'echarts'
import type { TaskTraceStep } from '~~/types/api'
import { downloadText } from '~~/utils/download'
import {
  convertDeviceOutputValue,
  defaultDisplayUnit,
  minutesToTimestamp,
  timestampToMinutes,
  unitOptionsForDimension,
  type DeviceOutputLiveData,
  type DeviceOutputVariable
} from '~~/utils/deviceOutputData'

interface AxisGroup {
  dimension: string
  label: string
  unit: string
  variables: DeviceOutputVariable[]
}

interface DisplayedSeries {
  variable: DeviceOutputVariable
  layerId: string
  name: string
}

const props = defineProps<{
  chartId: string
  title: string
  selectedKeys: string[]
  variables: DeviceOutputVariable[]
  liveData: DeviceOutputLiveData
  layerIds: string[]
  layerLabels: Record<string, string>
  unitSelections: Record<string, string>
  zoomStart: number
  zoomEnd: number
  analysisMode: 'range' | 'point'
  traceStep: number | null
  traceOptions: TaskTraceStep[]
  traceLoading: boolean
  traceError?: string
  maximumMinute?: number
}>()

const emit = defineEmits<{
  delete: []
  editVariables: []
  'update:title': [value: string]
  'update:unit': [payload: { dimension: string; unit: string }]
  'update:zoom': [payload: { start: number; end: number }]
  'update:mode': [value: 'range' | 'point']
  'update:traceStep': [value: number]
}>()

const chartRef = ref<HTMLDivElement | null>(null)
let chart: echarts.ECharts | null = null
let resizeObserver: ResizeObserver | null = null

const PALETTE = ['#0A4DA2', '#12B76A', '#F79009', '#7A5AF8', '#F04438', '#06AED4', '#D444F1', '#6172F3']

const selectedVariables = computed(() => {
  const byKey = new Map(props.variables.map(variable => [variable.key, variable]))
  return props.selectedKeys.map(key => byKey.get(key)).filter((item): item is DeviceOutputVariable => Boolean(item))
})

const axisGroups = computed<AxisGroup[]>(() => {
  const groups = new Map<string, AxisGroup>()
  for (const variable of selectedVariables.value) {
    const existing = groups.get(variable.dimension)
    if (existing) {
      existing.variables.push(variable)
      continue
    }
    groups.set(variable.dimension, {
      dimension: variable.dimension,
      label: variable.dimensionLabel,
      unit: props.unitSelections[variable.dimension]
        ?? defaultDisplayUnit(variable.dimension, variable.originalUnit),
      variables: [variable]
    })
  }
  return [...groups.values()]
})

const displayedSeries = computed<DisplayedSeries[]>(() => selectedVariables.value.flatMap((variable) => (
  props.layerIds
    .filter(layerId => variable.layerIds.includes(layerId))
    .map(layerId => ({
      variable,
      layerId,
      name: props.layerIds.length > 1
        ? `${variable.displayName} · ${props.layerLabels[layerId] ?? `时层${layerId}`}`
        : variable.displayName
    }))
)))

const dataMinutes = computed(() => displayedSeries.value.flatMap((item) => {
  const points = props.liveData[item.variable.key]?.[item.layerId] ?? []
  return points.map(point => timestampToMinutes(point.ts))
}).filter(Number.isFinite))

const minimumMinute = computed(() => {
  if (props.analysisMode !== 'point' || !dataMinutes.value.length) return 0
  return Math.min(...dataMinutes.value)
})

const maximumMinute = computed(() => {
  const dataMaximum = Math.max(0, ...dataMinutes.value)
  if (props.analysisMode === 'point') {
    if (props.layerIds.includes('1')) return props.maximumMinute || 1440
    return dataMaximum || props.maximumMinute || 1440
  }
  if (props.maximumMinute && props.maximumMinute > 0) {
    return dataMaximum > 0 ? Math.min(dataMaximum, props.maximumMinute) : props.maximumMinute
  }
  return dataMaximum || 1440
})

const xAxisInterval = computed(() => {
  if (props.analysisMode === 'range') return 60
  return props.layerIds.includes('3') ? 15 : 60
})

const rangeStartMinute = computed(() => maximumMinute.value * props.zoomStart / 100)
const rangeEndMinute = computed(() => maximumMinute.value * props.zoomEnd / 100)
const sliderStepMinutes = computed(() => {
  const sorted = [...new Set(dataMinutes.value)].sort((left, right) => left - right)
  const steps = sorted.slice(1)
    .map((minute, index) => minute - sorted[index]!)
    .filter(step => Number.isFinite(step) && step > 0)
  return Math.min(...steps, 5)
})
const hourlyTicks = computed(() => {
  const ticks = Array.from(
    { length: Math.floor(maximumMinute.value / 60) + 1 },
    (_, hour) => minutesToTimestamp(hour * 60)
  )
  if (maximumMinute.value % 60 !== 0) ticks.push(minutesToTimestamp(maximumMinute.value))
  return ticks
})
const selectedTrace = computed(() => props.traceOptions.find(option => option.step === props.traceStep))
const selectedLayerLabel = computed(() => props.layerIds
  .map(layerId => props.layerLabels[layerId] ?? `时层${layerId}`)
  .join('、'))
const hasDisplayedPoints = computed(() => displayedSeries.value.some(item => convertedPoints(item.variable, item.layerId).length > 0))

function selectedUnit(variable: DeviceOutputVariable): string {
  return axisGroups.value.find(group => group.dimension === variable.dimension)?.unit ?? variable.originalUnit
}

function convertedPoints(variable: DeviceOutputVariable, layerId: string): [number, number][] {
  const unit = selectedUnit(variable)
  return (props.liveData[variable.key]?.[layerId] ?? [])
    .map(point => [
      timestampToMinutes(point.ts),
      convertDeviceOutputValue(Number(point.value), variable.originalUnit, unit, variable.dimension)
    ] as [number, number])
    .filter(([minute, value]) => minute >= 0 && minute <= maximumMinute.value && Number.isFinite(value))
}

function formatNumber(value: number): string {
  const absolute = Math.abs(value)
  const digits = absolute >= 1000 ? 0 : absolute >= 100 ? 1 : absolute >= 1 ? 2 : 3
  return value.toLocaleString('zh-CN', { maximumFractionDigits: digits })
}

function escapeHtml(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;')
}

function axisSide(index: number): { position: 'left' | 'right'; offset: number } {
  const position = index % 2 === 0 ? 'left' : 'right'
  return { position, offset: Math.floor(index / 2) * 54 }
}

function render(): void {
  if (!chartRef.value || selectedVariables.value.length === 0) return
  if (!chart) {
    chart = echarts.init(chartRef.value)
  }
  if (!resizeObserver) {
    resizeObserver = new ResizeObserver(() => chart?.resize())
    resizeObserver.observe(chartRef.value)
  }

  const axisIndex = new Map(axisGroups.value.map((group, index) => [group.dimension, index]))
  const leftAxisCount = Math.ceil(axisGroups.value.length / 2)
  const rightAxisCount = Math.floor(axisGroups.value.length / 2)
  const series: echarts.SeriesOption[] = displayedSeries.value.map((item, index) => {
    const variable = item.variable
    const color = PALETTE[index % PALETTE.length]!
    return {
      id: `${variable.key}|${item.layerId}`,
      name: item.name,
      type: 'line',
      yAxisIndex: axisIndex.get(variable.dimension) ?? 0,
      data: convertedPoints(variable, item.layerId),
      showSymbol: false,
      symbolSize: 5,
      smooth: false,
      sampling: 'lttb',
      connectNulls: false,
      lineStyle: { width: 2, color },
      itemStyle: { color },
      emphasis: { focus: 'series', lineStyle: { width: 3 } }
    } satisfies echarts.LineSeriesOption
  })

  chart.setOption({
    animation: false,
    animationDuration: 260,
    color: PALETTE,
    legend: {
      top: 10,
      left: 'center',
      itemWidth: 18,
      itemHeight: 9,
      textStyle: { fontSize: 10, color: '#4E5969' }
    },
    grid: {
      left: 96 + Math.max(0, leftAxisCount - 1) * 54,
      right: 64 + Math.max(0, rightAxisCount - 1) * 54,
      top: 48,
      bottom: 32,
      containLabel: false
    },
    xAxis: {
      type: 'value',
      min: minimumMinute.value,
      max: maximumMinute.value,
      interval: xAxisInterval.value,
      axisLine: { lineStyle: { color: '#C9CDD4' } },
      axisTick: { show: false },
      axisLabel: {
        color: '#86909C',
        fontSize: 10,
        formatter: (value: number) => minutesToTimestamp(value)
      },
      splitLine: { show: false }
    },
    yAxis: axisGroups.value.map((group, index) => {
      const side = axisSide(index)
      return {
        type: 'value',
        name: `${group.label} / ${group.unit}`,
        nameLocation: 'end',
        nameGap: 10,
        position: side.position,
        offset: side.offset,
        scale: true,
        nameTextStyle: {
          color: PALETTE[index % PALETTE.length],
          fontSize: 10,
          align: side.position === 'left' ? 'right' : 'left'
        },
        axisLine: { show: true, lineStyle: { color: PALETTE[index % PALETTE.length] } },
        axisTick: { show: false },
        axisLabel: {
          color: '#86909C',
          fontSize: 10,
          formatter: (value: number) => formatNumber(value)
        },
        splitLine: index === 0
          ? { lineStyle: { color: '#E5E6EB', type: 'dashed' } }
          : { show: false }
      }
    }),
    tooltip: {
      trigger: 'axis',
      axisPointer: { type: 'cross', lineStyle: { color: '#86909C' } },
      confine: true,
      formatter: (params: unknown) => {
        const items = Array.isArray(params)
          ? params as Array<{ data?: [number, number]; seriesIndex?: number; marker?: string; seriesName?: string }>
          : []
        if (!items.length) return ''
        const minute = Number(items[0]?.data?.[0] ?? 0)
        let html = `<div style="font-weight:600;margin-bottom:6px">${minutesToTimestamp(minute)}</div>`
        for (const item of items) {
          const displayed = displayedSeries.value[item.seriesIndex ?? -1]
          const variable = displayed?.variable
          const value = Number(item.data?.[1])
          if (!variable || !Number.isFinite(value)) continue
          html += `<div style="display:flex;gap:12px;justify-content:space-between;min-width:220px">`
          html += `<span>${item.marker ?? ''}${escapeHtml(item.seriesName ?? variable.displayName)}</span>`
          html += `<b>${formatNumber(value)} ${escapeHtml(selectedUnit(variable))}</b></div>`
        }
        return html
      }
    },
    dataZoom: [{
      type: 'inside',
      start: props.analysisMode === 'range' ? props.zoomStart : 0,
      end: props.analysisMode === 'range' ? props.zoomEnd : 100,
      filterMode: 'none',
      disabled: true,
      zoomOnMouseWheel: false,
      moveOnMouseWheel: false,
      moveOnMouseMove: false,
      preventDefaultMouseMove: false
    }],
    series
  }, {
    notMerge: true,
    lazyUpdate: true
  })
}

function handleAxisUnitChange(dimension: string, event: Event): void {
  emit('update:unit', { dimension, unit: (event.target as HTMLSelectElement).value })
}

const traceCommittedIndex = computed(() => {
  const index = props.traceOptions.findIndex(option => option.step === props.traceStep)
  return Math.max(0, index)
})

const traceDraftIndex = ref(0)

watch([
  () => props.traceStep,
  () => props.traceOptions.map(option => option.step).join('|')
], () => {
  traceDraftIndex.value = traceCommittedIndex.value
}, { immediate: true })

const tracePreview = computed(() => {
  const maximumIndex = Math.max(0, props.traceOptions.length - 1)
  const index = Math.min(maximumIndex, Math.max(0, traceDraftIndex.value))
  return props.traceOptions[index] ?? selectedTrace.value
})

const traceTicks = computed(() => {
  const maximumIndex = Math.max(1, props.traceOptions.length - 1)
  return props.traceOptions.flatMap((option, index, options) => {
    const minute = timestampToMinutes(option.simTime)
    if (index !== 0 && index !== options.length - 1 && minute % 60 !== 0) return []
    const percentage = index / maximumIndex * 100
    const transform = index === 0
      ? 'translateX(0)'
      : index === options.length - 1
        ? 'translateX(-100%)'
        : 'translateX(-50%)'
    return [{ ...option, style: { left: `${percentage}%`, transform } }]
  })
})

const traceSelectionStyle = computed(() => {
  const maximumIndex = Math.max(1, props.traceOptions.length - 1)
  return { width: `${traceDraftIndex.value / maximumIndex * 100}%` }
})

const traceLabelStyle = computed(() => {
  const maximumIndex = Math.max(1, props.traceOptions.length - 1)
  const percentage = traceDraftIndex.value / maximumIndex * 100
  const transform = percentage <= 1
    ? 'translateX(0)'
    : percentage >= 99
      ? 'translateX(-100%)'
      : 'translateX(-50%)'
  return { left: `${percentage}%`, transform }
})

function updateTracePreview(event: Event): void {
  const maximumIndex = Math.max(0, props.traceOptions.length - 1)
  traceDraftIndex.value = Math.min(maximumIndex, Math.max(0, Math.round(Number((event.target as HTMLInputElement).value))))
}

function commitTraceStep(event: Event): void {
  updateTracePreview(event)
  const index = traceDraftIndex.value
  const option = props.traceOptions[index]
  if (option && option.step !== props.traceStep) emit('update:traceStep', option.step)
}

const visibleRangeLabel = computed(() => {
  return `${minutesToTimestamp(rangeStartMinute.value)} - ${minutesToTimestamp(rangeEndMinute.value)}`
})

function onRangeStartUpdate(startMinute: number): void {
  emit('update:zoom', {
    start: maximumMinute.value > 0 ? startMinute / maximumMinute.value * 100 : 0,
    end: props.zoomEnd
  })
}

function onRangeEndUpdate(endMinute: number): void {
  emit('update:zoom', {
    start: props.zoomStart,
    end: maximumMinute.value > 0 ? endMinute / maximumMinute.value * 100 : 100
  })
}

function csvCell(value: string): string {
  return `"${value.replaceAll('"', '""')}"`
}

function exportCsv(): void {
  if (!displayedSeries.value.length) return
  const rangeStart = props.analysisMode === 'point' ? minimumMinute.value : rangeStartMinute.value
  const rangeEnd = props.analysisMode === 'point' ? maximumMinute.value : rangeEndMinute.value
  const timestamps = [...new Set(displayedSeries.value.flatMap(item => convertedPoints(item.variable, item.layerId).map(point => point[0])))]
    .filter(minute => minute >= rangeStart && minute <= rangeEnd)
    .sort((a, b) => a - b)
  const valueMaps = displayedSeries.value.map(item => new Map(convertedPoints(item.variable, item.layerId)))
  const header = ['时间', ...displayedSeries.value.map(item => `${item.name} (${selectedUnit(item.variable)})`)]
  const rows = [header.map(csvCell).join(',')]
  for (const minute of timestamps) {
    const values = valueMaps.map(map => map.has(minute) ? String(map.get(minute)) : '')
    rows.push([minutesToTimestamp(minute), ...values].map(csvCell).join(','))
  }
  const safeTitle = props.title.trim().replace(/[\\/:*?"<>|]/g, '_') || '设备出力分析'
  downloadText(`${safeTitle}.csv`, `﻿${rows.join('\r\n')}`, 'text/csv;charset=utf-8')
}

function destroyChart(): void {
  resizeObserver?.disconnect()
  resizeObserver = null
  chart?.dispose()
  chart = null
}

watch(() => JSON.stringify([
  props.selectedKeys,
  props.liveData,
  props.layerIds,
  props.layerLabels,
  props.unitSelections,
  props.analysisMode,
  props.traceStep,
  props.maximumMinute,
  props.zoomStart,
  props.zoomEnd
]), () => {
  if (!selectedVariables.value.length) {
    destroyChart()
    return
  }
  void nextTick(render)
})

onMounted(() => {
  render()
})

onBeforeUnmount(() => {
  destroyChart()
})
</script>

<template>
  <section
    class="flex flex-col border border-app-border bg-white"
  >
    <div class="flex flex-wrap items-center gap-2 border-b border-app-border px-3 py-2.5">
      <input
        :value="title"
        type="text"
        class="min-w-[220px] flex-1 border border-transparent bg-transparent px-2 transition hover:border-app-border focus:border-primary"
        aria-label="图表标题"
        @input="emit('update:title', ($event.target as HTMLInputElement).value)"
      >
      <AppButton :label="`变量选择（${selectedVariables.length}）`" size="sm" tone="primary" @click="emit('editVariables')" />
      <AppButton label="导出数据" size="sm" tone="neutral" :disabled="!selectedVariables.length" @click="exportCsv" />
      <AppButton label="删除视图" size="sm" tone="danger" @click="emit('delete')" />
    </div>

    <div v-if="selectedVariables.length" class="flex flex-1 flex-col">
      <div class="relative min-h-[360px] flex-1">
        <div ref="chartRef" class="h-full min-h-[360px] w-full" />
        <div v-if="axisGroups.length" class="flex flex-wrap items-center gap-2 px-8 py-2">
          <label v-for="group in axisGroups" :key="group.dimension" class="inline-flex items-center gap-1 text-xs text-app-muted">
            <span>{{ group.label }}</span>
            <select
              :value="group.unit"
              class="h-6 border border-app-border bg-white px-1 text-xs text-app-text"
              @change="handleAxisUnitChange(group.dimension, $event)"
            >
              <option v-for="option in unitOptionsForDimension(group.dimension, group.variables[0]!.originalUnit)" :key="option.value" :value="option.value">
                {{ option.label }}
              </option>
            </select>
          </label>
        </div>
        <div
          v-if="analysisMode === 'point' && traceLoading"
          class="absolute inset-0 flex items-center justify-center bg-white/75 text-sm text-app-muted"
        >
          正在读取历史滚动求解快照...
        </div>
        <div
          v-else-if="analysisMode === 'point' && traceStep !== null && !hasDisplayedPoints && !traceError"
          class="absolute inset-0 flex items-center justify-center bg-white/75 text-sm text-app-muted"
        >
          该历史求解版本中没有所选变量的结果数据
        </div>
      </div>

      <div class="flex flex-wrap items-center gap-3 border-t border-app-border px-4 py-2.5 text-xs">
        <button
          type="button"
          class="rounded-[4px] border px-3 py-1 transition"
          :class="analysisMode === 'range' ? 'border-primary bg-primary-soft text-primary' : 'border-app-border text-app-muted'"
          @click="emit('update:mode', 'range')"
        >
          时间段窗口
        </button>
        <button
          type="button"
          class="rounded-[4px] border px-3 py-1 transition"
          :class="analysisMode === 'point' ? 'border-primary bg-primary-soft text-primary' : 'border-app-border text-app-muted'"
          @click="emit('update:mode', 'point')"
        >
          时间点追溯
        </button>
        <span v-if="analysisMode === 'range'" class="ml-auto text-app-muted">当前范围 {{ visibleRangeLabel }}</span>
        <span v-else class="ml-auto text-app-muted">追溯时刻 {{ tracePreview?.simTime ?? '--:--' }}</span>
      </div>

      <div v-if="analysisMode === 'range'" class="px-5">
        <DualRangeSlider
          :start="rangeStartMinute"
          :end="rangeEndMinute"
          :min="0"
          :max="maximumMinute"
          :step="sliderStepMinutes"
          :format-label="minutesToTimestamp"
          @update:start="onRangeStartUpdate"
          @update:end="onRangeEndUpdate"
        />
      </div>

      <div v-else class="bg-app-panel-soft/45 px-5 pb-4 pt-2 text-xs">
        <p v-if="traceError" class="text-app-danger">历史快照读取失败：{{ traceError }}</p>
        <template v-else-if="selectedTrace">
          <div class="relative h-4">
            <div class="absolute inset-x-2 top-1.5 h-1 rounded-full bg-app-border">
              <div class="h-1 rounded-full bg-primary" :style="traceSelectionStyle" />
            </div>
            <input
              :value="traceDraftIndex"
              type="range"
              min="0"
              :max="Math.max(0, traceOptions.length - 1)"
              step="1"
              :disabled="traceOptions.length < 2"
              class="device-output-trace-input absolute inset-x-0 top-[-2px] z-10 w-full"
              aria-label="追溯时刻"
              @input="updateTracePreview"
              @change="commitTraceStep"
            >
            <span
              class="absolute top-4 whitespace-nowrap text-xs text-app-muted"
              :style="traceLabelStyle"
            >{{ tracePreview?.simTime }}</span>
          </div>
        </template>
        <p v-else-if="!traceLoading" class="py-2 text-app-muted">所选时间层暂无可追溯的滚动求解时刻。</p>
      </div>
    </div>

    <div v-else class="flex h-[360px] flex-col items-center justify-center gap-3 text-center">
      <div class="flex h-12 w-12 items-center justify-center rounded-full bg-primary-soft text-xl text-primary">＋</div>
      <div>
        <p class="text-sm font-medium text-app-text">尚未选择设备变量</p>
        <p class="mt-1 text-xs text-app-muted">选择同一设备的多个变量，或对比多个设备的出力</p>
      </div>
      <AppButton label="选择设备变量" size="sm" tone="primary" @click="emit('editVariables')" />
    </div>
  </section>
</template>

<style scoped>
.device-output-trace-input {
  height: 20px;
  margin: 0;
  background: transparent;
  cursor: pointer;
  appearance: none;
  pointer-events: none;
}

.device-output-trace-input::-webkit-slider-runnable-track {
  height: 4px;
  background: transparent;
}

.device-output-trace-input::-webkit-slider-thumb {
  width: 14px;
  height: 14px;
  margin-top: -5px;
  border: 2px solid #0A4DA2;
  border-radius: 50%;
  background: #fff;
  cursor: grab;
  appearance: none;
  pointer-events: auto;
}

.device-output-trace-input::-moz-range-track {
  height: 4px;
  background: transparent;
}

.device-output-trace-input::-moz-range-thumb {
  width: 14px;
  height: 14px;
  border: 2px solid #0A4DA2;
  border-radius: 50%;
  background: #fff;
  cursor: grab;
  pointer-events: auto;
}

.device-output-trace-input:disabled {
  cursor: default;
  opacity: 0.6;
}

.device-output-trace-input:disabled::-webkit-slider-thumb {
  cursor: default;
}

.device-output-trace-input:disabled::-moz-range-thumb {
  cursor: default;
}

.device-output-trace-input:focus-visible::-webkit-slider-thumb {
  outline: 2px solid rgba(10, 77, 162, 0.35);
  outline-offset: 3px;
}
</style>
