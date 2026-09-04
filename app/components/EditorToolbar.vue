<script setup lang="ts">
import type { ToolbarGroupConfig } from '~~/config/system-config'

import { toolbarIconMap } from '../assets/icons/toolbar'

interface SelectMenuPosition {
  top: number
  left: number
  minWidth: number
}

interface ToolbarActionPayload {
  key: string
  value?: string | number | boolean
}

const props = defineProps<{
  groups: ToolbarGroupConfig[]
  values: Record<string, string | number | boolean | undefined>
}>()

const emit = defineEmits<{
  action: [payload: ToolbarActionPayload]
}>()

const toolbarRef = ref<HTMLElement | null>(null)
const selectMenuRef = ref<HTMLElement | null>(null)
const openSelectKey = ref<string | null>(null)
const selectMenuPosition = ref<SelectMenuPosition | null>(null)

let activeSelectTrigger: HTMLElement | null = null

const getValue = (actionKey: string): string | number | boolean | undefined => props.values[actionKey]
const getIcon = (iconName: string | undefined) => iconName ? toolbarIconMap[iconName] : undefined
const isToggleActive = (actionKey: string) => Boolean(getValue(actionKey))
const isSelectOpen = (actionKey: string) => openSelectKey.value === actionKey

const allActions = computed(() => props.groups.flatMap(group => group.actions))
const activeSelectAction = computed(() =>
  allActions.value.find(action => action.key === openSelectKey.value) ?? null
)
const activeSelectValueLabel = computed(() => {
  if (!activeSelectAction.value) {
    return ''
  }

  const currentValue = String(getValue(activeSelectAction.value.key) ?? '')
  return activeSelectAction.value.options?.find(option => option.value === currentValue)?.label ?? '未选择'
})

const closeSelectMenu = () => {
  openSelectKey.value = null
  selectMenuPosition.value = null
  activeSelectTrigger = null
}

const updateSelectMenuPosition = (trigger?: HTMLElement | null) => {
  if (!import.meta.client) {
    return
  }

  const target = trigger ?? activeSelectTrigger

  if (!target) {
    closeSelectMenu()
    return
  }

  const rect = target.getBoundingClientRect()
  const minWidth = Math.max(rect.width + 28, 180)
  const halfWidth = minWidth / 2
  const viewportPadding = 16
  const preferredLeft = rect.left + rect.width / 2
  const minLeft = viewportPadding + halfWidth
  const maxLeft = window.innerWidth - viewportPadding - halfWidth

  activeSelectTrigger = target
  selectMenuPosition.value = {
    top: rect.bottom + 8,
    left: Math.min(Math.max(preferredLeft, minLeft), Math.max(minLeft, maxLeft)),
    minWidth
  }
}

const handleToggleAction = (actionKey: string) => {
  emit('action', {
    key: actionKey,
    value: !isToggleActive(actionKey)
  })
}

const toggleSelectMenu = (actionKey: string, event: MouseEvent) => {
  const trigger = event.currentTarget as HTMLElement | null

  if (openSelectKey.value === actionKey) {
    closeSelectMenu()
    return
  }

  if (!trigger) {
    return
  }

  openSelectKey.value = actionKey
  updateSelectMenuPosition(trigger)
}

const chooseSelectOption = (actionKey: string, value: string) => {
  emit('action', {
    key: actionKey,
    value
  })
  closeSelectMenu()
}

const handleDocumentPointerDown = (event: PointerEvent) => {
  const target = event.target as Node | null

  if (!target) {
    return
  }

  if (toolbarRef.value?.contains(target) || selectMenuRef.value?.contains(target)) {
    return
  }

  closeSelectMenu()
}

const handleDocumentKeydown = (event: KeyboardEvent) => {
  if (event.key === 'Escape') {
    closeSelectMenu()
  }
}

const handleViewportChange = () => {
  if (!openSelectKey.value || !activeSelectTrigger) {
    return
  }

  updateSelectMenuPosition(activeSelectTrigger)
}

onMounted(() => {
  document.addEventListener('pointerdown', handleDocumentPointerDown)
  document.addEventListener('keydown', handleDocumentKeydown)
  window.addEventListener('resize', handleViewportChange)
  window.addEventListener('scroll', handleViewportChange, true)
})

onBeforeUnmount(() => {
  document.removeEventListener('pointerdown', handleDocumentPointerDown)
  document.removeEventListener('keydown', handleDocumentKeydown)
  window.removeEventListener('resize', handleViewportChange)
  window.removeEventListener('scroll', handleViewportChange, true)
})
</script>

