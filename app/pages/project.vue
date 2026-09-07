<script setup lang="ts">
import type { Project, ProjectSummary } from '~~/types/project'

import { projectCategoryFilters } from '~~/config/system-config'
import { PROJECT_TEMPLATE_OPTIONS } from '~~/config/project-templates'
import { useProjectApi } from '~~/composables/api/useProjectApi'
import { useToastCenter } from '~~/state/ui'
import { downloadJson } from '~~/utils/download'

const projectApi = useProjectApi()
const { push } = useToastCenter()
const activeFilter = ref<'all' | 'recent' | 'favorite'>('all')
const searchKeyword = ref('')
const selectedProjectId = ref<string>('')
const selectedProjectDetail = ref<Project | null>(null)
const detailPending = ref(false)
const fileInputRef = ref<HTMLInputElement | null>(null)
const showCreateDialog = ref(false)
const creatingProject = ref(false)
const newProjectName = ref('')

const { data, pending, refresh } = await useAsyncData('project-list', () => projectApi.listProjects())

const projectList = computed(() => data.value?.projects ?? [])

watchEffect(() => {
  if (!selectedProjectId.value && projectList.value.length > 0) {
    selectedProjectId.value = projectList.value[0].id
  }
})

const loadSelectedProjectDetail = async (projectId: string) => {
  if (!projectId) {
    selectedProjectDetail.value = null
    return
  }

  detailPending.value = true

  try {
    const detail = await projectApi.getProject(projectId)
    selectedProjectDetail.value = detail.project
  }
  finally {
    detailPending.value = false
  }
}

watch(selectedProjectId, value => {
  void loadSelectedProjectDetail(value)
}, { immediate: true })

const matchesCurrentFilter = (project: ProjectSummary) => {
  const keyword = searchKeyword.value.trim().toLowerCase()

  if (activeFilter.value === 'favorite' && !project.favorite) {
    return false
  }

  if (!keyword) {
    return true
  }

  return [project.name, project.description ?? '', ...project.tags]
    .some(text => text.toLowerCase().includes(keyword))
}

const sortByUpdateTime = (projects: ProjectSummary[]) =>
  [...projects]
    .sort((left, right) => new Date(right.updateTime).getTime() - new Date(left.updateTime).getTime())

const visibleProjects = computed(() => sortByUpdateTime(
  projectList.value.filter(project => !project.isBuiltInScenario && matchesCurrentFilter(project))
))

const visibleScenarioProjects = computed(() => sortByUpdateTime(
  projectList.value.filter(project => project.isBuiltInScenario && matchesCurrentFilter(project))
))

const selectedProject = computed<ProjectSummary | null>(() =>
  visibleProjects.value.find(project => project.id === selectedProjectId.value) ??
  projectList.value.find(project => project.id === selectedProjectId.value) ??
  null
)

const selectedProjectTemplate = computed(() =>
  PROJECT_TEMPLATE_OPTIONS.find(template => template.id === selectedProjectDetail.value?.templateId) ?? null
)

const selectedIsBuiltInScenario = computed(() => selectedProject.value?.isBuiltInScenario === true)

const openCreateDialog = () => {
  newProjectName.value = ''
  showCreateDialog.value = true
}

const createProject = async () => {
  const name = newProjectName.value.trim()
  if (!name) {
    push({ tone: 'warning', title: '请输入项目名称' })
    return
  }

  creatingProject.value = true
  try {
    const created = await projectApi.createProject({
      name,
      template: 'blank',
      description: '从空白画布创建的综合能源项目'
    })
    await refresh()
    selectedProjectId.value = created.project.id
    showCreateDialog.value = false
    push({ tone: 'success', title: '项目创建成功', description: '已创建空白项目' })
  }
  catch (error) {
    push({ tone: 'error', title: '项目创建失败', description: String(error) })
  }
  finally {
    creatingProject.value = false
  }
}

const renameProject = async () => {
  if (!selectedProject.value) {
    return
  }

  if (selectedProject.value.isBuiltInScenario) {
    push({ tone: 'info', title: '内置典型场景不可重命名' })
    return
  }

  const name = window.prompt('请输入新的项目名称', selectedProject.value.name)

  if (!name) {
    return
  }

  await projectApi.updateProject(selectedProject.value.id, { name })
  await refresh()
  await loadSelectedProjectDetail(selectedProject.value.id)
  push({ tone: 'success', title: '项目已重命名' })
}

const deleteProject = async () => {
  if (!selectedProject.value) {
    return
  }

  if (selectedProject.value.isBuiltInScenario) {
    push({ tone: 'info', title: '内置典型场景不可删除' })
    return
  }

  const confirmed = window.confirm(`确认删除项目“${selectedProject.value.name}”吗？`)

  if (!confirmed) {
    return
  }

  await projectApi.deleteProject(selectedProject.value.id)
  selectedProjectId.value = ''
  await refresh()
  push({ tone: 'success', title: '项目已删除' })
}

