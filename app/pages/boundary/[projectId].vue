<script setup lang="ts">
import { nextTick, watch } from 'vue'
import type { Project } from '~~/types/project'
import type { BoundaryItem, BoundaryMeaning, BoundaryRawData, BoundaryTransformedData } from '~~/types/boundary'
// 2026-07-07: BOUNDARY_COMPONENT_MAPPINGS 已注释（见 types/boundary.ts 顶部说明），先从 import 里去掉
// import { BOUNDARY_MEANING_LABELS, BOUNDARY_COMPONENT_MAPPINGS, INTERPOLATE_OPTIONS, DISTRIBUTION_OPTIONS, TIME_STEP_OPTIONS } from '~~/types/boundary'
import { BOUNDARY_MEANING_LABELS, INTERPOLATE_OPTIONS, DISTRIBUTION_OPTIONS, TIME_STEP_OPTIONS } from '~~/types/boundary'
import { componentDefinitionMap } from '~~/config/component-meta'
import { useProjectApi } from '~~/composables/api/useProjectApi'
import { useToastCenter } from '~~/state/ui'
import {
  getBoundaryRelatedComponentsForActiveCanvas,
  setBoundaryRelatedComponentsForActiveCanvas,
  syncBoundaryStateFromBoundaries
} from '~~/utils/boundary-sync'
import PropertySelect from '../../components/PropertySelect.vue'
import PropertyText from '../../components/PropertyText.vue'
import PropertyMultiSelect from '../../components/PropertyMultiSelect.vue'
import AppButton from '../../components/AppButton.vue'
import AppModal from '../../components/AppModal.vue'
import * as echarts from 'echarts'

// 将 BOUNDARY_MEANING_LABELS 对象转换为 PropertySelect 需要的数组格式
const meaningOptions = computed(() =>
  Object.entries(BOUNDARY_MEANING_LABELS).map(([value, label]) => ({ value, label }))
)

const route = useRoute()
const router = useRouter()
const projectId = computed(() => String(route.params.projectId ?? ''))
const projectApi = useProjectApi()
const { push } = useToastCenter()

const projectState = useState<Project | null>(`boundary-project-${projectId.value}`, () => null)
const { data, pending } = await useAsyncData(`boundary-page-${projectId.value}`, () => projectApi.getProject(projectId.value))

// 活动标签 - 需要在 initBoundaries 之前定义
const activeTab = ref<string>('')
const tabs = ref<{ key: string; label: string }[]>([])

// 当前编辑的边界
const currentBoundary = ref<BoundaryItem | null>(null)

// 边界名称编辑状态
const editingBoundaryId = ref<string | null>(null)
const editingBoundaryName = ref('')
const renameInputEl = ref<HTMLInputElement | null>(null)

// ============================================================
// 修复问题四：统一数据流
// rawData/transformedData 不再使用独立 ref，全部通过 currentBoundary 访问
// 仅在图表渲染时使用本地临时 ref 做渲染数据源
// =========================================================
const rawData = ref<BoundaryRawData | null>(null)
const transformedData = ref<BoundaryTransformedData | null>(null)

// 原始数据图表
const rawChartRef = ref<HTMLDivElement | null>(null)
let rawChartInstance: echarts.ECharts | null = null
// 转换后图表（每层一个）
const transformedChartRefs = ref<HTMLDivElement[]>([])
const transformedChartInstances: Record<string, echarts.ECharts> = {}

// 加载状态
const loading = ref(false)

// ============================================================
// 修复问题二 & 文件路径共享缓存
// 共享缓存：存储当前最新的非空 filePath，供所有空 filePath 的边界同步使用
// =========================================================
const sharedFilePathCache = ref<string>('')

// 同步 filePath 到所有空 filePath 的边界（不覆盖已有值的边界）
const syncFilePathToOtherBoundaries = (sourceBoundaryId: string, filePath: string) => {
  if (!project.value || !filePath.trim()) return

  let changed = false
  for (const boundary of project.value.boundaries) {
    if (boundary.id !== sourceBoundaryId && !boundary.filePath.trim()) {
      boundary.filePath = filePath
      changed = true
    }
  }
  if (changed) {
    projectState.value = { ...project.value }
  }
}

// 更新共享缓存并同步其他边界
const updateSharedFilePathCache = (boundaryId: string, filePath: string) => {
  if (!project.value) return

  // 更新缓存
  if (filePath.trim()) {
    sharedFilePathCache.value = filePath
  }

  // 同步到其他空 filePath 的边界
  syncFilePathToOtherBoundaries(boundaryId, filePath)
}

// ============================================================
// 表单字段
// =========================================================
const form = reactive({
  name: '',
  filePath: '',
  columnName: '',
  timeStep: '1h',
  meaning: 'wind_speed' as BoundaryMeaning,
  relatedComponents: [] as string[],
  interpolateType: 'copy' as const,
  randomDistribution: 'normal' as const,
  noiseLevel: 0
})

// 导入按钮是否可用
const canImport = computed(() => {
  return form.filePath.trim() !== '' &&
    form.columnName.trim() !== '' &&
    form.timeStep !== '' &&
    form.meaning !== ''
})

const project = computed(() => projectState.value)
const syncBoundaryFormSilently = ref(false)
let projectSyncTimer: ReturnType<typeof setTimeout> | null = null

const sameStringArray = (left: string[], right: string[]) =>
  left.length === right.length && left.every((value, index) => value === right[index])

const refreshCurrentBoundaryReference = () => {
  if (!project.value || !currentBoundary.value) {
    return
  }

  currentBoundary.value = project.value.boundaries.find(boundary => boundary.id === currentBoundary.value?.id) ?? null
}

const syncProjectFromBoundaries = () => {
  if (!project.value) {
    return
  }

  const synced = syncBoundaryStateFromBoundaries(project.value.workspace, project.value.boundaries)

  project.value.workspace = synced.workspace
  project.value.boundaries = synced.boundaries
  refreshCurrentBoundaryReference()

  if (currentBoundary.value) {
    const nextRelatedComponents = getBoundaryRelatedComponentsForActiveCanvas(
      currentBoundary.value,
      project.value.workspace
    )

    if (!sameStringArray(form.relatedComponents, nextRelatedComponents)) {
      syncBoundaryFormSilently.value = true
      form.relatedComponents = nextRelatedComponents
      syncBoundaryFormSilently.value = false
    }
  }

  projectState.value = { ...project.value }
}

