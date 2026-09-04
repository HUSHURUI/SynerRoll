<script setup lang="ts">
const props = defineProps<{
  title: string
  unit: string
  timeline: string[]
  series: Array<{ label: string; values: number[]; color: string }>
}>()

const width = 520
const height = 220
const padding = 28

const flatValues = computed(() => props.series.flatMap(item => item.values))
const maxValue = computed(() => Math.max(...flatValues.value, 1))

const buildPoints = (values: number[]) =>
  values
    .map((value, index) => {
      const x = padding + (index / Math.max(values.length - 1, 1)) * (width - padding * 2)
      const y = height - padding - (value / maxValue.value) * (height - padding * 2)
      return `${x},${y}`
    })
    .join(' ')
</script>

<template>
  <div class="rounded-xl border border-app-border bg-white p-4">
    <div class="mb-4 flex items-center justify-between">
      <div>
        <h3 class="text-sm font-semibold text-app-text">{{ title }}</h3>
        <p class="text-xs text-app-muted">{{ unit }}</p>
      </div>
      <div class="flex flex-wrap gap-3 text-xs text-app-muted">
        <span v-for="item in series" :key="item.label" class="inline-flex items-center gap-2">
          <span class="h-2.5 w-2.5 rounded-full" :style="{ backgroundColor: item.color }" />
          {{ item.label }}
        </span>
      </div>
    </div>

    <svg :viewBox="`0 0 ${width} ${height}`" class="h-56 w-full">
      <line :x1="padding" :y1="height - padding" :x2="width - padding" :y2="height - padding" stroke="#D0D5DD" />
      <line :x1="padding" :y1="padding" :x2="padding" :y2="height - padding" stroke="#D0D5DD" />
      <polyline
        v-for="item in series"
        :key="item.label"
        :points="buildPoints(item.values)"
        fill="none"
        :stroke="item.color"
        stroke-width="2"
      />
    </svg>
  </div>
</template>
