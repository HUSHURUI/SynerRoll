<script setup lang="ts">
import PropertyNumber from './PropertyNumber.vue'

import type { LayerDefinition } from '~~/types/simulation'
import { DEFAULT_LAYER_CONFIG } from '~~/types/simulation'
import { createId } from '~~/utils/id'

interface Props {
  open: boolean
  layers: LayerDefinition[]
}

const props = defineProps<Props>()

const emit = defineEmits<{
  close: []
  confirm: [layers: LayerDefinition[]]
}>()

// 复制一份本地数据用于编辑
const localLayers = ref<LayerDefinition[]>([])

watch(() => props.open, (isOpen) => {
  if (isOpen) {
    localLayers.value = JSON.parse(JSON.stringify(props.layers))
  }
})

const handleAdd = () => {
  const nextId = localLayers.value.length + 1
  localLayers.value.push({
    id: String(nextId),
    name: `时层${nextId}`,
    length: '24h',
    step: '15m',
    forward: '0m'
  })
}

const handleDelete = (id: string) => {
  if (localLayers.value.length <= 1) {
    return
  }
  const idx = localLayers.value.findIndex(l => l.id === id)
  if (idx !== -1) {
    localLayers.value.splice(idx, 1)
    // 删除后重编号，保证 id 连续 1,2,3,...
    localLayers.value.forEach((layer, i) => {
      layer.id = String(i + 1)
      layer.name = `时层${i + 1}`
    })
  }
}

const handleConfirm = () => {
  // 将各数值字段转换为带单位的字符串格式
  const layersToSave = localLayers.value.map(layer => ({
    ...layer,
    length: `${layer.length.replace(/\D/g, '')}h`,
    step: `${layer.step.replace(/\D/g, '')}m`,
    forward: layer.forward ? `${layer.forward.replace(/\D/g, '')}m` : '0m'
  }))
  emit('confirm', layersToSave)
  emit('close')
}

const handleCancel = () => {
  emit('close')
}
</script>

<template>
  <AppModal
    :open="open"
    title="时层配置"
    size="lg"
    @close="handleCancel"
  >
    <div class="space-y-4 px-4 py-2">
      <div class="flex items-center justify-end">
        <AppButton
          label="新增时层"
          icon="plus"
          size="md"
          tone="neutral"
          @click="handleAdd"
        />
      </div>

      <div class="rounded-lg border border-app-border">
        <table class="w-full">
          <thead>
            <tr class="border-b border-app-border">
              <th class="px-2 py-3 text-center text-sm font-bold text-app-text">时层名称</th>
              <th class="px-2 py-3 text-center text-sm font-bold text-app-text">调度长度</th>
              <th class="px-2 py-3 text-center text-sm font-bold text-app-text">调度步长</th>
              <th class="px-2 py-3 text-center text-sm font-bold text-app-text">滚动步长</th>
              <th class="px-4 py-3 text-center text-sm font-bold text-app-text">删除</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="layer in localLayers"
              :key="layer.id"
              class="hover:bg-app-panel-soft/50"
            >
              <td class="px-2 py-3 text-center">
                <input
                  v-model="layer.name"
                  class="h-8 w-full text-sm text-center"
                  placeholder="如：日前"
                >
              </td>
              <td class="px-2 py-3">
                <PropertyNumber
                  :model-value="Number(layer.length.replace(/\D/g, ''))"
                  class="h-8 w-12 text-sm"
                  unit="h"
                  :step="24"
                  :bordered="false"
                  @update:model-value="layer.length = `${$event}h`"
                />
              </td>
              <td class="px-2 py-3">
                <PropertyNumber
                  :model-value="Number(layer.step.replace(/\D/g, ''))"
                  class="h-8 w-12 text-sm"
                  unit="m"
                  :step="5"
                  :bordered="false"
                  @update:model-value="layer.step = `${$event}m`"
                />
              </td>
              <td class="px-2 py-3">
                <PropertyNumber
                  :model-value="Number(layer.forward.replace(/\D/g, ''))"
                  class="h-8 w-12 text-sm"
                  unit="m"
                  :step="5"
                  :bordered="false"
                  @update:model-value="layer.forward = `${$event}m`"
                />
              </td>
              <td class="px-2 py-3 text-center">
                <button
                  type="button"
                  class="inline-flex h-7 w-7 items-center justify-center rounded-[6px] text-app-muted transition hover:bg-app-danger/10 hover:text-app-danger disabled:opacity-30"
                  :disabled="localLayers.length <= 1"
                  title="删除时层"
                  @click="handleDelete(layer.id)"
                >
                  <svg class="h-4 w-4" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <path d="M2 4H14M12.667 4V12.667C12.667 13.02 12.387 13.333 12 13.333H4C3.613 13.333 3.333 13.02 3.333 12.667V4M5.333 4V2.667C5.333 2.313 5.613 2 6 2H10C10.387 2 10.667 2.313 10.667 2.667V4" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round" />
                  </svg>
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <template #footer>
      <AppButton label="取消" tone="neutral" @click="handleCancel" />
      <AppButton label="确定" tone="primary" @click="handleConfirm" />
    </template>
  </AppModal>
</template>
