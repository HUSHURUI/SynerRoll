<script setup lang="ts">
import * as echarts from 'echarts'
import type { DeviceFlexibilityResult } from '~~/types/api'

const props = defineProps<{
  title: string
  deviceType: string
  rows: DeviceFlexibilityResult[]
  boundary?: boolean
}>()

const chartRef = ref<HTMLDivElement | null>(null)
let chart: echarts.ECharts | null = null
let resizeObserver: ResizeObserver | null = null

const toMinutes = (timestamp: string): number => {
  const [hour = '0', minute = '0'] = timestamp.split(':')
  return Number(hour) * 60 + Number(minute)
}

const timeline = computed(() => [...new Set(props.rows.map(row => row.timestamp))]
  .sort((a, b) => toMinutes(a) - toMinutes(b)))

const valueByDirection = (direction: 'up' | 'down', field: 'device_flexibility' | 'device_contribution') => {
  const values = new Map(
    props.rows
      .filter(row => row.direction === direction)
      .map(row => [row.timestamp, Number(row[field] ?? row.device_flexibility)])
  )
  return timeline.value.map(timestamp => values.get(timestamp) ?? null)
}

const peak = (direction: 'up' | 'down'): number => Math.max(
  0,
  ...props.rows
    .filter(row => row.direction === direction)
    .map(row => Number(row.device_flexibility) || 0)
)

const render = () => {
  if (!chartRef.value) return
  chart ??= echarts.init(chartRef.value)

  const hasContribution = !props.boundary && props.rows.some(row => row.device_contribution != null)
  const series: echarts.SeriesOption[] = [
    {
      id: 'up-capacity',
      name: props.boundary ? '上调边界空间' : '上调灵活性',
      type: 'line',
      data: valueByDirection('up', 'device_flexibility'),
      showSymbol: false,
      lineStyle: { width: 2, color: '#165DFF' },
      itemStyle: { color: '#165DFF' },
      areaStyle: { color: 'rgba(22,93,255,0.08)' }
    },
    {
      id: 'down-capacity',
      name: props.boundary ? '下调边界空间' : '下调灵活性',
      type: 'line',
      data: valueByDirection('down', 'device_flexibility'),
      showSymbol: false,
      lineStyle: { width: 2, color: '#12B76A' },
      itemStyle: { color: '#12B76A' },
      areaStyle: { color: 'rgba(18,183,106,0.06)' }
    }
  ]

  if (hasContribution) {
    series.push(
      {
        id: 'up-contribution',
        name: '上调系统供给分摊',
        type: 'line',
        data: valueByDirection('up', 'device_contribution'),
        showSymbol: false,
        lineStyle: { width: 1.5, type: 'dashed', color: '#F79009' },
        itemStyle: { color: '#F79009' }
      },
      {
        id: 'down-contribution',
        name: '下调系统供给分摊',
        type: 'line',
        data: valueByDirection('down', 'device_contribution'),
        showSymbol: false,
        lineStyle: { width: 1.5, type: 'dashed', color: '#F04438' },
        itemStyle: { color: '#F04438' }
      }
    )
  }

  chart.setOption({
    animation: true,
    animationDuration: 300,
    color: ['#165DFF', '#12B76A', '#F79009', '#F04438'],
    legend: {
      right: 12,
      top: 5,
      itemWidth: 14,
      itemHeight: 8,
      textStyle: { fontSize: 10 }
    },
    grid: { left: 55, right: 18, top: 38, bottom: 30 },
    xAxis: {
      type: 'category',
      data: timeline.value,
      boundaryGap: false,
      axisLabel: { fontSize: 10, hideOverlap: true },
      axisLine: { lineStyle: { color: '#D0D5DD' } }
    },
    yAxis: {
      type: 'value',
      min: 0,
      name: 'kW',
      nameTextStyle: { fontSize: 10, color: '#667085' },
      axisLabel: { fontSize: 10 },
      splitLine: { lineStyle: { type: 'dashed', color: '#EAECF0' } }
    },
    tooltip: {
      trigger: 'axis',
      valueFormatter: (value: unknown) => `${Number(value).toFixed(2)} kW`
    },
    series
  }, {
    notMerge: false,
    lazyUpdate: true,
    replaceMerge: ['series']
  })
}

watch(() => JSON.stringify(props.rows), render)

onMounted(() => {
  render()
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
    <div class="flex flex-wrap items-start justify-between gap-3 px-1">
      <div>
        <div class="flex items-center gap-2">
          <h3 class="text-sm font-semibold text-app-text">{{ title }}</h3>
          <span class="rounded-full bg-app-panel-soft px-2 py-0.5 text-[10px] text-app-muted">{{ deviceType }}</span>
          <span v-if="boundary" class="rounded-full bg-blue-50 px-2 py-0.5 text-[10px] text-primary">并网边界</span>
        </div>
      </div>
      <div class="flex gap-4 text-right text-[11px] text-app-muted">
        <div>峰值上调 <span class="ml-1 font-semibold text-primary">{{ peak('up').toFixed(2) }} kW</span></div>
        <div>峰值下调 <span class="ml-1 font-semibold text-green-700">{{ peak('down').toFixed(2) }} kW</span></div>
      </div>
    </div>
    <div ref="chartRef" class="mt-2 h-44 w-full" />
  </section>
</template>