const persistProjectSync = async () => {
  if (!project.value || !projectId.value) {
    return
  }

  if (!projectId.value.startsWith('project-')) {
    console.warn('[Boundary] 无效的 projectId，跳过实时同步保存:', projectId.value)
    return
  }

  try {
    await projectApi.saveCanvas(projectId.value, {
      workspace: project.value.workspace
    })
    await projectApi.saveBoundaries(projectId.value, project.value.boundaries)
  }
  catch (err) {
    console.error('[Boundary] 实时同步保存失败:', err)
    throw err
  }
}

const scheduleProjectSyncPersist = () => {
  if (projectSyncTimer) {
    clearTimeout(projectSyncTimer)
  }

  projectSyncTimer = setTimeout(() => {
    projectSyncTimer = null
    void persistProjectSync()
  }, 300)
}

const flushProjectSyncPersist = async () => {
  if (projectSyncTimer) {
    clearTimeout(projectSyncTimer)
    projectSyncTimer = null
  }

  await persistProjectSync()
}

// 根据物理含义获取可用的组件节点
// 2026-07-07: 从 componentDefinitionMap.boundaryKey?.includes(meaning) 反查节点类型
const availableRelatedNodes = computed((): Array<{ id: string; data?: { label?: string } }> => {
  if (!project.value) return []
  const canvas = project.value.workspace.canvases.find(c => c.id === project.value!.workspace.activeCanvasId) || project.value.workspace.canvases[0]
  if (!canvas) return []

  // 收集所有"def.boundaryKey 包含当前 meaning"的组件 key，画布上属于这些类型的节点都是候选
  const acceptedComponentKeys = new Set<string>()
  for (const def of Object.values(componentDefinitionMap)) {
    if (def.boundaryKey?.includes(form.meaning)) {
      acceptedComponentKeys.add(def.key)
    }
  }
  return canvas.nodes.filter(n => acceptedComponentKeys.has(n.data?.componentKey ?? ''))
})

// 初始化边界
async function initBoundaries() {
  console.log('[Boundary] initBoundaries 被调用', { time: new Date().toISOString() })
  const proj = projectState.value
  if (!proj) {
    console.log('[Boundary] proj 为空，跳过初始化')
    return
  }

  // 确保 boundaries 数组存在
  if (!proj.boundaries) {
    proj.boundaries = []
  }

  // 如果已经有边界数据，跳过自动创建
  if (proj.boundaries.length > 0) {
    // 初始化共享文件路径缓存（取最后一个非空值）
    for (let i = proj.boundaries.length - 1; i >= 0; i--) {
      if (proj.boundaries[i]!.filePath.trim()) {
        sharedFilePathCache.value = proj.boundaries[i]!.filePath
        break
      }
    }
    // 更新标签页
    tabs.value = proj.boundaries.map((b, i) => ({
      key: b.id,
      label: b.name || `边界 ${i + 1}`
    }))
    if (tabs.value.length > 0) {
      activeTab.value = tabs.value[0].key
      loadBoundary(tabs.value[0].key)
    }
    return
  }

  const workspace = proj.workspace
  if (!workspace?.canvases?.length) return

  const canvas = workspace.canvases.find(c => c.id === workspace.activeCanvasId) || workspace.canvases[0]
  if (!canvas) return

  // 2026-07-07: 用 componentDefinitionMap[def.key].boundaryKey[0] 作为默认 meaning，
  // 每个组件自动建一个边界（WT→wind_speed, PV→irradiance, COAL→other）。
  // 同 meaning 的多个组件合并到同一个边界（追加 relatedComponents）。
  const nodes = canvas.nodes

  const newBoundaries: BoundaryItem[] = []

  for (const node of nodes) {
    const componentKey = node.data?.componentKey
    if (!componentKey) continue
    const def = componentDefinitionMap[componentKey]
    if (!def?.boundaryKey?.length) continue

    const meaning = def.boundaryKey[0]
    const existing = newBoundaries.find(b => b.meaning === meaning)
    if (existing) {
      if (!existing.relatedComponents.includes(node.id)) {
        existing.relatedComponents.push(node.id)
      }
    } else {
      const id = generateId()
      const cnName = BOUNDARY_MEANING_LABELS[meaning]
      newBoundaries.push({
        id,
        name: `${cnName}`,
        filePath: '',
        columnName: '',
        timeStep: '1h',
        meaning,
        relatedComponents: [node.id],
        interpolateType: 'copy',
        randomDistribution: 'normal',
        noiseLevel: 0
      })
    }
  }

  if (newBoundaries.length > 0) {
    projectState.value = {
      ...proj,
      boundaries: newBoundaries
    }
    syncProjectFromBoundaries()

    tabs.value = newBoundaries.map((b, i) => ({
      key: b.id,
      label: b.name || `边界 ${i + 1}`
    }))

    if (tabs.value.length > 0 && !activeTab.value) {
      activeTab.value = tabs.value[0].key
      loadBoundary(tabs.value[0].key)
    }

    scheduleProjectSyncPersist()
  }
}

function generateId(): string {
  return 'b_' + Date.now().toString(36) + Math.random().toString(36).slice(2, 8)
}

