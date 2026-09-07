<script setup lang="ts">
const props = defineProps<{
  title: string
  items: Array<{ label: string; value: number; color: string }>
}>()

const total = computed(() => props.items.reduce((sum, item) => sum + item.value, 0) || 1)

const polarToCartesian = (centerX: number, centerY: number, radius: number, angleInDegrees: number) => {
  const angleInRadians = (angleInDegrees - 90) * Math.PI / 180

  return {
    x: centerX + radius * Math.cos(angleInRadians),
    y: centerY + radius * Math.sin(angleInRadians)
  }
}

const describeArc = (startAngle: number, endAngle: number) => {
  const radius = 68
  const start = polarToCartesian(90, 90, radius, endAngle)
  const end = polarToCartesian(90, 90, radius, startAngle)
  const largeArcFlag = endAngle - startAngle <= 180 ? '0' : '1'

  return [`M`, start.x, start.y, `A`, radius, radius, 0, largeArcFlag, 0, end.x, end.y, `L`, 90, 90, `Z`].join(' ')
}

const segments = computed(() => {
  let currentAngle = 0

  return props.items.map(item => {
    const angle = (item.value / total.value) * 360
    const segment = {
      ...item,
      path: describeArc(currentAngle, currentAngle + angle)
    }
    currentAngle += angle
    return segment
  })
})
</script>

<template>
  <div class="rounded-xl border border-app-border bg-white p-4">
    <div class="mb-4">
      <h3 class="text-sm font-semibold text-app-text">{{ title }}</h3>
    </div>
    <div class="flex items-center gap-4">
      <svg viewBox="0 0 180 180" class="h-44 w-44 shrink-0">
        <path
          v-for="segment in segments"
          :key="segment.label"
          :d="segment.path"
          :fill="segment.color"
        />
      </svg>

      <div class="space-y-2 text-xs text-app-muted">
        <div v-for="item in items" :key="item.label" class="flex items-center gap-2">
          <span class="h-2.5 w-2.5 rounded-full" :style="{ backgroundColor: item.color }" />
          <span class="min-w-24">{{ item.label }}</span>
          <span>{{ ((item.value / total) * 100).toFixed(1) }}%</span>
        </div>
      </div>
    </div>
  </div>
</template>
