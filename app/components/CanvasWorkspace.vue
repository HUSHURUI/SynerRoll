<script setup lang="ts">
import { Controls } from '@vue-flow/controls'
import { ConnectionLineType, SelectionMode, VueFlow, useVueFlow, type NodeMouseEvent, type EdgeMouseEvent } from '@vue-flow/core'
import type { EdgeChange, NodeChange } from '@vue-flow/core'
import { markRaw, provide, computed } from 'vue'

import { componentDefinitionMap } from '~~/config/component-meta'
import type { CanvasClipboard, CanvasData, CanvasNodeData, CanvasSelection, FlowEdge, FlowNode, PageConfig } from '~~/types/canvas'
import {
  addBusPortAfterConnection,
  createNodeFromDefinition,
  getNodePortByHandleId,
  getPortPositionOffset,
  getPortIdFromHandleId,
  getRotatedPortSide,
  getMediumEdgeStyle,
  isBusNode as isDynamicBusNode,
  normalizeCanvasBusNodes,
  resolveDefinitionNodeSize,
  stripBusHandleSuffix,
  syncEdgeStyles,
  syncNodeStyles
} from '~~/utils/canvas'
import { createId } from '~~/utils/id'
import { deepClone } from '~~/utils/clone'

import CanvasNode from './CanvasNode.vue'

// Provide pageConfig to child components
const pageConfig = computed<PageConfig>(() => props.canvas.pageConfig)
provide('pageConfig', pageConfig)

type RuntimeFlowNode = FlowNode & {
  selected?: boolean
  dragging?: boolean
  resizing?: boolean
  computedPosition?: unknown
  handleBounds?: unknown
  dimensions?: unknown
  isParent?: boolean
}

type RuntimeFlowEdge = FlowEdge & {
  selected?: boolean
  sourceNode?: unknown
  targetNode?: unknown
  sourceX?: number
  sourceY?: number
  targetX?: number
  targetY?: number
}

interface ContextMenuState {
  x: number
  y: number
  target: 'pane' | 'node' | 'edge'
}

interface ContextMenuItem {
  key: string
  label: string
  shortcut?: string
  icon?: string
  divider?: boolean
}

interface ActionPayload {
  key: string
  value?: string | number | boolean
}

const props = defineProps<{
  canvas: CanvasData
  selection: CanvasSelection
  clipboard?: CanvasClipboard | null
}>()

const emit = defineEmits<{
  'update:canvas': [canvas: CanvasData]
  'selection-change': [selection: CanvasSelection]
  'node-double-click': [node: FlowNode]
  action: [payload: ActionPayload]
}>()

const flowId = 'syner-editor-flow'
const PAPER_FRAME_PADDING = 56

const canvasRenderKey = computed(() => [
  props.canvas.id,
  props.canvas.pageConfig.gridVisible,
  props.canvas.pageConfig.backgroundPattern,
  props.canvas.pageConfig.gridSize,
  props.canvas.pageConfig.gridColor,
  props.canvas.pageConfig.backgroundColor
].join('-'))

const canvasRef = ref<HTMLDivElement | null>(null)
const nodes = ref<RuntimeFlowNode[]>([])
const edges = ref<RuntimeFlowEdge[]>([])
const viewportSyncing = ref(false)
const contextMenu = ref<ContextMenuState | null>(null)
let selectionChangeScheduled = false
const isInitializing = ref(false)
const isContextMenuAction = ref(false)
const localGridVisible = ref(props.canvas.pageConfig.gridVisible)
const localBackgroundPattern = ref<'grid' | 'dots' | 'hidden'>(props.canvas.pageConfig.backgroundPattern)

const nodeTypes = {
  'syner-node': markRaw(CanvasNode)
}

const connectionLineStyle = { stroke: '#0a4da2', strokeWidth: 1.5 }
const defaultEdgeOptions = {
  type: 'smoothstep' as const,
  style: connectionLineStyle,
  updatable: false,
  selectable: true,
  focusable: true,
  interactionWidth: 20
}

const {
  screenToFlowCoordinate,
  fitBounds,
  getViewport,
  setViewport,
  zoomIn,
  zoomOut,
  zoomTo,
  setEdges,
  updateNodeInternals
} = useVueFlow(flowId)

const paperWidth = computed(() => Math.max(props.canvas.pageConfig.width, 320))
const paperHeight = computed(() => Math.max(props.canvas.pageConfig.height, 240))
const paperGridSize = computed(() => Math.max(props.canvas.pageConfig.gridSize, 4))

const paperStyle = computed<Record<string, string>>(() => {
  const { backgroundColor, gridColor } = props.canvas.pageConfig
  const gridVisible = localGridVisible.value
  const backgroundPattern = localBackgroundPattern.value

  const baseStyle = {
    width: `${paperWidth.value}px`,
    height: `${paperHeight.value}px`,
    backgroundColor,
    backgroundImage: 'none',
    backgroundSize: `${paperGridSize.value}px ${paperGridSize.value}px`,
    backgroundPosition: '0 0'
  }

  if (!gridVisible) {
    return baseStyle
  }

  const backgroundImage = backgroundPattern === 'dots'
    ? `radial-gradient(circle, ${gridColor} 1.1px, transparent 1.2px)`
    : `linear-gradient(to right, ${gridColor} 1px, transparent 1px), linear-gradient(to bottom, ${gridColor} 1px, transparent 1px)`

  return {
    ...baseStyle,
    backgroundImage,
    backgroundPosition: backgroundPattern === 'dots'
      ? `${paperGridSize.value / 2}px ${paperGridSize.value / 2}px`
      : '0 0'
  }
})