// 将当前表单数据保存到边界对象
function saveCurrentFormToBoundary() {
  console.log('[Boundary] saveCurrentFormToBoundary 被调用', {
    hasProject: !!project.value,
    hasCurrentBoundary: !!currentBoundary.value,
    currentBoundaryId: currentBoundary.value?.id,
    time: new Date().toISOString()
  })
  if (!project.value || !currentBoundary.value) return

  const boundary = project.value.boundaries.find(b => b.id === currentBoundary.value!.id)
  if (!boundary) return

  boundary.name = form.name
  boundary.filePath = form.filePath
  boundary.columnName = form.columnName
  boundary.timeStep = form.timeStep
  boundary.meaning = form.meaning
  boundary.relatedComponents = setBoundaryRelatedComponentsForActiveCanvas(
    boundary,
    project.value.workspace,
    form.relatedComponents
  )
  boundary.interpolateType = form.interpolateType
  boundary.randomDistribution = form.randomDistribution
  boundary.noiseLevel = form.noiseLevel

  // 持久化原始数据和转换数据，避免页面重载后丢失
  if (rawData.value) {
    boundary.rawData = {
      values: rawData.value.values,
      timestamps: rawData.value.timestamps,
      xAxisLabel: rawData.value.xAxisLabel,
      yAxisLabel: rawData.value.yAxisLabel
    }
  }
  if (transformedData.value) {
    boundary.transformedData = {
      layers: transformedData.value.layers.map(l => ({
        layerId: l.layerId,
        layerName: l.layerName,
        values: l.values,
        timestamps: l.timestamps
      }))
    }
  }

  // 文件路径变化时更新共享缓存并同步到其他边界
  if (boundary.filePath.trim()) {
    updateSharedFilePathCache(boundary.id, boundary.filePath)
  }

  currentBoundary.value = boundary
  projectState.value = { ...project.value }
}

// 开始重命名边界
function startRename(id: string, currentName: string) {
  console.log('[Boundary] startRename 被调用:', { id, currentName })
  editingBoundaryId.value = id
  editingBoundaryName.value = currentName
  nextTick(() => {
    renameInputEl.value?.focus()
    renameInputEl.value?.select()
  })
}

// 确认重命名
function confirmRename() {
  console.log('[Boundary] confirmRename 被调用:', {
    editingId: editingBoundaryId.value,
    newName: editingBoundaryName.value
  })
  if (!editingBoundaryId.value) return

  const id = editingBoundaryId.value
  const newName = editingBoundaryName.value.trim()

  if (newName !== '' && project.value) {
    const boundary = project.value.boundaries.find(b => b.id === id)
    if (boundary && boundary.name !== newName) {
      console.log('[Boundary] 重命名边界:', { oldName: boundary.name, newName })
      boundary.name = newName
      // 同步更新 form.name，防止 watch 触发后 saveCurrentFormToBoundary 用旧 form.name 覆盖
      form.name = newName
      projectState.value = { ...project.value }
      persistBoundaries()

      // 更新标签
      const tabIdx = tabs.value.findIndex(t => t.key === id)
      if (tabIdx !== -1 && tabs.value[tabIdx]) {
        tabs.value[tabIdx].label = newName
      }
    }
  }

  editingBoundaryId.value = null
  editingBoundaryName.value = ''
}

// 取消重命名
function cancelRename() {
  editingBoundaryId.value = null
  editingBoundaryName.value = ''
}

// 加载边界数据到表单
async function loadBoundary(id: string) {
  console.log('[Boundary] loadBoundary 被调用:', { id, time: new Date().toISOString() })

  const boundary = project.value?.boundaries.find(b => b.id === id)
  if (!boundary) {
    console.log('[Boundary] 未找到边界:', id)
    return
  }
  console.log('[Boundary] 找到边界:', { id, name: boundary.name })

  // 直接更新 currentBoundary 和 form
  currentBoundary.value = boundary
  Object.assign(form, {
    name: boundary.name,
    filePath: boundary.filePath,
    columnName: boundary.columnName,
    timeStep: boundary.timeStep,
    meaning: boundary.meaning,
    relatedComponents: getBoundaryRelatedComponentsForActiveCanvas(boundary, project.value.workspace),
    interpolateType: boundary.interpolateType,
    randomDistribution: boundary.randomDistribution,
    noiseLevel: boundary.noiseLevel
  })

  // 恢复持久化的数据
  if (boundary.rawData) {
    rawData.value = {
      boundaryId: boundary.id,
      values: boundary.rawData.values,
      timestamps: boundary.rawData.timestamps,
      xAxisLabel: boundary.rawData.xAxisLabel,
      yAxisLabel: boundary.rawData.yAxisLabel
    }
  } else {
    rawData.value = null
  }

  if (boundary.transformedData) {
    transformedData.value = {
      boundaryId: boundary.id,
      layers: boundary.transformedData.layers
    }
  } else {
    transformedData.value = null
  }

  // 尝试从 TS 库加载已存储的转换数据
  if (form.meaning && project.value?.layerConfig?.layers) {
    console.log('[Boundary] 准备从 TS 库加载转换数据', {
      meaning: form.meaning,
      relatedComponent: form.relatedComponents[0],
      layerIds: project.value.layerConfig.layers.map((l: any) => l.id)
    })
    try {
      const loadRes = await $fetch<{
        success: boolean
        data?: {
          allFound: boolean
          boundaries: { layerId: string; found: boolean; values?: number[]; timestamps?: string[] }[]
        }
      }>('/api/v1/boundary/load', {
        method: 'POST',
        body: {
          projectId: projectId.value,
          boundaries: project.value.layerConfig.layers.map((layer: any) => ({
            layerId: layer.id,
            meaning: form.meaning,
            boundaryId: boundary.id
            // 后端按 boundaryId 作为 source_id 查 TS 库，独立定位该边界的数据
          }))
        }
      })

      // BFF 把 allFound/boundaries 放在了 loadRes.data 下（apiSuccess 包装层）
      const payload = loadRes.data
      if (loadRes.success && payload) {
        const foundLayers = (payload.boundaries || []).filter((b: any) => b.found)
        if (foundLayers.length > 0) {
          // 用项目里 layerConfig 的 name 做更友好的标题
          const layerNameMap = new Map<string, string>(
            project.value.layerConfig.layers.map((l: any) => [String(l.id), l.name || `时层${l.id}`])
          )
          const storedLayers = foundLayers.map((b: any) => ({
            layerId: b.layerId,
            layerName: layerNameMap.get(String(b.layerId)) || `Layer ${b.layerId}`,
            values: b.values ?? [],
            timestamps: b.timestamps ?? []
          }))
          transformedData.value = {
            boundaryId: boundary.id,
            layers: storedLayers
          }
          console.log('[Boundary] 从 TS 库加载转换数据成功:', {
            requested: payload.boundaries.length,
            found: foundLayers.length,
            allFound: payload.allFound
          })
        } else {
          console.log('[Boundary] TS 库中未找到该边界的任何层数据')
        }
      } else {
        console.warn('[Boundary] TS 库返回结构异常:', loadRes)
      }
    } catch (err) {
      console.warn('[Boundary] 从 TS 库加载转换数据失败:', err)
    }
  }

  // 如果 rawData 缺失但有 filePath/columnName，重新从文件读一份（让原始数据图也回填）
  if (!rawData.value && form.filePath.trim() && form.columnName.trim()) {
    try {
      const importRes = await $fetch<{
        success: boolean
        data?: { values: number[]; timestamps: string[]; xAxisLabel: string; yAxisLabel: string }
        message?: string
      }>('/api/v1/boundary/import', {
        method: 'POST',
        body: {
          filePath: form.filePath,
          columnName: form.columnName,
          timeStep: form.timeStep,
          projectId: projectId.value
        }
      })
      if (importRes.success && importRes.data) {
        rawData.value = {
          boundaryId: boundary.id,
          values: importRes.data.values,
          timestamps: importRes.data.timestamps,
          xAxisLabel: importRes.data.xAxisLabel,
          yAxisLabel: importRes.data.yAxisLabel
        }
        console.log('[Boundary] 从文件重读原始数据成功')
      } else {
        console.warn('[Boundary] 从文件重读原始数据失败:', importRes.message)
      }
    } catch (err) {
      console.warn('[Boundary] 从文件重读原始数据异常:', err)
    }
  }

  // 恢复图表数据
  nextTick(() => {
    if (rawData.value) {
      updateRawChart()
    }
    if (transformedData.value) {
      updateTransformedChart()
    }
  })
}

