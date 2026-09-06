import type { CanvasWorkspace } from './canvas'
import type { Project, ProjectSummary } from './project'
import type { AlgorithmConfig, LayerConfigSet, SimulationProgress, SimulationResult } from './simulation'

export interface ApiResponse<T> {
  success: boolean
  data: T
  message?: string
}

export interface ProjectListResponse {
  projects: ProjectSummary[]
}

export interface ProjectDetailResponse {
  project: Project
}

export interface CreateProjectRequest {
  name: string
  description?: string
  template?: 'blank' | 'demo'
}

export interface UpdateProjectRequest {
  name?: string
  description?: string
  favorite?: boolean
  tags?: string[]
}

export interface SaveCanvasRequest {
  workspace: CanvasWorkspace
}

export interface SaveLayerConfigRequest {
  layerConfig: LayerConfigSet
}

export interface UpdateAlgorithmConfigRequest {
  algorithm: AlgorithmConfig
}

export interface SimulationResponse {
  progress: SimulationProgress
  result: SimulationResult | null
}

export interface ResultExportResponse {
  payload: import('./simulation').BackendExportPayload
  csv: string
}

// ───── 计算任务（task）相关 ─────
export type TaskMode = 'online' | 'offline'
export type TaskStatus =
  | 'pending'
  | 'parsing'
  | 'building'
  | 'solving'
  | 'completed'
  | 'failed'
  | 'cancelled'

export interface ComputeTask {
  id: string
  project_id: string
  canvas_id: string
  layer_id: string
  mode: TaskMode
  name: string | null
  status: TaskStatus
  params_hash: string
  sim_start_time: string
  sim_end_time: string | null
  cur_time: string | null
  created_at: string
  updated_at: string
  started_at: string | null
  finished_at: string | null
  error_message: string | null
  extra_json: string | null
}

export interface ComputeTaskListResponse {
  tasks: ComputeTask[]
}

export interface ComputeTaskStateResponse {
  task: ComputeTask
}

export interface CreateTaskRequest {
  projectId: string
  canvasId: string
  layerId: string
  mode: TaskMode
  simMode?: 'multi_layer' | 'single_layer'
  targetLayerId?: string
  simStartTime: string
  simEndTime?: string | null
  name?: string | null
}

export interface TaskDataRow {
  sourceId: string
  varName: string
  remark?: string
  layerId: string
  ts: string
  value: number
}

export interface TaskDataResponse {
  label: string
  rows: TaskDataRow[]
}

export interface TaskTraceStep {
  step: number
  layerId: string
  simTime: string
}

export interface TaskTraceStepsResponse {
  steps: TaskTraceStep[]
}

export interface TaskTraceDataResponse {
  rows: TaskDataRow[]
}