const contextMenuItems = computed(() => {
  if (!contextMenu.value) {
    return []
  }

  if (contextMenu.value.target === 'node') {
    return [
      { key: 'cut', label: '剪切', shortcut: 'Ctrl+X', icon: 'cut' },
      { key: 'copy', label: '复制', shortcut: 'Ctrl+C', icon: 'copy' },
      { key: 'duplicate', label: '创建副本', shortcut: 'Ctrl+D', icon: 'duplicate' },
      { key: 'remove', label: '删除', shortcut: 'Delete', icon: 'delete' },
      { divider: true },
      { key: 'rotate-right', label: '顺时针旋转', shortcut: 'Ctrl+R', icon: 'rotate-right' },
      { key: 'rotate-left', label: '逆时针旋转', shortcut: 'Ctrl+Shift+R', icon: 'rotate-left' },
      { divider: true },
      { key: 'undo', label: '撤销', shortcut: 'Ctrl+Z', icon: 'undo' },
      { key: 'redo', label: '重做', shortcut: 'Ctrl+Y', icon: 'redo' },
      { divider: true },
      { key: 'help', label: '帮助', icon: 'help' }
    ]
  }

  if (contextMenu.value.target === 'edge') {
    return [
      { key: 'cut', label: '剪切', shortcut: 'Ctrl+X', icon: 'cut' },
      { key: 'copy', label: '复制', shortcut: 'Ctrl+C', icon: 'copy' },
      { key: 'duplicate', label: '创建副本', shortcut: 'Ctrl+D', icon: 'duplicate' },
      { key: 'remove', label: '删除', shortcut: 'Delete', icon: 'delete' },
      { divider: true },
      { key: 'undo', label: '撤销', shortcut: 'Ctrl+Z', icon: 'undo' },
      { key: 'redo', label: '重做', shortcut: 'Ctrl+Y', icon: 'redo' },
      { divider: true },
      { key: 'help', label: '帮助', icon: 'help' }
    ]
  }

  return [
    { key: 'paste', label: '粘贴', shortcut: 'Ctrl+V', icon: 'paste' },
    { divider: true },
    { key: 'zoom-in', label: '放大', icon: 'zoom-in' },
    { key: 'zoom-out', label: '缩小', icon: 'zoom-out' },
    { divider: true },
    { key: 'select-all', label: '全选', shortcut: 'Ctrl+A', icon: 'select-all' },
    { divider: true },
    { key: 'undo', label: '撤销', shortcut: 'Ctrl+Z', icon: 'undo' },
    { key: 'redo', label: '重做', shortcut: 'Ctrl+Y', icon: 'redo' },
    { divider: true },
    { key: 'export-canvas', label: '导出画布', icon: 'export' }
  ]
})

const isViewportUntouched = (viewport: CanvasData['viewport']) =>
  viewport.x === 0 && viewport.y === 0 && viewport.zoom === 1

const isSameViewport = (left: CanvasData['viewport'], right: CanvasData['viewport']) =>
  Math.abs(left.x - right.x) < 0.5
  && Math.abs(left.y - right.y) < 0.5
  && Math.abs(left.zoom - right.zoom) < 0.001

const getSelectedNodeIds = () =>
  new Set(nodes.value.filter(node => node.selected).map(node => node.id))

const getSelectedEdgeIds = () =>
  new Set(edges.value.filter(edge => edge.selected).map(edge => edge.id))

const createSelection = (): CanvasSelection => {
  const selectedNodes = nodes.value.filter(node => node.selected)
  const selectedEdges = edges.value.filter(edge => edge.selected)

  const ignoreEdges = selectedNodes.length > 1

  return {
    nodeIds: selectedNodes.map(node => node.id),
    edgeIds: ignoreEdges ? [] : selectedEdges.map(edge => edge.id),
    primaryNodeId: selectedNodes[0]?.id ?? null,
    primaryEdgeId: ignoreEdges ? null : (selectedEdges[0]?.id ?? null)
  }
}

const hasSameSelection = (nextSelection: CanvasSelection) => {
  const currentSelection = createSelection()

  if (currentSelection.nodeIds.length !== nextSelection.nodeIds.length || currentSelection.edgeIds.length !== nextSelection.edgeIds.length) {
    return false
  }

  const nextNodeIds = new Set(nextSelection.nodeIds)
  const nextEdgeIds = new Set(nextSelection.edgeIds)

  return currentSelection.nodeIds.every(nodeId => nextNodeIds.has(nodeId))
    && currentSelection.edgeIds.every(edgeId => nextEdgeIds.has(edgeId))
}

const emitSelectionChange = () => {
  emit('selection-change', createSelection())
}

const scheduleSelectionChange = () => {
  if (selectionChangeScheduled) {
    return
  }

  selectionChangeScheduled = true

  nextTick(() => {
    selectionChangeScheduled = false
    emitSelectionChange()
  })
}

const applySelection = (nextSelection: CanvasSelection) => {
  const nodeIds = new Set(nextSelection.nodeIds)
  const edgeIds = new Set(nextSelection.edgeIds)

  nodes.value = nodes.value.map(node => ({
    ...node,
    selected: nodeIds.has(node.id)
  }))
  edges.value = edges.value.map(edge => ({
    ...edge,
    selected: edgeIds.has(edge.id)
  }))
}

const clearSelection = () => {
  applySelection({
    nodeIds: [],
    edgeIds: [],
    primaryNodeId: null,
    primaryEdgeId: null
  })
}

const selectNode = (nodeId: string, additive = false) => {
  const selectedNodeIds = additive ? getSelectedNodeIds() : new Set<string>()

  if (additive && selectedNodeIds.has(nodeId)) {
    selectedNodeIds.delete(nodeId)
  }
  else {
    selectedNodeIds.add(nodeId)
  }

  applySelection({
    nodeIds: [...selectedNodeIds],
    edgeIds: [],
    primaryNodeId: selectedNodeIds.has(nodeId) ? nodeId : [...selectedNodeIds][0] ?? null,
    primaryEdgeId: null
  })
}

const selectEdge = (edgeId: string, additive = false) => {
  const selectedEdgeIds = additive ? getSelectedEdgeIds() : new Set<string>()

  if (additive && selectedEdgeIds.has(edgeId)) {
    selectedEdgeIds.delete(edgeId)
  }
  else {
    selectedEdgeIds.add(edgeId)
  }

  applySelection({
    nodeIds: [],
    edgeIds: [...selectedEdgeIds],
    primaryNodeId: null,
    primaryEdgeId: selectedEdgeIds.has(edgeId) ? edgeId : [...selectedEdgeIds][0] ?? null
  })
}

