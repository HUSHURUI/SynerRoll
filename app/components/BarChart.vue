<script setup lang="ts">
const props = defineProps<{
  title: string
  items: Array<{ label: string; value: number; color: string }>
}>()

const maxValue = computed(() => Math.max(...props.items.map(item => item.value), 1))
</script>

<template>
  <div class="rounded-xl border border-app-border bg-white p-4">
    <div class="mb-4">
      <h3 class="text-sm font-semibold text-app-text">{{ title }}</h3>
    </div>

    <div class="space-y-3">
      <div v-for="item in items" :key="item.label">
        <div class="mb-1 flex items-center justify-between text-xs text-app-muted">
          <span>{{ item.label }}</span>
          <span>{{ item.value.toFixed(2) }}</span>
        </div>
        <div class="h-3 rounded-full bg-app-panel-soft">
          <div class="h-3 rounded-full" :style="{ width: `${(item.value / maxValue) * 100}%`, backgroundColor: item.color }" />
        </div>
      </div>
    </div>
  </div>
</template>
