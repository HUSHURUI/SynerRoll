<script setup lang="ts">
import type { EditorMenuItem } from '~~/config/system-config'

defineProps<{
  menus: EditorMenuItem[]
  activeMenu: string
}>()

defineEmits<{
  select: [menuKey: string]
}>()
</script>

<template>
  <nav class="flex h-6 items-center justify-center gap-8 py-2">
    <button
      v-for="menu in menus"
      :key="menu.key"
      type="button"
      class="relative inline-flex items-center justify-center px-1 pb-2 pt-1 text-sm font-medium leading-none transition"
      :class="activeMenu === menu.key ? 'editor-tab-active' : 'hover:text-primary'"
      @click="$emit('select', menu.key)"
    >
      {{ menu.label }}
      <span
        v-if="activeMenu === menu.key"
        class="absolute bottom-0 left-0 h-0.5 w-full rounded-full bg-primary"
      />
    </button>
  </nav>
</template>
