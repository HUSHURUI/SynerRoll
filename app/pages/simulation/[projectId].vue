<script setup lang="ts">
import type { Project } from '~~/types/project'
import type { LayerDefinition } from '~~/types/simulation'

import { useProjectApi } from '~~/composables/api/useProjectApi'
import { useToastCenter } from '~~/state/ui'
import { downloadJson } from '~~/utils/download'
import { buildBackendPayload } from '~~/utils/backend-export'

const route = useRoute()
const projectId = computed(() => String(route.params.projectId ?? ''))
const projectApi = useProjectApi()
const { push } = useToastCenter()

const projectState = useState<Project | null>(`simulation-project-${projectId.value}`, () => null)

const { data, pending, refresh } = await useAsyncData(`simulation-page-${projectId.value}`, () => projectApi.getProject(projectId.value))

watchEffect(() => {
  if (!data.value?.project) {
    return
  }

  projectState.value = data.value.project
})

const project = computed(() => projectState.value)
const activeCanvasId = computed(() => project.value?.workspace.activeCanvasId ?? '')

useHead(() => ({
  title: project.value ? `${project.value.name} - 算法配置` : '算法配置 - SynerRoll'
}))

const saveProject = async () => {
  if (!project.value) {
    return
  }

  const updated = await projectApi.updateProject(project.value.id, {
    name: project.value.name,
    tags: project.value.tags
  })
  push({ tone: 'success', title: '配置已保存' })
  await refresh()
}

const exportBackendPayload = async () => {
  if (!project.value) {
    return
  }

  const payload = buildBackendPayload(project.value)
  downloadJson(`${project.value.name}-backend-payload.json`, payload)
  push({ tone: 'success', title: '后端载荷已导出' })
}
</script>

