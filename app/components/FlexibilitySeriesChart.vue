<script setup lang="ts">
import * as echarts from 'echarts'
import type { FlexibilityPeriodResult } from '~~/types/api'

const props = defineProps<{
  rows: FlexibilityPeriodResult[]
  direction: 'up' | 'down'
  deviceLabels?: Record<string, string>
}>()

const emit = defineEmits<{
  hoverTimestamp: [timestamp: string | null]
}>()

const chartRef = ref<HTMLDivElement | null>(null)
let chart: echarts.ECharts | null = null
let resizeObserver: ResizeObserver | null = null

const DAY_MINUTES = 24 * 60
const HOURLY_TICKS = Array.from({ length: 25 }, (_, hour) => `${String(hour).padStart(2, '0')}:00`)
const rangeStartMinutes = ref(0)
const rangeEndMinutes = ref(DAY_MINUTES)

const CONTRIBUTION_COLORS = [
  '#165DFF',
  '#12B76A',
  '#F79009',
  '#7A5AF8',
  '#06AED4',
  '#F04438',
  '#EE46BC',
  '#667085'
]

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
  HYDRO: '常规水电'
}

const directionLabel = computed(() => props.direction === 'up' ? '上调' : '下调')

const toMinutes = (timestamp: string): number => {
  const [hour = '0', minute = '0'] = timestamp.split(':')
  return Number(hour) * 60 + Number(minute)
}

const directionRows = computed(() => props.rows
  .filter(row => row.direction === props.direction)
  .slice()
  .sort((a, b) => toMinutes(a.timestamp) - toMinutes(b.timestamp)))

const visibleRows = computed(() => directionRows.value.filter(row => {
  const timestamp = toMinutes(row.timestamp)
  return timestamp >= rangeStartMinutes.value && timestamp < rangeEndMinutes.value
}))

const sliderStepMinutes = computed(() => {
  const steps = directionRows.value
    .map(row => {
      const start = toMinutes(row.timestamp)
      let end = toMinutes(row.next_timestamp)
      if (end <= start) end += DAY_MINUTES
      return end - start
    })
    .filter(step => Number.isFinite(step) && step > 0)
  return Math.min(...steps, 5)
})

const formatMinutes = (minutes: number): string => {
  if (minutes >= DAY_MINUTES) return '24:00'
  const hour = Math.floor(minutes / 60)
  const minute = minutes % 60
  return `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`
}

const rangeSelectionStyle = computed(() => ({
  left: `${rangeStartMinutes.value / DAY_MINUTES * 100}%`,
  right: `${(DAY_MINUTES - rangeEndMinutes.value) / DAY_MINUTES * 100}%`
}))

const rangeLabelStyle = (minutes: number): Record<string, string> => {
  const percentage = minutes / DAY_MINUTES * 100
  const transform = percentage <= 1 ? 'translateX(0)' : percentage >= 99 ? 'translateX(-100%)' : 'translateX(-50%)'
  return { left: `${percentage}%`, transform }
}

const updateRangeStart = (event: Event) => {
  const value = Number((event.target as HTMLInputElement).value)
  rangeStartMinutes.value = Math.min(
    Math.max(0, value),
    rangeEndMinutes.value - sliderStepMinutes.value
  )
}

const updateRangeEnd = (event: Event) => {
  const value = Number((event.target as HTMLInputElement).value)
  rangeEndMinutes.value = Math.max(
    Math.min(DAY_MINUTES, value),
    rangeStartMinutes.value + sliderStepMinutes.value
  )
}

const contributionColorByDevice = computed(() => {
  const keys = new Set<string>()
  for (const row of props.rows) {
    for (const device of row.device_results ?? []) {
      keys.add(`${device.device_type}:${device.device_id}`)
    }
  }

  return new Map(
    [...keys]
      .sort((left, right) => left.localeCompare(right))
      .map((key, index) => [key, CONTRIBUTION_COLORS[index % CONTRIBUTION_COLORS.length]!])
  )
})

interface ContributionItem {
  key: string
  label: string
  value: number
  percentage: number
  color: string
}

