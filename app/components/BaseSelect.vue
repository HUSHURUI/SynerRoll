<script setup lang="ts">
const model = defineModel<string | number | boolean>({ required: true })

defineProps<{
  options: Array<{ label: string; value: string | number | boolean }>
}>()
</script>

<template>
  <select v-model="model" class="field-select">
    <option v-for="option in options" :key="String(option.value)" :value="option.value">
      {{ option.label }}
    </option>
  </select>
</template>
