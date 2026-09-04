<script setup lang="ts">
import type { CanvasClipboard, CanvasData, CanvasSelection, FlowNode } from '~~/types/canvas'
import type { Project } from '~~/types/project'
import type { AlgorithmConfig, LayerDefinition } from '~~/types/simulation'

import { componentDefinitionMap } from '~~/config/component-meta'
import { editorMenus, toolbarConfig } from '~~/config/system-config'
import { useProjectApi } from '~~/composables/api/useProjectApi'
import { useEditorHistory } from '~~/state/editor'
import { useProjectCache } from '~~/state/project'
import { useEditorUiState, useToastCenter } from '~~/state/ui'
import { buildBackendPayload } from '~~/utils/backend-export'
import {
  alignSelectedNodes,
  appendCanvas,
  buildClipboard,
  deleteSelectionFromCanvas,
  distributeSelectedNodes,
  findCanvasById,
  matchSelectedNodeSize,
  pasteClipboard,
  removeCanvas,
  reorderSelectedNodes,
  replaceCanvas,
  resetPasteCount,
  updateNodeFromFields
} from '~~/utils/canvas'
import { syncBoundaryStateFromNodes } from '~~/utils/boundary-sync'
import { downloadJson } from '~~/utils/download'

const route = useRoute()
const projectId = computed(() => String(route.params.projectId ?? ''))
const projectApi = useProjectApi()
const { setProject } = useProjectCache()
const { push } = useToastCenter()

const uiState = useEditorUiState(projectId.value)
const history = useEditorHistory(projectId.value)
const editorProject = useState<Project | null>(`editor-project-${projectId.value}`, () => null)
const editorClipboard = useState<CanvasClipboard | null>(`editor-clipboard-${projectId.value}`, () => null)
const selection = ref<CanvasSelection>({
  nodeIds: [],
  edgeIds: [],
  primaryNodeId: null,
  primaryEdgeId: null
})
const isFullscreen = ref(false)
const canvasWorkspaceRef = ref<{
  fitToView: () => void
  zoomIn: () => void
  zoomOut: () => void
  setZoomPercent: (value: number) => void
  beginInit: () => void
  refreshLayout: () => void | Promise<void>
  toggleGrid: () => void
  setBackgroundPattern: (pattern: 'grid' | 'dots') => void
} | null>(null)

// 时层配置弹窗
const showLayerConfigModal = ref(false)

// 算法配置弹窗
const showAlgorithmConfigModal = ref(false)

// [废弃 2026-07-14] 仿真解析弹窗 — 功能已迁移到计算任务系统
// const showSimulationParseModal = ref(false)

const handleLayerConfigConfirm = async (layers: LayerDefinition[]) => {
  if (!project.value) {
    return
  }

  const nextLayerConfig = { layers }

  try {
    await projectApi.saveLayerConfig(project.value.id, { layerConfig: nextLayerConfig })
    project.value.layerConfig = nextLayerConfig
    push({ tone: 'success', title: '时层配置已更新' })
  }
  catch (saveError) {
    console.error(saveError)
    push({ tone: 'danger', title: '时层配置保存失败', description: '请稍后重试。' })
  }
}

const handleAlgorithmConfigConfirm = async (config: AlgorithmConfig) => {
  if (!project.value) {
    return
  }

  try {
    await projectApi.saveAlgorithmConfig(project.value.id, { algorithm: config, solverConfig: project.value.solverConfig! })
    project.value.algorithm = config
    push({ tone: 'success', title: '算法配置已更新' })
  }
  catch (saveError) {
    console.error(saveError)
    push({ tone: 'danger', title: '算法配置保存失败', description: '请稍后重试。' })
  }
}

const { data, pending, error } = await useAsyncData(
  `editor-project-${projectId.value}`,
  () => projectApi.getProject(projectId.value)
)

watchEffect(() => {
  if (!data.value?.project) {
    return
  }

  editorProject.value = data.value.project
  setProject(data.value.project)
})

