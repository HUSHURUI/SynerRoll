<script setup lang="ts">
defineProps<{
  tabs: Array<{ key: string; label: string }>
}>()

const model = defineModel<string>({ required: true })
</script>

<template>
  <div class="flex items-center gap-6 bg-transparent px-5">
    <button
      v-for="tab in tabs"
      :key="tab.key"
      type="button"
      class="editor-tab"
      :class="model === tab.key ? 'editor-tab-active' : 'hover:text-primary'"
      @click="model = tab.key"
    >
      {{ tab.label }}
      <span
        v-if="model === tab.key"
        class="editor-tab-underline " 
      />
    </button>
  </div>
</template>