const serializeNode = (node: RuntimeFlowNode): FlowNode => {
  const nextNode = deepClone(node) as RuntimeFlowNode

  delete nextNode.selected
  delete nextNode.dragging
  delete nextNode.resizing
  delete nextNode.computedPosition
  delete nextNode.handleBounds
  delete nextNode.dimensions
  delete nextNode.isParent

  return syncNodeStyles([nextNode as FlowNode])[0]!
}

const serializeEdge = (edge: RuntimeFlowEdge): FlowEdge => {
  const nextEdge = deepClone(edge) as RuntimeFlowEdge

  delete nextEdge.selected
  delete nextEdge.sourceNode
  delete nextEdge.targetNode
  delete nextEdge.sourceX
  delete nextEdge.sourceY
  delete nextEdge.targetX
  delete nextEdge.targetY

  return syncEdgeStyles([nextEdge as FlowEdge])[0]!
}

const getCurrentViewport = (): CanvasData['viewport'] => {
  if (!import.meta.client) {
    return deepClone(props.canvas.viewport)
  }

  const viewport = getViewport()

  return {
    x: viewport.x,
    y: viewport.y,
    zoom: viewport.zoom
  }
}

const buildCanvasPayload = (overrides: Partial<CanvasData> = {}): CanvasData => ({
  id: props.canvas.id,
  name: props.canvas.name,
  nodes: syncNodeStyles(nodes.value.map(node => serializeNode(node))),
  edges: syncEdgeStyles(edges.value.map(edge => serializeEdge(edge))),
  viewport: getCurrentViewport(),
  pageConfig: deepClone(props.canvas.pageConfig),
  updatedAt: new Date().toISOString(),
  ...overrides
})

const syncLocalElements = (canvas: CanvasData, preserveSelection: boolean) => {
  const selectedNodeIds = preserveSelection ? getSelectedNodeIds() : new Set<string>()
  const selectedEdgeIds = preserveSelection ? getSelectedEdgeIds() : new Set<string>()
  const normalizedCanvas = normalizeCanvasBusNodes(canvas)

  nodes.value = deepClone(syncNodeStyles(normalizedCanvas.nodes)).map(node => ({
    ...node,
    selected: selectedNodeIds.has(node.id)
  }))
  edges.value = deepClone(syncEdgeStyles(normalizedCanvas.edges)).map(edge => ({
    ...edge,
    selected: selectedEdgeIds.has(edge.id)
  }))
}

const syncLocalCanvas = (canvas: CanvasData, options?: { preserveSelection?: boolean; selection?: CanvasSelection }) => {
  syncLocalElements(canvas, options?.preserveSelection ?? false)
  localGridVisible.value = canvas.pageConfig.gridVisible

  if (options?.selection) {
    applySelection(options.selection)
  }
}

const buildInitialViewport = () => {
  if (!canvasRef.value) {
    return null
  }

  const bounds = canvasRef.value.getBoundingClientRect()

  if (!bounds.width || !bounds.height) {
    return null
  }

  const fitZoom = Math.min(
    1,
    (bounds.width - PAPER_FRAME_PADDING * 2) / paperWidth.value,
    (bounds.height - PAPER_FRAME_PADDING * 2) / paperHeight.value
  )
  const zoom = Number(Math.max(0.1, fitZoom).toFixed(3))

  return {
    x: Math.round((bounds.width - paperWidth.value * zoom) / 2),
    y: Math.round((bounds.height - paperHeight.value * zoom) / 2),
    zoom
  }
}

const syncViewportFromCanvas = async (canvas = props.canvas) => {
  if (!import.meta.client) {
    return
  }

  await nextTick()

  const nextViewport = isViewportUntouched(canvas.viewport)
    ? buildInitialViewport()
    : canvas.viewport

  if (!nextViewport) {
    return
  }

  if (isSameViewport(getViewport(), nextViewport)) {
    return
  }

  viewportSyncing.value = true
  await setViewport(nextViewport)
  requestAnimationFrame(() => {
    viewportSyncing.value = false
  })
}

const waitForRenderFrame = () => new Promise<void>((resolve) => {
  if (!import.meta.client) {
    resolve()
    return
  }

  requestAnimationFrame(() => resolve())
})

let flowLayoutRefreshToken = 0

const refreshFlowLayout = async (canvas = props.canvas) => {
  if (!import.meta.client) {
    return
  }

  const refreshToken = ++flowLayoutRefreshToken

  await nextTick()
  await waitForRenderFrame()
  await waitForRenderFrame()

  if (refreshToken !== flowLayoutRefreshToken) {
    return
  }

  await syncViewportFromCanvas(canvas)
  await nextTick()

  const nodeIds = nodes.value
    .filter(node => !node.dragging && !node.resizing)
    .map(node => node.id)

  if (nodeIds.length === 0) {
    const refreshedEdges = edges.value.map(edge => ({ ...edge }))
    edges.value = refreshedEdges
    setEdges(refreshedEdges)
    return
  }

  updateNodeInternals(nodeIds)
  await nextTick()

  if (refreshToken !== flowLayoutRefreshToken) {
    return
  }

  nodes.value = nodes.value.map(node => ({ ...node }))
  const refreshedEdges = edges.value.map(edge => ({ ...edge }))
  edges.value = refreshedEdges
  setEdges(refreshedEdges)

  await waitForRenderFrame()

  if (refreshToken !== flowLayoutRefreshToken) {
    return
  }

  updateNodeInternals(nodeIds)
}

const closeContextMenu = () => {
  contextMenu.value = null
}

const openContextMenu = (event: MouseEvent, target: ContextMenuState['target']) => {
  event.preventDefault()

  const bounds = canvasRef.value?.getBoundingClientRect()

  contextMenu.value = {
    x: bounds ? event.clientX - bounds.left : event.clientX,
    y: bounds ? event.clientY - bounds.top : event.clientY,
    target
  }
}

