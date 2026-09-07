import type {
  ApplyCapacityPlanningRequest,
  ApplyCapacityPlanningResult,
  BoundaryDataset,
  CapacityPlanningResult,
  CapacityPlanningTask
} from '~~/types/capacity-planning'

import { apiSuccess } from '#server/utils/response'
import { updateProject } from '#server/utils/project-store'

const JULIA_CAPACITY_URL = 'http://localhost:8080/api/capacity-planning'
const JULIA_TASK_URL = 'http://localhost:8080/api/task/create'

const minutesToLabel = (minutes: number) => {
  const wholeMinutes = Math.max(0, Math.floor(minutes))
  return `${Math.floor(wholeMinutes / 60)}:${String(wholeMinutes % 60).padStart(2, '0')}`
}

export default defineEventHandler(async (event) => {
  const planningId = getRouterParam(event, 'id') ?? ''
  const body = await readBody<ApplyCapacityPlanningRequest>(event)
  if (!body.expectedProjectUpdatedAt) {
    throw createError({ statusCode: 400, statusMessage: '缺少 expectedProjectUpdatedAt' })
  }

  const [taskResponse, resultResponse] = await Promise.all([
    $fetch<{ success: boolean; data?: CapacityPlanningTask; message?: string }>(
      `${JULIA_CAPACITY_URL}/${encodeURIComponent(planningId)}`
    ),
    $fetch<{ success: boolean; data?: CapacityPlanningResult; message?: string }>(
      `${JULIA_CAPACITY_URL}/${encodeURIComponent(planningId)}/result`
    )
  ])
  if (!taskResponse.success || !taskResponse.data || taskResponse.data.status !== 'completed') {
    throw createError({ statusCode: 400, statusMessage: taskResponse.message || '容量规划任务尚未完成' })
  }
  if (!resultResponse.success || !resultResponse.data) {
    throw createError({ statusCode: 400, statusMessage: resultResponse.message || '容量规划结果不存在' })
  }

  const planningTask = taskResponse.data
  const planningResult = resultResponse.data
  const datasetId = planningTask.config.clustering.datasetId
  const datasetResponse = await $fetch<{ success: boolean; data?: BoundaryDataset; message?: string }>(
    `${JULIA_CAPACITY_URL}/datasets/${encodeURIComponent(datasetId)}?projectId=${encodeURIComponent(planningTask.projectId)}`
  )
  if (!datasetResponse.success || !datasetResponse.data) {
    throw createError({ statusCode: 400, statusMessage: datasetResponse.message || '规划使用的历史数据集已不存在' })
  }
  const dataset = datasetResponse.data

  const updatedProject = await updateProject(planningTask.projectId, (current) => {
    if (current.updateTime !== body.expectedProjectUpdatedAt) {
      throw createError({
        statusCode: 409,
        statusMessage: `项目已在规划后更新（当前 ${current.updateTime}），请重新规划或确认新版本`
      })
    }

    const next = structuredClone(current)
    const canvas = next.workspace.canvases.find(item => item.id === planningTask.canvasId)
    if (!canvas) {
      throw createError({ statusCode: 409, statusMessage: '规划画布已不存在，不能应用结果' })
    }

    for (const variable of planningResult.variables) {
      const node = canvas.nodes.find(item => item.id === variable.componentId)
      if (!node) {
        throw createError({ statusCode: 409, statusMessage: `设备 ${variable.componentName} 已不存在` })
      }
      const business = node.data.business
      if (business.componentKey !== variable.componentKey) {
        throw createError({ statusCode: 409, statusMessage: `设备 ${variable.componentName} 的类型已改变` })
      }
      if (typeof business.commonTechParams.capacity !== 'number') {
        throw createError({ statusCode: 409, statusMessage: `设备 ${variable.componentName} 的 capacity 已不是数值` })
      }
      business.commonTechParams.capacity = variable.optimalValue
    }
    return next
  })

  const simStartTime = '0:00'
  const simEndTime = minutesToLabel(dataset.pointCount * dataset.resolutionMinutes)
  try {
    const computeResponse = await $fetch<{
      success: boolean
      data?: Record<string, unknown>
      message?: string
    }>(JULIA_TASK_URL, {
      method: 'POST',
      body: {
        projectId: updatedProject.id,
        canvasId: planningTask.canvasId,
        layerId: planningTask.config.planningLayerId,
        mode: body.mode || 'offline',
        simStartTime,
        simEndTime,
        name: body.name || '容量规划最优解全历史仿真',
        boundarySource: 'full-history',
        datasetId,
        boundaryTailPolicy: 'wrap-first-day-lookahead',
        projectJson: updatedProject
      }
    })
    if (!computeResponse.success || !computeResponse.data) {
      return apiSuccess<ApplyCapacityPlanningResult>({
        projectApplied: true,
        projectUpdatedAt: updatedProject.updateTime,
        taskCreated: false,
        taskId: null,
        boundarySource: 'full-history',
        datasetId,
        simStartTime,
        simEndTime,
        boundaryTailPolicy: 'wrap-first-day-lookahead',
        message: computeResponse.message || '容量已应用，但创建仿真任务失败'
      })
    }
    return apiSuccess<ApplyCapacityPlanningResult>({
      projectApplied: true,
      projectUpdatedAt: updatedProject.updateTime,
      taskCreated: true,
      taskId: typeof computeResponse.data.id === 'string' ? computeResponse.data.id : null,
      boundarySource: 'full-history',
      datasetId,
      simStartTime,
      simEndTime,
      boundaryTailPolicy: 'wrap-first-day-lookahead'
    })
  }
  catch (error) {
    return apiSuccess<ApplyCapacityPlanningResult>({
      projectApplied: true,
      projectUpdatedAt: updatedProject.updateTime,
      taskCreated: false,
      taskId: null,
      boundarySource: 'full-history',
      datasetId,
      simStartTime,
      simEndTime,
      boundaryTailPolicy: 'wrap-first-day-lookahead',
      message: `容量已应用，但创建仿真任务失败：${error instanceof Error ? error.message : String(error)}`
    })
  }
})