// 监听活动标签变化，切换前保存当前表单
watch(activeTab, (newId, oldId) => {
  console.log('[Boundary] activeTab 变化:', { oldId, newId, time: new Date().toISOString() })
  if (oldId && oldId !== newId) {
    // 如果正在重命名，跳过保存（blur 会处理）
    if (!editingBoundaryId.value) {
      console.log('[Boundary] 切换标签，准备保存旧边界:', oldId)
      saveCurrentFormToBoundary()
      scheduleProjectSyncPersist()
    } else {
      console.log('[Boundary] 正在重命名，跳过保存')
    }
  }
  if (newId) {
    console.log('[Boundary] 加载新边界:', newId)
    loadBoundary(newId)
  }
})

// 创建新边界
function createBoundary() {
  const id = generateId()
  // 新建边界时使用共享缓存的 filePath
  const newBoundary: BoundaryItem = {
    id,
    name: `边界${tabs.value.length + 1}`,
    filePath: sharedFilePathCache.value,
    columnName: '',
    timeStep: '1h',
    meaning: 'wind_speed',
    relatedComponents: [],
    interpolateType: 'copy',
    randomDistribution: 'normal',
    noiseLevel: 0
  }

  if (!project.value) return

  project.value.boundaries.push(newBoundary)
  projectState.value = { ...project.value }

  tabs.value.push({ key: id, label: newBoundary.name })
  activeTab.value = id
  loadBoundary(id)

  scheduleProjectSyncPersist()
}

// 删除边界相关状态
const showDeleteConfirm = ref(false)
const pendingDeleteBoundary = ref<BoundaryItem | null>(null)
const deletingBoundary = ref(false)

// 弹出确认弹窗
function deleteBoundary(id: string) {
  if (!project.value) return
  const boundary = project.value.boundaries.find(b => b.id === id)
  if (!boundary) return
  pendingDeleteBoundary.value = boundary
  showDeleteConfirm.value = true
}

// 取消删除
function cancelDeleteBoundary() {
  if (deletingBoundary.value) return
  showDeleteConfirm.value = false
  pendingDeleteBoundary.value = null
}

// 确认删除：先调后端，再做本地清理与持久化
async function confirmDeleteBoundary() {
  const boundary = pendingDeleteBoundary.value
  if (!boundary || !project.value) return

  deletingBoundary.value = true
  try {
    const res = await $fetch<{
      success: boolean
      data?: { deletedLayers?: number }
      message?: string
    }>('/api/v1/boundary/delete', {
      method: 'POST',
      body: {
        projectId: projectId.value,
        boundaryId: boundary.id
      }
    })

    if (!res.success) {
      push({ tone: 'danger', title: '后端删除失败', description: res.message })
      return
    }

    const layers = res.data?.deletedLayers ?? 0
    push({
      tone: 'success',
      title: '边界已删除',
      description: layers > 0 ? `时序库中共删除 ${layers} 层数据` : '时序库中无该边界的数据'
    })
  }
  catch (err) {
    push({ tone: 'danger', title: '删除请求异常', description: String(err) })
    return
  }
  finally {
    deletingBoundary.value = false
    showDeleteConfirm.value = false
    pendingDeleteBoundary.value = null
  }

  // 本地清理
  const idx = project.value.boundaries.findIndex(b => b.id === boundary.id)
  if (idx !== -1) {
    project.value.boundaries.splice(idx, 1)
    projectState.value = { ...project.value }
    syncProjectFromBoundaries()
  }

  tabs.value = tabs.value.filter(t => t.key !== boundary.id)
  if (activeTab.value === boundary.id) {
    const nextTab = tabs.value[0]
    if (nextTab) {
      activeTab.value = nextTab.key
      loadBoundary(nextTab.key)
    }
    else {
      currentBoundary.value = null
      rawData.value = null
      transformedData.value = null
    }
  }

  scheduleProjectSyncPersist()
}