const runContextAction = (key: string) => {
  isContextMenuAction.value = true
  performAction(key)
  emit('action', { key })
  closeContextMenu()
  setTimeout(() => {
    isContextMenuAction.value = false
  }, 100)
}

const performAction = (key: string) => {}

const onNodesChange = (changes: NodeChange[]) => {
  const selectionChanges = changes.filter(change => change.type === 'select')

  if (selectionChanges.length > 0) {
    const selectedMap = new Map(selectionChanges.map(change => [change.id, change.selected]))

    nodes.value = nodes.value.map(node => (
      selectedMap.has(node.id)
        ? { ...node, selected: selectedMap.get(node.id) ?? false }
        : node
    ))
  }

  if (selectionChanges.length > 0 || changes.some(change => change.type === 'remove')) {
    scheduleSelectionChange()
  }
}

const onEdgesChange = (changes: EdgeChange[]) => {
  
  const selectionChanges = changes.filter(change => change.type === 'select')
  const removeChanges = changes.filter(change => change.type === 'remove')

  if (selectionChanges.length > 0) {
    const selectedMap = new Map(selectionChanges.map(change => [change.id, change.selected]))

    edges.value = edges.value.map(edge => (
      selectedMap.has(edge.id)
        ? { ...edge, selected: selectedMap.get(edge.id) ?? false }
        : edge
    ))
  }

  if (selectionChanges.length > 0 || removeChanges.length > 0) {
    scheduleSelectionChange()
  }
}

// 检查节点是否为energy类型
const isEnergyNode = (nodeId: string): boolean => {
  const node = nodes.value.find(n => n.id === nodeId)
  if (!node?.data?.componentKey) return false
  const def = componentDefinitionMap[node.data.componentKey]
  return def?.canvasType === 'energy'
}

// 检查端口是否已经连接（排除刚创建的连线）
const isPortConnected = (nodeId: string, handleId: string, excludeEdgeId?: string): boolean => {
  return edges.value.some(edge =>
    edge.id !== excludeEdgeId &&
    ((edge.source === nodeId && edge.sourceHandle === handleId) ||
     (edge.target === nodeId && edge.targetHandle === handleId))
  )
}

const onConnect = (params: { source?: string | null; target?: string | null; sourceHandle?: string | null; targetHandle?: string | null }) => {
  if (isInitializing.value) return
  if (!params.source || !params.target || params.source === params.target) {
    return
  }

  const existingEdge = edges.value.find(edge =>
    edge.source === params.source
    && edge.target === params.target
    && (edge.sourceHandle ?? null) === (params.sourceHandle ?? null)
    && (edge.targetHandle ?? null) === (params.targetHandle ?? null)
  )

  if (existingEdge) {
    return
  }

  const sourceNode = nodes.value.find(node => node.id === params.source)
  const targetNode = nodes.value.find(node => node.id === params.target)

  // ===== 功能1: energy组件端口只能连接一根线 =====
  if (params.sourceHandle && isEnergyNode(params.source)) {
    if (isPortConnected(params.source, params.sourceHandle)) {
      return // 源端口已连接，拒绝
    }
  }
  if (params.targetHandle && isEnergyNode(params.target)) {
    if (isPortConnected(params.target, params.targetHandle)) {
      return // 目标端口已连接，拒绝
    }
  }

  // 从源端口定义获取介质类型
  let medium: 'electric' | 'thermal' | 'gas' | 'hydrogen' | 'material' | 'general' = 'electric'
  if (sourceNode && sourceNode.data && params.sourceHandle) {
    const sourceDef = componentDefinitionMap[sourceNode.data.componentKey]
    const sourcePort = sourceDef?.ports.find(p => p.id === params.sourceHandle)
    if (sourcePort) {
      medium = sourcePort.medium
    }
  }

  const mediumStyle = getMediumEdgeStyle(medium)

  const edgeId = createId('edge')

  const newEdge: FlowEdge = {
    id: edgeId,
    source: params.source,
    target: params.target,
    sourceHandle: params.sourceHandle ?? undefined,
    targetHandle: params.targetHandle ?? undefined,
    type: 'smoothstep',
    data: {
      label: '',
      medium,
      style: {
        strokeColor: mediumStyle.strokeColor,
        strokeWidth: mediumStyle.strokeWidth,
        strokeDasharray: mediumStyle.strokeDasharray,
        labelColor: mediumStyle.strokeColor,
        arrowType: 'none' as const
      }
    }
  }

  edges.value = syncEdgeStyles([
    ...edges.value.map(edge => ({
      ...edge,
      selected: false
    })),
    { ...newEdge, selected: true }
  ]) as RuntimeFlowEdge[]

  emit('update:canvas', buildCanvasPayload())
  scheduleSelectionChange()
}

const getConnectionPortKey = (nodeId: string, handleId?: string | null): string | null => {
  if (!handleId) {
    return null
  }

  const node = nodes.value.find(currentNode => currentNode.id === nodeId)

  if (!node) {
    return `${nodeId}:${handleId}`
  }

  return isDynamicBusNode(node)
    ? `${nodeId}:${getPortIdFromHandleId(handleId) ?? handleId}`
    : `${nodeId}:${handleId}`
}

const isPhysicalPortConnected = (nodeId: string, handleId?: string | null, excludeEdgeId?: string): boolean => {
  const portKey = getConnectionPortKey(nodeId, handleId)

  if (!portKey) {
    return false
  }

  return edges.value.some(edge =>
    edge.id !== excludeEdgeId &&
    (getConnectionPortKey(edge.source, stripBusHandleSuffix(edge.sourceHandle)) === portKey ||
      getConnectionPortKey(edge.target, stripBusHandleSuffix(edge.targetHandle)) === portKey)
  )
}

