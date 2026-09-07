<script setup lang="ts">
const model = defineModel<boolean>({ required: true })
</script>

<template>
  <button
    type="button"
    class="property-switch"
    :class="model ? 'property-switch--on' : 'property-switch--off'"
    @click="model = !model"
  >
    <span class="property-switch__thumb" />
  </button>
</template>

<style scoped>
.property-switch {
  position: relative;
  width: 44px;
  height: 24px;
  border-radius: 12px;
  border: none;
  cursor: pointer;
  transition: background-color 0.2s ease;
  flex-shrink: 0;
  margin-left: 16px;
  margin-block: 5px;
}

.property-switch--off {
  background-color: #dde1e6;
}

.property-switch--on {
  background-color: #0a4da2;
}

.property-switch__thumb {
  position: absolute;
  top: 4px;
  width: 16px;
  height: 16px;
  border-radius: 50%;
  background: #ffffff;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.15);
  transition: left 0.2s ease;
}

.property-switch--off .property-switch__thumb {
  left: 2px;
}

.property-switch--on .property-switch__thumb {
  left: 24px;
}
</style>