const project = computed({
  get: () => editorProject.value,
  set: value => {
    editorProject.value = value
    if (value) {
      setProject(value)
    }
  }
})

const activeCanvas = computed(() =>
  project.value ? findCanvasById(project.value.workspace) : null
)

const selectedNode = computed<FlowNode | null>(() =>
  activeCanvas.value?.nodes.find(node => node.id === selection.value.primaryNodeId) ?? null
)

const toolbarValues = computed<Record<string, string | number | boolean>>(() => {
  const gridVisible = activeCanvas.value?.pageConfig.gridVisible ?? true
  const backgroundPattern = activeCanvas.value?.pageConfig.backgroundPattern ?? 'grid'
  const gridSize = activeCanvas.value?.pageConfig.gridSize ?? 15

  const gridType = gridVisible ? backgroundPattern : 'hidden'

  return {
    'canvas-bg-color': activeCanvas.value?.pageConfig.backgroundColor ?? '#FFFFFF',
    'canvas-width': activeCanvas.value?.pageConfig.width ?? 1366,
    'canvas-height': activeCanvas.value?.pageConfig.height ?? 751,
    'canvas-size-type': (() => {
      const w = activeCanvas.value?.pageConfig.width ?? 1366
      const h = activeCanvas.value?.pageConfig.height ?? 751
      if (w === h) return 'square'
      if (w < h) return 'portrait'
      return 'landscape'
    })(),
    'grid-size': String(gridSize),
    'grid-type': gridType,
    'show-component-name': activeCanvas.value?.pageConfig.showComponentName ?? true,
    'show-parameter-tag': activeCanvas.value?.pageConfig.showParameterTag ?? false,
    'show-ports': activeCanvas.value?.pageConfig.showPorts ?? false,
    'label-language': activeCanvas.value?.pageConfig.labelLanguage ?? 'chinese',
    'rotation-input': selectedNode.value?.data.style.rotation ?? 0,
    'x-input': Math.round(selectedNode.value?.position.x ?? 0),
    'y-input': Math.round(selectedNode.value?.position.y ?? 0),
    'width-input': selectedNode.value?.data.style.width ?? 0,
    'height-input': selectedNode.value?.data.style.height ?? 0,
    'line-color': selectedNode.value?.data.style.strokeColor ?? '#475467',
    'line-width': selectedNode.value?.data.style.strokeWidth ?? 1.5
  }
})

interface ToolbarActionPayload {
  key: string
  value?: string | number | boolean
}

const toolbarGroups = computed(() => toolbarConfig[uiState.value.activeMenu])
const zoomPercent = computed(() => Math.round((activeCanvas.value?.viewport.zoom ?? 1) * 100))
const editorRailWidth = computed(() => (uiState.value.leftCollapsed ? 54 : 320))
const propertiesRailWidth = computed(() => (uiState.value.rightCollapsed ? 54 : 320))
const contentGridStyle = computed(() => ({
  gridTemplateColumns: `${editorRailWidth.value}px minmax(0, 1fr) ${propertiesRailWidth.value}px`
}))

useHead(() => ({
  title: project.value ? `${project.value.name} - SynerRoll` : 'SynerRoll 编辑器'
}))

let saveTimer: ReturnType<typeof setTimeout> | null = null

const resetSelection = () => {
  selection.value = { nodeIds: [], edgeIds: [], primaryNodeId: null, primaryEdgeId: null }
  uiState.value.activePropertyTab = 'page'
}

const syncWorkspaceWithBoundaries = (workspace: Project['workspace']) => {
  if (!project.value) {
    return {
      workspace,
      boundaries: [] as Project['boundaries']
    }
  }

  return syncBoundaryStateFromNodes(workspace, project.value.boundaries ?? [])
}

const scheduleSave = () => {
  if (!project.value) {
    return
  }

  if (saveTimer) {
    clearTimeout(saveTimer)
  }

  saveTimer = setTimeout(async () => {
    if (!project.value) {
      return
    }

    try {
      await projectApi.saveCanvas(project.value.id, {
        workspace: project.value.workspace
      })
      await projectApi.saveBoundaries(project.value.id, project.value.boundaries)
    }
    catch (saveError) {
      console.error(saveError)
      push({ tone: 'danger', title: '自动保存失败', description: '请稍后重试。' })
    }
  }, 600)
}

