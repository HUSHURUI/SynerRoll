<script setup lang="ts">
import { computed } from 'vue'

interface MenuItem {
  key: string
  label: string
  shortcut?: string
  disabled?: boolean
  divider?: boolean
}

const props = defineProps<{
  x: number
  y: number
  items: MenuItem[]
}>()

const emit = defineEmits<{
  select: [key: string]
  close: []
}>()

const menuStyle = computed(() => ({
  left: `${props.x}px`,
  top: `${props.y}px`
}))

const handleItemClick = (key: string) => {
  emit('select', key)
}

const handleMouseDown = (event: MouseEvent) => {
  event.preventDefault()
}
</script>

<template>
  <div
    class="absolute z-50 min-w-[160px] rounded-lg bg-app-surface border border-app-border shadow-lg py-1 focus:outline-none"
    :style="menuStyle"
    @mousedown="handleMouseDown"
  >
    <template v-for="(item, index) in items" :key="index">
      <div v-if="item.divider" class="my-1 border-t border-app-border" />
      <button
        v-else
        class="w-full flex items-center justify-between px-3 py-2 text-sm text-app-foreground hover:bg-app-muted disabled:opacity-50 disabled:cursor-not-allowed"
        :class="{ 'opacity-50 cursor-not-allowed': item.disabled }"
        :disabled="item.disabled"
        @click="handleItemClick(item.key)"
      >
        <span>{{ item.label }}</span>
        <span v-if="item.shortcut" class="text-xs text-app-muted">{{ item.shortcut }}</span>
      </button>
    </template>
  </div>
</template>