<template>
  <div ref="toolbarRef" class="editor-card relative h-[60px] overflow-visible p-1">
    <div class="overflow-x-auto overflow-y-hidden h-full">
      <div class="mx-auto flex min-w-max items-center justify-center gap-4">
        <div
          v-for="group in groups"
          :key="group.key"
          class="flex shrink-0 items-center gap-3 border-r border-app-border pr-4 last:border-r-0 last:pr-0"
        >
          <template v-for="action in group.actions" :key="action.key">
            <button
              v-if="action.type === 'button'"
              type="button"
              class="inline-flex min-w-[48px] cursor-pointer flex-col items-center gap-1 rounded-[10px] px-1.5 py-1.5 text-[12px] text-app-text transition hover:bg-app-panel-soft hover:text-primary"
              @click="emit('action', { key: action.key })"
            >
              <component :is="getIcon(action.icon)" v-if="getIcon(action.icon)" />
              <span class="leading-none whitespace-nowrap">{{ action.label }}</span>
            </button>

            <button
              v-else-if="action.type === 'toggle'"
              type="button"
              class="inline-flex min-w-[52px] cursor-pointer flex-col items-center gap-1 rounded-[10px] px-1.5 py-1.5 text-[12px] transition"
              :class="isToggleActive(action.key)
                ? 'bg-app-panel-soft text-primary ring-1 ring-primary/10'
                : 'text-app-text hover:bg-app-panel-soft hover:text-primary'"
              :aria-pressed="isToggleActive(action.key)"
              @click="handleToggleAction(action.key)"
            >
              <component :is="getIcon(action.icon)" v-if="getIcon(action.icon)" />
              <span class="leading-none whitespace-nowrap">{{ action.label }}</span>
            </button>

            <label
              v-else-if="action.type === 'number'"
              class="inline-flex items-center gap-1 rounded-[10px] px-1 py-1 text-[12px] text-app-text"
            >
              <input
                class="field-input-sm toolbar-number-input h-[30px] w-[80px] text-right"
                type="number"
                :placeholder="action.placeholder"
                :value="String(getValue(action.key) ?? '')"
                @change="emit('action', { key: action.key, value: Number(($event.target as HTMLInputElement).value) })"
              >
              <span class="text-[12px] text-app-muted leading-none pr-0.5">px</span>
              <span class="text-[12px] font-medium leading-none whitespace-nowrap">{{ action.label }}</span>
              
            </label>

            <label
              v-else-if="action.type === 'color'"
              class="inline-flex items-center gap-2 rounded-[10px] px-1 py-1 text-[12px] text-app-text"
            >
              <input
                class="toolbar-color-input h-[28px] w-[28px] cursor-pointer rounded-md border border-app-border p-0.5"
                type="color"
                :value="String(getValue(action.key) ?? '#000000')"
                @input="emit('action', { key: action.key, value: ($event.target as HTMLInputElement).value })"
              >
              <span class="text-[12px] font-medium leading-none whitespace-nowrap">{{ action.label }}</span>
            </label>

            <button
              v-else
              type="button"
              class="inline-flex min-w-[58px] cursor-pointer flex-col items-center gap-1 rounded-[10px] px-1.5 py-1.5 text-[12px] transition"
              :class="isSelectOpen(action.key)
                ? 'bg-app-panel-soft text-primary ring-1 ring-primary/10'
                : 'text-app-text hover:bg-app-panel-soft hover:text-primary'"
              @click="toggleSelectMenu(action.key, $event)"
            >
              <component :is="getIcon(action.icon)" v-if="getIcon(action.icon)" />
              <div class="flex items-center gap-1 leading-none whitespace-nowrap">
                <span>{{ action.label }}</span>
                <span class="inline-flex h-4 w-4 items-center justify-center">
                  <svg
                    class="h-3 w-3 transition-transform"
                    :class="isSelectOpen(action.key) ? 'rotate-180' : ''"
                    viewBox="0 0 12 12"
                    fill="none"
                    xmlns="http://www.w3.org/2000/svg"
                  >
                    <path
                      d="M3 4.5L6 7.5L9 4.5"
                      stroke="currentColor"
                      stroke-width="1.4"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    />
                  </svg>
                </span>
              </div>
            </button>
          </template>
        </div>
      </div>
    </div>
  </div>

  <Teleport to="body">
    <div
      v-if="openSelectKey && activeSelectAction && selectMenuPosition"
      ref="selectMenuRef"
      class="fixed z-[70] rounded-[12px] border border-app-border bg-white p-2 text-left shadow-lg"
      :style="{
        top: `${selectMenuPosition.top}px`,
        left: `${selectMenuPosition.left}px`,
        minWidth: `${selectMenuPosition.minWidth}px`,
        transform: 'translateX(-50%)'
      }"
    >
      <div class="mt-1 flex flex-col gap-1">
        <button
          v-for="option in activeSelectAction.options ?? []"
          :key="option.value"
          type="button"
          class="flex w-full items-center gap-2 rounded-[8px] px-3 py-2 text-sm transition"
          :class="String(getValue(activeSelectAction.key)) === option.value
            ? 'bg-app-panel-soft text-primary'
            : 'text-app-text hover:bg-app-panel-soft'"
          @click="chooseSelectOption(activeSelectAction.key, option.value)"
        >
          <span class="inline-flex w-4 items-center justify-center text-primary">
            <svg
              v-if="String(getValue(activeSelectAction.key)) === option.value"
              class="h-3.5 w-3.5"
              viewBox="0 0 16 16"
              fill="none"
              xmlns="http://www.w3.org/2000/svg"
            >
              <path
                d="M3.5 8.5L6.5 11.5L12.5 4.5"
                stroke="currentColor"
                stroke-width="1.6"
                stroke-linecap="round"
                stroke-linejoin="round"
              />
            </svg>
          </span>
          <span class="whitespace-nowrap">{{ option.label }}</span>
        </button>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.toolbar-number-input {
  appearance: auto;
  -webkit-appearance: auto;
  -moz-appearance: auto;
}

.toolbar-number-input::-webkit-inner-spin-button,
.toolbar-number-input::-webkit-outer-spin-button {
  -webkit-appearance: auto;
  margin: 0;
  opacity: 1;
}
</style>
