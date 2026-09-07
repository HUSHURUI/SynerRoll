import { MarkerType, Position } from '@vue-flow/core'

import { componentDefinitionMap } from '~~/config/component-meta'
import { MEDIUM_EDGE_STYLES } from '~~/types/component'
import type { ComponentDefinition, MediumType, PortDefinition, PortSide } from '~~/types/component'
import type {
  CanvasClipboard,
  CanvasData,
  CanvasEdgeData,
  CanvasNodeData,
  CanvasNodeStyle,
  CanvasSelection,
  CanvasWorkspace,
  FlowEdge,
  FlowNode,
  NodePortConfig,
  PageConfig
} from '~~/types/canvas'

import { deepClone } from './clone'
import { createId } from './id'

// 获取介质的默认连线样式
export const getMediumEdgeStyle = (medium: MediumType) => MEDIUM_EDGE_STYLES[medium] ?? MEDIUM_EDGE_STYLES.general

const BUS_PORT_ID_PATTERN = /^bus-(top|right|bottom|left)-(\d+)$/
const BUS_DEFAULT_SIDES: PortSide[] = ['left', 'right']
const VISUAL_MIN_INSERT_SIDES = new Set<PortSide>(['left', 'bottom'])
const BUS_COMPONENT_MEDIUM_MAP: Record<string, MediumType> = {
  ELEC_BUS: 'electric',
  COLD_BUS: 'thermal',
  THERMAL_BUS: 'thermal',
  H2_BUS: 'hydrogen',
  GAS_BUS: 'gas',
  CARBON_BUS: 'carbon',
  OTHER_BUS: 'general'
}

export const BUS_SOURCE_HANDLE_SUFFIX = '-src'
export const BUS_TARGET_HANDLE_SUFFIX = '-tgt'

const PORT_SIDE_SORT_ORDER: Record<PortSide, number> = {
  left: 0,
  right: 1,
  top: 2,
  bottom: 3
}

const sortPortDefinitions = (left: PortDefinition, right: PortDefinition): number => {
  const sideDiff = PORT_SIDE_SORT_ORDER[left.side] - PORT_SIDE_SORT_ORDER[right.side]

  if (sideDiff !== 0) {
    return sideDiff
  }

  return left.offset - right.offset
}

const sortPortEntriesByOffset = (
  left: [string, NonNullable<NodePortConfig[string]>],
  right: [string, NonNullable<NodePortConfig[string]>]
): number => (left[1].offset ?? 50) - (right[1].offset ?? 50)

const getCanvasNodeData = (nodeOrData: Pick<FlowNode, 'data'> | CanvasNodeData): CanvasNodeData =>
  ('data' in nodeOrData ? nodeOrData.data : nodeOrData) as CanvasNodeData

const getBusPortMedium = (componentKey: string): MediumType =>
  BUS_COMPONENT_MEDIUM_MAP[componentKey] ?? 'general'

const inferBusPortSide = (portId: string): PortSide | undefined => {
  const matched = portId.match(BUS_PORT_ID_PATTERN)
  return (matched?.[1] as PortSide | undefined) ?? undefined
}

const createBusPortId = (portConfig: NodePortConfig, side: PortSide): string => {
  const usedIndexes = new Set(
    Object.keys(portConfig)
      .map(portId => portId.match(BUS_PORT_ID_PATTERN))
      .filter((matched): matched is RegExpMatchArray => Boolean(matched))
      .filter(matched => matched[1] === side)
      .map(matched => Number(matched[2]))
  )

  let nextIndex = 1

  while (usedIndexes.has(nextIndex)) {
    nextIndex += 1
  }

  return `bus-${side}-${nextIndex}`
}

const createBusPortState = (
  componentKey: string,
  side: PortSide,
  offset = 50
): NonNullable<NodePortConfig[string]> => ({
  label: '',
  side,
  offset,
  medium: getBusPortMedium(componentKey)
})

