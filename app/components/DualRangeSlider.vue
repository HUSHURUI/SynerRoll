<script setup lang="ts">
const props = withDefaults(defineProps<{
  start: number
  end: number
  min: number
  max: number
  step?: number
  formatLabel?: (value: number) => string
}>(), {
  step: 1
})

const emit = defineEmits<{
  'update:start': [value: number]
  'update:end': [value: number]
}>()

const defaultFormat = (value: number): string => String(value)
const labelFn = computed(() => props.formatLabel ?? defaultFormat)

const percentage = (value: number): number => {
  const range = props.max - props.min
  return range > 0 ? (value - props.min) / range * 100 : 0
}

const fillStyle = computed(() => ({
  left: `${percentage(props.start)}%`,
  right: `${100 - percentage(props.end)}%`
}))

const labelStyle = (value: number): Record<string, string> => {
  const pct = percentage(value)
  const transform = pct <= 1
    ? 'translateX(0)'
    : pct >= 99
      ? 'translateX(-100%)'
      : 'translateX(-50%)'
  return { left: `${pct}%`, transform }
}

const onStartInput = (event: Event) => {
  const value = Number((event.target as HTMLInputElement).value)
  emit('update:start', Math.min(Math.max(props.min, value), props.end - props.step))
}

const onEndInput = (event: Event) => {
  const value = Number((event.target as HTMLInputElement).value)
  emit('update:end', Math.max(Math.min(props.max, value), props.start + props.step))
}
</script>

<template>
  <div class="relative h-10">
    <div class="absolute inset-x-0 top-1.5 h-1 rounded-full bg-app-border">
      <div class="absolute top-0 h-1 rounded-full bg-primary" :style="fillStyle" />
    </div>
    <input
      :value="start"
      type="range"
      :min="min"
      :max="max"
      :step="step"
      class="drs-input absolute inset-x-0 top-[-2px] z-10 w-full"
      aria-label="起始值"
      @input="onStartInput"
    >
    <input
      :value="end"
      type="range"
      :min="min"
      :max="max"
      :step="step"
      class="drs-input absolute inset-x-0 top-[-2px] z-20 w-full"
      aria-label="终止值"
      @input="onEndInput"
    >
    <span
      class="absolute top-4 whitespace-nowrap text-xs text-app-muted"
      :style="labelStyle(start)"
    >{{ labelFn(start) }}</span>
    <span
      class="absolute top-4 whitespace-nowrap text-xs text-app-muted"
      :style="labelStyle(end)"
    >{{ labelFn(end) }}</span>
  </div>
</template>

<style scoped>
.drs-input {
  height: 20px;
  margin: 0;
  background: transparent;
  cursor: pointer;
  appearance: none;
  pointer-events: none;
}

.drs-input::-webkit-slider-runnable-track {
  height: 4px;
  background: transparent;
}

.drs-input::-webkit-slider-thumb {
  width: 14px;
  height: 14px;
  margin-top: -5px;
  border: 2px solid #0A4DA2;
  border-radius: 50%;
  background: #fff;
  cursor: grab;
  appearance: none;
  pointer-events: auto;
}

.drs-input::-moz-range-track {
  height: 4px;
  background: transparent;
}

.drs-input::-moz-range-thumb {
  width: 14px;
  height: 14px;
  border: 2px solid #0A4DA2;
  border-radius: 50%;
  background: #fff;
  cursor: grab;
  pointer-events: auto;
}

.drs-input:focus-visible::-webkit-slider-thumb {
  outline: 2px solid rgba(10, 77, 162, 0.35);
  outline-offset: 3px;
}
</style>
