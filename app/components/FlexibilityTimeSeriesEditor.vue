<script setup lang="ts">
type SeriesSourceMode = 'manual' | 'file' | 'boundary'

interface BoundarySeriesOption {
  value: string
  label: string
  timestamps: string[]
  values: number[]
  source: 'database' | 'project'
}

interface EditableSeriesRow {
  id: string
  timestamp: string
  value: string
}

const props = defineProps<{
  modelValue: Record<string, number>
  mode: SeriesSourceMode
  label: string
  nonnegative?: boolean
  boundaryOptions?: BoundarySeriesOption[]
  expectedTimestamps?: string[]
}>()

const emit = defineEmits<{
  'update:modelValue': [value: Record<string, number>]
  validation: [message: string]
}>()

const fileInput = ref<HTMLInputElement | null>(null)
const fileName = ref('')
const fileHeaders = ref<string[]>([])
const fileRows = ref<unknown[][]>([])
const timestampColumn = ref('0')
const valueColumn = ref('1')
const selectedBoundary = ref('')
const validationMessage = ref('')
const fileLoaded = ref(false)

const nextRowId = () => globalThis.crypto?.randomUUID?.() ?? `${Date.now()}-${Math.random()}`

const recordToRows = (value: Record<string, number>): EditableSeriesRow[] => {
  const entries = Object.entries(value)
  if (!entries.length) return [{ id: nextRowId(), timestamp: 'default', value: '0' }]
  return entries.map(([timestamp, rowValue]) => ({
    id: nextRowId(),
    timestamp,
    value: String(rowValue)
  }))
}

const manualRows = ref<EditableSeriesRow[]>(recordToRows(props.modelValue))
let syncingFromParent = false

watch(() => props.modelValue, (value) => {
  if (syncingFromParent || props.mode === 'manual') return
  manualRows.value = recordToRows(value)
}, { deep: true })

const timeLabelMinutes = (timestamp: string): number => {
  if (timestamp === 'default') return Number.MAX_SAFE_INTEGER
  const match = /^(\d+):(\d{2})$/.exec(timestamp)
  if (!match) return Number.MAX_SAFE_INTEGER - 1
  return Number(match[1]) * 60 + Number(match[2])
}

const normalizedEntries = (
  entries: Array<{ timestamp: unknown; value: unknown }>
): { value: Record<string, number> | null; error: string } => {
  if (!entries.length) return { value: null, error: `${props.label}至少需要一条数据` }

  const result: Record<string, number> = {}
  for (let index = 0; index < entries.length; index++) {
    const timestamp = String(entries[index]!.timestamp ?? '').trim()
    const rawValue = entries[index]!.value
    if (!timestamp) return { value: null, error: `第 ${index + 1} 行缺少时间戳` }
    if (timestamp !== 'default') {
      const match = /^(\d+):(\d{2})$/.exec(timestamp)
      if (!match || Number(match[2]) >= 60) {
        return { value: null, error: `${timestamp} 不是有效时间标签，请使用 H:MM 或 default` }
      }
    }
    if (Object.prototype.hasOwnProperty.call(result, timestamp)) {
      return { value: null, error: `时间戳 ${timestamp} 重复` }
    }
    if (rawValue === '' || rawValue === null || rawValue === undefined) {
      return { value: null, error: `${timestamp} 缺少数值` }
    }
    const numericValue = Number(rawValue)
    if (!Number.isFinite(numericValue)) {
      return { value: null, error: `${timestamp} 的值不是有限数值` }
    }
    if (props.nonnegative && numericValue < 0) {
      return { value: null, error: `${timestamp} 的值不能小于 0` }
    }
    result[timestamp] = numericValue
  }
  if (!Object.prototype.hasOwnProperty.call(result, 'default') && props.expectedTimestamps?.length) {
    const missing = props.expectedTimestamps.filter(timestamp =>
      !Object.prototype.hasOwnProperty.call(result, timestamp)
    )
    if (missing.length) {
      const preview = missing.slice(0, 3).join('、')
      return {
        value: null,
        error: `缺少 ${missing.length} 个评价时点（如 ${preview}），请补齐或增加 default`
      }
    }
  }
  return { value: result, error: '' }
}

const setValidation = (message: string) => {
  validationMessage.value = message
  emit('validation', message)
}

const applyEntries = (entries: Array<{ timestamp: unknown; value: unknown }>) => {
  const normalized = normalizedEntries(entries)
  setValidation(normalized.error)
  if (!normalized.value) return false
  syncingFromParent = true
  emit('update:modelValue', normalized.value)
  syncingFromParent = false
  if (props.mode !== 'manual') manualRows.value = recordToRows(normalized.value)
  return true
}

const validateManualRows = () => {
  if (props.mode !== 'manual') return
  applyEntries(manualRows.value.map(row => ({ timestamp: row.timestamp, value: row.value })))
}

watch(manualRows, validateManualRows, { deep: true })

const addManualRow = () => {
  manualRows.value.push({ id: nextRowId(), timestamp: '', value: '' })
}

