<script setup lang="ts">
withDefaults(
  defineProps<{
    title: string
    compact?: boolean
  }>(),
  {
    compact: false
  }
)
</script>

<template>
  <section class="space-y-3 rounded-[12px] bg-app-panel-soft/55" :class="compact ? 'p-3' : 'p-4'">
    <header class="mb-3 flex items-center justify-between">
      <h3 class="panel-title">{{ title }}</h3>
      <slot name="extra" />
    </header>
    <div class="space-y-3">
      <slot />
    </div>
  </section>
</template>