const applyWorkspace = (workspace: Project['workspace']) => {
  if (!project.value) {
    return
  }

  const syncedState = syncWorkspaceWithBoundaries(workspace)

  project.value.workspace = syncedState.workspace
  project.value.boundaries = syncedState.boundaries
  project.value.updateTime = new Date().toISOString()

  scheduleSave()
}

const commitAndApplyCanvas = (nextCanvas: CanvasData, label: string) => {
  if (!project.value || !activeCanvas.value) {
    return
  }

  history.commit(project.value.workspace, label)
  applyWorkspace(replaceCanvas(project.value.workspace, nextCanvas))
}

// 将旋转角度规约为 0~360 度之间的有效值
const normalizeRotation = (value: number): number => {
  return ((value % 360) + 360) % 360
}

const mutateSelectedNode = (
  updater: (node: FlowNode) => FlowNode,
  label: string
) => {
  if (!activeCanvas.value || !selectedNode.value) {
    return
  }

  const nextCanvas: CanvasData = {
    ...activeCanvas.value,
    nodes: activeCanvas.value.nodes.map(node => (node.id === selectedNode.value?.id ? updater(node) : node))
  }
  commitAndApplyCanvas(nextCanvas, label)
}

const handleCanvasUpdate = (nextCanvas: CanvasData) => {
  commitAndApplyCanvas(nextCanvas, '编辑画布')
}

const copyCurrentSelection = () => {
  if (!activeCanvas.value || !project.value) {
    return false
  }

  const clipboard = buildClipboard(activeCanvas.value, selection.value)

  if (!clipboard) {
    push({ tone: 'info', title: '当前没有可复制的元件' })
    return false
  }

  resetPasteCount()
  editorClipboard.value = clipboard
  push({ tone: 'success', title: '已复制当前选中元素' })

  return true
}

