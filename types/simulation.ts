// ============================================================
// 时层配置（项目级别）
// ============================================================

export interface LayerDefinition {
  id: string
  name: string
  length: string
  step: string
  forward: string
}

// 时层配置集合（项目级别，每个项目有一组时层配置）
export interface LayerConfigSet {
  layers: LayerDefinition[]
}

// 默认时层配置
export const DEFAULT_LAYER_CONFIG: LayerConfigSet = {
  layers: [
    { id: '1', name: '周前', length: '168h', step: '60m', forward: '60m'},
    { id: '2', name: '日前', length: '24h', step: '60m', forward: '60m' },
    { id: '3', name: '日内', length: '8h', step: '30m', forward: '60m' },
    { id: '4', name: '短时', length: '4h', step: '15m', forward: '60m' },
    { id: '5', name: '实时', length: '1h', step: '5m', forward: '5m' }
  ]
}

// ============================================================
// 算法与求解器配置（Project 级别）
// ============================================================

export interface AlgorithmConfig {
  electricityLoadPrediction: string
  windTurbinePrediction: string
  optimizationAlgorithm: string
  slackEnabled: boolean
  slackPenalty: number
}

export interface SolverConfig {
  tolerance: number
  maxIteration: number
  threadCount: number
  warmStart: boolean
}

// ============================================================
// 仿真状态（独立存储，非 Project 组成部分）
// ============================================================

export type SimulationStatus = 'idle' | 'running' | 'paused' | 'completed' | 'stopped' | 'error'

export interface SimulationProgress {
  status: SimulationStatus
  percent: number
  currentStage: string
  message: string
  updatedAt: string
  simulationId: string
  startedAt?: string
  durationMs?: number
}

export interface SimulationResult {
  projectId: string
  simulationId: string
  startTime: string
  endTime: string
  status: SimulationStatus
  resultData: SimulationResultDataset
  summary: Record<string, number>
  reportMarkdown?: string
  reportUrl?: string
}

export interface SimulationResultDataset {
  timeline: string[]
  output: MetricSeries[]
  load: MetricSeries[]
  storage: MetricSeries[]
  cost: MetricSeries[]
}

export interface MetricSeries {
  label: string
  unit: string
  values: number[]
}

export interface BackendComponentRecord {
  type: string
  paras: Record<string, string | number | boolean>
  costs: Record<string, number>
  layer: Record<string, Record<string, string | number | boolean>>
}

export interface BackendNodeRecord {
  Type: string
  Component: string[]
}

import type { BoundaryItem } from './boundary'

export interface BackendExportPayload {
  algorithm: Record<string, string>
  boundary: BoundaryItem[]
  component: BackendComponentRecord[]
  layer: Record<string, { id: string; name: string; length: string; step: string; forward: string | null }>
  node: BackendNodeRecord[]
}
