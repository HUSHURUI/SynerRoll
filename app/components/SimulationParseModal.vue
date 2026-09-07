<!--
  [已废弃 2026-07-14] 旧的仿真解析弹窗
  功能已迁移到计算任务系统：tasks/index.vue → POST /api/task/create → run_task 内自动 parse
  保留文件避免 Nuxt auto-import 报错，内容已清空
-->
<script setup lang="ts">
// 废弃：此组件不再使用
defineProps<{ open: boolean; projectId: string }>()
defineEmits<{ close: [] }>()
</script>

<template>
  <!-- 废弃：功能已迁移到计算任务系统 -->
</template>