const handleToolbarAction = (
  action: string | ToolbarActionPayload,
  value?: string | number | boolean
) => {
  if (!activeCanvas.value || !project.value) {
    return
  }

  const actionKey = typeof action === 'string' ? action : action.key
  const actionValue = typeof action === 'string' ? value : action.value
  value = actionValue

  if (actionKey === 'undo') {
    handleUndo()
    return
  }

  if (actionKey === 'redo') {
    handleRedo()
    return
  }

  if (actionKey.startsWith('align-')) {
    commitAndApplyCanvas(alignSelectedNodes(activeCanvas.value, selection.value, actionKey), '节点对齐')
    return
  }

  if (actionKey === 'distribute-horizontal' || actionKey === 'distribute-vertical') {
    commitAndApplyCanvas(
      distributeSelectedNodes(activeCanvas.value, selection.value, actionKey === 'distribute-horizontal' ? 'horizontal' : 'vertical'),
      '节点分布'
    )
    return
  }

  if (actionKey === 'match-width' || actionKey === 'match-height' || actionKey === 'match-size') {
    commitAndApplyCanvas(
      matchSelectedNodeSize(
        activeCanvas.value,
        selection.value,
        actionKey === 'match-width' ? 'width' : actionKey === 'match-height' ? 'height' : 'size'
      ),
      '尺寸匹配'
    )
    return
  }

  if (['bring-forward', 'send-backward', 'bring-front', 'send-back'].includes(actionKey)) {
    const mode =
      actionKey === 'bring-front'
        ? 'front'
        : actionKey === 'send-back'
          ? 'back'
          : actionKey === 'bring-forward'
            ? 'forward'
            : 'backward'
    commitAndApplyCanvas(reorderSelectedNodes(activeCanvas.value, selection.value, mode), '调整层级')
    return
  }

  if (actionKey === 'rotation-input' && typeof actionValue === 'number' && selectedNode.value) {
    mutateSelectedNode(node => updateNodeFromFields(node, { rotation: normalizeRotation(actionValue) }), '旋转节点')
    return
  }

  if (actionKey === 'rotate-left' && selectedNode.value) {
    mutateSelectedNode(node => updateNodeFromFields(node, { rotation: normalizeRotation((node.data?.style?.rotation ?? 0) - 90) }), '旋转节点')
    return
  }

  if (actionKey === 'rotate-right' && selectedNode.value) {
    mutateSelectedNode(node => updateNodeFromFields(node, { rotation: normalizeRotation((node.data?.style?.rotation ?? 0) + 90) }), '旋转节点')
    return
  }

  if (['x-input', 'y-input', 'width-input', 'height-input'].includes(actionKey) && typeof actionValue === 'number' && selectedNode.value) {
    if (actionKey === 'x-input' || actionKey === 'y-input') {
      mutateSelectedNode(
        node => ({
          ...node,
          position: {
            ...node.position,
            [actionKey === 'x-input' ? 'x' : 'y']: value
          }
        }),
        '更新节点位置'
      )
      return
    }

    mutateSelectedNode(
      node =>
        updateNodeFromFields(node, {
          [actionKey === 'width-input' ? 'width' : 'height']: value
        }),
      '更新节点尺寸'
    )
    return
  }

  if (actionKey === 'copy') {
    copyCurrentSelection()
    return
  }

  if (actionKey === 'cut') {
    copyCurrentSelection()
    commitAndApplyCanvas(deleteSelectionFromCanvas(activeCanvas.value, selection.value), '剪切元素')
    resetSelection()
    return
  }

  if (actionKey === 'duplicate') {
    const clipboard = buildClipboard(activeCanvas.value, selection.value)
    const pasted = pasteClipboard(activeCanvas.value, clipboard)
    if (pasted.selection.nodeIds.length === 0 && pasted.selection.edgeIds.length === 0) {
      push({ tone: 'info', title: '当前没有可复制的元件' })
      return
    }
    commitAndApplyCanvas(pasted.canvas, '复制节点')
    selection.value = pasted.selection
    return
  }

  if (actionKey === 'paste') {
    const pasted = pasteClipboard(activeCanvas.value, editorClipboard.value)
    if (pasted.selection.nodeIds.length === 0 && pasted.selection.edgeIds.length === 0) {
      push({ tone: 'info', title: '剪贴板为空' })
      return
    }
    commitAndApplyCanvas(pasted.canvas, '粘贴节点')
    selection.value = pasted.selection
    return
  }

  if (actionKey === 'remove') {
    commitAndApplyCanvas(deleteSelectionFromCanvas(activeCanvas.value, selection.value), '删除元素')
    resetSelection()
    return
  }

  if (actionKey === 'fit-view') {
    canvasWorkspaceRef.value?.fitToView()
    return
  }

  if (actionKey === 'zoom-in') {
    canvasWorkspaceRef.value?.zoomIn()
    return
  }

  if (actionKey === 'zoom-out') {
    canvasWorkspaceRef.value?.zoomOut()
    return
  }

  if (actionKey === 'toggle-grid' && typeof actionValue === 'boolean') {
    canvasWorkspaceRef.value?.beginInit()
    canvasWorkspaceRef.value?.toggleGrid()

    return
  }

  if (actionKey === 'grid-style' && typeof actionValue === 'string') {
    canvasWorkspaceRef.value?.beginInit()
    canvasWorkspaceRef.value?.setBackgroundPattern(actionValue as 'grid' | 'dots')

    return
  }

  if (actionKey === 'canvas-bg-color' && typeof actionValue === 'string') {
    const nextCanvas: CanvasData = {
      ...activeCanvas.value,
      pageConfig: {
        ...activeCanvas.value.pageConfig,
        backgroundColor: actionValue
      }
    }
    commitAndApplyCanvas(nextCanvas, '设置背景颜色')
    return
  }

  if (actionKey === 'canvas-width' && typeof actionValue === 'number') {
    const nextCanvas: CanvasData = {
      ...activeCanvas.value,
      pageConfig: {
        ...activeCanvas.value.pageConfig,
        width: actionValue
      }
    }
    commitAndApplyCanvas(nextCanvas, '设置画布宽度')
    return
  }

  if (actionKey === 'canvas-height' && typeof actionValue === 'number') {
    const nextCanvas: CanvasData = {
      ...activeCanvas.value,
      pageConfig: {
        ...activeCanvas.value.pageConfig,
        height: actionValue
      }
    }
    commitAndApplyCanvas(nextCanvas, '设置画布高度')
    return
  }

  if (actionKey === 'canvas-size-type' && typeof actionValue === 'string') {
    let width = 1500
    let height = 1050
    if (actionValue === 'portrait') {
      width = 1050
      height = 1500
    } else if (actionValue === 'square') {
      width = 1000
      height = 1000
    }
    const nextCanvas: CanvasData = {
      ...activeCanvas.value,
      pageConfig: {
        ...activeCanvas.value.pageConfig,
        width,
        height
      }
    }
    commitAndApplyCanvas(nextCanvas, '设置画布尺寸')
    return
  }

  if (actionKey === 'grid-size' && typeof actionValue === 'string') {
    const nextCanvas: CanvasData = {
      ...activeCanvas.value,
      pageConfig: {
        ...activeCanvas.value.pageConfig,
        gridSize: Number(actionValue)
      }
    }
    commitAndApplyCanvas(nextCanvas, '设置网格大小')
    return
  }

  if (actionKey === 'grid-type' && typeof actionValue === 'string') {
    const isHidden = actionValue === 'hidden'
    const nextCanvas: CanvasData = {
      ...activeCanvas.value,
      pageConfig: {
        ...activeCanvas.value.pageConfig,
        gridVisible: !isHidden,
        backgroundPattern: isHidden ? 'grid' : actionValue as 'grid' | 'dots'
      }
    }
    commitAndApplyCanvas(nextCanvas, '设置网格类型')
    return
  }

  if (actionKey === 'show-component-name' && typeof actionValue === 'boolean') {
    const nextCanvas: CanvasData = {
      ...activeCanvas.value,
      pageConfig: {
        ...activeCanvas.value.pageConfig,
        showComponentName: actionValue
      }
    }
    commitAndApplyCanvas(nextCanvas, '设置显示元件名称')
    return
  }

  if (actionKey === 'show-parameter-tag' && typeof actionValue === 'boolean') {
    const nextCanvas: CanvasData = {
      ...activeCanvas.value,
      pageConfig: {
        ...activeCanvas.value.pageConfig,
        showParameterTag: actionValue
      }
    }
    commitAndApplyCanvas(nextCanvas, '设置显示参数标签')
    return
  }

  if (actionKey === 'show-ports' && typeof actionValue === 'boolean') {
    const nextCanvas: CanvasData = {
      ...activeCanvas.value,
      pageConfig: {
        ...activeCanvas.value.pageConfig,
        showPorts: actionValue
      }
    }
    commitAndApplyCanvas(nextCanvas, '设置显示接口标签')
    return
  }

  if (actionKey === 'label-language' && typeof actionValue === 'string') {
    const nextCanvas: CanvasData = {
      ...activeCanvas.value,
      pageConfig: {
        ...activeCanvas.value.pageConfig,
        labelLanguage: actionValue as 'chinese' | 'english'
      }
    }
    commitAndApplyCanvas(nextCanvas, '设置标签语言')
    return
  }


  if (actionKey === 'line-color' && typeof actionValue === 'string' && selectedNode.value) {
    mutateSelectedNode(node => updateNodeFromFields(node, { strokeColor: actionValue }), '设置线条颜色')
    return
  }

  if (actionKey === 'line-width' && typeof actionValue === 'number' && selectedNode.value) {
    mutateSelectedNode(node => updateNodeFromFields(node, { strokeWidth: actionValue }), '设置线条宽度')
    return
  }

  if (actionKey === 'export-project') {
    downloadJson(`${project.value.name}.json`, project.value)
    return
  }

  if (actionKey === 'export-backend') {
    downloadJson(`${project.value.name}-backend.json`, buildBackendPayload(project.value))
    push({ tone: 'success', title: '后端载荷已导出', description: '已按当前仿真选定画布生成 JSON 载荷。' })
    return
  }

  if (actionKey === 'goto-simulation') {
    navigateTo(`/simulation/${project.value.id}`)
    return
  }

  if (actionKey === 'goto-result') {
    navigateTo(`/result/${project.value.id}`)
    return
  }

  if (actionKey === 'layer-config') {
    showLayerConfigModal.value = true
    return
  }

  if (actionKey === 'algorithm-config') {
    showAlgorithmConfigModal.value = true
    return
  }

  if (actionKey === 'boundary-config') {
    navigateTo(`/boundary/${projectId.value}`)
    return
  }

  if (actionKey === 'simulation-parse') {
    // 计算任务方案：仿真计算 → 跳转到任务页，预填 projectId/canvasId
    const canvas = activeCanvas.value
    const qs = new URLSearchParams()
    if (projectId.value) qs.set('projectId', projectId.value)
    if (canvas) qs.set('canvasId', canvas.id)
    qs.set('create', '1')
    void navigateTo(`/tasks${qs.toString() ? `?${qs}` : ''}`)
    return
  }

  if (actionKey === 'capacity-planning') {
    const qs = new URLSearchParams({ canvasId: activeCanvas.value.id })
    void navigateTo(`/capacity-planning/${project.value.id}?${qs}`)
    return
  }

  if (actionKey === 'select-all') {
    if (!activeCanvas.value) {
      return
    }
    const allNodeIds = activeCanvas.value.nodes.map(node => node.id)
    const allEdgeIds = activeCanvas.value.edges.map(edge => edge.id)
    selection.value = {
      nodeIds: allNodeIds,
      edgeIds: allEdgeIds,
      primaryNodeId: allNodeIds[0] ?? null,
      primaryEdgeId: allEdgeIds[0] ?? null
    }
    return
  }

  if (actionKey === 'export-canvas') {
    downloadJson(`${project.value?.name ?? 'canvas'}.json`, project.value)
    push({ tone: 'success', title: '画布已导出' })
    return
  }

  if (actionKey === 'help') {
    push({ tone: 'info', title: '帮助', description: '右键点击元件或画布空白处查看快捷操作。' })
    return
  }
}

