import type { SimulationProgress, SimulationResult } from '~~/types/simulation'
import { createId } from '~~/utils/id'

export interface SimulationState {
  progress: SimulationProgress
  result: SimulationResult | null
}

const createInitialProgress = (): SimulationProgress => ({
  status: 'idle',
  percent: 0,
  currentStage: '待启动',
  message: '仿真尚未开始',
  updatedAt: new Date().toISOString(),
  simulationId: createId('sim')
})

export const useSimulationState = (projectId: string) =>
  useState<SimulationState>(`simulation-state-${projectId}`, () => ({
    progress: createInitialProgress(),
    result: null
  }))

export const useSimulationStore = () => {
  const states = useState<Record<string, SimulationState>>('simulation-store', () => {})

  const getState = (projectId: string): SimulationState => {
    if (!states.value[projectId]) {
      states.value[projectId] = {
        progress: createInitialProgress(),
        result: null
      }
    }
    return states.value[projectId]
  }

  const setProgress = (projectId: string, progress: SimulationProgress): void => {
    states.value = {
      ...states.value,
      [projectId]: {
        ...getState(projectId),
        progress
      }
    }
  }

  const setResult = (projectId: string, result: SimulationResult): void => {
    states.value = {
      ...states.value,
      [projectId]: {
        ...getState(projectId),
        result
      }
    }
  }

  return {
    states,
    getState,
    setProgress,
    setResult
  }
}