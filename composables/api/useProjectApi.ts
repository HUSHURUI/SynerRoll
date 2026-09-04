import type {
  CreateProjectRequest,
  ProjectDetailResponse,
  ProjectListResponse,
  SaveCanvasRequest,
  SaveLayerConfigRequest,
  UpdateProjectRequest
} from '~~/types/api'
import type { AlgorithmConfig, SolverConfig } from '~~/types/simulation'
import { useApiClient } from './useApiClient'

export const useProjectApi = () => {
  const apiClient = useApiClient()

  return {
    listProjects: () => apiClient.get<ProjectListResponse>('/project'),
    getProject: (projectId: string) => apiClient.get<ProjectDetailResponse>(`/project/${projectId}`),
    createProject: (payload: CreateProjectRequest) =>
      apiClient.mutate<ProjectDetailResponse>('/project', { method: 'POST', body: payload }),
    updateProject: (projectId: string, payload: UpdateProjectRequest) =>
      apiClient.mutate<ProjectDetailResponse>(`/project/${projectId}`, { method: 'PUT', body: payload }),
    deleteProject: (projectId: string) => apiClient.mutate<{ projectId: string }>(`/project/${projectId}`, { method: 'DELETE' }),
    getCanvas: (projectId: string) => apiClient.get<{ workspace: import('~~/types/canvas').CanvasWorkspace }>(`/project/${projectId}/canvas`),
    saveCanvas: (projectId: string, payload: SaveCanvasRequest) =>
      apiClient.mutate<ProjectDetailResponse>(`/project/${projectId}/canvas`, { method: 'PUT', body: payload }),
    getAlgorithmConfig: (projectId: string) =>
      apiClient.get<{ algorithm: AlgorithmConfig; solverConfig: SolverConfig }>(`/project/${projectId}/algorithm-config`),
    saveAlgorithmConfig: (projectId: string, payload: { algorithm: AlgorithmConfig; solverConfig: SolverConfig }) =>
      apiClient.mutate<ProjectDetailResponse>(`/project/${projectId}/algorithm-config`, { method: 'PUT', body: payload }),
    saveBoundaries: (projectId: string, boundaries: import('~~/types/boundary').BoundaryItem[]) =>
      apiClient.mutate<ProjectDetailResponse>(`/project/${projectId}/boundary`, { method: 'PUT', body: { boundaries } }),
    saveLayerConfig: (projectId: string, payload: SaveLayerConfigRequest) =>
      apiClient.mutate<ProjectDetailResponse>(`/project/${projectId}/layer-config`, { method: 'PUT', body: payload }),
    // [废弃 2026-07-14] 仿真解析已迁移到计算任务系统：POST /api/task/create → run_task 内自动 parse
    // runSimulationParse: (projectId: string) =>
    //   apiClient.mutate<{ success: boolean; message: string; outputPath: string }>(`/project/${projectId}/simulation-parse`, { method: 'POST' })
  }
}