const handleSelectionChange = (nextSelection: CanvasSelection) => {
  selection.value = nextSelection

  if (nextSelection.primaryNodeId || nextSelection.primaryEdgeId) {
    uiState.value.activeMenu = 'style'
    uiState.value.activePropertyTab = 'page'
  } else {
    uiState.value.activeMenu = 'canvas'
    uiState.value.activePropertyTab = 'page'
  }
}

const handleNodeDoubleClick = (node: FlowNode) => {
  const definition = componentDefinitionMap[node.data.componentKey]
  uiState.value.activePropertyTab = definition?.canvasType === 'energy' ? 'model' : 'style'
}

const handleAddCanvas = () => {
  if (!project.value) {
    return
  }

  history.commit(project.value.workspace, '新增画布')
  applyWorkspace(appendCanvas(project.value.workspace, `画布${project.value.workspace.canvases.length + 1}`))
  resetSelection()
}

const handleCloseCanvas = (canvasId: string) => {
  if (!project.value || project.value.workspace.canvases.length <= 1) {
    return
  }

  history.commit(project.value.workspace, '关闭画布')
  applyWorkspace(removeCanvas(project.value.workspace, canvasId))
  resetSelection()
}

const handleSelectCanvas = (canvasId: string) => {
  if (!project.value) {
    return
  }

  applyWorkspace({
    ...project.value.workspace,
    activeCanvasId: canvasId
  })
  resetSelection()
}

