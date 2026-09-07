import type { Edge, Node } from '@vue-flow/core'

import type { ComponentMeta, MediumType, PortSide } from './component'

// ─────────────────────────────────────────────────────────────────────────────
// 页面配置
// ─────────────────────────────────────────────────────────────────────────────

export interface PageConfig {
  width: number
  height: number
  backgroundColor: string
  backgroundPattern: 'grid' | 'dots' | 'hidden'
  gridVisible: boolean
  gridSize: number
  gridColor: string
  snapToGrid: boolean
  showComponentName: boolean
  showParameterTag: boolean
  showPorts: boolean
  labelLanguage: 'chinese' | 'english' | 'hidden'
}

// ─────────────────────────────────────────────────────────────────────────────
// 样式类型
// ─────────────────────────────────────────────────────────────────────────────

export interface CanvasNodeStyle {
  width: number
  height: number
  rotation: number
  fillColor: string
  strokeColor: string
  strokeWidth: number
  fontSize: number
  textColor: string
  borderRadius: number
  opacity: number
  // 名称标签样式
  nameFontSize?: number
  nameTextColor?: string
  // 参数标签样式
  paramFontSize?: number
  paramTextColor?: string
}

export interface CanvasEdgeStyle {
  strokeColor: string
  strokeWidth: number
  strokeDasharray: string
  labelColor: string
  // 箭头类型：none=无箭头，start=起点箭头，end=终点箭头，both=双向箭头
  arrowType: 'none' | 'start' | 'end' | 'both'
}

// ─────────────────────────────────────────────────────────────────────────────
// 节点 / 连线 数据载体
// ─────────────────────────────────────────────────────────────────────────────

export interface CanvasNodeData {
  // 用户自定义的节点名称
  label: string
  // 组件库中的唯一标识（如 "WT"、"GRID"）
  componentKey: string
  // 运行时业务数据（参数、时层配置等）
  business: ComponentMeta
  // 外观样式
  style: CanvasNodeStyle
  // 节点级端口配置（覆盖组件定义的端口设置）
  portConfig?: NodePortConfig
}

export interface CanvasEdgeData {
  label: string
  // 介质类型，继承自源端口的 medium，决定连线颜色
  medium: MediumType
  style: CanvasEdgeStyle
}

// FlowNode / FlowEdge 是 VueFlow 的类型别名
export type FlowNode = Node<CanvasNodeData>
export type FlowEdge = Edge<CanvasEdgeData>

// 节点级端口配置（用于覆盖组件定义中的端口设置）
export interface NodePortState {
  label?: string
  offset?: number
  side?: PortSide
  medium?: MediumType
}

export interface NodePortConfig {
  [portId: string]: NodePortState
}

// ─────────────────────────────────────────────────────────────────────────────
// 数据结构
// ─────────────────────────────────────────────────────────────────────────────

// 单个画布
export interface CanvasData {
  id: string
  name: string
  nodes: FlowNode[]
  edges: FlowEdge[]
  viewport: Viewport
  pageConfig: PageConfig
  updatedAt: string
}

// 多画布工作区
export interface CanvasWorkspace {
  activeCanvasId: string
  canvases: CanvasData[]
  clipboard: CanvasClipboard | null
}

// 复制粘贴缓存
export interface CanvasClipboard {
  nodes: FlowNode[]
  edges: FlowEdge[]
}

// 选区
export interface CanvasSelection {
  nodeIds: string[]
  edgeIds: string[]
  primaryNodeId: string | null
  primaryEdgeId: string | null
}

// 历史快照（undo/redo 用）
export interface HistorySnapshot {
  label: string
  workspace: CanvasWorkspace
  capturedAt: string
}

// ─────────────────────────────────────────────────────────────────────────────
// VueFlow 视角类型（内联避免 import 兼容问题）
// ─────────────────────────────────────────────────────────────────────────────

export interface Viewport {
  x: number
  y: number
  zoom: number
}