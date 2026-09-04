<script setup lang="ts">
const model = defineModel<string | number>({ required: true })

const props = defineProps<{
  options: Array<{ label: string; value: string | number }>
}>()

const open = ref(false)
const triggerRef = ref<HTMLElement>()

const selectedLabel = computed(() => {
  return props.options.find(o => o.value === model.value)?.label ?? ''
})

const toggle = () => {
  open.value = !open.value
}

const select = (value: string | number) => {
  model.value = value
  open.value = false
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
  <div ref="triggerRef" class="property-select">
    <button type="button" class="property-select__trigger" @click="toggle">
      <span class="property-select__value">{{ selectedLabel }}</span>
      <svg class="property-select__arrow" :class="{ 'property-select__arrow--open': open }" viewBox="0 0 16 16" fill="none">
        <path d="M4 6l4 4 4-4" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
      </svg>
    </button>

    <Transition name="dropdown">
      <div v-if="open" class="property-select__menu">
        <button
          v-for="opt in options"
          :key="opt.value"
          type="button"
          class="property-select__option"
          :class="{ 'property-select__option--active': opt.value === model }"
          @click="select(opt.value)"
        >
          {{ opt.label }}
        </button>
      </div>
    </Transition>
  </div>
</template>

<style scoped>
.property-select {
  position: relative;
  width: 100%;
}

.property-select__trigger {
  display: flex;
  align-items: center;
  width: 100%;
  height: 32px;
  border: 1px solid #dde1e6;
  border-radius: 6px;
  background: #ffffff;
  padding: 0 8px 0 12px;
  font-size: 14px;
  color: #1d2129;
  cursor: pointer;
  transition: border-color 0.2s ease;
}

.property-select__trigger:hover {
  border-color: #c8ced8;
}

.property-select__trigger:focus {
  outline: none;
  border-color: #0a4da2;
}

.property-select__value {
  flex: 1;
  text-align: left;
}

.property-select__arrow {
  width: 12px;
  height: 12px;
  color: #86909c;
  transition: transform 0.2s ease;
  flex-shrink: 0;
}

.property-select__arrow--open {
  transform: rotate(180deg);
}

.property-select__menu {
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
  overflow: hidden;
}

.property-select__option {
  display: block;
  width: 100%;
  padding: 8px 12px;
  text-align: left;
  font-size: 14px;
  color: #1d2129;
  background: transparent;
  border: none;
  border-radius: 6px;
  cursor: pointer;
  transition: background-color 0.15s ease;
}

.property-select__option:hover {
  background: #f5f7fa;
}

.property-select__option--active {
  background: #e8f0fb;
  color: #0a4da2;
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
