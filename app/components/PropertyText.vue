<script setup lang="ts">
const model = defineModel<string | number>({ required: true })

withDefaults(
  defineProps<{
    placeholder?: string
    disabled?: boolean
  }>(),
  {
    placeholder: '',
    disabled: false
  }
)
</script>

<template>
  <input
    type="text"
    class="property-text"
    :class="{ 'property-text--disabled': disabled }"
    :value="model"
    :placeholder="placeholder"
    :disabled="disabled"
    @change="disabled ? null : (model = ($event.target as HTMLInputElement).value)"
  >
</template>

<style scoped>
.property-text {
  width: 100%;
  height: 32px;
  border: 1px solid #dde1e6;
  border-radius: 6px;
  background: #ffffff;
  padding: 0 12px;
  font-size: 14px;
  color: #1d2129;
  transition: border-color 0.2s ease;
}

.property-text::placeholder {
  color: #86909c;
}

.property-text:focus {
  outline: none;
  border-color: #0a4da2;
}

.property-text--disabled {
  background-color: #f5f7fa;
  color: #86909c;
  cursor: not-allowed;
}
</style>