const removeManualRow = (id: string) => {
  manualRows.value = manualRows.value.filter(row => row.id !== id)
}

const openFilePicker = () => fileInput.value?.click()

const parseJsonFile = (text: string): boolean => {
  const parsed = JSON.parse(text) as unknown
  if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
    return applyEntries(
      Object.entries(parsed as Record<string, unknown>).map(([timestamp, value]) => ({ timestamp, value }))
    )
  }
  if (Array.isArray(parsed) && parsed.every(row => row && typeof row === 'object' && !Array.isArray(row))) {
    const rows = parsed as Array<Record<string, unknown>>
    const keys = Object.keys(rows[0] ?? {})
    const timestampKey = keys.find(key => /^(timestamp|time|ts|时间|时刻)$/i.test(key)) ?? keys[0]
    const valueKey = keys.find(key => /^(value|power|target|功率|数值)$/i.test(key)) ?? keys[1]
    if (!timestampKey || !valueKey) throw new Error('JSON数组需要包含时间戳列和数值列')
    return applyEntries(rows.map(row => ({ timestamp: row[timestampKey], value: row[valueKey] })))
  }
  throw new Error('JSON需为“时间戳-数值”对象或对象数组')
}

const applyImportedColumns = () => {
  if (!fileRows.value.length) return
  const timestampIndex = Number(timestampColumn.value)
  const valueIndex = Number(valueColumn.value)
  if (timestampIndex === valueIndex) {
    setValidation('时间戳列和数值列不能相同')
    return
  }
  applyEntries(fileRows.value.map(row => ({
    timestamp: row[timestampIndex],
    value: row[valueIndex]
  })))
}

watch([timestampColumn, valueColumn], () => {
  if (props.mode === 'file' && fileRows.value.length) applyImportedColumns()
})

const handleFile = async (event: Event) => {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]
  if (!file) return
  fileName.value = file.name
  fileHeaders.value = []
  fileRows.value = []
  fileLoaded.value = false
  try {
    const extension = file.name.split('.').pop()?.toLowerCase()
    if (extension === 'json') {
      const applied = parseJsonFile(await file.text())
      fileLoaded.value = applied
      if (applied) setValidation('')
      return
    }
    if (!['csv', 'xlsx', 'xls'].includes(extension ?? '')) {
      throw new Error('仅支持 CSV、Excel（.xlsx/.xls）和 JSON 文件')
    }

    const XLSX = await import('xlsx')
    const workbook = XLSX.read(await file.arrayBuffer(), { type: 'array' })
    const firstSheetName = workbook.SheetNames[0]
    if (!firstSheetName) throw new Error('文件中没有可读取的工作表')
    const worksheet = workbook.Sheets[firstSheetName]
    if (!worksheet) throw new Error('无法读取第一个工作表')
    const matrix = XLSX.utils.sheet_to_json<unknown[]>(worksheet, {
      header: 1,
      raw: false,
      defval: ''
    })
    if (matrix.length < 2) throw new Error('文件至少需要一行表头和一行数据')
    const headers = (matrix[0] ?? []).map((header, index) => String(header || `列${index + 1}`))
    if (headers.length < 2) throw new Error('文件至少需要时间戳列和数值列')
    fileHeaders.value = headers
    fileRows.value = matrix.slice(1).filter(row => row.some(cell => String(cell).trim() !== ''))
    timestampColumn.value = String(Math.max(0, headers.findIndex(header => /timestamp|time|ts|时间|时刻/i.test(header))))
    const inferredValue = headers.findIndex((header, index) => index !== Number(timestampColumn.value) && /value|power|target|功率|数值/i.test(header))
    valueColumn.value = String(inferredValue >= 0 ? inferredValue : (Number(timestampColumn.value) === 0 ? 1 : 0))
    fileLoaded.value = true
    applyImportedColumns()
  }
  catch (error) {
    setValidation(error instanceof Error ? error.message : String(error))
  }
  finally {
    input.value = ''
  }
}

const applyBoundarySeries = () => {
  const option = props.boundaryOptions?.find(item => item.value === selectedBoundary.value)
  if (!option) {
    setValidation('请选择一条已有边界曲线')
    return
  }
  if (option.timestamps.length !== option.values.length) {
    setValidation('所选边界曲线的时间戳与数值数量不一致')
    return
  }
  applyEntries(option.timestamps.map((timestamp, index) => ({
    timestamp,
    value: option.values[index]
  })))
}

watch(selectedBoundary, () => {
  if (props.mode === 'boundary') applyBoundarySeries()
})

watch(() => props.mode, (mode) => {
  if (mode === 'manual') validateManualRows()
  else if (mode === 'file') setValidation(fileLoaded.value ? validationMessage.value : '请选择并导入一个时序文件')
  else if (mode === 'boundary') applyBoundarySeries()
}, { immediate: true })