// 持久化边界到后端
async function persistBoundaries() {
  console.log('[Boundary] persistBoundaries 被调用', {
    projectId: projectId.value,
    hasProject: !!project.value,
    boundariesCount: project.value?.boundaries?.length,
    time: new Date().toISOString()
  })
  if (!project.value || !projectId.value) return
  // 防止无效 projectId
  if (!projectId.value.startsWith('project-')) {
    console.warn('[Boundary] 无效的 projectId，跳过保存:', projectId.value)
    return
  }
  try {
    console.log('[Boundary] 正在保存边界到后端...')
    await projectApi.saveBoundaries(projectId.value, project.value.boundaries)
    console.log('[Boundary] 边界保存成功')
  } catch (err) {
    console.error('[Boundary] 保存边界失败:', err)
  }
}

const handleRelatedComponentsChange = (value: string[]) => {
  form.relatedComponents = value

  if (syncBoundaryFormSilently.value || !currentBoundary.value) {
    return
  }

  saveCurrentFormToBoundary()
  syncProjectFromBoundaries()
  scheduleProjectSyncPersist()
}

// 保存边界
function saveBoundary() {
  if (!project.value || !currentBoundary.value) return

  const idx = project.value.boundaries.findIndex(b => b.id === currentBoundary.value!.id)
  if (idx !== -1) {
    Object.assign(project.value.boundaries[idx], {
      name: form.name,
      filePath: form.filePath,
      columnName: form.columnName,
      timeStep: form.timeStep,
      meaning: form.meaning,
      relatedComponents: setBoundaryRelatedComponentsForActiveCanvas(
        project.value.boundaries[idx],
        project.value.workspace,
        form.relatedComponents
      ),
      interpolateType: form.interpolateType,
      randomDistribution: form.randomDistribution,
      noiseLevel: form.noiseLevel
    })
    syncProjectFromBoundaries()
    scheduleProjectSyncPersist()

    // 更新标签
    const tabIdx = tabs.value.findIndex(t => t.key === currentBoundary.value!.id)
    if (tabIdx !== -1) {
      tabs.value[tabIdx].label = form.name
    }

    push({ tone: 'success', title: '边界已保存' })
  }
}

// 导入原始数据
async function importData() {
  console.log('[Boundary] importData 被调用', { canImport: canImport.value })
  if (!canImport.value) return

  loading.value = true
  try {
    const response = await $fetch<{
      success: boolean
      data: {
        values: number[]
        timestamps: string[]
        xAxisLabel: string
        yAxisLabel: string
      }
      message?: string
    }>('/api/v1/boundary/import', {
      method: 'POST',
      body: {
        filePath: form.filePath,
        columnName: form.columnName,
        timeStep: form.timeStep,
        projectId: projectId.value
      }
    })

    rawData.value = {
      boundaryId: currentBoundary.value?.id ?? '',
      values: response.data.values,
      timestamps: response.data.timestamps,
      xAxisLabel: response.data.xAxisLabel,
      yAxisLabel: response.data.yAxisLabel
    }

    await nextTick()
    updateRawChart()
    console.log('[Boundary] 数据导入成功')
    push({ tone: 'success', title: '数据导入成功' })
  } catch (err) {
    console.error('[Boundary] 数据导入失败:', err)
    push({ tone: 'error', title: '数据导入失败', description: String(err) })
  } finally {
    loading.value = false
  }
}

// 转换数据
async function transformData() {
  console.log('[Boundary] transformData 被调用', { filePath: form.filePath, columnName: form.columnName })
  if (!form.filePath || !form.columnName || !project.value) return

  loading.value = true
  try {
    const response = await $fetch<{
      success: boolean
      data: {
        layers: { layerId: string; layerName: string; values: number[]; timestamps: string[] }[]
      }
      source?: string
    }>('/api/v1/boundary/transform', {
      method: 'POST',
      body: {
        filePath: form.filePath,
        columnName: form.columnName,
        timeStep: form.timeStep,
        interpolateType: form.interpolateType,
        noiseLevel: form.noiseLevel,
        layerConfig: project.value.layerConfig,
        projectId: projectId.value
      }
    })

    transformedData.value = {
      boundaryId: currentBoundary.value?.id ?? '',
      layers: response.data.layers
    }

    await nextTick()
    updateTransformedChart()
    console.log('[Boundary] 数据转换成功')
    push({ tone: 'success', title: '数据转换成功' })
  } catch (err) {
    console.error('[Boundary] 数据转换失败:', err)
    push({ tone: 'error', title: '数据转换失败', description: String(err) })
  } finally {
    loading.value = false
  }
}

// 导出转换后数据
function exportData() {
  if (!transformedData.value) return

  downloadJson(transformedData.value, `boundary_${currentBoundary.value?.id}_transformed.json`)
}

// 提交边界数据
async function submitBoundary() {
  if (!project.value || !currentBoundary.value) return
  if (!transformedData.value || transformedData.value.layers.length === 0) {
    push({ tone: 'warning', title: '请先进行数据转换' })
    return
  }

  console.log('[Boundary] 提交数据:', {
    meaning: form.meaning,
    relatedComponents: form.relatedComponents,
    layers: transformedData.value.layers
  })

  try {
    await $fetch('/api/v1/boundary/submit', {
      method: 'POST',
      body: {
        projectId: projectId.value,
        boundaries: transformedData.value.layers.map(layer => ({
          layerId: layer.layerId,
          values: layer.values,
          timestamps: layer.timestamps,
          meaning: form.meaning,
          boundaryId: currentBoundary.value!.id
          // boundaryId 由后端作为 TS 库 source_id 写入；同一 meaning 不同边界互不覆盖
        }))
      }
    })

    saveCurrentFormToBoundary()
    syncProjectFromBoundaries()
    await flushProjectSyncPersist()

    push({ tone: 'success', title: '边界配置已提交' })
  } catch (err) {
    push({ tone: 'error', title: '提交失败', description: String(err) })
  }
}

// 同步边界到节点（双向同步）
async function syncBoundariesToNodes() {
  console.log('[Boundary] syncBoundariesToNodes 被调用', { time: new Date().toISOString() })
  saveCurrentFormToBoundary()
  syncProjectFromBoundaries()
}

