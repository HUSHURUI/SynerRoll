import type {
  BoundaryDataset,
  BoundaryDatasetSummary,
  ApplyCapacityPlanningRequest,
  ApplyCapacityPlanningResult,
  CapacityPlanningResult,
  CapacityPlanningTask,
  CapacityPlanningFormSchema,
  ClusteringConfig,
  ImportBoundaryDatasetRequest,
  ScenarioPreviewResult,
  CreateCapacityPlanningRequest,
  CapacityVariableValidationRequest,
  CapacityVariableValidationResult
} from '~~/types/capacity-planning'
import { useApiClient } from './useApiClient'

export const useCapacityPlanningApi = () => {
  const apiClient = useApiClient()

  const getFormSchema = (projectId: string, canvasId: string) =>
    apiClient.mutate<CapacityPlanningFormSchema>('/capacity-planning/form-schema', {
      method: 'POST',
      body: { projectId, canvasId }
    })

  const validateVariables = (request: CapacityVariableValidationRequest) =>
    apiClient.mutate<CapacityVariableValidationResult>('/capacity-planning/validate', {
      method: 'POST',
      body: request
    })

  const listDatasets = (projectId: string) =>
    apiClient.get<{ datasets: BoundaryDatasetSummary[] }>(
      `/capacity-planning/datasets?projectId=${encodeURIComponent(projectId)}`
    )

  const getDataset = (projectId: string, datasetId: string) =>
    apiClient.get<BoundaryDataset>(
      `/capacity-planning/datasets/${encodeURIComponent(datasetId)}?projectId=${encodeURIComponent(projectId)}`
    )

  const importDataset = (request: ImportBoundaryDatasetRequest) =>
    apiClient.mutate<BoundaryDataset>('/capacity-planning/datasets/import', {
      method: 'POST',
      body: request
    })

  const previewScenarios = (request: ClusteringConfig) =>
    apiClient.mutate<ScenarioPreviewResult>('/capacity-planning/scenarios/preview', {
      method: 'POST',
      body: request
    })

  const createPlanning = (request: CreateCapacityPlanningRequest) =>
    apiClient.mutate<CapacityPlanningTask>('/capacity-planning', {
      method: 'POST',
      body: request
    })

  const startPlanning = (planningId: string) =>
    apiClient.mutate<CapacityPlanningTask>(`/capacity-planning/${encodeURIComponent(planningId)}/start`, {
      method: 'POST'
    })

  const cancelPlanning = (planningId: string) =>
    apiClient.mutate<CapacityPlanningTask>(`/capacity-planning/${encodeURIComponent(planningId)}/cancel`, {
      method: 'POST'
    })

  const getPlanning = (planningId: string) =>
    apiClient.get<CapacityPlanningTask>(`/capacity-planning/${encodeURIComponent(planningId)}`)

  const getPlanningResult = (planningId: string) =>
    apiClient.get<CapacityPlanningResult>(`/capacity-planning/${encodeURIComponent(planningId)}/result`)

  const listPlannings = (projectId: string) =>
    apiClient.get<{ tasks: CapacityPlanningTask[] }>(
      `/capacity-planning?projectId=${encodeURIComponent(projectId)}`
    )

  const updatePlanningConfig = (planningId: string, config: { clustering?: Partial<ClusteringConfig>; variables?: CapacityVariableDraft[] }) =>
    apiClient.mutate<CapacityPlanningTask>(
      `/capacity-planning/${encodeURIComponent(planningId)}/config`,
      {
        method: 'PUT',
        body: config
      }
    )

  const applyAndSimulate = (planningId: string, request: ApplyCapacityPlanningRequest) =>
    apiClient.mutate<ApplyCapacityPlanningResult>(
      `/capacity-planning/${encodeURIComponent(planningId)}/apply-and-simulate`,
      {
        method: 'POST',
        body: request
      }
    )

  return {
    getFormSchema,
    validateVariables,
    listDatasets,
    getDataset,
    importDataset,
    previewScenarios,
    createPlanning,
    startPlanning,
    cancelPlanning,
    getPlanning,
    getPlanningResult,
    listPlannings,
    updatePlanningConfig,
    applyAndSimulate
  }
}