const onConnectBusAware = (params: { source?: string | null; target?: string | null; sourceHandle?: string | null; targetHandle?: string | null }) => {
  if (isInitializing.value) {
    return
  }

  if (!params.source || !params.target || params.source === params.target || !params.sourceHandle || !params.targetHandle) {
    return
  }

  const existingEdge = edges.value.find(edge =>
    edge.source === params.source &&
    edge.target === params.target &&
    (edge.sourceHandle ?? null) === params.sourceHandle &&
    (edge.targetHandle ?? null) === params.targetHandle
  )

  if (existingEdge) {
    return
  }

  if (isPhysicalPortConnected(params.source, params.sourceHandle) || isPhysicalPortConnected(params.target, params.targetHandle)) {
    return
  }

  const sourceNode = nodes.value.find(node => node.id === params.source)

  if (!sourceNode) {
    return
  }

  const sourcePort = getNodePortByHandleId(sourceNode, params.sourceHandle)
  const medium = sourcePort?.medium ?? 'electric'
  const mediumStyle = getMediumEdgeStyle(medium)

  const newEdge: FlowEdge = {
    id: createId('edge'),
    source: params.source,
    target: params.target,
    sourceHandle: stripBusHandleSuffix(params.sourceHandle) ?? undefined,
    targetHandle: stripBusHandleSuffix(params.targetHandle) ?? undefined,
    type: 'smoothstep',
    data: {
      label: '',
      medium,
      style: {
        strokeColor: mediumStyle.strokeColor,
        strokeWidth: mediumStyle.strokeWidth,
        strokeDasharray: mediumStyle.strokeDasharray,
        labelColor: mediumStyle.strokeColor,
        arrowType: 'none'
      }
    }
  }

  nodes.value = nodes.value.map(node => {
    if (node.id === params.source) {
      return addBusPortAfterConnection(node, params.sourceHandle)
    }

    if (node.id === params.target) {
      return addBusPortAfterConnection(node, params.targetHandle)
    }

    return node
  }) as RuntimeFlowNode[]

  edges.value = syncEdgeStyles([
    ...edges.value.map(edge => ({
      ...edge,
      selected: false
    })),
    { ...newEdge, selected: true }
  ]) as RuntimeFlowEdge[]

  emit('update:canvas', buildCanvasPayload())
  scheduleSelectionChange()
}

const onDrop = (event: DragEvent) => {
  if (isInitializing.value) return
  const componentKey = event.dataTransfer?.getData('application/synerroll-component')

  if (!componentKey || !canvasRef.value) {
    return
  }

  const definition = componentDefinitionMap[componentKey]

  if (!definition) {
    return
  }

  const position = screenToFlowCoordinate({
    x: event.clientX,
    y: event.clientY
  })
  const nodeSize = resolveDefinitionNodeSize(definition)
  const centeredPosition = {
    x: position.x - nodeSize.width / 2,
    y: position.y - nodeSize.height / 2
  }

  const isInsidePaper = centeredPosition.x >= 0
    && centeredPosition.y >= 0
    && centeredPosition.x + nodeSize.width <= paperWidth.value
    && centeredPosition.y + nodeSize.height <= paperHeight.value

  if (!isInsidePaper) {
    return
  }

  const snappedPosition = props.canvas.pageConfig.snapToGrid
    ? {
        x: Math.round(centeredPosition.x / props.canvas.pageConfig.gridSize) * props.canvas.pageConfig.gridSize,
        y: Math.round(centeredPosition.y / props.canvas.pageConfig.gridSize) * props.canvas.pageConfig.gridSize
      }
    : centeredPosition

  const node = createNodeFromDefinition(definition, snappedPosition, nodes.value)

  nodes.value = [
    ...nodes.value.map(currentNode => ({
      ...currentNode,
      selected: false
    })),
    {
      ...node,
      selected: true
    }
  ]
  edges.value = edges.value.map(edge => ({
    ...edge,
    selected: false
  }))

  emit('update:canvas', buildCanvasPayload())
  scheduleSelectionChange()
}

const onNodeClick = (event: NodeMouseEvent) => {
  closeContextMenu()
  if (event.event.shiftKey) {
    const currentSelected = getSelectedNodeIds()
    const clickedNode = nodes.value.find(n => n.selected)
    if (clickedNode) {
      clickedNode.selected = !currentSelected.has(clickedNode.id) || !currentSelected.has(clickedNode.id)
    }
  }
  scheduleSelectionChange()
}

const onEdgeClick = () => {
  closeContextMenu()
  scheduleSelectionChange()
}

const onPaneClick = () => {
  closeContextMenu()
  scheduleSelectionChange()
}

const onNodeContextMenu = (event: NodeMouseEvent) => {
  if (!getSelectedNodeIds().has(event.node.id)) {
    selectNode(event.node.id)
    scheduleSelectionChange()
  }
  openContextMenu(event.event as MouseEvent, 'node')
}

const onEdgeContextMenu = (event: EdgeMouseEvent) => {
  if (!getSelectedEdgeIds().has(event.edge.id)) {
    selectEdge(event.edge.id)
    scheduleSelectionChange()
  }
  openContextMenu(event.event as MouseEvent, 'edge')
}

const onPaneContextMenu = (event: MouseEvent) => {
  clearSelection()
  scheduleSelectionChange()
  openContextMenu(event, 'pane')
}

const getRotatedSide = (originalSide: string, rotation: number): string => {
  const normalizedRotation = ((rotation % 360) + 360) % 360
  const sideOrder = ['top', 'right', 'bottom', 'left']
  const originalIndex = sideOrder.indexOf(originalSide)
  if (originalIndex === -1) return originalSide
  const rotationSteps = Math.round(normalizedRotation / 90)
  const newIndex = (originalIndex + rotationSteps) % 4
  return sideOrder[newIndex] ?? originalSide
}

const findPortInfo = (node: RuntimeFlowNode, handleId: string): { side: string; offset: number } | null => {
  const nodeData = node.data as CanvasNodeData | undefined
  if (!nodeData) return null

  const portConfigOverride = nodeData.portConfig?.[handleId]

  const definition = componentDefinitionMap[nodeData.componentKey]
  const portDef = definition?.ports.find(p => p.id === handleId)
  if (portDef) {
    const offset = portConfigOverride?.offset ?? portDef.offset
    return { side: portDef.side, offset }
  }

  return null
}

const calculateHandlePosition = (side: string, offset: number, width: number, height: number) => {
  return getPortPositionOffset(side as 'top' | 'right' | 'bottom' | 'left', offset, width, height)
}