// 更新原始数据图表
function updateRawChart() {
  if (!rawChartRef.value || !rawData.value) {
    console.warn('updateRawChart: ref or data is missing', rawChartRef.value, rawData.value)
    return
  }

  // 销毁旧实例（如果存在）
  if (rawChartInstance) {
    rawChartInstance.dispose()
    rawChartInstance = null
  }

  // 等待 DOM 更新完成
  nextTick(() => {
    if (!rawChartRef.value) return

    // 确保容器有尺寸
    const container = rawChartRef.value
    console.log('Echarts container size:', container.clientWidth, container.clientHeight)

    rawChartInstance = echarts.init(container)

    const option = {
      tooltip: { trigger: 'axis' },
      grid: {
        left: '3%',    // 左侧距离，原默认10%
        right: '3%',   // 右侧距离，原默认10%
        top: '10%',    // 顶部距离，原默认60px
        bottom: '8%', // 底部距离，适配x轴时间标签
        containLabel: true // 关键：所有坐标轴文字都限制在grid内，不会额外撑出空白
      },
      xAxis: {
        type: 'category' as const,
        data: rawData.value!.timestamps,
        name: rawData.value!.xAxisLabel,
        nameLocation: 'middle' as const,
        nameGap: 30
      },
      yAxis: {
        type: 'value' as const,
        name: form.meaning || rawData.value!.yAxisLabel,
        nameLocation: 'middle' as const,
        nameGap: 40
      },
      series: [{
        data: rawData.value!.values,
        type: 'line' as const,
        smooth: true,
        symbol: 'none',
        lineStyle: { width: 2 },
        itemStyle: { color: '#165DFF' }
      }]
    }

    rawChartInstance.setOption(option)
    rawChartInstance.resize()
  })
}

// 更新转换后数据图表（每层单独一个图）
function updateTransformedChart() {
  if (!transformedData.value) return

  nextTick(() => {
    // 为每一层渲染独立的图表
    for (const layer of transformedData.value!.layers) {
      const el = document.getElementById(`layer-chart-${layer.layerId}`)
      if (!el) continue

      let instance = transformedChartInstances[layer.layerId]
      if (instance) {
        instance.dispose()
      }

      instance = echarts.init(el)
      transformedChartInstances[layer.layerId] = instance

      instance.setOption({
        title: {
          text: layer.layerName,
          textStyle: { fontSize: 13, fontWeight: 'normal' },
          left: 'center',
          top: 5
        },
        tooltip: { trigger: 'axis' },
        grid: {
          left: '3%', right: '3%', top: 35, bottom: '8%', containLabel: true
        },
        xAxis: {
          type: 'category',
          data: layer.timestamps,
          name: rawData.value?.xAxisLabel || '时间',
          nameLocation: 'middle',
          nameGap: 30
        },
        yAxis: {
          type: 'value',
          name: form.meaning || rawData.value?.yAxisLabel || '',
          nameLocation: 'middle',
          nameGap: 40
        },
        series: [{
          data: layer.values,
          type: 'line',
          smooth: true,
          symbol: 'none',
          lineStyle: { width: 2 },
          itemStyle: { color: '#165DFF' }
        }]
      })
    }
  })
}

// 清理图表
onBeforeUnmount(() => {
  rawChartInstance?.dispose()
  Object.values(transformedChartInstances).forEach(inst => inst.dispose())
})

// 窗口调整时重新绘制图表
onMounted(() => {
  window.addEventListener('resize', () => {
    rawChartInstance?.resize()
    Object.values(transformedChartInstances).forEach(inst => inst.resize())
  })
})

useHead(() => ({
  title: project.value ? `${project.value.name} - 边界配置` : '边界配置 - SynerRoll'
}))

// 返回编辑页
async function goBack() {
  console.log('[Boundary] goBack 被调用', { projectId: projectId.value, time: new Date().toISOString() })
  if (project.value) {
    try {
      console.log('[Boundary] 开始保存流程...')
      // 保存当前表单
      saveCurrentFormToBoundary()
      syncProjectFromBoundaries()
      await flushProjectSyncPersist()
      // 导航前刷新画布页数据
      await refreshNuxtData(`editor-project-${projectId.value}`)
      console.log('[Boundary] 保存流程完成，准备导航')
    } catch (err) {
      console.error('[Boundary] goBack 中出错:', err)
    }
  }
  router.push(`/editor/${projectId.value}`)
}

function downloadJson(data: any, filename: string) {
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}

// 监听数据加载完成，初始化边界
watch(() => data.value?.project, (proj) => {
  if (proj) {
    projectState.value = proj
    initBoundaries()
  }
}, { immediate: true })

// 监听 projectState 变化，加载边界数据
watch(projectState, () => {
  if (projectState.value && tabs.value.length > 0 && !currentBoundary.value) {
    const firstTab = tabs.value[0]
    if (firstTab) {
      loadBoundary(firstTab.key)
    }
  }
}, { immediate: true })

watch(
  () => availableRelatedNodes.value.map(node => node.id).join('|'),
  () => {
    if (!currentBoundary.value || syncBoundaryFormSilently.value) {
      return
    }

    const allowedNodeIds = new Set(availableRelatedNodes.value.map(node => node.id))
    const filteredRelatedComponents = form.relatedComponents.filter(nodeId => allowedNodeIds.has(nodeId))

    if (sameStringArray(filteredRelatedComponents, form.relatedComponents)) {
      return
    }

    syncBoundaryFormSilently.value = true
    form.relatedComponents = filteredRelatedComponents
    syncBoundaryFormSilently.value = false

    saveCurrentFormToBoundary()
    syncProjectFromBoundaries()
    scheduleProjectSyncPersist()
  }
)

// ============================================================
// 修复问题一：为所有表单字段添加实时保存 watch
// ============================================================

// name 字段实时保存
watch(() => form.name, (newName) => {
  if (!currentBoundary.value || syncBoundaryFormSilently.value) return
  if (newName === currentBoundary.value.name) return
  saveCurrentFormToBoundary()
  scheduleProjectSyncPersist()
})

