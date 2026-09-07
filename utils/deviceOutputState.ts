export type StoredDeviceOutputAnalysisMode = 'range' | 'point'

export interface StoredDeviceOutputChart {
  id: string
  title: string
  selectedKeys: string[]
  units: Record<string, string>
  zoomStart: number
  zoomEnd: number
  analysisMode: StoredDeviceOutputAnalysisMode
  traceStep: number | null
}

export interface StoredDeviceOutputAnalysisState {
  selectedLayerIds: string[]
  selectedLayerId?: string
  activeChartId: string
  charts: StoredDeviceOutputChart[]
}

const stateByTask = new Map<string, StoredDeviceOutputAnalysisState>()

function copyState(state: StoredDeviceOutputAnalysisState): StoredDeviceOutputAnalysisState {
  return {
    selectedLayerIds: [...(state.selectedLayerIds ?? (state.selectedLayerId ? [state.selectedLayerId] : []))],
    activeChartId: state.activeChartId,
    charts: state.charts.map(chart => ({
      ...chart,
      selectedKeys: [...chart.selectedKeys],
      units: { ...chart.units }
    }))
  }
}

export function readDeviceOutputAnalysisState(taskId: string): StoredDeviceOutputAnalysisState | null {
  if (import.meta.server) return null
  const state = stateByTask.get(taskId)
  return state ? copyState(state) : null
}

export function saveDeviceOutputAnalysisState(taskId: string, state: StoredDeviceOutputAnalysisState): void {
  if (import.meta.server || !taskId) return
  stateByTask.set(taskId, copyState(state))
}
