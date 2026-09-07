<script setup lang="ts">
import type { DeviceOutputDevice, DeviceOutputMedium, DeviceOutputVariable } from '~~/utils/deviceOutputData'

const props = defineProps<{
  open: boolean
  devices: DeviceOutputDevice[]
  selectedKeys: string[]
  layerIds: string[]
}>()

const emit = defineEmits<{
  close: []
  apply: [keys: string[]]
}>()

const searchDraft = ref('')
const appliedSearch = ref('')
const activeMedium = ref<'all' | DeviceOutputMedium>('all')
const draftSelected = ref<string[]>([])

watch(() => props.open, (open) => {
  if (!open) return
  draftSelected.value = [...props.selectedKeys]
  searchDraft.value = ''
  appliedSearch.value = ''
  activeMedium.value = 'all'
}, { immediate: true })

const layerVariables = computed(() => props.devices.flatMap(device => device.variables)
  .filter(variable => variable.layerIds.some(layerId => props.layerIds.includes(layerId))))

const mediumOptions = computed(() => {
  const present = new Map<DeviceOutputMedium, string>()
  for (const variable of layerVariables.value) present.set(variable.medium, variable.mediumLabel)
  return [
    { value: 'all' as const, label: '全部' },
    ...[...present.entries()].map(([value, label]) => ({ value, label }))
  ]
})

const normalizedSearch = computed(() => appliedSearch.value.trim().toLowerCase())

function applySearch(): void {
  appliedSearch.value = searchDraft.value
}

function matchesSearch(device: DeviceOutputDevice, variable?: DeviceOutputVariable): boolean {
  const search = normalizedSearch.value
  if (!search) return true
  const values = [
    device.name,
    device.componentLabel,
    device.componentType,
    device.id,
    device.code,
    variable?.variableName,
    variable?.baseVarName,
    variable?.varName,
    variable?.sourceId,
    variable?.mediumLabel
  ]
  return values.some(value => String(value ?? '').toLowerCase().includes(search))
}

const visibleDevices = computed(() => props.devices.map((device) => {
  const deviceMatches = matchesSearch(device)
  const variables = device.variables.filter((variable) => {
    if (!variable.layerIds.some(layerId => props.layerIds.includes(layerId))) return false
    if (activeMedium.value !== 'all' && variable.medium !== activeMedium.value) return false
    return deviceMatches || matchesSearch(device, variable)
  })
  return { ...device, variables }
}).filter(device => device.variables.length > 0))

function isSelected(key: string): boolean {
  return draftSelected.value.includes(key)
}

function toggleVariable(key: string): void {
  draftSelected.value = isSelected(key)
    ? draftSelected.value.filter(item => item !== key)
    : [...draftSelected.value, key]
}

function visibleDeviceSelected(device: DeviceOutputDevice): boolean {
  return device.variables.length > 0 && device.variables.every(variable => isSelected(variable.key))
}

function toggleDevice(device: DeviceOutputDevice): void {
  const keys = device.variables.map(variable => variable.key)
  if (visibleDeviceSelected(device)) {
    draftSelected.value = draftSelected.value.filter(key => !keys.includes(key))
    return
  }
  draftSelected.value = [...new Set([...draftSelected.value, ...keys])]
}

function applySelection(): void {
  emit('apply', [...draftSelected.value])
  emit('close')
}
</script>

<template>
  <AppModal :open="open" title="选择设备变量" size="lg" @close="emit('close')">
    <div class="space-y-3 px-3 py-2">
      <div class="flex items-center gap-2">
        <div class="relative min-w-0 flex-1">
          <input
            v-model="searchDraft"
            type="search"
            class="field-input pl-9"
            placeholder="搜索设备、设备简称、变量、能流或设备 ID"
            @keydown.enter.prevent="applySearch"
          >
          <svg class="pointer-events-none absolute left-3 top-2.5 h-4 w-4 text-app-muted" viewBox="0 0 16 16" fill="none">
            <circle cx="7" cy="7" r="4.5" stroke="currentColor" stroke-width="1.4" />
            <path d="M10.5 10.5L14 14" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" />
          </svg>
        </div>
        <AppButton label="搜索" size="md" tone="primary" @click="applySearch" />
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <!-- 左侧：按钮组 -->
        <div class="flex flex-wrap items-center gap-2">
          <button
            v-for="option in mediumOptions"
            :key="option.value"
            type="button"
            class="rounded-[4px] border px-2 py-1 text-xs transition"
            :class="activeMedium === option.value
              ? 'border-primary bg-primary-soft text-primary'
              : 'border-app-border bg-white text-app-muted hover:text-app-text'"
            @click="activeMedium = option.value"
          >
            {{ option.label }}
          </button>
        </div>
      
        <!-- 右侧：计数+清空，ml-auto 推到最右边 -->
        <div class="flex items-center gap-3 ml-auto">
          <span class="text-xs text-app-muted">已选 {{ draftSelected.length }} 项</span>
          <button type="button" class="text-xs text-primary hover:underline" @click="draftSelected = []">
            清空已选
          </button>
        </div>
      </div>

      <div v-if="visibleDevices.length" class="grid gap-3 md:grid-cols-2">
        <section
          v-for="device in visibleDevices"
          :key="device.id"
          class="rounded-[4px] bg-white p-3 shadow-[0px_0px_10px_rgba(0,0,0,0.15)]"
        >
          <div class="flex items-start justify-between gap-3 border-b border-app-border pb-2">
            <div class="min-w-0 flex items-center gap-2">
              <h3 class="truncate text-sm font-semibold text-app-text">{{ device.name }}</h3>
              <p class="mt-0.5 truncate text-[11px] text-app-muted">
                {{ device.componentType }} - {{ device.code }}
              </p>
            </div>
            <button
              type="button"
              class="shrink-0 text-xs text-primary hover:underline"
              @click="toggleDevice(device)"
            >
              {{ visibleDeviceSelected(device) ? '取消全选' : '全选' }}
            </button>
          </div>

          <div class="mt-2 space-y-1">
            <label
              v-for="variable in device.variables"
              :key="variable.key"
              class="flex cursor-pointer items-center gap-2 rounded-md px-2 py-1.5 text-xs transition hover:bg-app-panel-soft"
            >
              <input
                type="checkbox"
                class="field-checkbox shrink-0"
                :checked="isSelected(variable.key)"
                @change="toggleVariable(variable.key)"
              >
              <span class="min-w-0 flex-1 truncate text-app-text">{{ variable.variableName }}</span>
              <span class="shrink-0 text-[10px] text-app-muted">{{ variable.mediumLabel }} / {{ variable.originalUnit }}</span>
            </label>
          </div>
        </section>
      </div>

      <div v-else class="flex h-32 items-center justify-center rounded-[10px] border border-dashed border-app-border text-sm text-app-muted">
        当前筛选条件下没有可用变量
      </div>
    </div>

    <template #footer>
      <AppButton label="取消" size="sm" tone="neutral" @click="emit('close')" />
      <AppButton :label="`选择 ${draftSelected.length} 个变量`" size="sm" tone="primary" @click="applySelection" />
    </template>
  </AppModal>
</template>
