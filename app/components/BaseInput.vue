<script setup lang="ts">
const model = defineModel<string | number>({ required: true })

withDefaults(
  defineProps<{
    type?: 'text' | 'number'
    placeholder?: string
    min?: number
    max?: number
    step?: number
  }>(),
  {
    type: 'text',
    placeholder: '',
    min: undefined,
    max: undefined,
    step: undefined
  }
)
</script>

<template>
  <input
    v-model="model"
    :type="type"
    :placeholder="placeholder"
    :min="min"
    :max="max"
    :step="step"
    class="field-input"
  >
</template>