const contributionItems = computed<ContributionItem[]>(() => {
  const totals = new Map<string, { label: string; value: number }>()

  for (const row of visibleRows.value) {
    const start = toMinutes(row.timestamp)
    let end = toMinutes(row.next_timestamp)
    if (end <= start) end += DAY_MINUTES
    const durationHours = Math.max(0, end - start) / 60

    for (const device of row.device_results ?? []) {
      const contribution = Number(device.device_contribution ?? device.device_flexibility)
      if (!Number.isFinite(contribution) || contribution <= 0) continue

      const key = `${device.device_type}:${device.device_id}`
      const fallbackLabel = `${DEVICE_TYPE_LABELS[device.device_type] ?? device.device_type} ${device.device_id}`
      const current = totals.get(key)
      totals.set(key, {
        label: props.deviceLabels?.[device.device_id] ?? fallbackLabel,
        value: (current?.value ?? 0) + contribution * durationHours
      })
    }
  }

  const sorted = [...totals.entries()]
    .map(([key, item]) => ({ key, ...item }))
    .sort((left, right) => right.value - left.value || left.label.localeCompare(right.label))
  const total = sorted.reduce((sum, item) => sum + item.value, 0)

  return sorted.map(item => ({
    ...item,
    percentage: total > 0 ? item.value / total * 100 : 0,
    color: contributionColorByDevice.value.get(item.key) ?? CONTRIBUTION_COLORS[0]!
  }))
})

const totalContribution = computed(() => contributionItems.value.reduce((sum, item) => sum + item.value, 0))

const emitAxisTimestamp = (event: { axesInfo?: Array<{ value?: string | number }> }) => {
  const axisValue = event.axesInfo?.[0]?.value
  if (axisValue == null) {
    emit('hoverTimestamp', null)
    return
  }

  const timestamp = typeof axisValue === 'string'
    ? axisValue
    : visibleRows.value[Number(axisValue)]?.timestamp
  emit('hoverTimestamp', timestamp ?? null)
}

const render = () => {
  if (!chartRef.value) return
  chart ??= echarts.init(chartRef.value)

  const rows = visibleRows.value

  const timeline = rows.map(row => row.timestamp)
  chart.setOption({
    animation: true,
    animationDuration: 300,
    animationDurationUpdate: 220,
    animationEasing: 'cubicOut',
    animationEasingUpdate: 'linear',
    color: ['#165DFF', '#F79009', '#12B76A', '#F04438'],
    title: {
      text: `${directionLabel.value}灵活性时序`,
      subtext: '单位：kW',
      left: 12,
      top: 6,
      textStyle: { fontSize: 13, fontWeight: 600, color: '#1D2939' },
      subtextStyle: { fontSize: 10, color: '#667085' }
    },
    legend: {
      data: ['系统供给', '系统需求', '裕度', '缺额'],
      right: 12,
      top: 10,
      itemWidth: 14,
      itemHeight: 8,
      textStyle: { fontSize: 10 }
    },
    grid: { left: 52, right: 18, top: 58, bottom: 38 },
    xAxis: {
      type: 'category',
      data: timeline,
      boundaryGap: false,
      axisLabel: { fontSize: 10, hideOverlap: true },
      axisLine: { lineStyle: { color: '#D0D5DD' } }
    },
    yAxis: {
      type: 'value',
      scale: true,
      axisLabel: { fontSize: 10 },
      splitLine: { lineStyle: { type: 'dashed', color: '#EAECF0' } }
    },
    tooltip: {
      trigger: 'axis',
      valueFormatter: (value: unknown) => `${Number(value).toFixed(2)} kW`
    },
    series: [
      { id: 'supply', name: '系统供给', type: 'line', showSymbol: false, data: rows.map(row => row.system_supply) },
      { id: 'requirement', name: '系统需求', type: 'line', showSymbol: false, data: rows.map(row => row.requirement) },
      { id: 'margin', name: '裕度', type: 'line', showSymbol: false, data: rows.map(row => row.margin) },
      { id: 'deficit', name: '缺额', type: 'line', showSymbol: false, data: rows.map(row => row.deficit), lineStyle: { type: 'dashed' } }
    ]
  }, {
    notMerge: false,
    lazyUpdate: true,
    replaceMerge: ['series']
  })
}

watch(
  [() => JSON.stringify(props.rows), () => props.direction, rangeStartMinutes, rangeEndMinutes],
  render
)

onMounted(() => {
  render()
  chart?.on('updateAxisPointer', emitAxisTimestamp)
  chart?.on('globalout', () => emit('hoverTimestamp', null))
  resizeObserver = new ResizeObserver(() => chart?.resize())
  resizeObserver.observe(chartRef.value!)
})

onBeforeUnmount(() => {
  resizeObserver?.disconnect()
  chart?.dispose()
  chart = null
})
</script>

