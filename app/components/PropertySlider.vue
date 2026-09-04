<script setup lang="ts">
const model = defineModel<number>({ required: true })

withDefaults(
  defineProps<{
    unit?: string
    min?: number
    max?: number
    step?: number
  }>(),
  {
    unit: '',
    min: 0,
    max: 100,
    step: 1,
  }
)

const percentage = computed(() => {
  return model.value
})
</script>

<template>
  <div class="property-slider">
    <div class="property-slider__track">
      <div class="property-slider__fill" :style="{ width: percentage + '%' }" />
      <input
        type="range"
        class="property-slider__range"
        :value="model"
        :min="min"
        :max="max"
        :step="step"
        @input="model = Number(($event.target as HTMLInputElement).value)"
      >
    </div>

    <div class="property-slider__input-wrap">
      <input
        type="number"
        class="property-slider__input"
        :value="model"
        :min="min"
        :max="max"
        :step="step"
        @change="model = Number(($event.target as HTMLInputElement).value)"
      >
      <span v-if="unit" class="property-slider__unit">{{ unit }}</span>
    </div>
  </div>
</template>

<style scoped>
.property-slider {
  display: flex;
  align-items: center;
  gap: 8px;
  width: 100%;
}

.property-slider__track {
  position: relative;
  flex: 1;
  height: 4px;
  background: #dde1e6;
  border-radius: 2px;
}

.property-slider__fill {
  position: absolute;
  left: 0;
  top: 0;
  height: 100%;
  background: #0a4da2;
  border-radius: 2px;
  pointer-events: none;
}

.property-slider__range {
  position: absolute;
  top: 50%;
  left: 0;
  width: 100%;
  height: 20px;
  transform: translateY(-50%);
  background: transparent;
  cursor: pointer;
  margin: 0;
  -webkit-appearance: none;
  appearance: none;
}

.property-slider__range::-webkit-slider-thumb {
  width: 12px;
  height: 12px;
  border-radius: 50%;
  background: #ffffff;
  border: 2px solid #0a4da2;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.15);
  cursor: pointer;
  -webkit-appearance: none;
  transition: transform 0.15s ease;
}

.property-slider__range::-webkit-slider-thumb:hover {
  transform: scale(1.15);
}

.property-slider__input-wrap {
  display: flex;
  align-items: center;
  border: 1px solid #dde1e6;
  border-radius: 6px;
  background: #ffffff;
  overflow: hidden;
  flex-shrink: 0;
}

.property-slider__input {
  width: 52px;
  height: 28px;
  border: none;
  background: transparent;
  text-align: left;
  font-size: 14px;
  color: #1d2129;
  padding: 0 6px 0 8px;
  -moz-appearance: textfield;
}

.property-slider__input::-webkit-outer-spin-button,
.property-slider__input::-webkit-inner-spin-button {
  -webkit-appearance: none;
  margin: 0;
}

.property-slider__input:focus {
  outline: none;
}

.property-slider__unit {
  padding-right: 6px;
  font-size: 12px;
  color: #86909c;
}
</style>