const handleToggleFullscreen = async () => {
  if (!import.meta.client) {
    return
  }

  if (!document.fullscreenElement) {
    await document.documentElement.requestFullscreen()
  }
  else {
    await document.exitFullscreen()
  }
}

const syncFullscreenState = () => {
  if (!import.meta.client) {
    return
  }

  isFullscreen.value = Boolean(document.fullscreenElement)
}

const handleUndo = () => {
  if (!project.value) {
    return
  }

  const previous = history.undo(project.value.workspace)

  if (!previous) {
    return
  }

  resetSelection()
  applyWorkspace(previous)
}

const handleRedo = () => {
  if (!project.value) {
    return
  }

  const next = history.redo(project.value.workspace)

  if (!next) {
    return
  }

  resetSelection()
  applyWorkspace(next)
}

const handleKeydown = (event: KeyboardEvent) => {
  const target = event.target as HTMLElement | null
  const isInputElement = target && ['INPUT', 'TEXTAREA', 'SELECT'].includes(target.tagName)

  if (isInputElement || !activeCanvas.value || !project.value) {
    return
  }

  const modifierPressed = event.ctrlKey || event.metaKey

  if (event.key === 'Delete' || event.key === 'Backspace') {
    event.preventDefault()
    handleToolbarAction('remove')
  }

  if (modifierPressed && event.key.toLowerCase() === 'z') {
    event.preventDefault()
    if (event.shiftKey) {
      handleRedo()
    }
    else {
      handleUndo()
    }
  }

  if (modifierPressed && event.key.toLowerCase() === 'y') {
    event.preventDefault()
    handleRedo()
  }

  if (modifierPressed && event.key.toLowerCase() === 'd') {
    event.preventDefault()
    handleToolbarAction('duplicate')
  }

  if (modifierPressed && event.key.toLowerCase() === 'c') {
    event.preventDefault()
    copyCurrentSelection()
  }

  if (modifierPressed && event.key.toLowerCase() === 'x') {
    event.preventDefault()
    handleToolbarAction('cut')
  }

  if (modifierPressed && event.key.toLowerCase() === 'r') {
    event.preventDefault()
    if (event.shiftKey) {
      handleToolbarAction('rotate-left')
    } else {
      handleToolbarAction('rotate-right')
    }
  }

  if (modifierPressed && event.key.toLowerCase() === 'v') {
    event.preventDefault()
    handleToolbarAction('paste')
  }

  if (modifierPressed && event.key.toLowerCase() === 'a') {
    event.preventDefault()
    handleToolbarAction('select-all')
  }
}

