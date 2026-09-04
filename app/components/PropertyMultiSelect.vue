<script setup lang="ts">
const model = defineModel<string[]>({ required: true })

const props = defineProps<{
  options: Array<{ label: string; value: string }>
  placeholder?: string
}>()

const open = ref(false)
const triggerRef = ref<HTMLElement>()

const selectedLabels = computed(() => {
  return model.value
    .map(v => props.options.find(o => o.value === v)?.label ?? v)
})

const toggle = () => {
  open.value = !open.value
}

const isSelected = (value: string) => {
  return model.value.includes(value)
}

const toggleSelect = (value: string) => {
  const idx = model.value.indexOf(value)
  if (idx === -1) {
    model.value = [...model.value, value]
  } else {
    model.value = model.value.filter(v => v !== value)
  }
}

const removeTag = (value: string, event: MouseEvent) => {
  event.stopPropagation()
  model.value = model.value.filter(v => v !== value)
}

const handleClickOutside = (e: MouseEvent) => {
  if (open.value && triggerRef.value && !triggerRef.value.contains(e.target as Node)) {
    open.value = false
  }
}

onMounted(() => {
  document.addEventListener('click', handleClickOutside)
})

onUnmounted(() => {
  document.removeEventListener('click', handleClickOutside)
})
</script>

<template>
  <div ref="triggerRef" class="property-multi-select">
    <button type="button" class="property-multi-select__trigger" @click="toggle">
      <div class="property-multi-select__tags" v-if="selectedLabels.length > 0">
        <span
          v-for="label in selectedLabels"
          :key="label"
          class="property-multi-select__tag"
        >
          {{ label }}
        </span>
      </div>
      <span v-else class="property-multi-select__placeholder">{{ placeholder || '请选择...' }}</span>
      <svg class="property-multi-select__arrow" :class="{ 'property-multi-select__arrow--open': open }" viewBox="0 0 16 16" fill="none">
        <path d="M4 6l4 4 4-4" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
      </svg>
    </button>

    <Transition name="dropdown">
      <div v-if="open" class="property-multi-select__menu">
        <button
          v-for="opt in options"
          :key="opt.value"
          type="button"
          class="property-multi-select__option"
          :class="{ 'property-multi-select__option--active': isSelected(opt.value) }"
          @click="toggleSelect(opt.value)"
        >
          <input
            type="checkbox"
            :checked="isSelected(opt.value)"
            class="property-multi-select__checkbox"
            @click.stop
          />
          {{ opt.label }}
        </button>
        <div v-if="options.length === 0" class="property-multi-select__empty">
          无可用选项
        </div>
      </div>
    </Transition>
  </div>
</template>

<style scoped>
.property-multi-select {
  position: relative;
  width: 100%;
}

.property-multi-select__trigger {
  display: flex;
  align-items: center;
  width: 100%;
  min-height: 32px;
  border: 1px solid #dde1e6;
  border-radius: 6px;
  background: #ffffff;
  padding: 4px 8px;
  font-size: 14px;
  color: #1d2129;
  cursor: pointer;
  transition: border-color 0.2s ease;
  gap: 4px;
}

.property-multi-select__trigger:hover {
  border-color: #c8ced8;
}

.property-multi-select__trigger:focus {
  outline: none;
  border-color: #0a4da2;
}

.property-multi-select__tags {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
  flex: 1;
}

.property-multi-select__tag {
  display: inline-flex;
  align-items: center;
  gap: 2px;
  padding: 2px 6px;
  background: #ffffff;
  border: 1px solid #dde1e6;
  border-radius: 4px;
  font-size: 12px;
  color: #0a4da2;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.05);
}

.property-multi-select__placeholder {
  color: #86909c;
  flex: 1;
}

.property-multi-select__arrow {
  width: 12px;
  height: 12px;
  color: #86909c;
  transition: transform 0.2s ease;
  flex-shrink: 0;
}

.property-multi-select__arrow--open {
  transform: rotate(180deg);
}

.property-multi-select__menu {
  position: absolute;
  top: calc(100% + 4px);
  left: 0;
  right: 0;
  z-index: 100;
  background: #ffffff;
  border: 1px solid #dde1e6;
  border-radius: 8px;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
  padding: 4px;
  max-height: 192px;
  overflow-y: auto;
}

.property-multi-select__option {
  display: flex;
  align-items: center;
  gap: 8px;
  width: 100%;
  padding: 6px 12px;
  text-align: left;
  font-size: 14px;
  color: #1d2129;
  background: transparent;
  border: none;
  border-radius: 6px;
  cursor: pointer;
  transition: background-color 0.15s ease;
}

.property-multi-select__option:hover {
  background: #f5f7fa;
}

.property-multi-select__option--active {
  background: #e8f0fb;
  color: #0a4da2;
}

.property-multi-select__checkbox {
  width: 16px;
  height: 16px;
  cursor: pointer;
}

.property-multi-select__empty {
  padding: 12px;
  text-align: center;
  color: #86909c;
  font-size: 14px;
}

.dropdown-enter-active,
.dropdown-leave-active {
  transition: opacity 0.15s ease, transform 0.15s ease;
}

.dropdown-enter-from,
.dropdown-leave-to {
  opacity: 0;
  transform: translateY(-4px);
}
</style>