const toggleFavorite = async (project: ProjectSummary) => {
  await projectApi.updateProject(project.id, { favorite: !project.favorite })
  await refresh()
  if (selectedProjectId.value === project.id) {
    await loadSelectedProjectDetail(project.id)
  }
}

const exportProject = async () => {
  if (!selectedProject.value) {
    return
  }

  const detail = await projectApi.getProject(selectedProject.value.id)
  downloadJson(`${detail.project.name}.json`, detail.project)
}

const importProject = async (event: Event) => {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]

  if (!file) {
    return
  }

  const content = await file.text()
  const parsed = JSON.parse(content) as { name?: string; description?: string }
  const created = await projectApi.createProject({
    name: parsed.name || file.name.replace(/\.json$/i, ''),
    description: parsed.description || '由 JSON 导入'
  })
  await projectApi.saveCanvas(created.project.id, {
    workspace: (JSON.parse(content) as { workspace: import('~~/types/canvas').CanvasWorkspace }).workspace
  })
  await refresh()
  selectedProjectId.value = created.project.id
  input.value = ''
  push({ tone: 'success', title: '项目导入成功' })
}
</script>

<template>
  <div class="min-h-screen bg-app-surface">
    <div class="border-b border-app-border bg-white">
      <div class="mx-auto flex max-w-[1680px] items-center justify-between px-6 py-4">
        <div>
          <h1 class="text-2xl font-bold text-app-text">SynerRoll 项目管理</h1>
          <p class="mt-1 text-sm text-app-muted">综合能源系统多尺度滚动仿真平台前端工作台</p>
        </div>
        <div class="flex items-center gap-2">
          <AppButton label="新建项目" icon="package" tone="neutral" data-testid="open-project-template-dialog" @click="openCreateDialog" />
          <AppButton label="导入项目" icon="download" tone="primary" @click="fileInputRef?.click()" />
          <input ref="fileInputRef" class="hidden" type="file" accept=".json" @change="importProject">
        </div>
      </div>
    </div>

    <div class="mx-auto grid max-w-[1680px] grid-cols-[240px_minmax(0,1fr)_340px] gap-6 px-6 py-6">
      <aside class="panel-card p-4">
        <h2 class="mb-4 text-sm font-semibold text-app-text">项目分类</h2>
        <div class="space-y-2">
          <button
            v-for="filter in projectCategoryFilters"
            :key="filter.key"
            type="button"
            class="w-full rounded-lg border px-3 py-3 text-left transition"
            :class="activeFilter === filter.key ? 'border-primary bg-primary-soft text-primary' : 'border-app-border bg-white text-app-text hover:bg-app-panel-soft'"
            @click="activeFilter = filter.key"
          >
            <p class="text-sm font-medium">{{ filter.label }}</p>
            <p class="mt-1 text-xs text-app-muted">{{ filter.description }}</p>
          </button>
        </div>
      </aside>

      <section class="space-y-4">
        <div class="panel-card flex items-center justify-between p-4">
          <div class="relative w-full max-w-md">
            <span class="pointer-events-none absolute inset-y-0 left-3 inline-flex items-center text-app-muted">
              <AppIcon name="search" :size="14" />
            </span>
            <input
              v-model="searchKeyword"
              class="field-input pl-9"
              placeholder="搜索项目、标签或描述"
            >
          </div>
          <div class="flex items-center gap-2">
            <AppButton label="重命名" icon="docs" tone="neutral" :disabled="selectedIsBuiltInScenario" @click="renameProject" />
            <AppButton label="导出" icon="download" tone="neutral" @click="exportProject" />
            <AppButton label="删除" icon="delete" tone="danger" :disabled="selectedIsBuiltInScenario" @click="deleteProject" />
          </div>
        </div>

        <div v-if="pending" class="panel-card flex min-h-[420px] items-center justify-center text-app-muted">
          正在加载项目列表...
        </div>

        <template v-else>
          <div class="grid grid-cols-1 gap-4 xl:grid-cols-2 2xl:grid-cols-3">
            <ProjectCard
              v-for="project in visibleProjects"
              :key="project.id"
              :project="project"
              :selected="selectedProjectId === project.id"
              @select="selectedProjectId = project.id"
              @open="navigateTo(`/editor/${project.id}`)"
              @favorite="toggleFavorite(project)"
            />
          </div>

          <section v-if="visibleScenarioProjects.length > 0" class="space-y-3 pt-3">
            <div>
              <h2 class="text-lg font-semibold text-app-text">典型场景</h2>
            </div>
            <div class="grid grid-cols-1 gap-4 xl:grid-cols-2 2xl:grid-cols-3">
              <ProjectCard
                v-for="project in visibleScenarioProjects"
                :key="project.id"
                :project="project"
                :selected="selectedProjectId === project.id"
                @select="selectedProjectId = project.id"
                @open="navigateTo(`/editor/${project.id}`)"
                @favorite="toggleFavorite(project)"
              />
            </div>
          </section>
        </template>
      </section>

      <aside class="panel-card p-4">
        <template v-if="selectedProject">
          <div class="mb-4">
            <p class="text-xs uppercase tracking-[0.18em] text-app-muted">Detail</p>
            <h2 class="mt-2 text-xl font-semibold text-app-text">{{ selectedProject.name }}</h2>
            <p class="mt-2 text-sm leading-6 text-app-muted">
              {{ selectedProject.description || '当前项目暂无详细描述。' }}
            </p>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <div class="rounded-lg border border-app-border bg-app-panel-soft p-3">
              <p class="text-xs text-app-muted">更新时间</p>
              <p class="mt-2 text-sm font-semibold text-app-text">{{ new Date(selectedProject.updateTime).toLocaleString() }}</p>
            </div>
            <div class="rounded-lg border border-app-border bg-app-panel-soft p-3">
              <p class="text-xs text-app-muted">负责人</p>
              <p class="mt-2 text-sm font-semibold text-app-text">{{ selectedProject.owner }}</p>
            </div>
            <div class="rounded-lg border border-app-border bg-app-panel-soft p-3">
              <p class="text-xs text-app-muted">节点数量</p>
              <p class="mt-2 text-sm font-semibold text-app-text">{{ selectedProject.nodeCount }}</p>
            </div>
            <div class="rounded-lg border border-app-border bg-app-panel-soft p-3">
              <p class="text-xs text-app-muted">连线数量</p>
              <p class="mt-2 text-sm font-semibold text-app-text">{{ selectedProject.edgeCount }}</p>
            </div>
          </div>

          <div class="mt-4 flex flex-wrap gap-2">
            <span
              v-for="tag in selectedProject.tags"
              :key="tag"
              class="rounded-full bg-primary-soft px-2 py-1 text-xs text-primary"
            >
              {{ tag }}
            </span>
          </div>

          <div class="mt-6 space-y-3">
            <div class="rounded-lg border border-app-border bg-app-panel-soft p-3">
              <p class="text-xs font-semibold text-app-text">起始模板</p>
              <p class="mt-1 text-sm text-app-text">{{ selectedProjectTemplate?.label || '历史或自定义项目' }}</p>
              <p class="mt-1 text-xs leading-5 text-app-muted">模板仅记录项目起点，仿真始终读取当前画布中的实际组件和参数。</p>
            </div>
            <div class="rounded-lg border border-app-border bg-app-panel-soft p-3">
              <p class="text-xs font-semibold text-app-text">当前活动画布</p>
              <p class="mt-1 text-xs leading-5 text-app-muted">在编辑器中切换活动画布即可更改仿真输入。</p>
              <div class="mt-2 text-sm text-app-text">
                {{ selectedProjectDetail?.workspace.activeCanvasId || '未设置' }}
              </div>
            </div>

            <AppButton label="进入建模编辑器" icon="shape" tone="primary" class="w-full justify-center" @click="navigateTo(`/editor/${selectedProject.id}`)" />
            <AppButton label="进入算法配置" icon="play" tone="neutral" class="w-full justify-center" @click="navigateTo(`/simulation/${selectedProject.id}`)" />
            <AppButton label="查看结果分析" icon="chart" tone="neutral" class="w-full justify-center" @click="navigateTo(`/result/${selectedProject.id}`)" />
          </div>
        </template>

        <div v-else class="flex h-full min-h-[420px] items-center justify-center text-sm text-app-muted">
          请选择一个项目查看详情。
        </div>
      </aside>
    </div>

    <AppModal
      :open="showCreateDialog"
      title="新建项目"
      size="sm"
      @close="showCreateDialog = false"
    >
      <div class="space-y-4 p-3">
        <label class="block space-y-1.5 text-sm text-app-text">
          <span class="font-medium">项目名称</span>
          <input
            v-model="newProjectName"
            data-testid="new-project-name"
            class="field-input"
            placeholder="请输入项目名称"
            @keyup.enter="createProject"
          >
        </label>
        <p class="text-xs leading-5 text-app-muted">新项目从空白画布创建；三个预置典型场景可直接从工作台打开。</p>
      </div>
      <template #footer>
        <AppButton label="取消" tone="neutral" @click="showCreateDialog = false" />
        <AppButton
          :label="creatingProject ? '创建中...' : '创建项目'"
          tone="primary"
          data-testid="create-project-submit"
          :disabled="creatingProject"
          @click="createProject"
        />
      </template>
    </AppModal>
  </div>
</template>
