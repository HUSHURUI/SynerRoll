<script setup lang="ts">
import type { Project } from '~~/types/project'

import { useProjectApi } from '~~/composables/api/useProjectApi'
import { buildBackendPayload } from '~~/utils/backend-export'
import { downloadJson } from '~~/utils/download'

const route = useRoute()
const projectId = computed(() => String(route.params.projectId ?? ''))
const projectApi = useProjectApi()

const projectState = useState<Project | null>(`result-project-${projectId.value}`, () => null)

const { data, pending } = await useAsyncData(`result-page-${projectId.value}`, () => projectApi.getProject(projectId.value))

watchEffect(() => {
  if (!data.value?.project) {
    return
  }

  projectState.value = data.value.project
})

const project = computed(() => projectState.value)

useHead(() => ({
  title: project.value ? `${project.value.name} - 结果分析` : '结果分析 - SynerRoll'
}))

const exportBackendPayload = () => {
  if (!project.value) {
    return
  }

  const payload = buildBackendPayload(project.value)
  downloadJson(`${project.value.name}-backend-payload.json`, payload)
}
</script>

<template>
  <div class="min-h-screen bg-app-surface">
    <div class="border-b border-app-border bg-white">
      <div class="mx-auto flex max-w-[1680px] items-center justify-between px-6 py-4">
        <div>
          <h1 class="text-2xl font-bold text-app-text">仿真结果分析</h1>
          <p class="mt-1 text-sm text-app-muted">{{ project?.name || '正在加载项目' }}</p>
        </div>
        <div class="flex items-center gap-2">
          <AppButton label="返回编辑器" icon="shape" tone="neutral" @click="navigateTo(`/editor/${projectId}`)" />
          <AppButton label="导出载荷" icon="download" tone="primary" @click="exportBackendPayload" />
        </div>
      </div>
    </div>

    <div v-if="pending || !project" class="mx-auto flex min-h-[60vh] max-w-[1680px] items-center justify-center px-6 py-6 text-app-muted">
      正在加载结果...
    </div>

    <div v-else class="mx-auto flex min-h-[60vh] max-w-[960px] items-center justify-center px-6 py-6">
      <PanelSection title="仿真结果" class="w-full">
        <div class="space-y-4">
          <p class="text-sm text-app-muted">
            仿真结果功能正在开发中。当前可导出项目载荷并在后端进行计算。
          </p>

          <div class="rounded-lg border border-app-border bg-app-panel-soft p-6 text-center">
            <div class="mb-4 text-4xl text-app-muted">
              <svg class="mx-auto h-12 w-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
              </svg>
            </div>
            <p class="text-sm text-app-text">仿真计算完成后，结果将在此展示</p>
          </div>

          <div class="grid grid-cols-2 gap-4">
            <div class="rounded-lg border border-app-border p-4">
              <p class="text-xs text-app-muted">活动画布</p>
              <p class="mt-1 font-medium text-app-text">
                {{ project.workspace.canvases.find(c => c.id === project.workspace.activeCanvasId)?.name || '未选择' }}
              </p>
            </div>
            <div class="rounded-lg border border-app-border p-4">
              <p class="text-xs text-app-muted">节点数量</p>
              <p class="mt-1 font-medium text-app-text">
                {{ project.workspace.canvases.find(c => c.id === project.workspace.activeCanvasId)?.nodes.length || 0 }}
              </p>
            </div>
          </div>
        </div>

        <template #extra>
          <AppButton label="前往算法配置" icon="play" tone="primary" @click="navigateTo(`/simulation/${projectId}`)" />
        </template>
      </PanelSection>
    </div>
  </div>
</template>