export const getBusHandleId = (portId: string, type: 'source' | 'target'): string =>
  `${portId}${type === 'source' ? BUS_SOURCE_HANDLE_SUFFIX : BUS_TARGET_HANDLE_SUFFIX}`

// 去掉总线端口 handle 的后缀，用于存储时统一格式
export const stripBusHandleSuffix = (handleId?: string | null): string | null =>
  getPortIdFromHandleId(handleId)

export const getPortIdFromHandleId = (handleId?: string | null): string | null => {
  if (!handleId) {
    return null
  }

  if (handleId.endsWith(BUS_SOURCE_HANDLE_SUFFIX)) {
    return handleId.slice(0, -BUS_SOURCE_HANDLE_SUFFIX.length)
  }

  if (handleId.endsWith(BUS_TARGET_HANDLE_SUFFIX)) {
    return handleId.slice(0, -BUS_TARGET_HANDLE_SUFFIX.length)
  }

  return handleId
}

export const getRotatedPortSide = (side: PortSide, rotation: number): PortSide => {
  const normalizedRotation = ((rotation % 360) + 360) % 360
  const sideOrder: PortSide[] = ['top', 'right', 'bottom', 'left']
  const originalIndex = sideOrder.indexOf(side)

  if (originalIndex < 0) {
    return side
  }

  return sideOrder[(originalIndex + Math.round(normalizedRotation / 90)) % sideOrder.length] ?? side
}

export const getPortPositionOffset = (
  side: PortSide,
  offset: number,
  width: number,
  height: number
): { x: number; y: number } => {
  const normalizedOffset = (offset - 50) / 50
  const halfWidth = width / 2
  const halfHeight = height / 2

  switch (side) {
    case 'top':
      return {
        x: normalizedOffset * halfWidth,
        y: -halfHeight
      }
    case 'right':
      return {
        x: halfWidth,
        y: normalizedOffset * halfHeight
      }
    case 'bottom':
      return {
        x: -normalizedOffset * halfWidth,
        y: halfHeight
      }
    case 'left':
      return {
        x: -halfWidth,
        y: -normalizedOffset * halfHeight
      }
    default:
      return {
        x: 0,
        y: 0
      }
  }
}

export const isBusNodeData = (nodeData?: Pick<CanvasNodeData, 'componentKey'> | null): boolean => {
  if (!nodeData) {
    return false
  }

  return componentDefinitionMap[nodeData.componentKey]?.category === 'bus'
}

export const isBusNode = (node?: Pick<FlowNode, 'data'> | null): boolean => isBusNodeData(node?.data)

export const normalizeBusPortConfig = (componentKey: string, portConfig?: NodePortConfig): NodePortConfig => {
  const normalized: NodePortConfig = {}

  Object.entries(portConfig ?? {}).forEach(([portId, portState]) => {
    normalized[portId] = {
      label: portState?.label ?? '',
      side: portState?.side ?? inferBusPortSide(portId) ?? 'left',
      offset: portState?.offset ?? 50,
      medium: portState?.medium ?? getBusPortMedium(componentKey)
    }
  })

  BUS_DEFAULT_SIDES.forEach(side => {
    const hasSidePort = Object.values(normalized).some(portState => (portState.side ?? 'left') === side)

    if (!hasSidePort) {
      normalized[createBusPortId(normalized, side)] = createBusPortState(componentKey, side)
    }
  })

  const rebalanced: NodePortConfig = {}

  ;(['left', 'right', 'top', 'bottom'] as PortSide[]).forEach(side => {
    const sideEntries = Object.entries(normalized)
      .filter(([, portState]) => (portState.side ?? 'left') === side)
      .sort(sortPortEntriesByOffset)

    const offsets = calculateUniformOffsets(sideEntries.length)

    sideEntries.forEach(([portId, portState], index) => {
      rebalanced[portId] = {
        ...portState,
        side,
        offset: offsets[index] ?? portState.offset ?? 50,
        medium: portState.medium ?? getBusPortMedium(componentKey)
      }
    })
  })

  return rebalanced
}

