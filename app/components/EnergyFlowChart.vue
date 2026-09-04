<script setup lang="ts">
import * as echarts from 'echarts'

interface Point {
  ts: string
  value: number
}

const props = defineProps<{
  /** 总线名称 */
  busLabel: string
  /** 该总线关联的变量名列表，如 ["E_WT_out_7e8a", "E_ES_in_7e77"] */
  variables: string[]
  /** 全量时序数据: { "WT_7e8a|E_WT_out_7e8a": { "1": [{ts, value}] } } */
  liveData: Record<string, Record<string, Point[]>>
  /** 当前选中的时层 ID */
  layerId: string
  /** 节点 code → 设备名称映射，如 { "7e8a": "风机1" } */
  codeToLabel: Record<string, string>
}>()

// ───── 变量解析辅助 ─────

/** 从变量名提取设备 code（最后一段），如 E_WT_out_7e8a → 7e8a */
function extractCode(varName: string): string {
  const parts = varName.split('_')
  return parts[parts.length - 1] ?? ''
}

/** 判断变量是源（正）还是荷（负）: _out_ → +1, _in_ → -1 */
function getSign(varName: string): number {
  if (varName.includes('SHORTAGE')) return -1
  if (varName.includes('EXCESS')) return 1
  if (varName.includes('_out_')) return 1
  if (varName.includes('_in_')) return -1
  return 0
}

/** 获取设备显示名称 */
function getDeviceName(varName: string): string {
  const code = extractCode(varName)
  return props.codeToLabel[code] ?? code
}

/** 在 liveData 中查找匹配的 key */
function findDataKey(varName: string): string | null {
  for (const key of Object.keys(props.liveData)) {
    if (key.endsWith(`|${varName}`)) return key
  }
  for (const key of Object.keys(props.liveData)) {
    if (key.includes(varName)) return key
  }
  const normalized = varName.replace(/_out_|_in_/g, '_')
  if (normalized !== varName) {
    for (const key of Object.keys(props.liveData)) {
      if (key.endsWith(`|${normalized}`)) return key
    }
    for (const key of Object.keys(props.liveData)) {
      if (key.includes(normalized)) return key
    }
  }
  return null
}

/** 获取指定变量在当前时层的时序数据 */
function getVarData(varName: string): Point[] {
  const key = findDataKey(varName)
  if (!key) return []
  return props.liveData[key]?.[props.layerId] ?? []
}

// ───── 分类变量 ─────

const sourceVars = computed(() => props.variables.filter(v => getSign(v) > 0))
const sinkVars = computed(() => props.variables.filter(v => getSign(v) < 0))

// ───── 贡献度：源/荷分别计算 ─────

interface ContributionItem {
  name: string
  value: number
  color: string
}

const PALETTE = [
  '#3b82f6', // 蓝
  '#22c55e', // 绿
  '#f59e0b', // 黄
  '#ef4444', // 红
  '#8b5cf6', // 紫
  '#06b6d4', // 青
  '#f97316', // 橙
  '#ec4899', // 粉
]

function calcContribution(vars: string[]): ContributionItem[] {
  const deviceMap = new Map<string, number>()
  for (const varName of vars) {
    const code = extractCode(varName)
    const data = getVarData(varName)
    const totalEnergy = data.reduce((sum, p) => sum + Math.abs(p.value), 0)
    deviceMap.set(code, (deviceMap.get(code) ?? 0) + totalEnergy)
  }
  const items: ContributionItem[] = []
  let idx = 0
  for (const [code, value] of deviceMap) {
    items.push({
      name: props.codeToLabel[code] ?? code,
      value,
      color: PALETTE[idx % PALETTE.length]!
    })
    idx++
  }
  items.sort((a, b) => b.value - a.value)
  return items
}

const sourceContribution = computed(() => calcContribution(sourceVars.value))
const sinkContribution = computed(() => calcContribution(sinkVars.value))

const sourceTotal = computed(() => sourceContribution.value.reduce((s, d) => s + d.value, 0))
const sinkTotal = computed(() => sinkContribution.value.reduce((s, d) => s + d.value, 0))

// ───── 堆叠条形图（echarts） ─────

const chartRef = ref<HTMLDivElement | null>(null)
let chartInstance: echarts.ECharts | null = null

/** "H:MM" → 分钟数 */
function tsToMinutes(ts: string): number {
  const parts = ts.split(':')
  if (parts.length < 2) return 0
  return parseInt(parts[0]!, 10) * 60 + parseInt(parts[1]!, 10)
}

/** 分钟数 → "H:MM" */
function minutesToLabel(m: number): string {
  const h = Math.floor(m / 60)
  const min = m % 60
  return `${h}:${min.toString().padStart(2, '0')}`
}

