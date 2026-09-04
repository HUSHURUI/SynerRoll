<script setup lang="ts">
import { useToastCenter } from '~~/state/ui'

const { toasts, remove } = useToastCenter()

const toneClassMap = {
  info: 'border-primary/20 bg-white',
  success: 'border-app-success/20 bg-white',
  warning: 'border-app-warning/20 bg-white',
  danger: 'border-app-danger/20 bg-white'
} as const
</script>

<template>
  <div class="pointer-events-none fixed right-6 top-6 z-[100] space-y-2">
    <div
      v-for="toast in toasts"
      :key="toast.id"
      class="pointer-events-auto w-80 rounded-[12px] border p-3 shadow-panel"
      :class="toneClassMap[toast.tone]"
    >
      <div class="flex items-start justify-between gap-3">
        <div class="space-y-1">
          <p class="text-sm font-semibold text-app-text">{{ toast.title }}</p>
          <p v-if="toast.description" class="text-xs leading-5 text-app-muted">
            {{ toast.description }}
          </p>
        </div>
        <button type="button" class="text-app-muted" @click="remove(toast.id)">
          ×
        </button>
      </div>
    </div>
  </div>
</template>