const getRotatedHandleOffset = (node: RuntimeFlowNode, handleId: string, rotation: number, width: number, height: number) => {
  const portInfo = findPortInfo(node, handleId)
  if (!portInfo) {
    return { x: 0, y: 0 }
  }

  const { side: originalSide, offset } = portInfo
  const rotatedSide = getRotatedSide(originalSide, rotation)
  const position = calculateHandlePosition(rotatedSide, offset, width, height)

  return position
}

const updateEdgeEndpointsForNode = (nodeId: string, rotation: number) => {

  const node = nodes.value.find(n => n.id === nodeId)
  if (!node) {
    return
  }

  if ((node as RuntimeFlowNode).dragging) {
    return
  }

  if ((node as RuntimeFlowNode).resizing) {
    return
  }

  const style = node.style as Record<string, string | number> | undefined
  const pos = node.position as { x: number; y: number } | undefined

  if (!style || !pos) {
    return
  }

  const widthStr = String(style.width || '0')
  const heightStr = String(style.height || '0')
  const width = parseFloat(widthStr.replace('px', '')) || 0
  const height = parseFloat(heightStr.replace('px', '')) || 0

  if (width === 0 || height === 0) {
    return
  }

  const centerX = pos.x + width / 2
  const centerY = pos.y + height / 2

  const updatedEdges = edges.value.map(edge => {
    if (edge.source !== nodeId && edge.target !== nodeId) {
      return edge
    }

    const newEdge = { ...edge }

    if (edge.source === nodeId && edge.sourceHandle) {

      const handleOffset = getRotatedHandleOffset(node, edge.sourceHandle, rotation, width, height)
      newEdge.sourceX = centerX + handleOffset.x
      newEdge.sourceY = centerY + handleOffset.y
    }
    if (edge.target === nodeId && edge.targetHandle) {

      const handleOffset = getRotatedHandleOffset(node, edge.targetHandle, rotation, width, height)
      newEdge.targetX = centerX + handleOffset.x
      newEdge.targetY = centerY + handleOffset.y
    }

    return newEdge
  })

  edges.value = updatedEdges
  setEdges(updatedEdges)

  nextTick(() => {
    updateNodeInternals([nodeId])

    const freshEdges = edges.value.map(e => ({ ...e }))
    edges.value = freshEdges
    setEdges(freshEdges)
  })
}

const getResolvedHandleOffset = (node: RuntimeFlowNode, handleId: string, width: number, height: number) => {
  const port = getNodePortByHandleId(node, handleId)

  if (!port) {
    return { x: 0, y: 0 }
  }

  return calculateHandlePosition(
    getRotatedPortSide(port.side, Number(node.data?.style?.rotation) || 0),
    port.offset ?? 50,
    width,
    height
  )
}

const refreshNodeHandlesAndEdges = (nodeId: string) => {
  const node = nodes.value.find(currentNode => currentNode.id === nodeId)

  if (!node || node.dragging || node.resizing) {
    return
  }

  const width = Number(node.data?.style?.width ?? 0)
  const height = Number(node.data?.style?.height ?? 0)

  if (width <= 0 || height <= 0) {
    return
  }

  const centerX = node.position.x + width / 2
  const centerY = node.position.y + height / 2

  const updatedEdges = edges.value.map(edge => {
    if (edge.source !== nodeId && edge.target !== nodeId) {
      return edge
    }

    const nextEdge = { ...edge }

    if (edge.source === nodeId && edge.sourceHandle) {
      const handleOffset = getResolvedHandleOffset(node, edge.sourceHandle, width, height)
      nextEdge.sourceX = centerX + handleOffset.x
      nextEdge.sourceY = centerY + handleOffset.y
    }

    if (edge.target === nodeId && edge.targetHandle) {
      const handleOffset = getResolvedHandleOffset(node, edge.targetHandle, width, height)
      nextEdge.targetX = centerX + handleOffset.x
      nextEdge.targetY = centerY + handleOffset.y
    }

    return nextEdge
  })

  edges.value = updatedEdges
  setEdges(updatedEdges)

  nextTick(() => {
    updateNodeInternals([nodeId])
    const freshEdges = edges.value.map(edge => ({ ...edge }))
    edges.value = freshEdges
    setEdges(freshEdges)
  })
}

const onWheel = (event: WheelEvent) => {
  event.preventDefault()

  const currentViewport = getViewport()
  const scrollAmount = event.shiftKey ? Math.abs(event.deltaX) || Math.abs(event.deltaY) : Math.abs(event.deltaY)

  if (event.shiftKey) {

    const delta = event.deltaX || event.deltaY
    setViewport({
      x: currentViewport.x - delta,
      y: currentViewport.y,
      zoom: currentViewport.zoom
    })
  } else {
    setViewport({
      x: currentViewport.x,
      y: currentViewport.y - event.deltaY,
      zoom: currentViewport.zoom
    })
  }
}

const onNodeDoubleClick = (payload: { node: FlowNode }) => {
  emit('node-double-click', payload.node)
}

const onNodeDragStop = () => {
  if (isInitializing.value) return
  emit('update:canvas', buildCanvasPayload())
}

const onViewportChangeEnd = (nextViewport: CanvasData['viewport']) => {
  if (isInitializing.value || viewportSyncing.value || isSameViewport(nextViewport, props.canvas.viewport)) {
    return
  }

  emit('update:canvas', buildCanvasPayload({ viewport: nextViewport }))
}

const handleDocumentPointerDown = (event: PointerEvent) => {
  const target = event.target as Node | null

  if (!target || !canvasRef.value?.contains(target)) {
    closeContextMenu()
  }
}

const handleDocumentKeydown = (event: KeyboardEvent) => {
  if (event.key === 'Escape') {
    closeContextMenu()
    return
  }
}

watch(
  () => props.canvas.id,
  nextId => {
    if (nextId) {
      isInitializing.value = true
      syncLocalCanvas(props.canvas, {
        preserveSelection: false,
        selection: props.selection
      })
      void refreshFlowLayout(props.canvas)
      setTimeout(() => {
        isInitializing.value = false
      }, 100)
    }
  },
  { immediate: true }
)