const renderChart = () => {
  if (!chartRef.value) return
  if (!chartInstance) {
    chartInstance = echarts.init(chartRef.value)
  }

  // 收集所有时间戳
  const allTsSet = new Set<number>()
  for (const varName of props.variables) {
    const data = getVarData(varName)
    data.forEach(p => allTsSet.add(tsToMinutes(p.ts)))
  }
  const allTs = Array.from(allTsSet).sort((a, b) => a - b)
  const xLabels = allTs.map(m => minutesToLabel(m))

  const series: echarts.SeriesOption[] = []
  // 源和荷共用一个 stack，正数自然向上、负数自然向下，保证同时刻对齐
  let colorIdx = 0

  for (const varName of sourceVars.value) {
    const data = getVarData(varName)
    const dataMap = new Map(data.map(p => [tsToMinutes(p.ts), p.value]))
    const barData = allTs.map(m => dataMap.get(m) ?? 0)

    series.push({
      type: 'bar',
      name: getDeviceName(varName),
      data: barData,
      stack: 'balance',
      barWidth: '60%',
      itemStyle: { color: PALETTE[colorIdx % PALETTE.length] },
    })
    colorIdx++
  }

  for (const varName of sinkVars.value) {
    const data = getVarData(varName)
    const dataMap = new Map(data.map(p => [tsToMinutes(p.ts), -Math.abs(p.value)]))
    const barData = allTs.map(m => dataMap.get(m) ?? 0)

    series.push({
      type: 'bar',
      name: getDeviceName(varName),
      data: barData,
      stack: 'balance',
      barWidth: '60%',
      itemStyle: { color: PALETTE[colorIdx % PALETTE.length] },
    })
    colorIdx++
  }

  chartInstance.setOption({
    title: {
      text: props.busLabel,
      textStyle: { fontSize: 12, fontWeight: 'normal' },
      left: 'center',
      top: 2
    },
    legend: {
      show: true,
      top: 2,
      right: 8,
      itemWidth: 12,
      itemHeight: 8,
      textStyle: { fontSize: 9 }
    },
    grid: { left: 50, right: 12, top: 24, bottom: 30, containLabel: false },
    xAxis: {
      type: 'category',
      data: xLabels,
      axisLabel: {
        fontSize: 8,
        rotate: 45,
        interval: Math.max(0, Math.floor(xLabels.length / 12))
      },
      splitLine: { show: false }
    },
    yAxis: {
      type: 'value',
      axisLabel: { fontSize: 9 },
      splitLine: { lineStyle: { type: 'dashed', color: '#eee' } }
    },
    series,
    tooltip: {
      trigger: 'axis',
      formatter: (params: unknown) => {
        const arr = Array.isArray(params) ? params as { data?: number; seriesName?: string; color?: string; axisValue?: string }[] : []
        if (!arr.length) return ''
        let html = `<b>${arr[0]?.axisValue ?? ''}</b>`
        for (const p of arr) {
          const val = typeof p.data === 'number' ? p.data : 0
          if (Math.abs(val) < 0.01) continue
          html += `<br/><span style="color:${p.color ?? ''}">●</span> ${p.seriesName ?? ''}: ${val.toFixed(1)}`
        }
        return html
      }
    },
    animation: false
  }, true)
}

watch(() => JSON.stringify(props.liveData) + props.layerId + JSON.stringify(props.variables), () => renderChart())

onMounted(() => {
  renderChart()
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
  <div class="flex gap-3 h-80">
    <!-- 堆叠条形图 -->
    <div ref="chartRef" class="flex-1 min-w-0" />

    <!-- 贡献度：源/荷双栏 -->
    <div class="w-36 flex flex-col gap-2">
      <!-- 源 -->
      <div class="flex-1 flex flex-col min-h-0">
        
        <div class="flex-1 flex gap-1 min-h-0">
          <div class="w-8 flex flex-col-reverse border border-app-border rounded overflow-hidden bg-app-panel-soft">
            <div
              v-for="(item, i) in sourceContribution"
              :key="i"
              class="w-full"
              :style="{
                height: sourceTotal > 0 ? `${(item.value / sourceTotal) * 100}%` : '0%',
                backgroundColor: item.color,
                minHeight: item.value > 0 ? '2px' : '0px'
              }"
              :title="`${item.name}: ${item.value.toFixed(1)}`"
            />
          </div>
          <div class="flex-1 flex flex-col-reverse justify-between text-[9px] leading-tight py-0.5 overflow-hidden">
            <div
              v-for="(item, i) in sourceContribution"
              :key="i"
              class="flex items-center gap-1 truncate"
            >
              <span class="inline-block w-1.5 h-1.5 rounded-sm flex-shrink-0" :style="{ backgroundColor: item.color }" />
              <span class="truncate">{{ item.name }}</span>
              <span class="text-app-muted flex-shrink-0">{{ sourceTotal > 0 ? ((item.value / sourceTotal) * 100).toFixed(2) : '0.00' }}%</span>
            </div>
          </div>
        </div>
      </div>

      <!-- 荷 -->
      <div class="flex-1 flex flex-col min-h-0">
        
        <div class="flex-1 flex gap-1 min-h-0">
          <div class="w-8 flex flex-col-reverse border border-app-border rounded overflow-hidden bg-app-panel-soft">
            <div
              v-for="(item, i) in sinkContribution"
              :key="i"
              class="w-full"
              :style="{
                height: sinkTotal > 0 ? `${(item.value / sinkTotal) * 100}%` : '0%',
                backgroundColor: item.color,
                minHeight: item.value > 0 ? '2px' : '0px'
              }"
              :title="`${item.name}: ${item.value.toFixed(1)}`"
            />
          </div>
          <div class="flex-1 flex flex-col-reverse justify-between text-[9px] leading-tight py-0.5 overflow-hidden">
            <div
              v-for="(item, i) in sinkContribution"
              :key="i"
              class="flex items-center gap-1 truncate"
            >
              <span class="inline-block w-1.5 h-1.5 rounded-sm flex-shrink-0" :style="{ backgroundColor: item.color }" />
              <span class="truncate">{{ item.name }}</span>
              <span class="text-app-muted flex-shrink-0">{{ sinkTotal > 0 ? ((item.value / sinkTotal) * 100).toFixed(2) : '0.00' }}%</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