export const normalizeBusNode = (node: FlowNode): FlowNode => {
  if (!isBusNode(node) || !node.data) {
    return node
  }

  return {
    ...node,
    data: {
      ...node.data,
      portConfig: normalizeBusPortConfig(node.data.componentKey, node.data.portConfig)
    }
  }
}

export const normalizeCanvasBusNodes = (canvas: CanvasData): CanvasData => ({
  ...canvas,
  nodes: syncNodeStyles(canvas.nodes.map(node => normalizeBusNode(node)))
})

export const getNodePorts = (nodeOrData: Pick<FlowNode, 'data'> | CanvasNodeData): PortDefinition[] => {
  const nodeData = getCanvasNodeData(nodeOrData)
  const definition = componentDefinitionMap[nodeData.componentKey]

  if (definition?.category === 'bus') {
    return Object.entries(normalizeBusPortConfig(nodeData.componentKey, nodeData.portConfig))
      .map(([portId, portState]) => ({
        id: portId,  // 总线端口使用纯 portId（与 edges 中的 handle 格式一致）
        label: portState.label ?? '',
        direction: 'in' as const,
        side: portState.side ?? 'left',
        offset: portState.offset ?? 50,
        medium: portState.medium ?? getBusPortMedium(nodeData.componentKey)
      }))
      .sort(sortPortDefinitions)
  }

  return (definition?.ports ?? [])
    .map(port => ({
      ...port,
      label: nodeData.portConfig?.[port.id]?.label ?? port.label,
      offset: nodeData.portConfig?.[port.id]?.offset ?? port.offset
    }))
    .sort(sortPortDefinitions)
}

export const getNodePortByHandleId = (
  nodeOrData: Pick<FlowNode, 'data'> | CanvasNodeData,
  handleId?: string | null
): PortDefinition | null => {
  const portId = getPortIdFromHandleId(handleId)

  if (!portId) {
    return null
  }

  return getNodePorts(nodeOrData).find(port => port.id === portId) ?? null
}

const updateBusNodePortConfig = (node: FlowNode, portConfig: NodePortConfig): FlowNode => ({
  ...node,
  data: {
    ...node.data!,
    portConfig
  }
})

export const addBusPortAfterConnection = (node: FlowNode, handleId?: string | null): FlowNode => {
  if (!isBusNode(node) || !handleId || !node.data) {
    return node
  }

  const portConfig = normalizeBusPortConfig(node.data.componentKey, node.data.portConfig)
  const portId = getPortIdFromHandleId(handleId)
  const connectedPort = portId ? portConfig[portId] : undefined

  if (!connectedPort?.side) {
    return updateBusNodePortConfig(node, portConfig)
  }

  const side = connectedPort.side
  const rotatedSide = getRotatedPortSide(side, node.data.style.rotation)
  const sideOffsets = Object.values(portConfig)
    .filter(portState => (portState.side ?? 'left') === side)
    .map(portState => portState.offset ?? 50)

  const anchorOffset = sideOffsets.length === 0
    ? 50
    : VISUAL_MIN_INSERT_SIDES.has(rotatedSide)
      ? Math.min(...sideOffsets) - 1
      : Math.max(...sideOffsets) + 1

  const nextPortConfig: NodePortConfig = {
    ...portConfig,
    [createBusPortId(portConfig, side)]: createBusPortState(node.data.componentKey, side, anchorOffset)
  }

  return updateBusNodePortConfig(node, normalizeBusPortConfig(node.data.componentKey, nextPortConfig))
}

export const removeBusPortAfterEdgeRemoval = (node: FlowNode, handleId?: string | null): FlowNode => {
  if (!isBusNode(node) || !handleId || !node.data) {
    return node
  }

  const portConfig = normalizeBusPortConfig(node.data.componentKey, node.data.portConfig)
  const portId = getPortIdFromHandleId(handleId)

  if (!portId || !portConfig[portId]) {
    return updateBusNodePortConfig(node, portConfig)
  }

  const nextPortConfig: NodePortConfig = { ...portConfig }
  delete nextPortConfig[portId]

  return updateBusNodePortConfig(node, normalizeBusPortConfig(node.data.componentKey, nextPortConfig))
}

