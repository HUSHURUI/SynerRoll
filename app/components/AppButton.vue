<script setup lang="ts">
const props = withDefaults(
  defineProps<{
    label?: string
    icon?: string
    type?: 'button' | 'submit'
    size?: 'sm' | 'md'
    tone?: 'primary' | 'neutral' | 'ghost' | 'danger' | 'green'
    disabled?: boolean
  }>(),
  {
    label: '',
    icon: '',
    type: 'button',
    size: 'md',
    tone: 'neutral',
    disabled: false
  }
)

const toneClassMap = {
  primary: 'border-primary bg-primary text-white hover:bg-primary-active',
  green: 'border-app-border bg-green-500 text-white hover:bg-green-600',
  neutral: 'border-app-border bg-white text-app-text hover:text-primary',
  ghost: 'border-transparent bg-transparent text-app-text hover:bg-app-panel-soft',
  danger: 'border-app-danger bg-app-danger text-white hover:bg-red-600'
} as const

const sizeClassMap = {
  sm: 'h-6 px-3 text-xs',
  md: 'h-8 px-4 text-sm'
} as const
</script>

<template>
  <button
    :type="type"
    :disabled="disabled"
    class="inline-flex items-center gap-2 rounded-[4px] border font-medium transition disabled:cursor-not-allowed disabled:opacity-30"
    :class="[toneClassMap[tone], sizeClassMap[size]]"
  >
    <AppIcon v-if="icon" :name="icon" :size="16" />
    <span v-if="label">{{ label }}</span>
    <slot />
  </button>
</template>