// filePath 字段实时保存（同时更新共享缓存）
watch(() => form.filePath, (newFilePath) => {
  if (!currentBoundary.value || syncBoundaryFormSilently.value) return
  if (newFilePath === currentBoundary.value.filePath) return
  saveCurrentFormToBoundary()
  if (newFilePath.trim()) {
    updateSharedFilePathCache(currentBoundary.value.id, newFilePath)
  }
  scheduleProjectSyncPersist()
})

// columnName 字段实时保存
watch(() => form.columnName, (newColumnName) => {
  if (!currentBoundary.value || syncBoundaryFormSilently.value) return
  if (newColumnName === currentBoundary.value.columnName) return
  saveCurrentFormToBoundary()
  scheduleProjectSyncPersist()
})

// timeStep 字段实时保存
watch(() => form.timeStep, (newTimeStep) => {
  if (!currentBoundary.value || syncBoundaryFormSilently.value) return
  if (newTimeStep === currentBoundary.value.timeStep) return
  saveCurrentFormToBoundary()
  scheduleProjectSyncPersist()
})

// meaning 字段实时保存
watch(() => form.meaning, (newMeaning) => {
  if (!currentBoundary.value || syncBoundaryFormSilently.value) return
  if (newMeaning === currentBoundary.value.meaning) return
  saveCurrentFormToBoundary()
  scheduleProjectSyncPersist()
})

// interpolateType 字段实时保存
watch(() => form.interpolateType, (newVal) => {
  if (!currentBoundary.value || syncBoundaryFormSilently.value) return
  if (newVal === currentBoundary.value.interpolateType) return
  saveCurrentFormToBoundary()
  scheduleProjectSyncPersist()
})

// randomDistribution 字段实时保存
watch(() => form.randomDistribution, (newVal) => {
  if (!currentBoundary.value || syncBoundaryFormSilently.value) return
  if (newVal === currentBoundary.value.randomDistribution) return
  saveCurrentFormToBoundary()
  scheduleProjectSyncPersist()
})

// noiseLevel 字段实时保存
watch(() => form.noiseLevel, (newVal) => {
  if (!currentBoundary.value || syncBoundaryFormSilently.value) return
  if (newVal === currentBoundary.value.noiseLevel) return
  saveCurrentFormToBoundary()
  scheduleProjectSyncPersist()
})
</script>

