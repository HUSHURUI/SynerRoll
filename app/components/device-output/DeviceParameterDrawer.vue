<script setup lang="ts">
import type { ConfigField } from '~~/types/component'
import type { Project } from '~~/types/project'
import type { DeviceOutputDevice } from '~~/utils/deviceOutputData'
import { componentDefinitionMap } from '~~/config/component-meta'

interface ParameterRow {
  key: string
  label: string
  value: string
  unit?: string
}

interface ParameterSection {
  title: string
  rows: ParameterRow[]
}

const props = defineProps<{
  open: boolean
  project: Project | null
  canvasId: string
  devices: DeviceOutputDevice[]
  selectedDeviceId?: string
}>()

const emit = defineEmits<{
  close: []
}>()

const activeDeviceId = ref('')

watch(() => [props.open, props.selectedDeviceId, props.devices.length] as const, ([open]) => {
  if (!open) return
  const preferred = props.selectedDeviceId && props.devices.some(device => device.id === props.selectedDeviceId)
    ? props.selectedDeviceId
    : props.devices[0]?.id
  activeDeviceId.value = preferred ?? ''
}, { immediate: true })

const canvas = computed(() => props.project?.workspace.canvases.find(item => item.id === props.canvasId))
const node = computed(() => canvas.value?.nodes.find(item => String(item.id) === activeDeviceId.value))
const device = computed(() => props.devices.find(item => item.id === activeDeviceId.value))
const definition = computed(() => componentDefinitionMap[String(node.value?.data?.componentKey ?? '')])

function displayValue(value: unknown): string {
  if (value == null || value === '') return '--'
  if (typeof value === 'boolean') return value ? '是' : '否'
  if (typeof value === 'number') return Number.isInteger(value) ? value.toLocaleString('zh-CN') : String(value)
  if (typeof value === 'object' && 'enabled' in (value as Record<string, unknown>)) {
    return (value as { enabled?: boolean }).enabled ? '启用' : '停用'
  }
  return String(value)
}

function parameterRows(values: Record<string, unknown> | undefined, fields: ConfigField[] = []): ParameterRow[] {
  if (!values) return []
  const fieldMap = new Map(fields.map(field => [field.key, field]))
  const orderedKeys = [
    ...fields.map(field => field.key).filter(key => key in values),
    ...Object.keys(values).filter(key => !fieldMap.has(key))
  ]
  return [...new Set(orderedKeys)].map((key) => {
    const field = fieldMap.get(key)
    return {
      key,
      label: field?.label ?? key,
      value: displayValue(values[key]),
      unit: field?.unit
    }
  })
}

const sections = computed<ParameterSection[]>(() => {
  const business = node.value?.data?.business
  if (!business) return []
  const component = definition.value
  const result: ParameterSection[] = []

  const commonTech = parameterRows(business.commonTechParams, component?.commonTechParamFields)
  if (commonTech.length) result.push({ title: '通用技术参数', rows: commonTech })

  const commonEconomic = parameterRows(business.commonEconomicParams, component?.commonEconomicParamFields)
  if (commonEconomic.length) result.push({ title: '通用经济参数', rows: commonEconomic })

  const layerNameMap = new Map((props.project?.layerConfig.layers ?? []).map(layer => [layer.id, layer.name]))
  for (const layer of props.project?.layerConfig.layers ?? []) {
    const config = business.layerConfigs?.[layer.id]
    if (!config) continue
    const rows: ParameterRow[] = [
      { key: 'status', label: '运行状态', value: displayValue(config.status) },
      ...parameterRows(config.techParams, component?.layerTechParamFields),
      ...parameterRows(config.economicParams, component?.layerEconomicParamFields),
      ...parameterRows(config.constraints, component?.layerConstraintFields),
      ...parameterRows(config.objectives, component?.layerObjectiveFields)
    ]
    result.push({ title: `${layerNameMap.get(layer.id) ?? `时层 ${layer.id}`}参数`, rows })
  }

  return result
})
</script>

<template>
  <AppModal :open="open" title="查看设备参数" size="lg" @close="emit('close')">
    <div class="space-y-4 px-3 py-2">
      <div class="grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-end">
        <label>
          <span class="field-label">设备</span>
          <select v-model="activeDeviceId" class="field-select">
            <option v-for="item in devices" :key="item.id" :value="item.id">
              {{ item.name }}（{{ item.componentLabel }}）
            </option>
          </select>
        </label>
        <span class="inline-flex h-9 items-center rounded-full bg-primary-soft px-3 text-xs font-medium text-primary">只读</span>
      </div>

      <section v-if="node && device" class="rounded-[10px] border border-app-border bg-app-panel-soft/60 p-3">
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h3 class="text-sm font-semibold text-app-text">{{ device.name }}</h3>
            <p class="mt-1 text-xs text-app-muted">{{ device.componentLabel }} · {{ device.componentType }}</p>
          </div>
          <div class="text-right text-[11px] leading-5 text-app-muted">
            <div>设备 ID：{{ device.id }}</div>
            <div>结果变量：{{ device.variables.length }} 个</div>
          </div>
        </div>
      </section>

      <div v-if="sections.length" class="space-y-3">
        <section v-for="section in sections" :key="section.title" class="rounded-[10px] border border-app-border bg-white">
          <h3 class="border-b border-app-border px-4 py-2.5 text-sm font-semibold text-app-text">{{ section.title }}</h3>
          <dl class="grid gap-px bg-app-border sm:grid-cols-2">
            <div
              v-for="row in section.rows"
              :key="`${section.title}-${row.key}`"
              class="flex min-h-11 items-center justify-between gap-3 bg-white px-4 py-2 text-xs"
            >
              <dt class="text-app-muted">{{ row.label }}</dt>
              <dd class="text-right font-medium text-app-text">
                {{ row.value }}<span v-if="row.unit" class="ml-1 font-normal text-app-muted">{{ row.unit }}</span>
              </dd>
            </div>
          </dl>
        </section>
      </div>

      <div v-else class="flex h-28 items-center justify-center rounded-[10px] border border-dashed border-app-border text-sm text-app-muted">
        当前设备没有可显示的配置参数
      </div>
    </div>

    <template #footer>
      <AppButton label="关闭" size="sm" tone="primary" @click="emit('close')" />
    </template>
  </AppModal>
</template>
