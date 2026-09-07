<script setup lang="ts">
import { computed } from 'vue'

const model = defineModel<number>({ required: true })

const props = withDefaults(defineProps<{
  unit?: string
  min?: number
  max?: number
  step?: number
  bordered?: boolean
}>(), {
  bordered: true
})

const decrement = () => {
  model.value = model.value - (props.step ?? 1)
}

const increment = () => {
  model.value = model.value + (props.step ?? 1)
}

// 科学计数法显示：绝对值 < 0.001 或 >= 1000 时自动转换
const displayValue = computed(() => {
  const val = model.value
  if (!Number.isFinite(val)) return String(val)
  const abs = Math.abs(val)
  if (abs !== 0 && (abs < 0.001 || abs >= 1000)) {
    return val.toExponential().replace('e+', 'e').replace(/\.?0+(e)/, '$1')
  }
  return String(val)
})

const onInputChange = (e: Event) => {
  const str = (e.target as HTMLInputElement).value
  const num = Number(str)
  if (!isNaN(num)) {
    model.value = num
  }
}
</script>

<template>
  <div class="property-number" :class="{ 'bordered': bordered }">
    <button type="button" class="property-number__btn property-number__btn--left" @click="decrement">
      <svg class="h-3 w-3" viewBox="0 0 16 16" fill="none">
        <path d="M3 8h10" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" />
      </svg>
    </button>

    <div class="property-number__input-wrap">
      <input
        type="text"
        class="property-number__input"
        :value="displayValue"
        @change="onInputChange"
      >
      <span class="property-number__unit">{{ props.unit }}</span>
    </div>

    <button type="button" class="property-number__btn property-number__btn--right" @click="increment">
      <svg class="h-3 w-3" viewBox="0 0 16 16" fill="none">
        <path d="M8 3v10M3 8h10" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" />
      </svg>
    </button>
  </div>
</template>

<style scoped>
.property-number {
  display: flex;
  align-items: center;
  width: 100%;
  height: 32px;
  border-radius: 6px;
  background: #ffffff;
  overflow: hidden;
}

.property-number.bordered {
  border: 1px solid #dde1e6;
}

.property-number__btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 20px;
  height: 20px;
  background: transparent;
  color: #86909c;
  cursor: pointer;
  transition: all 0.2s ease;
  flex-shrink: 0;
  border: none;
  border-radius: 4px;
  margin: 0 4px;
}

.property-number__btn--left {
  border-radius: 4px;
}

.property-number__btn--right {
  border-radius: 4px;
}

.property-number__btn:hover {
  color: #0a4da2;
  background: #e8f0fb;
}

.property-number__btn:active {
  background: #dde1e6;
}

.property-number__input-wrap {
  display: flex;
  align-items: center;
  justify-content: center;
  flex: 1;
  min-width: 0;
  height: 100%;
  background: transparent;
}

.property-number__input {
  flex: 0 0 auto;
  min-width: 0;
  width: 40px;
  height: 100%;
  border: none;
  background: transparent;
  text-align: center;
  font-size: 14px;
  color: #1d2129;
  padding: 0;
  -moz-appearance: textfield;
}

.property-number__input::-webkit-outer-spin-button,
.property-number__input::-webkit-inner-spin-button {
  -webkit-appearance: none;
  margin: 0;
}

.property-number__input:focus {
  outline: none;
}

.property-number__unit {
  flex-shrink: 0;
  padding-right: 4px;
  padding-left: 2px;
  font-size: 12px;
  color: #86909C;
}
</style>