export const syncBusPortsAfterEdgeRemoval = (canvas: CanvasData, removedEdges: FlowEdge[]): CanvasData => {
  if (removedEdges.length === 0) {
    return canvas
  }

  let nextNodes = canvas.nodes

  removedEdges.forEach(edge => {
    nextNodes = nextNodes.map(node => {
      if (node.id === edge.source) {
        return removeBusPortAfterEdgeRemoval(node, edge.sourceHandle)
      }

      if (node.id === edge.target) {
        return removeBusPortAfterEdgeRemoval(node, edge.targetHandle)
      }

      return node
    })
  })

  return {
    ...canvas,
    nodes: syncNodeStyles(nextNodes)
  }
}

export const createDefaultPageConfig = (): PageConfig => ({
  width: 1500,
  height: 1050,
  backgroundColor: '#FFFFFF',
  backgroundPattern: 'grid',
  gridVisible: true,
  gridSize: 15,
  gridColor: '#E5E7EB',
  snapToGrid: true,
  showComponentName: true,
  showParameterTag: false,
  showPorts: true,
  labelLanguage: 'chinese'
})

export const createEmptyCanvas = (name = '画布1'): CanvasData => ({
  id: createId('canvas'),
  name,
  nodes: [],
  edges: [],
  viewport: { x: 0, y: 0, zoom: 1.5 },
  pageConfig: createDefaultPageConfig(),
  updatedAt: new Date().toISOString()
})

export const resolveDefinitionNodeSize = (definition: ComponentDefinition): { width: number; height: number } => {
  return {
    width: definition.defaultSize.width,
    height: definition.defaultSize.height
  }
}

const createNodeStyle = (definition: ComponentDefinition): CanvasNodeStyle => {
  const size = resolveDefinitionNodeSize(definition)

  return {
    width: size.width,
    height: size.height,
    rotation: definition.appearance.rotation,
    fillColor: definition.appearance.fillColor,
    strokeColor: definition.appearance.strokeColor,
    strokeWidth: definition.appearance.strokeWidth,
    fontSize: definition.appearance.fontSize,
    textColor: definition.appearance.textColor,
    borderRadius: definition.appearance.borderRadius,
    opacity: definition.appearance.opacity
  }
}

export const nodeStyleToCss = (style: CanvasNodeStyle, zIndex = 1): Record<string, string | number> => ({
  width: `${style.width}px`,
  height: `${style.height}px`,
  opacity: style.opacity,
  zIndex
})

export const edgeStyleToCss = (data: CanvasEdgeData): Record<string, string | number> => ({
  stroke: data.style.strokeColor,
  color: data.style.strokeColor,
  strokeWidth: data.style.strokeWidth,
  strokeDasharray: data.style.strokeDasharray,
  strokeLinecap: 'square',
  strokeLinejoin: 'miter'
})

/**
 * 去重节点名称：检查现有节点中是否有同类型同名的，自动追加 (1)(2)...
 */
export const deduplicateNodeName = (
  definition: ComponentDefinition,
  existingNodes: FlowNode[]
): string => {
  const baseName = definition.label
  const existingNames = new Set<string>()

  for (const node of existingNodes) {
    const nodeData = getCanvasNodeData(node)
    // 只比较同类型的非总线节点
    if (nodeData.categoryKey === definition.category && nodeData.componentKey === definition.key) {
      existingNames.add(nodeData.label)
    }
  }

  if (!existingNames.has(baseName)) {
    return baseName
  }

  // 找到已使用的最大序号
  const suffixRegex = new RegExp(`^${baseName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\((\\d+)\\)$`)
  let maxIndex = 0

  for (const name of existingNames) {
    const match = name.match(suffixRegex)
    if (match) {
      const idx = parseInt(match[1], 10)
      if (idx > maxIndex) maxIndex = idx
    }
  }

  return `${baseName}(${maxIndex + 1})`
}

