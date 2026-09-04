export type CapacityVariableMode = 'optimize' | 'fixed'

export interface CapacityVariableDraft {
  componentId: string
  componentKey: string
  componentName: string
  parameterPath: 'data.business.commonTechParams.capacity'
  unit: string
  currentValue: number
  mode: CapacityVariableMode
  fixedValue: number
  lowerBound: number
  upperBound: number
  suggestedValue: number
  step?: number | null
  schemaMin?: number | null
  schemaMax?: number | null
  needsUserInput: boolean
}

export interface CapacityPlanningFormSchema {
  schemaVersion: 'capacity-variable-form-v1'
  projectId: string
  projectName: string
  projectUpdatedAt: string
  canvasId: string
  canvasName: string
  variables: CapacityVariableDraft[]
  warnings: string[]
}

export interface CapacityVariableValidationResult {
  canvasId: string
  projectUpdatedAt: string
  variables: CapacityVariableDraft[]
}

export interface CapacityVariableValidationRequest {
  projectId: string
  canvasId: string
  variables: CapacityVariableDraft[]
}

export interface BoundaryDatasetSeriesInput {
  boundaryId: string
  columnName: string
  unit: string
}

export interface BoundaryDatasetSeries extends BoundaryDatasetSeriesInput {
  name: string
  meaning: string
  componentId: string
}

export interface BoundaryDatasetSummary {
  id: string
  projectId: string
  name: string
  timezone: string
  resolutionMinutes: number
  startAt: string
  endAt: string
  createdAt: string
  contentHash: string
  pointCount: number
  seriesCount: number
}

export interface BoundaryDataset extends BoundaryDatasetSummary {
  series: BoundaryDatasetSeries[]
}

export interface ImportBoundaryDatasetRequest {
  projectId: string
  name: string
  filePath: string
  timezone: string
  resolutionMinutes: number
  timestampColumn?: string
  startAt?: string
  series: BoundaryDatasetSeriesInput[]
}

export interface ClusteringConfig {
  projectId: string
  datasetId: string
  featureIds: string[]
  clusterCount: number
  algorithm: 'kmeans' | 'kmedoids'
  normalize: 'zscore' | 'minmax' | 'none'
  missingDayThreshold: number
  seed: number
  representative: 'nearest-observation'
}

export interface TypicalDayScenario {
  scenarioId: string
  representativeDate: string
  weightDays: number
  probability: number
  memberDates: string[]
  distanceToCenter: number
  series: Record<string, number[]>
}

export interface ScenarioPreviewResult {
  scenarioSetHash: string
  dataset: BoundaryDataset
  config: Omit<ClusteringConfig, 'projectId' | 'datasetId'> & { resolutionMinutes: number }
  scenarios: TypicalDayScenario[]
  quality: {
    validDayCount: number
    excludedDayCount: number
    excludedDays: Record<string, string>
    sse: number
    iterations: number
    converged: boolean
    normalization: Record<string, Record<string, number | string>>
    alignment: {
      originallyAligned: boolean
      originalLengthsConsistent: boolean
      originalPointCounts: Record<string, number>
      alignedPointCount: number
      truncatedPointCount: number
      truncatedPointCounts: Record<string, number>
      commonStartAt: string
      commonEndAt: string
    }
    weightedMeanError: Record<string, {
      originalMean: number
      representativeMean: number
      relativeError: number
    }>
    warnings: string[]
  }
}

export type CapacityPlanningStatus =
  | 'draft'
  | 'queued'
  | 'validating'
  | 'clustering'
  | 'optimizing'
  | 'completed'
  | 'failed'
  | 'cancelled'

export interface CapacityOptimizerConfig {
  method: 'adaptive_de_rand_1_bin_radiuslimited'
  maxFuncEvals: number
  populationSize: number
  maxTimeSeconds?: number
  seed: number
  failurePenalty: number
}

export interface CapacityEconomicsConfig {
  evaluator: 'operating-objective-v1'
  currency: string
}

export interface CreateCapacityPlanningRequest {
  projectId: string
  canvasId: string
  name: string
  variables: CapacityVariableDraft[]
  planningLayerId: string
  clustering: Omit<ClusteringConfig, 'projectId'>
  optimizer: CapacityOptimizerConfig
  economics: CapacityEconomicsConfig
}

export interface CapacityPlanningConvergencePoint {
  ordinal: number
  fitness: number
  feasible: boolean
  bestSoFar: number | null
}

export interface CapacityPlanningProgress {
  phase: CapacityPlanningStatus
  completedEvaluations: number
  failedEvaluations: number
  maxFuncEvals?: number
  bestFitness: number | null
  bestCandidate: Record<string, { value: number; unit: string; mode: CapacityVariableMode }> | null
  convergence?: CapacityPlanningConvergencePoint[]
  elapsedMs: number
}

export interface CapacityPlanningTask {
  id: string
  projectId: string
  canvasId: string
  name: string | null
  status: CapacityPlanningStatus
  projectUpdatedAt: string
  projectSnapshotHash: string
  scenarioSetHash: string | null
  config: {
    variables: CapacityVariableDraft[]
    clustering: ClusteringConfig
    optimizer: CapacityOptimizerConfig
    economics: CapacityEconomicsConfig
    planningLayerId: string
  }
  progress: CapacityPlanningProgress
  bestEvaluationId: number | null
  createdAt: string
  updatedAt: string
  startedAt: string | null
  finishedAt: string | null
  errorCode: string | null
  errorMessage: string | null
}

export interface CapacityPlanningResultVariable {
  componentId: string
  componentKey: string
  componentName: string
  mode: CapacityVariableMode
  unit: string
  currentValue: number
  optimalValue: number
  changeRate: number | null
}

export interface CapacityPlanningResult {
  planningId: string
  projectId: string
  canvasId: string
  projectUpdatedAt: string
  scenarioSetHash: string
  fitness: number
  breakdown: Record<string, unknown>
  warnings: string[]
  economicEvaluatorVersion: string
  simulationEvaluatorVersion: string
  variables: CapacityPlanningResultVariable[]
  bestCandidate: Record<string, { value: number; unit: string; mode: CapacityVariableMode }>
  evaluationCount: number
  failedEvaluationCount: number
  convergence: CapacityPlanningConvergencePoint[]
  scenarioSummary: {
    config: ScenarioPreviewResult['config']
    quality: ScenarioPreviewResult['quality']
    scenarios: Array<Pick<TypicalDayScenario, 'scenarioId' | 'representativeDate' | 'weightDays' | 'probability'>>
  }
}

export interface ApplyCapacityPlanningRequest {
  expectedProjectUpdatedAt: string
  mode: 'offline'
  name: string
}

export interface ApplyCapacityPlanningResult {
  projectApplied: boolean
  projectUpdatedAt: string
  taskCreated: boolean
  taskId: string | null
  boundarySource: 'full-history'
  datasetId: string
  simStartTime: string
  simEndTime: string
  boundaryTailPolicy: 'wrap-first-day-lookahead'
  message?: string
}
