<script setup lang="ts">
import type { ProjectSummary } from '~~/types/project'

defineProps<{
  project: ProjectSummary
  selected: boolean
}>()

defineEmits<{
  select: []
  open: []
  favorite: []
}>()
</script>

<template>
  <article
    class="rounded-xl border p-4 transition"
    :class="selected ? 'border-primary bg-primary-soft' : 'border-app-border bg-white hover:border-primary/40'"
  >
    <div class="mb-3 flex items-start justify-between gap-3">
      <button type="button" class="min-w-0 text-left" @click="$emit('select')">
        <h3 class="truncate text-base font-semibold text-app-text">{{ project.name }}</h3>
        <p class="mt-1 text-xs text-app-muted">{{ project.description || '暂无项目描述' }}</p>
      </button>
      <button type="button" class="text-app-muted" @click="$emit('favorite')">
        {{ project.favorite ? '★' : '☆' }}
      </button>
    </div>

    <div class="mb-4 flex flex-wrap gap-2">
      <span
        v-for="tag in project.tags"
        :key="tag"
        class="rounded-full bg-white/80 px-2 py-1 text-[11px] text-app-muted"
      >
        {{ tag }}
      </span>
    </div>

    <div class="mb-4 grid grid-cols-2 gap-3 text-xs text-app-muted">
      <div>
        <p>节点数</p>
        <p class="mt-1 text-sm font-semibold text-app-text">{{ project.nodeCount }}</p>
      </div>
      <div>
        <p>连线数</p>
        <p class="mt-1 text-sm font-semibold text-app-text">{{ project.edgeCount }}</p>
      </div>
    </div>

    <div class="flex items-center justify-between">
      <span class="rounded-full bg-white px-2 py-1 text-[11px] text-app-text">
        {{ project.status }}
      </span>
      <AppButton label="打开" size="sm" tone="primary" @click="$emit('open')" />
    </div>
  </article>
</template>