export const createNodeFromDefinition = (
  definition: ComponentDefinition,
  position: { x: number; y: number },
  existingNodes?: FlowNode[]
): FlowNode => {
  const resolvedLabel = existingNodes ? deduplicateNodeName(definition, existingNodes) : definition.label

  const nodeData: CanvasNodeData = {
    label: resolvedLabel,
    componentKey: definition.key,
    categoryKey: definition.category,
    business: deepClone({
      ...definition.defaultMeta,
      componentName: resolvedLabel
    }),
    style: createNodeStyle(definition),
  }

  // 为所有节点生成 portConfig，使后端能读取端口介质信息
  if (definition.category === 'bus') {
    nodeData.portConfig = normalizeBusPortConfig(definition.key)
  } else if (definition.ports.length > 0) {
    const portConfig: NodePortConfig = {}
    for (const port of definition.ports) {
      portConfig[port.id] = {
        medium: port.medium,
        side: port.side,
        label: port.label
      }
    }
    nodeData.portConfig = portConfig
  }

  return {
    id: createId('node'),
    type: 'syner-node',
    position,
    sourcePosition: Position.Right,
    targetPosition: Position.Left,
    draggable: true,
    selectable: true,
    connectable: true,
    style: nodeStyleToCss(nodeData.style),
    data: nodeData
  }
}

export const calculateUniformOffsets = (count: number): number[] => {
  if (count === 0) return []
  if (count === 1) return [50]
  const step = 100 / (count + 1)
  return Array.from({ length: count }, (_, i) => Math.round((i + 1) * step))
}

// 根据端口定义获取vue-flow的handle type
export const getHandleType = (direction: 'in' | 'out'): 'target' | 'source' => {
  return direction === 'in' ? 'target' : 'source'
}

