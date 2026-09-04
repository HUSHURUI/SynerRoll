<script setup lang="ts">
import * as echarts from 'echarts'

interface Point {
  ts: string
  value: number
}

const props = defineProps<{
  layers: Record<string, Point[]>
  title: string
  unit: string
  /** 层ID→层名称映射，如 { "1": "日前", "2": "日内" } */
  layerNames?: Record<string, string>
}>()

const chartRef = ref<HTMLDivElement | null>(null)
let chartInstance: echarts.ECharts | null = null

/** "H:MM" → 分钟数（用于 x 轴定位） */
function tsToMinutes(ts: string): number {
  const parts = ts.split(':')
  if (parts.length < 2) return 0
  return parseInt(parts[0]!, 10) * 60 + parseInt(parts[1]!, 10)
}

/** 分钟数 → "H:MM" 显示标签 */
function minutesToLabel(m: number): string {
  const h = Math.floor(m / 60)
  const min = m % 60
  return `${h}:${min.toString().padStart(2, '0')}`
}

/** 运行总览只展示整数量级，小数及求解器产生的极小浮点残差直接截断。 */
function truncateSeriesValue(value: number): number {
  return Math.trunc(Math.abs(value))
}

function formatIntegerValue(value: number): string {
  return Math.trunc(value).toLocaleString('en-US')
}

// 色带，越早的层越半透明，最新的层不透明
const PALETTE = [
  '239,68,68',   // 红
  '234,179,8',   // 黄
  '34,197,94',   // 绿
  '59,130,246',  // 蓝
  '168,85,247',  // 紫
]
function layerColor(index: number, total: number): string {
  const rgb = PALETTE[index % PALETTE.length]!
  const opacity = total <= 1 ? 1.0 : 0.35 + 0.65 * (index / (total - 1))
  return `rgba(${rgb},${opacity.toFixed(2)})`
}

const render = () => {
  if (!chartRef.value) return
  if (!chartInstance) {
    chartInstance = echarts.init(chartRef.value)
  }

  const layerIds = Object.keys(props.layers).sort((a, b) => Number(a) - Number(b))
  const series: echarts.SeriesOption[] = layerIds.map((lid, i) => {
    const points = props.layers[lid] ?? []
    const data: [number, number][] = points.map(p => [tsToMinutes(p.ts), truncateSeriesValue(p.value)])
    const color = layerColor(i, layerIds.length)
    return {
      id: `layer-${lid}`,
      type: 'line',
      name: props.layerNames?.[lid] ?? `层${lid}`,
      data,
      showSymbol: false,
      smooth: false,
      lineStyle: { width: 1.5, color },
      itemStyle: { color },
      areaStyle: { opacity: 0.05, color },
    }
  })

  chartInstance.setOption({
    title: {
      text: props.title,
      textStyle: { fontSize: 11, fontWeight: 'normal' },
      left: 'center',
      top: 2
    },
    legend: {
      show: layerIds.length > 1,
      top: 2,
      right: 8,
      itemWidth: 12,
      itemHeight: 8,
      textStyle: { fontSize: 9 }
    },
    grid: { left: 42, right: 12, top: layerIds.length > 1 ? 20 : 24, bottom: 20, containLabel: false },
    xAxis: {
      type: 'value',
      min: 0,
      max: 1440,
      interval: 60,
      axisLabel: {
        fontSize: 9,
        formatter: (v: number) => minutesToLabel(v)
      },
      splitLine: { show: false }
    },
    yAxis: {
      type: 'value',
      name: props.unit,
      nameGap: 8,
      nameTextStyle: { fontSize: 9, color: '#667085' },
      minInterval: 1,
      axisLabel: {
        fontSize: 9,
        formatter: (value: number) => formatIntegerValue(value)
      },
      scale: true,
      splitLine: { lineStyle: { type: 'dashed', color: '#eee' } }
    },
    series,
    tooltip: {
      trigger: 'axis',
      formatter: (params: unknown) => {
        const arr = Array.isArray(params) ? params as { data?: number[]; seriesName?: string; color?: string }[] : []
        if (!arr.length) return ''
        const m = arr[0]?.data?.[0] ?? 0
        let html = `<b>${minutesToLabel(m as number)}</b>`
        for (const p of arr) {
          const d = p.data
          if (!d || d.length < 2) continue
          const val = typeof d[1] === 'number' ? d[1] : 0
          const unitSuffix = props.unit ? ` ${props.unit}` : ''
          html += `<br/><span style="color:${p.color ?? ''}">●</span> ${p.seriesName ?? ''}: ${formatIntegerValue(val)}${unitSuffix}`
        }
        return html
      }
    },
    animation: true,
    animationDuration: 300,
    animationDurationUpdate: 220,
    animationEasing: 'cubicOut',
    animationEasingUpdate: 'linear'
  }, {
    notMerge: false,
    lazyUpdate: true,
    replaceMerge: ['series']
  })
}

// 数据或单位变化时重绘。
watch([() => JSON.stringify(props.layers), () => props.unit], () => render())

onMounted(() => {
  render()
  const ro = new ResizeObserver(() => chartInstance?.resize())
  if (chartRef.value) ro.observe(chartRef.value)
  onBeforeUnmount(() => ro.disconnect())
})

onBeforeUnmount(() => {
  chartInstance?.dispose()
  chartInstance = null
})
</script>

<template>
  <div ref="chartRef" class="w-full h-36" />
</template>