<template>
  <div class="h-screen flex flex-col bg-app-bg">
    <!-- 头部 -->
    <header class="flex items-center h-14 px-4 bg-primary border-b border-app-border">
      <button
        class="inline-flex items-center gap-1 px-3 h-8 rounded text-sm text-white hover:bg-white/10"
        @click="goBack"
      >
        <svg class="w-4 h-4" viewBox="0 0 16 16" fill="none">
          <path d="M10 12L6 8L10 4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>
        返回
      </button>
      <div class="ml-4 text-sm text-white">
        {{ project?.name }} - 边界配置
      </div>
    </header>

    <div class="flex-1 min-h-0 flex gap-2 p-2">
      <!-- 左侧：边界列表 -->
      <aside class="panel-card w-56 flex flex-col">
        <div class="flex items-center justify-between px-3 h-12 border-b border-app-border">
          <span class="text-sm font-medium">边界列表</span>
          <button
            class="inline-flex items-center justify-center w-6 h-6 rounded hover:bg-white/10"
            title="新建边界"
            @click="createBoundary"
          >
            <svg class="w-4 h-4" viewBox="0 0 16 16" fill="none">
              <path d="M8 3V13M3 8H13" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
            </svg>
          </button>
        </div>

        <div class="flex-1 overflow-y-auto">
          <div
            v-for="tab in tabs"
            :key="tab.key"
            class="flex items-center px-3 h-11 cursor-pointer transition-colors"
            :class="activeTab === tab.key ? 'bg-primary-soft' : 'hover:bg-app-panel-soft'"
            @click="activeTab = tab.key"
            @dblclick="startRename(tab.key, tab.label)"
          >
            <input
              v-if="editingBoundaryId === tab.key"
              v-model="editingBoundaryName"
              class="flex-1 h-7 px-2 text-sm border border-primary rounded bg-app-input focus:outline-none"
              @blur="confirmRename"
              @keydown.enter="confirmRename"
              @keydown.esc="cancelRename"
              @click.stop
              :ref="el => { if (el) renameInputEl = el as HTMLInputElement }"
            />
            <span v-else class="flex-1 text-sm truncate px-4">{{ tab.label }}</span>
            <button
              v-if="editingBoundaryId !== tab.key"
              class="w-5 h-5 flex items-center justify-center rounded hover:bg-white/20"
              @click.stop="deleteBoundary(tab.key)"
            >
              <svg class="w-3 h-3" viewBox="0 0 16 16" fill="none">
                <path d="M12 4L4 12M4 4L12 12" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
              </svg>
            </button>
          </div>
        </div>
      </aside>

      <!-- 右侧：边界配置 -->
      <main class="flex-1 flex flex-col gap-2 overflow-hidden" v-if="currentBoundary">
        <!-- 第一个面板：基本配置 + 原始数据图表 -->
        <div class="panel-card px-8 py-4 flex flex-col flex-1 min-h-0 space-y-4 overflow-hidden">
          <!-- 第一行：导入配置 -->
          <div class="flex items-center gap-6">
            <div class="flex items-center gap-2 w-1/2">
              <label class="w-16 text-sm text-app shrink-0">导入文件</label>
              <PropertyText
                v-model="form.filePath"
                placeholder="C:\Users\...\data.csv"
              />
            </div>
            <div class="flex items-center gap-2 w-1/6">
              <label class="w-16 text-sm text-app shrink-0 text-center">列名</label>
              <PropertyText
                v-model="form.columnName"
                placeholder="wind_speed"
              />
            </div>
            <div class="flex items-center gap-2 w-1/6">
              <label class="w-16 text-sm text-app shrink-0">时间尺度</label>
              <PropertySelect
                v-model="form.timeStep"
                :options="TIME_STEP_OPTIONS"
              />
            </div>
            <div class="flex items-center gap-2 w-1/6">
              <label class="w-16 text-sm text-app shrink-0">物理含义</label>
              <PropertySelect
                v-model="form.meaning"
                :options="meaningOptions"
              />
            </div>
            <div class="flex items-center gap-2 w-1/6 justify-end">
              <AppButton
                label="导入"
                tone="primary"
                :disabled="!canImport"
                @click="importData"
              />
              <AppButton
                label="预览"
                tone="primary"
                @click="rawData = null"
              />
              <AppButton
                label="清除"
                tone="danger"
                @click="rawData = null"
              />
            </div>
          </div>

          <!-- 第二行：关联组件 -->
          <div class="flex items-center gap-3">
            <div class="flex items-center gap-2 flex-1 ">
              <label class="w-16 text-sm text-app shrink-0">关联组件</label>
              <div class="flex-1 relative">
                <PropertyMultiSelect
                  v-model="form.relatedComponents"
                  @update:model-value="handleRelatedComponentsChange"
                  :options="availableRelatedNodes.map(n => ({ label: n.data?.label || n.id, value: n.id }))"
                  placeholder="请选择组件..."
                />
              </div>
            </div>
          </div>

          <!-- 原始数据图表 -->
          <div class="relative flex-1 min-h-0">
            <div v-if="!rawData" class="absolute inset-0 flex flex-col items-center justify-center text-app-muted border border-dashed border-app-border rounded">
              <svg class="w-10 h-10 mb-2" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
                <path d="M3 3v18h18M7 16l4-4 4 4 5-6" stroke-linecap="round" stroke-linejoin="round"/>
              </svg>
              <span class="text-sm">尚未导入数据</span>
            </div>
            <div ref="rawChartRef" class="absolute inset-0" :class="{ 'invisible': !rawData }"></div>
          </div>
        </div>

        <!-- 第二个面板：转换配置 + 转换后数据图表 -->
        <div class="panel-card px-8 py-4 flex flex-col flex-1 min-h-0 space-y-4 overflow-hidden">
          <!-- 转换配置 -->
          <div class="flex items-center gap-3">
            <div class="flex items-center gap-2 w-1/6">
              <label class="w-16 text-sm text-app shrink-0">插值方式</label>
              <PropertySelect
                v-model="form.interpolateType"
                :options="INTERPOLATE_OPTIONS"
              />
            </div>
            <div class="flex items-center gap-2 w-1/6">
              <label class="w-16 text-sm text-app shrink-0">随机分布</label>
              <PropertySelect
                v-model="form.randomDistribution"
                :options="DISTRIBUTION_OPTIONS"
              />
            </div>
            <div class="flex items-center gap-2 w-1/6">
              <label class="w-16 text-sm text-app shrink-0">噪声水平</label>
              <input
                v-model.number="form.noiseLevel"
                type="number"
                step="0.01"
                min="0"
                class="flex-1 h-8 px-2 rounded border border-app-border bg-app-input text-sm"
              />
            </div>
            <div class="flex items-center gap-2 flex-1 justify-end">
              <AppButton
                label="转换"
                tone="primary"
                :disabled="!form.filePath || !form.columnName"
                @click="transformData"
              />
              <AppButton
                label="导出"
                tone="primary"
                :disabled="!transformedData"
                @click="exportData"
              />
              <AppButton
                label="提交"
                tone="green"
                @click="submitBoundary"
              />
            </div>
          </div>

          <div class="relative w-full h-full overflow-y-auto">
            <div v-if="!transformedData" class="absolute inset-0 flex flex-col items-center justify-center text-app-muted border border-dashed border-app-border rounded">
              <svg class="w-10 h-10 mb-2" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
                <path d="M3 3v18h18M7 16l4-4 4 4 5-6" stroke-linecap="round" stroke-linejoin="round"/>
              </svg>
              <span class="text-sm">点击转换后显示数据</span>
            </div>
            <div v-else class="grid grid-cols-1 gap-3 p-1">
              <div
                v-for="layer in transformedData.layers"
                :key="layer.layerId"
                :id="`layer-chart-${layer.layerId}`"
                class="w-full"
                style="height: 280px"
              ></div>
            </div>
          </div>
        
        </div>

      </main>

      <!-- 无边界时的提示 -->
      <main v-else class="flex-1 flex items-center justify-center text-app-muted">
        <div class="text-center">
          <p class="text-lg mb-2">暂无边界配置</p>
          <p class="text-sm">请在画布中添加需要边界数据的组件</p>
          <AppButton
            label="创建边界"
            tone="primary"
            class="mt-4"
            @click="createBoundary"
          />
        </div>
      </main>
    </div>

    <!-- 删除确认弹窗 -->
    <AppModal
      :open="showDeleteConfirm"
      title="删除边界"
      size="sm"
      @close="cancelDeleteBoundary"
    >
      <div class="px-4 py-2">
        <p class="text-sm text-app">
          确定要删除边界「<span class="font-medium">{{ pendingDeleteBoundary?.name }}</span>」吗？
        </p>
        <p class="text-xs text-app-muted mt-2 leading-relaxed">
          该边界在时序数据库中的全部层数据（按物理含义
          <span class="font-mono">{{ pendingDeleteBoundary?.meaning }}</span>
          检索）都将被删除，此操作不可撤销。
        </p>
      </div>
      <template #footer>
        <AppButton label="取消" tone="neutral" :disabled="deletingBoundary" @click="cancelDeleteBoundary" />
        <AppButton
          :label="deletingBoundary ? '删除中...' : '确认删除'"
          tone="danger"
          :disabled="deletingBoundary"
          @click="confirmDeleteBoundary"
        />
      </template>
    </AppModal>

    <!-- 加载遮罩 -->
    <div
      v-if="loading"
      class="fixed inset-0 bg-black/20 flex items-center justify-center z-50"
    >
      <div class="bg-app-panel rounded-lg px-6 py-4 text-sm">处理中...</div>
    </div>
  </div>
</template>