// 根据源端口的介质获取连线样式
export const createEdgeBetweenNodes = (
  source: string,
  target: string,
  medium: MediumType = 'electric',
  sourceHandle?: string | null,
  targetHandle?: string | null
): FlowEdge => {
  const mediumStyle = getMediumEdgeStyle(medium)

  const edgeData: CanvasEdgeData = {
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

  return {
    id: createId('edge'),
    source,
    target,
    sourceHandle: sourceHandle ?? undefined,
    targetHandle: targetHandle ?? undefined,
    type: 'smoothstep',
    style: edgeStyleToCss(edgeData),
    selectable: true,
    focusable: true,
    updatable: false,
    interactionWidth: 20,
    data: edgeData
  }
}

export const findCanvasById = (workspace: CanvasWorkspace, canvasId?: string): CanvasData => {
  const activeCanvasId = canvasId ?? workspace.activeCanvasId
  return workspace.canvases.find(canvas => canvas.id === activeCanvasId) ?? workspace.canvases[0]
}

export const syncCanvasTimestamp = (canvas: CanvasData): CanvasData => ({
  ...canvas,
  updatedAt: new Date().toISOString()
})

export const syncNodeStyles = (nodes: FlowNode[]): FlowNode[] =>
  nodes.map(node => ({
    ...node,
    style: nodeStyleToCss(node.data.style, Number(node.style?.zIndex ?? node.zIndex ?? 1))
  }))

export const syncEdgeStyles = (edges: FlowEdge[]): FlowEdge[] =>
  edges.map(edge => {
    const arrowType = edge.data?.style?.arrowType ?? 'none'
    return {
      ...edge,
      type: 'step',
      markerStart: arrowType === 'start' || arrowType === 'both' ? MarkerType.ArrowClosed : undefined,
      markerEnd: arrowType === 'end' || arrowType === 'both' ? MarkerType.ArrowClosed : undefined,
      selectable: true,
      focusable: true,
      updatable: false,
      interactionWidth: Number(edge.interactionWidth ?? 20),
      style: edge.data ? edgeStyleToCss(edge.data) : undefined,
      data: edge.data ? {
        ...edge.data,
        style: {
          ...edge.data.style,
          arrowType
        }
      } : undefined
    }
  })

export const replaceCanvas = (workspace: CanvasWorkspace, nextCanvas: CanvasData): CanvasWorkspace => ({
  ...workspace,
  activeCanvasId: nextCanvas.id,
  canvases: workspace.canvases.map(canvas => (canvas.id === nextCanvas.id ? syncCanvasTimestamp(nextCanvas) : canvas))
})

export const appendCanvas = (workspace: CanvasWorkspace, name: string): CanvasWorkspace => {
  const canvas = createEmptyCanvas(name)
  return {
    ...workspace,
    activeCanvasId: canvas.id,
    canvases: [...workspace.canvases, canvas]
  }
}

export const removeCanvas = (workspace: CanvasWorkspace, canvasId: string): CanvasWorkspace => {
  const nextCanvases = workspace.canvases.filter(canvas => canvas.id !== canvasId)

  if (nextCanvases.length === 0) {
    const fallback = createEmptyCanvas('画布1')
    return {
      ...workspace,
      activeCanvasId: fallback.id,
      canvases: [fallback]
    }
  }

  return {
    ...workspace,
    activeCanvasId: nextCanvases[0].id,
    canvases: nextCanvases
  }
}

export const buildClipboard = (canvas: CanvasData, selection: CanvasSelection): CanvasClipboard | null => {
  if (selection.nodeIds.length === 0 && selection.edgeIds.length === 0) {
    return null
  }

  const nodeIds = new Set(selection.nodeIds)
  const edgeIds = new Set(selection.edgeIds)

  if (nodeIds.size === 0 && edgeIds.size > 0) {
    canvas.edges.forEach(edge => {
      if (edgeIds.has(edge.id)) {
        nodeIds.add(edge.source)
        nodeIds.add(edge.target)
      }
    })
  }

  const nodes = canvas.nodes.filter(node => nodeIds.has(node.id))
  const edges = canvas.edges.filter(edge => edgeIds.has(edge.id) || (nodeIds.has(edge.source) && nodeIds.has(edge.target)))

  if (nodes.length === 0 && edges.length === 0) {
    return null
  }

  return {
    nodes: deepClone(nodes),
    edges: deepClone(edges)
  }
}

let pasteCount = 0

export const resetPasteCount = () => {
  pasteCount = 0
}

export const pasteClipboard = (
  canvas: CanvasData,
  clipboard: CanvasClipboard | null
): { canvas: CanvasData; selection: CanvasSelection } => {
  if (!clipboard) {
    return {
      canvas,
      selection: { nodeIds: [], edgeIds: [], primaryNodeId: null, primaryEdgeId: null }
    }
  }

  const nodeIdMap = new Map<string, string>()
  const offset = pasteCount * 16
  pasteCount++

  const pastedNodes = clipboard.nodes.map(node => {
    const nextId = createId('node')
    nodeIdMap.set(node.id, nextId)
    const normalizedNode = normalizeBusNode(deepClone(node))

    return {
      ...normalizedNode,
      id: nextId,
      position: {
        x: node.position.x + 36 + offset,
        y: node.position.y + 36 + offset
      }
    }
  })

  // 为粘贴的非总线节点去重命名
  const existingNodes = canvas.nodes
  const alreadyPasted: FlowNode[] = []
  for (const pastedNode of pastedNodes) {
    const nodeData = getCanvasNodeData(pastedNode)
    if (!isBusNode(pastedNode)) {
      const definition = componentDefinitionMap[nodeData.componentKey]
      if (definition) {
        // 去重时同时考虑已粘贴的节点，避免批量粘贴时同名
        const newName = deduplicateNodeName(definition, [...existingNodes, ...alreadyPasted])
        pastedNode.data = {
          ...nodeData,
          label: newName,
          business: {
            ...nodeData.business,
            componentName: newName
          }
        }
        alreadyPasted.push(pastedNode)
      }
    }
  }

  const pastedEdges = clipboard.edges
    .filter(edge => nodeIdMap.has(edge.source) && nodeIdMap.has(edge.target))
    .map(edge => ({
      ...deepClone(edge),
      id: createId('edge'),
      source: nodeIdMap.get(edge.source) ?? edge.source,
      target: nodeIdMap.get(edge.target) ?? edge.target
    }))

  const nextCanvas: CanvasData = {
    ...canvas,
    nodes: syncNodeStyles([...canvas.nodes, ...pastedNodes]),
    edges: syncEdgeStyles([...canvas.edges, ...pastedEdges])
  }

  return {
    canvas: syncCanvasTimestamp(nextCanvas),
    selection: {
      nodeIds: pastedNodes.map(node => node.id),
      edgeIds: pastedEdges.map(edge => edge.id),
      primaryNodeId: pastedNodes[0]?.id ?? null,
      primaryEdgeId: pastedEdges[0]?.id ?? null
    }
  }
}

export const deleteSelectionFromCanvas = (canvas: CanvasData, selection: CanvasSelection): CanvasData => {
  const removedEdges = canvas.edges.filter(
    edge =>
      selection.edgeIds.includes(edge.id) ||
      selection.nodeIds.includes(edge.source) ||
      selection.nodeIds.includes(edge.target)
  )

  // Filter out nodes being deleted
  const updatedNodes = canvas.nodes.filter(node => !selection.nodeIds.includes(node.id))

  // Filter out edges being deleted (including edges connected to deleted nodes)
  const updatedEdges = canvas.edges.filter(
    edge =>
      !selection.edgeIds.includes(edge.id) &&
      !selection.nodeIds.includes(edge.source) &&
      !selection.nodeIds.includes(edge.target)
  )

  return syncBusPortsAfterEdgeRemoval({
    ...canvas,
    nodes: updatedNodes,
    edges: updatedEdges
  }, removedEdges)
}

const getSelectedNodes = (canvas: CanvasData, selection: CanvasSelection): FlowNode[] =>
  canvas.nodes.filter(node => selection.nodeIds.includes(node.id))

export const alignSelectedNodes = (canvas: CanvasData, selection: CanvasSelection, mode: string): CanvasData => {
  const selectedNodes = getSelectedNodes(canvas, selection)

  if (selectedNodes.length < 2) {
    return canvas
  }

  const minX = Math.min(...selectedNodes.map(node => node.position.x))
  const maxX = Math.max(...selectedNodes.map(node => node.position.x + node.data.style.width))
  const minY = Math.min(...selectedNodes.map(node => node.position.y))
  const maxY = Math.max(...selectedNodes.map(node => node.position.y + node.data.style.height))
  const centerX = (minX + maxX) / 2
  const centerY = (minY + maxY) / 2

  return {
    ...canvas,
    nodes: syncNodeStyles(
      canvas.nodes.map(node => {
        if (!selection.nodeIds.includes(node.id)) {
          return node
        }

        if (mode === 'align-left') {
          return { ...node, position: { ...node.position, x: minX } }
        }

        if (mode === 'align-center') {
          return { ...node, position: { ...node.position, x: centerX - node.data.style.width / 2 } }
        }

        if (mode === 'align-right') {
          return { ...node, position: { ...node.position, x: maxX - node.data.style.width } }
        }

        if (mode === 'align-top') {
          return { ...node, position: { ...node.position, y: minY } }
        }

        if (mode === 'align-middle') {
          return { ...node, position: { ...node.position, y: centerY - node.data.style.height / 2 } }
        }

        if (mode === 'align-bottom') {
          return { ...node, position: { ...node.position, y: maxY - node.data.style.height } }
        }

        return node
      })
    )
  }
}

export const distributeSelectedNodes = (canvas: CanvasData, selection: CanvasSelection, axis: 'horizontal' | 'vertical'): CanvasData => {
  const selectedNodes = [...getSelectedNodes(canvas, selection)].sort((left, right) =>
    axis === 'horizontal'
      ? left.position.x - right.position.x
      : left.position.y - right.position.y
  )

  if (selectedNodes.length < 3) {
    return canvas
  }

  const first = selectedNodes[0]
  const last = selectedNodes[selectedNodes.length - 1]
  const distance =
    axis === 'horizontal'
      ? (last.position.x - first.position.x) / (selectedNodes.length - 1)
      : (last.position.y - first.position.y) / (selectedNodes.length - 1)

  const orderedIds = selectedNodes.map(node => node.id)

  return {
    ...canvas,
    nodes: syncNodeStyles(
      canvas.nodes.map(node => {
        const index = orderedIds.indexOf(node.id)

        if (index < 0) {
          return node
        }

        return {
          ...node,
          position:
            axis === 'horizontal'
              ? { ...node.position, x: first.position.x + distance * index }
              : { ...node.position, y: first.position.y + distance * index }
        }
      })
    )
  }
}

export const matchSelectedNodeSize = (canvas: CanvasData, selection: CanvasSelection, mode: 'width' | 'height' | 'size'): CanvasData => {
  const selectedNodes = getSelectedNodes(canvas, selection)

  if (selectedNodes.length < 2) {
    return canvas
  }

  const reference = selectedNodes[0]

  return {
    ...canvas,
    nodes: syncNodeStyles(
      canvas.nodes.map(node => {
        if (!selection.nodeIds.includes(node.id) || node.id === reference.id) {
          return node
        }

        return {
          ...node,
          data: {
            ...node.data,
            style: {
              ...node.data.style,
              width: mode === 'height' ? node.data.style.width : reference.data.style.width,
              height: mode === 'width' ? node.data.style.height : reference.data.style.height
            }
          }
        }
      })
    )
  }
}

export const reorderSelectedNodes = (canvas: CanvasData, selection: CanvasSelection, mode: 'front' | 'back' | 'forward' | 'backward'): CanvasData => {
  const selectedNodes = getSelectedNodes(canvas, selection)

  if (selectedNodes.length === 0) {
    return canvas
  }

  const currentZIndexes = canvas.nodes.map(node => Number(node.style?.zIndex ?? 1))
  const maxZIndex = Math.max(...currentZIndexes, 1)
  const minZIndex = Math.min(...currentZIndexes, 1)

  return {
    ...canvas,
    nodes: syncNodeStyles(
      canvas.nodes.map(node => {
        if (!selection.nodeIds.includes(node.id)) {
          return node
        }

        const nextZIndex =
          mode === 'front'
            ? maxZIndex + 1
            : mode === 'back'
              ? Math.max(minZIndex - 1, 0)
              : mode === 'forward'
                ? Number(node.style?.zIndex ?? 1) + 1
                : Math.max(Number(node.style?.zIndex ?? 1) - 1, 0)

        return {
          ...node,
          style: {
            ...nodeStyleToCss(node.data.style),
            zIndex: nextZIndex
          }
        }
      })
    )
  }
}

export const updateNodeFromFields = (
  node: FlowNode,
  patch: Partial<CanvasNodeStyle>,
  label?: string
): FlowNode => ({
  ...node,
  data: {
    ...node.data,
    label: label ?? node.data.label,
    style: {
      ...node.data.style,
      ...patch
    }
  },
  style: nodeStyleToCss({
    ...node.data.style,
    ...patch
  }, Number(node.style?.zIndex ?? node.zIndex ?? 1))
})

export const createInitialWorkspace = (): CanvasWorkspace => {
  const canvas = createEmptyCanvas('画布1')

  return {
    activeCanvasId: canvas.id,
    canvases: [canvas],
    clipboard: null
  }
}