<template>
  <section class="rounded-[12px] border border-app-border bg-white p-3">
    <div class="grid gap-3 lg:grid-cols-[minmax(0,1fr)_240px]">
      <div class="relative min-w-0 h-64">
        <div
          v-if="visibleRows.length === 0"
          class="absolute inset-0 z-10 flex items-center justify-center bg-white text-sm text-app-muted"
        >
          所选时段暂无{{ directionLabel }}逐时段结果
        </div>
        <div ref="chartRef" class="h-64 w-full" />
      </div>

      <aside class="self-start rounded-[10px] border border-app-border bg-app-panel-soft/60 px-3 pb-2 pt-3">
        <div class="flex items-start justify-between gap-2">
          <div>
            <h3 class="text-xs font-semibold text-app-text">灵活性贡献度分析</h3>

          </div>
        </div>

        <div v-if="contributionItems.length" class="mt-3 flex h-48 min-h-0 gap-3">
          <div class="flex h-full w-12 shrink-0 flex-col overflow-hidden rounded-lg border border-white bg-white shadow-sm">
            <div
              v-for="item in contributionItems"
              :key="item.key"
              class="min-h-px w-full border-b border-white/80 last:border-b-0"
              :style="{ height: `${item.percentage}%`, backgroundColor: item.color }"
              :title="`${item.label} ${item.percentage.toFixed(1)}%`"
            />
          </div>
          <div class="min-w-0 flex-1 overflow-y-auto pr-1">
            <div
              v-for="item in contributionItems"
              :key="item.key"
              class="mb-2 flex items-center gap-2 last:mb-0"
            >
              <span class="h-2.5 w-2.5 shrink-0 rounded-sm" :style="{ backgroundColor: item.color }" />
              <span class="min-w-0 flex-1 truncate text-[11px] text-app-text" :title="item.label">{{ item.label }}</span>
              <span class="shrink-0 font-mono text-[11px] font-semibold text-app-text">{{ item.percentage.toFixed(1) }}%</span>
            </div>
          </div>
        </div>
        <div v-else class="mt-3 flex h-48 items-center justify-center rounded-lg border border-dashed border-app-border bg-white text-center text-[11px] leading-5 text-app-muted">
          所选时段暂无设备贡献数据
        </div>
      </aside>
    </div>

    <div class="-mt-2 px-4 pb-1">
      <div class="relative h-10">
        <span
          class="absolute top-0 whitespace-nowrap rounded bg-primary px-1.5 py-0.5 font-mono text-[9px] text-white"
          :style="rangeLabelStyle(rangeStartMinutes)"
        >{{ formatMinutes(rangeStartMinutes) }}</span>
        <span
          class="absolute top-0 whitespace-nowrap rounded bg-primary px-1.5 py-0.5 font-mono text-[9px] text-white"
          :style="rangeLabelStyle(rangeEndMinutes)"
        >{{ formatMinutes(rangeEndMinutes) }}</span>

        <div class="absolute inset-x-0 top-[28px] h-1.5 rounded-full bg-app-border">
          <div class="absolute top-0 h-1.5 rounded-full bg-primary" :style="rangeSelectionStyle" />
        </div>
        <input
          :value="rangeStartMinutes"
          type="range"
          min="0"
          :max="DAY_MINUTES"
          :step="sliderStepMinutes"
          class="flexibility-range-input absolute inset-x-0 top-[19px] z-10 w-full"
          aria-label="起始时间"
          @input="updateRangeStart"
        >
        <input
          :value="rangeEndMinutes"
          type="range"
          min="0"
          :max="DAY_MINUTES"
          :step="sliderStepMinutes"
          class="flexibility-range-input absolute inset-x-0 top-[19px] z-20 w-full"
          aria-label="终止时间"
          @input="updateRangeEnd"
        >
      </div>
      <div class="mt-1 flex justify-between font-mono text-[9px] text-app-muted">
        <span v-for="tick in HOURLY_TICKS" :key="tick">{{ tick }}</span>
      </div>
    </div>
  </section>
</template>

<style scoped>
.flexibility-range-input {
  height: 20px;
  margin: 0;
  appearance: none;
  pointer-events: none;
  background: transparent;
}

.flexibility-range-input::-webkit-slider-runnable-track {
  height: 6px;
  background: transparent;
}

.flexibility-range-input::-webkit-slider-thumb {
  width: 16px;
  height: 16px;
  margin-top: -5px;
  appearance: none;
  pointer-events: auto;
  cursor: grab;
  border: 3px solid #ffffff;
  border-radius: 999px;
  background: #165dff;
  box-shadow: 0 0 0 1px #165dff, 0 2px 5px rgba(22, 93, 255, 0.3);
}

.flexibility-range-input::-webkit-slider-thumb:active {
  cursor: grabbing;
  transform: scale(1.08);
}

.flexibility-range-input::-moz-range-track {
  height: 6px;
  background: transparent;
}

.flexibility-range-input::-moz-range-thumb {
  width: 12px;
  height: 12px;
  pointer-events: auto;
  cursor: grab;
  border: 3px solid #ffffff;
  border-radius: 999px;
  background: #165dff;
  box-shadow: 0 0 0 1px #165dff, 0 2px 5px rgba(22, 93, 255, 0.3);
}

.flexibility-range-input:focus-visible::-webkit-slider-thumb {
  outline: 2px solid rgba(22, 93, 255, 0.35);
  outline-offset: 3px;
}
</style>