onMounted(() => {
  window.addEventListener('keydown', handleKeydown)
  document.addEventListener('fullscreenchange', syncFullscreenState)
})

onActivated(() => {
  window.addEventListener('keydown', handleKeydown)
  document.addEventListener('fullscreenchange', syncFullscreenState)
  nextTick(() => {
    void canvasWorkspaceRef.value?.refreshLayout()
  })
})

onDeactivated(() => {
  window.removeEventListener('keydown', handleKeydown)
  document.removeEventListener('fullscreenchange', syncFullscreenState)
})

onBeforeUnmount(() => {
  window.removeEventListener('keydown', handleKeydown)
  document.removeEventListener('fullscreenchange', syncFullscreenState)
})
</script>

<template>
  <div v-if="pending" class="flex min-h-screen items-center justify-center text-app-muted">
    正在加载编辑器...
  </div>

  <div v-else-if="error || !project || !activeCanvas" class="flex min-h-screen items-center justify-center bg-app-surface px-6">
    <section class="editor-card w-full max-w-md p-6">
      <h2 class="text-lg font-semibold text-app-text">项目加载失败</h2>
      <p class="mt-2 text-sm text-app-muted">
        未找到对应项目，或项目数据已经损坏。
      </p>
      <div class="mt-4">
        <AppButton label="返回项目页" icon="arrow" tone="primary" @click="navigateTo('/project')" />
      </div>
    </section>
  </div>

  <div v-else class="flex h-screen flex-col overflow-hidden bg-app-surface">
    <EditorHeader
      :project-name="project.name"
      :is-fullscreen="isFullscreen"
      @navigate-home="navigateTo('/project')"
      @docs="push({ tone: 'info', title: '文档入口预留', description: '后续可在此接入产品文档链接。' })"
      @repo="push({ tone: 'info', title: '仓库入口预留', description: '后续可在此接入代码仓库链接。' })"
      @fullscreen="handleToggleFullscreen"
      @settings="navigateTo('/settings')"
      @profile="navigateTo('/profile')"
    />

    <div class="flex min-h-0 flex-1 flex-col gap-2 px-2 py-2">
      <EditorMenuBar
        :menus="editorMenus"
        :active-menu="uiState.activeMenu"
        @select="uiState.activeMenu = $event as typeof uiState.activeMenu"
      />

      <EditorToolbar
        :groups="toolbarGroups"
        :values="toolbarValues"
        @action="handleToolbarAction"
      />
      

      <div class="relative isolate grid min-h-0 flex-1 gap-2" :style="contentGridStyle">
        <LibrarySidebar
          class="relative z-20 min-h-0"
          :active-category="uiState.activeCategory"
          :collapsed="uiState.leftCollapsed"
          @select-category="uiState.activeCategory = $event"
          @toggle-collapse="uiState.leftCollapsed = !uiState.leftCollapsed"
        />

        <ClientOnly>
          <CanvasWorkspace
            ref="canvasWorkspaceRef"
            class="relative z-0 min-h-0"
            :canvas="activeCanvas"
            :selection="selection"
            :clipboard="editorClipboard"
            @update:canvas="handleCanvasUpdate"
            @selection-change="handleSelectionChange"
            @node-double-click="handleNodeDoubleClick"
            @action="handleToolbarAction"
          />
        </ClientOnly>

        <ClientOnly>
          <PropertiesPanel
            class="relative z-20 min-h-0 justify-self-end"
            v-model:active-tab="uiState.activePropertyTab"
            :canvas="activeCanvas"
            :selection="selection"
            :collapsed="uiState.rightCollapsed"
            :layer-config="project.layerConfig"
            :boundaries="project.boundaries"
            @update:canvas="handleCanvasUpdate"
            @toggle-collapse="uiState.rightCollapsed = !uiState.rightCollapsed"
          />
        </ClientOnly>
      </div>

    </div>
    <EditorStatusBar
        :canvases="project.workspace.canvases.map(canvas => ({ id: canvas.id, name: canvas.name }))"
        :active-canvas-id="project.workspace.activeCanvasId"
        :node-count="activeCanvas.nodes.length"
        :edge-count="activeCanvas.edges.length"
        :zoom-percent="zoomPercent"
        @select-canvas="handleSelectCanvas"
        @add-canvas="handleAddCanvas"
        @close-canvas="handleCloseCanvas"
        @zoom-in="canvasWorkspaceRef?.zoomIn()"
        @zoom-out="canvasWorkspaceRef?.zoomOut()"
        @reset-zoom="canvasWorkspaceRef?.setZoomPercent(100)"
        @set-zoom="canvasWorkspaceRef?.setZoomPercent($event)"
      />

    <!-- 时层配置弹窗 -->
    <LayerConfigModal
      :open="showLayerConfigModal"
      :layers="project?.layerConfig?.layers ?? []"
      @close="showLayerConfigModal = false"
      @confirm="handleLayerConfigConfirm"
    />

    <!-- 算法配置弹窗 -->
    <AlgorithmConfigModal
      :open="showAlgorithmConfigModal"
      :algorithm="project?.algorithm ?? { electricityLoadPrediction: 'None', windTurbinePrediction: 'None', optimizationAlgorithm: 'MILP', slackEnabled: false, slackPenalty: 1000000 }"
      @close="showAlgorithmConfigModal = false"
      @confirm="handleAlgorithmConfigConfirm"
    />

    <!-- [废弃 2026-07-14] 仿真解析弹窗 — 功能已迁移到计算任务系统 -->
    <!-- <SimulationParseModal
      :open="showSimulationParseModal"
      :project-id="projectId"
      @close="showSimulationParseModal = false"
    /> -->
  </div>
</template>