watch(() => props.expectedTimestamps, () => {
  if (props.mode === 'manual') validateManualRows()
  else if (props.mode === 'file' && fileLoaded.value) {
    applyEntries(Object.entries(props.modelValue).map(([timestamp, value]) => ({ timestamp, value })))
  }
  else if (props.mode === 'boundary' && selectedBoundary.value) applyBoundarySeries()
}, { deep: true })

const previewRows = computed(() =>
  Object.entries(props.modelValue)
    .sort((left, right) => timeLabelMinutes(left[0]) - timeLabelMinutes(right[0]))
)
</script>

<template>
  <div class="space-y-3 rounded-[10px] border border-app-border bg-white p-3">
    <div v-if="mode === 'manual'" class="space-y-2">
      <div class="flex items-center justify-between gap-3">
        <div class="text-xs font-medium text-app-text">{{ label }}分时表格</div>
        <button type="button" class="text-xs font-medium text-primary hover:underline" @click="addManualRow">+ 添加时段</button>
      </div>
      <div class="max-h-44 overflow-y-auto rounded-lg border border-app-border">
        <table class="w-full text-xs">
          <thead class="sticky top-0 bg-app-panel-soft text-app-muted">
            <tr><th class="px-3 py-2 text-left font-medium">时间戳</th><th class="px-3 py-2 text-left font-medium">数值（kW）</th><th class="w-14 px-2 py-2" /></tr>
          </thead>
          <tbody>
            <tr v-for="row in manualRows" :key="row.id" class="border-t border-app-border">
              <td class="p-1.5"><input v-model="row.timestamp" class="field-input h-8 text-xs" placeholder="0:00 或 default"></td>
              <td class="p-1.5"><input v-model="row.value" type="number" class="field-input h-8 text-xs" placeholder="0"></td>
              <td class="p-1.5 text-center"><button type="button" class="text-app-muted hover:text-app-danger" title="删除" @click="removeManualRow(row.id)">×</button></td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <div v-else-if="mode === 'file'" class="space-y-3">
      <input ref="fileInput" type="file" accept=".csv,.xlsx,.xls,.json" class="hidden" @change="handleFile">
      <div class="flex flex-wrap items-center gap-2">
        <AppButton label="选择 CSV / Excel / JSON" tone="neutral" size="sm" @click="openFilePicker" />
        <span class="text-xs text-app-muted">{{ fileName || '尚未选择文件' }}</span>
      </div>
      <div v-if="fileHeaders.length" class="grid gap-2 sm:grid-cols-2">
        <label class="space-y-1 text-xs text-app-muted">
          <span>时间戳列</span>
          <select v-model="timestampColumn" class="field-input h-8 text-xs">
            <option v-for="(header, index) in fileHeaders" :key="`time-${index}`" :value="String(index)">{{ header }}</option>
          </select>
        </label>
        <label class="space-y-1 text-xs text-app-muted">
          <span>数值列</span>
          <select v-model="valueColumn" class="field-input h-8 text-xs">
            <option v-for="(header, index) in fileHeaders" :key="`value-${index}`" :value="String(index)">{{ header }}</option>
          </select>
        </label>
      </div>
      <p class="text-[11px] leading-5 text-app-muted">首行作为表头；时间标签使用 H:MM。导入后只把规范化的“时间戳—数值”数据提交给后端。</p>
    </div>

    <div v-else class="space-y-2">
      <label class="space-y-1 text-xs text-app-muted">
        <span>项目边界数据库曲线</span>
        <select v-model="selectedBoundary" class="field-input h-8 text-xs" :disabled="!boundaryOptions?.length">
          <option value="">{{ boundaryOptions?.length ? '请选择计划/AGC曲线' : '当前时层没有可用功率曲线' }}</option>
          <option v-for="option in boundaryOptions" :key="option.value" :value="option.value">{{ option.label }}</option>
        </select>
      </label>
      <p class="text-[11px] leading-5 text-app-muted">优先读取 boundary.db 中所选时层的数据；数据库暂不可用时使用项目中保存的同层缓存。</p>
    </div>

    <div v-if="validationMessage" class="rounded-lg bg-red-50 px-3 py-2 text-xs text-app-danger">{{ validationMessage }}</div>
    <div v-else class="rounded-lg bg-green-50 px-3 py-2 text-xs text-green-700">校验通过，共 {{ previewRows.length }} 个时点。</div>

    <div v-if="previewRows.length" class="overflow-hidden rounded-lg border border-app-border">
      <div class="flex items-center justify-between bg-app-panel-soft px-3 py-2 text-[11px] text-app-muted">
        <span>规范化数据预览</span><span>显示前 {{ Math.min(8, previewRows.length) }} / {{ previewRows.length }} 条</span>
      </div>
      <table class="w-full text-xs">
        <tbody>
          <tr v-for="([timestamp, value], index) in previewRows.slice(0, 8)" :key="`${timestamp}-${index}`" class="border-t border-app-border first:border-t-0">
            <td class="px-3 py-1.5 text-app-muted">{{ timestamp }}</td>
            <td class="px-3 py-1.5 text-right font-medium text-app-text">{{ value }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