watch(
  () => props.canvas,
  () => {
    if (!isInitializing.value) {
      syncLocalCanvas(props.canvas, {
        preserveSelection: true
      })
    }
  },
  { deep: true }
)

watch(
  () => props.canvas.pageConfig.backgroundPattern,
  (newVal) => {
    localBackgroundPattern.value = newVal
  }
)

watch(
  () => props.selection,
  nextSelection => {
    if (!hasSameSelection(nextSelection)) {
      applySelection(nextSelection)
    }
  },
  { deep: true, immediate: true }
)

let previousRotations: Record<string, number> = {}
const nodeRotations = computed((): { id: string; rotation: number }[] => {
  return nodes.value.map(n => ({ id: n.id, rotation: Number(n.data?.style?.rotation) || 0 }))
})
watch(
  nodeRotations,
  (currentRotations) => {
    currentRotations.forEach(({ id, rotation }) => {
      const prevRotation = previousRotations[id]
      if (prevRotation !== undefined && prevRotation !== rotation) {
        refreshNodeHandlesAndEdges(id)
      }
      previousRotations[id] = rotation
    })
  },
  { deep: true }
)

let previousPortConfigs: Record<string, { portConfig?: unknown; rotation: number }> = {}
const nodePortRotationConfigs = computed((): { id: string; portConfig?: unknown; rotation: number }[] => {
  return nodes.value.map(n => ({
    id: n.id,
    portConfig: n.data?.portConfig,
    rotation: Number(n.data?.style?.rotation) || 0
  }))
})
watch(
  nodePortRotationConfigs,
  (currentNodes) => {
    currentNodes.forEach(node => {

      const prevNode = previousPortConfigs[node.id]
      if (prevNode && (
        JSON.stringify(prevNode.portConfig) !== JSON.stringify(node.portConfig)
      )) {
        refreshNodeHandlesAndEdges(node.id)
      }
      previousPortConfigs[node.id] = {
        portConfig: node.portConfig,
        rotation: node.rotation
      }
    })
  },
  { deep: true, immediate: true }
)

let previousNodeSizes: Record<string, { width: number; height: number }> = {}
const nodeSizeConfigs = computed(() =>
  nodes.value.map(node => ({
    id: node.id,
    width: Number(node.data?.style?.width) || 0,
    height: Number(node.data?.style?.height) || 0
  }))
)

watch(
  nodeSizeConfigs,
  currentNodes => {
    currentNodes.forEach(node => {
      const previous = previousNodeSizes[node.id]

      if (previous && (previous.width !== node.width || previous.height !== node.height)) {
        refreshNodeHandlesAndEdges(node.id)
      }

      previousNodeSizes[node.id] = {
        width: node.width,
        height: node.height
      }
    })
  },
  { deep: true, immediate: true }
)

onMounted(() => {
  document.addEventListener('pointerdown', handleDocumentPointerDown)
  document.addEventListener('keydown', handleDocumentKeydown)
  void refreshFlowLayout(props.canvas)
})

onActivated(() => {
  document.addEventListener('pointerdown', handleDocumentPointerDown)
  document.addEventListener('keydown', handleDocumentKeydown)
  void refreshFlowLayout(props.canvas)
})

onDeactivated(() => {
  document.removeEventListener('pointerdown', handleDocumentPointerDown)
  document.removeEventListener('keydown', handleDocumentKeydown)
})

onBeforeUnmount(() => {
  document.removeEventListener('pointerdown', handleDocumentPointerDown)
  document.removeEventListener('keydown', handleDocumentKeydown)
})

defineExpose({
  fitToView: () =>
    fitBounds(
      { x: 0, y: 0, width: paperWidth.value, height: paperHeight.value },
      { padding: PAPER_FRAME_PADDING }
    ),
  zoomIn: () => zoomIn(),
  zoomOut: () => zoomOut(),
  setZoomPercent: (value: number) => zoomTo(value / 100),
  beginInit: () => {
    isInitializing.value = true
  },
  syncFromCanvas: (canvas: CanvasData, selection?: CanvasSelection) => {
    syncLocalCanvas(canvas, {
      preserveSelection: true,
      selection: selection ?? props.selection
    })
    void refreshFlowLayout(canvas)
    setTimeout(() => {
      isInitializing.value = false
    }, 100)
  },
  refreshLayout: () => refreshFlowLayout(props.canvas),
  setGridVisible: (visible: boolean) => {
    
    localGridVisible.value = visible
    emit('update:canvas', {
      id: props.canvas.id,
      name: props.canvas.name,
      nodes: syncNodeStyles(nodes.value.map(node => serializeNode(node))),
      edges: syncEdgeStyles(edges.value.map(edge => serializeEdge(edge))),
      viewport: getCurrentViewport(),
      pageConfig: {
        ...props.canvas.pageConfig,
        gridVisible: visible
      },
      updatedAt: new Date().toISOString()
    })
  },
  toggleGrid: () => {

    const newVisible = !localGridVisible.value
    localGridVisible.value = newVisible
    emit('update:canvas', {
      id: props.canvas.id,
      name: props.canvas.name,
      nodes: syncNodeStyles(nodes.value.map(node => serializeNode(node))),
      edges: syncEdgeStyles(edges.value.map(edge => serializeEdge(edge))),
      viewport: getCurrentViewport(),
      pageConfig: {
        ...props.canvas.pageConfig,
        gridVisible: newVisible
      },
      updatedAt: new Date().toISOString()
    })
  },
  setBackgroundPattern: (pattern: 'grid' | 'dots') => {
    localBackgroundPattern.value = pattern

    const newPageConfig = {
      ...props.canvas.pageConfig,
      gridVisible: localGridVisible.value,
      backgroundPattern: localBackgroundPattern.value
    }

    emit('update:canvas', {
      id: props.canvas.id,
      name: props.canvas.name,
      nodes: syncNodeStyles(nodes.value.map(node => serializeNode(node))),
      edges: syncEdgeStyles(edges.value.map(edge => serializeEdge(edge))),
      viewport: getCurrentViewport(),
      pageConfig: newPageConfig,
      updatedAt: new Date().toISOString()
    })

    setTimeout(() => {
      localGridVisible.value = newPageConfig.gridVisible
      localBackgroundPattern.value = newPageConfig.backgroundPattern
    }, 0)
  }
})
</script>

