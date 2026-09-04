<script setup lang="ts">
withDefaults(
  defineProps<{
    paths: string[]
    strokeWidth?: number
  }>(),
  {
    strokeWidth: 1.8
  }
)
</script>

<template>
  <svg
    viewBox="0 0 24 24"
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
    class="h-5 w-5 shrink-0"
  >
    <path
      v-for="(path, index) in paths"
      :key="index"
      :d="path"
      stroke="currentColor"
      stroke-linecap="round"
      stroke-linejoin="round"
      :stroke-width="strokeWidth"
    />
  </svg>
</template>
