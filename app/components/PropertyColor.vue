<script setup lang="ts">
const model = defineModel<string>({ required: true })
const inputRef = ref<HTMLInputElement>()

const openPicker = () => {
  inputRef.value?.click()
}
</script>

<template>
  
  <div class="property-color">
    
    <div class="property-color__input-wrap">
      <input
        v-model="model"
        type="text"
        class="property-color__input"
        placeholder="#000000"
        spellcheck="false"
      >
    </div>
    <div
      class="property-color__preview"
      :style="{ backgroundColor: model }"
      @click="openPicker"
    />
    
    <input
      ref="inputRef"
      type="color"
      class="property-color__input--hidden"
      :value="model"
      @input="model = ($event.target as HTMLInputElement).value"
    >
  </div>
</template>

<style scoped>

.property-color {
  display: flex;
  align-items: center;
  width: 100%;
  height: 32px;
  border: 1px solid #dde1e6;
  border-radius: 6px;
  background: #ffffff;
  overflow: hidden;
  padding: 0 8px;
}

.property-color__preview {
  width: 25px;
  height: 20px;
  flex-shrink: 0;
  cursor: pointer;
  transition: all 0.2s ease;
  border: 1px solid #dde1e6;
}

.property-color__preview:hover {
  border-color: #0a4da2;
}

.property-color__input-wrap {
  display: flex;
  align-items: center;
  justify-content: left;
  flex: 1;
  min-width: 0;
  height: 100%;
  background: transparent;
}

.property-color__input {
  flex: 0 0 auto;
  min-width: 0;
  width: 70px;
  height: 100%;
  border: none;
  background: transparent;
  text-align: center;
  font-size: 14px;
  color: #1d2129;
  padding: 0;
  outline: none;
}

.property-color__input::placeholder {
  color: #86909c;
}

.property-color__input:focus {
  outline: none;
}

.property-color__input--hidden {
  position: absolute;
  opacity: 0;
  width: 0;
  height: 0;
  padding: 0;
  border: none;
  pointer-events: none;
}
</style>