<template>
  <div class="min-h-screen bg-app-surface">
    <div class="border-b border-app-border bg-white">
      <div class="mx-auto flex max-w-[1680px] items-center justify-between px-6 py-4">
        <div>
          <h1 class="text-2xl font-bold text-app-text">算法配置</h1>
          <p class="mt-1 text-sm text-app-muted">
            {{ project?.name || '正在加载项目' }}
          </p>
        </div>
        <div class="flex items-center gap-2">
          <AppButton label="返回编辑器" icon="shape" tone="neutral" @click="navigateTo(`/editor/${projectId}`)" />
          <AppButton label="保存配置" icon="docs" tone="neutral" @click="saveProject" />
          <AppButton label="导出后端载荷" icon="download" tone="primary" @click="exportBackendPayload" />
        </div>
      </div>
    </div>

    <div v-if="pending || !project" class="mx-auto flex min-h-[60vh] max-w-[1680px] items-center justify-center px-6 py-6 text-app-muted">
      正在加载配置...
    </div>

    <div v-else class="mx-auto grid max-w-[1680px] grid-cols-[minmax(0,1fr)_360px] gap-6 px-6 py-6">
      <section class="space-y-6">
        <PanelSection title="时层配置">
          <div class="space-y-3">
            <div
              v-for="layer in project.layerConfig.layers"
              :key="layer.id"
              class="grid grid-cols-[64px_1fr_1fr_1fr_96px] items-center gap-3 rounded-lg border border-app-border p-3"
            >
              <span class="text-sm font-medium text-app-text">{{ layer.name }}</span>
              <div class="text-sm text-app-muted">
                <span class="text-xs text-app-muted">时长: </span>{{ layer.length }}
              </div>
              <div class="text-sm text-app-muted">
                <span class="text-xs text-app-muted">步长: </span>{{ layer.step }}
              </div>
              <div class="text-sm text-app-muted">
                <span class="text-xs text-app-muted">前推: </span>{{ layer.forward }}
              </div>
              <span class="text-xs text-app-muted">层级 {{ layer.id }}</span>
            </div>
          </div>
          <p class="mt-2 text-xs text-app-muted">如需修改时层配置，请在编辑器中使用时层配置弹窗。</p>
        </PanelSection>

        <PanelSection title="边界数据">
          <div v-if="project.boundaries && project.boundaries.length > 0" class="space-y-4">
            <article
              v-for="boundary in project.boundaries"
              :key="boundary.id"
              class="rounded-lg border border-app-border p-4"
            >
              <div class="mb-3 flex items-center justify-between">
                <div>
                  <h3 class="text-sm font-semibold text-app-text">{{ boundary.name }}</h3>
                  <p class="text-xs text-app-muted">{{ boundary.meaning }} · {{ boundary.timeStep }}</p>
                </div>
                <span class="rounded-full bg-app-panel-soft px-2 py-1 text-xs text-app-muted">
                  {{ boundary.columnName }}
                </span>
              </div>

              <div class="grid grid-cols-3 gap-3">
                <label class="block">
                  <span class="field-label">插值方式</span>
                  <BaseInput v-model="boundary.interpolateType" />
                </label>
                <label class="block">
                  <span class="field-label">噪声等级</span>
                  <BaseInput v-model="boundary.noiseLevel" type="number" />
                </label>
                <div class="block">
                  <span class="field-label">关联组件</span>
                  <div class="rounded-md border border-app-border bg-app-panel-soft px-3 py-2 text-xs text-app-muted">
                    {{ boundary.relatedComponents?.join(', ') || '未关联' }}
                  </div>
                </div>
              </div>
            </article>
          </div>
          <p v-else class="text-sm text-app-muted">
            当前项目尚未配置边界数据。请在编辑器中进行配置。
          </p>
        </PanelSection>

        <PanelSection title="算法与求解器">
          <div class="grid grid-cols-2 gap-4">
            <label class="block">
              <span class="field-label">电负荷预测</span>
              <BaseInput v-model="project.algorithm.electricityLoadPrediction" />
            </label>
            <label class="block">
              <span class="field-label">风电预测</span>
              <BaseInput v-model="project.algorithm.windTurbinePrediction" />
            </label>
            <label class="block">
              <span class="field-label">优化算法</span>
              <BaseSelect
                v-model="project.algorithm.optimizationAlgorithm"
                :options="[{ label: 'MILP', value: 'MILP' }, { label: 'MPC', value: 'MPC' }, { label: 'GA', value: 'GA' }]"
              />
            </label>
            <div />
            <div class="col-span-2 grid grid-cols-4 gap-3">
              <label class="block">
                <span class="field-label">容差</span>
                <BaseInput v-model="project.solverConfig.tolerance" type="number" />
              </label>
              <label class="block">
                <span class="field-label">最大迭代</span>
                <BaseInput v-model="project.solverConfig.maxIteration" type="number" />
              </label>
              <label class="block">
                <span class="field-label">线程数</span>
                <BaseInput v-model="project.solverConfig.threadCount" type="number" />
              </label>
              <label class="flex items-center gap-2 pt-6 text-sm text-app-text">
                <input v-model="project.solverConfig.warmStart" class="field-checkbox" type="checkbox">
                热启动
              </label>
            </div>
          </div>
        </PanelSection>

        <PanelSection title="仿真画布">
          <p class="text-sm text-app-muted">
            当前活动画布将作为仿真模型输入。
          </p>
          <div class="mt-3 rounded-lg border border-app-border bg-app-panel-soft p-4">
            <select v-model="project.workspace.activeCanvasId" class="field-select w-full">
              <option
                v-for="canvas in project.workspace.canvases"
                :key="canvas.id"
                :value="canvas.id"
              >
                {{ canvas.name }} ({{ canvas.nodes.length }} 节点)
              </option>
            </select>
          </div>
        </PanelSection>
      </section>

      <aside class="space-y-6">
        <PanelSection title="仿真控制">
          <div class="space-y-3">
            <div class="rounded-lg border border-app-border bg-app-panel-soft p-4 text-center text-sm text-app-muted">
              <p>仿真功能开发中</p>
              <p class="mt-1 text-xs">请在编辑器中完成配置后，导出后端载荷进行计算。</p>
            </div>

            <div class="grid grid-cols-3 gap-2">
              <AppButton label="启动" icon="play" tone="primary" disabled />
              <AppButton label="暂停" icon="docs" tone="neutral" disabled />
              <AppButton label="终止" icon="delete" tone="danger" disabled />
            </div>
          </div>
        </PanelSection>

        <PanelSection title="输出配置">
          <div class="space-y-2">
            <div class="rounded-md border border-app-border px-3 py-2 text-sm text-app-text">
              <span>功率平衡</span>
              <span class="ml-2 text-xs text-app-muted">已启用</span>
            </div>
            <div class="rounded-md border border-app-border px-3 py-2 text-sm text-app-text">
              <span>储能状态</span>
              <span class="ml-2 text-xs text-app-muted">已启用</span>
            </div>
            <div class="rounded-md border border-app-border px-3 py-2 text-sm text-app-text">
              <span>运行成本</span>
              <span class="ml-2 text-xs text-app-muted">已启用</span>
            </div>
          </div>
        </PanelSection>

        <PanelSection title="页面跳转">
          <div class="space-y-2">
            <AppButton label="回到项目管理" icon="arrow" tone="neutral" class="w-full justify-center" @click="navigateTo('/project')" />
            <AppButton label="前往边界配置" icon="chart" tone="neutral" class="w-full justify-center" @click="navigateTo(`/boundary/${projectId}`)" />
          </div>
        </PanelSection>
      </aside>
    </div>
  </div>
</template>