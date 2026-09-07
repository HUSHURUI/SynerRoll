<script setup lang="ts">
import PropertySwitch from './PropertySwitch.vue'
import PropertyNumber from './PropertyNumber.vue'

import type { AlgorithmConfig } from '~~/types/simulation'

interface Props {
  open: boolean
  algorithm: AlgorithmConfig
}

const props = defineProps<Props>()

const emit = defineEmits<{
  close: []
  confirm: [config: AlgorithmConfig]
}>()

const localConfig = ref<AlgorithmConfig>({
  electricityLoadPrediction: 'None',
  windTurbinePrediction: 'None',
  optimizationAlgorithm: 'MILP',
  slackEnabled: false,
  slackPenalty: 1000000
})

watch(() => props.open, (isOpen) => {
  if (isOpen) {
    localConfig.value = { ...props.algorithm }
  }
})

const handleConfirm = () => {
  emit('confirm', { ...localConfig.value })
  emit('close')
}

const handleCancel = () => {
  emit('close')
}
</script>

<template>
  <AppModal
    :open="open"
    title="算法配置"
    size="sm"
    @close="handleCancel"
  >
    <div class="space-y-5 px-4 py-3">
      <!-- 松弛变量开关 -->
      <div class="flex items-center justify-between">
        <div>
          <div class="text-sm font-medium text-app-text">启用松弛变量</div>
          <div class="mt-0.5 text-xs text-app-muted">能量平衡约束加入 SHORTAGE / EXCESS 松弛项，保证模型始终有解</div>
        </div>
        <PropertySwitch v-model="localConfig.slackEnabled" />
      </div>

      <!-- 惩罚系数 -->
      <div>
        <div class="mb-1.5 text-sm font-medium text-app-text">惩罚系数</div>
        <div class="mb-1.5 text-xs text-app-muted">松弛变量在目标函数中的惩罚权重，数值越大越不容易使用松弛</div>
        <PropertyNumber
          v-model="localConfig.slackPenalty"
          :step="100000"
          :min="1"
          unit=""
        />
      </div>
    </div>

    <template #footer>
      <AppButton label="取消" tone="neutral" @click="handleCancel" />
      <AppButton label="确定" tone="primary" @click="handleConfirm" />
    </template>
  </AppModal>
</template>