<template>
  <div
    ref="canvasRef"
    class="canvas-workspace relative min-h-0 flex-1 overflow-hidden rounded-[16px] cursor-default"
    @dragover.prevent
    @drop.prevent="onDrop"
    @wheel="onWheel"
  >
    <VueFlow
      :key="canvasRenderKey"
      :id="flowId"
      v-model:nodes="nodes"
      v-model:edges="edges"
      :node-types="nodeTypes"
      :default-viewport="canvas.viewport"
      :default-edge-options="defaultEdgeOptions"
      :min-zoom="0.1"
      :max-zoom="2"
      :zoom-on-scroll="false"
      :snap-to-grid="canvas.pageConfig.snapToGrid"
      :snap-grid="[canvas.pageConfig.gridSize, canvas.pageConfig.gridSize]"
      :connection-line-type="ConnectionLineType.Step"
      :connection-line-style="connectionLineStyle"
      :selection-mode="SelectionMode.Partial"
      :elements-selectable="true"
      :nodes-draggable="true"
      :nodes-connectable="true"
      :edges-updatable="false"
      :elevate-edges-on-select="true"
      :pan-on-drag="[1]"
      :selection-key-code="true"
      :delete-key-code="null"
      :select-nodes-on-drag="true"
      class="h-full w-full"
      @nodes-change="onNodesChange"
      @edges-change="onEdgesChange"
      @connect="onConnectBusAware"
      @node-click="onNodeClick"
      @edge-click="onEdgeClick"
      @pane-click="onPaneClick"
      @node-context-menu="onNodeContextMenu"
      @edge-context-menu="onEdgeContextMenu"
      @pane-context-menu="onPaneContextMenu"
      @node-double-click="onNodeDoubleClick"
      @node-drag-stop="onNodeDragStop"
      @viewport-change-end="onViewportChangeEnd"
    >
      <template #zoom-pane>
        <div
          :key="`${canvas.pageConfig.gridVisible}-${canvas.pageConfig.backgroundPattern}-${canvas.pageConfig.gridSize}-${canvas.pageConfig.gridColor}-${canvas.pageConfig.backgroundColor}`"
          class="canvas-paper rounded-[12px]"
          :style="paperStyle"
        />
      </template>
      <Controls 
        position="top-right"
        :showInteractive=false
      />
    </VueFlow>

    <div
      v-if="contextMenu"
      class="absolute z-[80] min-w-[180px] rounded-[12px] border border-app-border bg-white p-1 shadow-lg"
      :style="{
        left: `${contextMenu.x}px`,
        top: `${contextMenu.y}px`
      }"
    >
      <template v-for="(item, index) in contextMenuItems" :key="index">
        <div v-if="item.divider" class="my-1 border-t border-app-border" />
        <button
          v-else
          type="button"
          class="flex w-full items-center justify-between rounded-[8px] px-3 py-2 text-left text-sm text-app-text transition hover:bg-app-panel-soft hover:text-primary"
          @click.stop="runContextAction(item.key!)"
          @keydown.stop
        >
          <span class="flex items-center gap-2">
            <AppIcon v-if="item.icon" :name="item.icon" :size="14" />
            <span>{{ item.label }}</span>
          </span>
          <span v-if="item.shortcut" class="text-xs text-app-muted">{{ item.shortcut }}</span>
        </button>
      </template>
    </div>
  </div>
</template>

<style scoped>
.canvas-workspace {
  background-image: radial-gradient(circle at top, rgba(255, 255, 255, 0.95), rgba(245, 247, 250, 0.98));
}

.canvas-paper {
  position: absolute;
  top: 0;
  left: 0;
  z-index: -1;
  pointer-events: none;
  border: 1px solid rgba(221, 225, 230, 0.98);
  box-shadow: 0 18px 40px rgba(15, 23, 42, 0.12), 0 8px 20px rgba(15, 23, 42, 0.08);
}

.canvas-paper::after {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: inherit;
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.72);
}

.canvas-workspace :deep(.vue-flow__transformationpane) {
  position: relative;
  overflow: visible;
}

.canvas-workspace :deep(.vue-flow__pane) {
  cursor: default !important;
}

.canvas-workspace :deep(.vue-flow__selection) {
  cursor: crosshair;
}

.canvas-workspace :deep(.vue-flow__node) {
  cursor: grab;
}

.canvas-workspace :deep(.vue-flow__node.dragging) {
  cursor: grabbing;
}

.canvas-workspace :deep(.vue-flow__handle) {
  cursor: crosshair;
}

.canvas-workspace :deep(.vue-flow__viewport) {
  overflow: visible;
  background: transparent;
}

.canvas-workspace :deep(.vue-flow__edges) {
  overflow: visible;
}

.canvas-workspace :deep(.vue-flow__edge-path) {
  stroke-linecap: square;
  stroke-linejoin: miter;
}

.canvas-workspace :deep(.vue-flow__edge.selected) {
  z-index: 12;
}

.canvas-workspace :deep(.vue-flow__edge.selected .vue-flow__edge-path),
.canvas-workspace :deep(.vue-flow__edge:focus .vue-flow__edge-path) {
  filter: drop-shadow(0 0px 12px rgb(0, 26, 255));
}

.canvas-workspace :deep(.vue-flow__edge.selected .vue-flow__edge-interaction),
.canvas-workspace :deep(.vue-flow__edge:focus .vue-flow__edge-interaction) {
  stroke: transparent !important;
  stroke-width: 30 !important;
}

.canvas-workspace :deep(.vue-flow__node.draggable) {
  cursor: grab;
}

.canvas-workspace :deep(.vue-flow__node.draggable.dragging) {
  cursor: grabbing;
}
</style>
