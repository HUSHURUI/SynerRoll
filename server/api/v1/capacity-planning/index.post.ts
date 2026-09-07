import type {
  CapacityPlanningTask,
  CreateCapacityPlanningRequest
} from '~~/types/capacity-planning'

import { apiSuccess } from '#server/utils/response'
import { readProjectById } from '#server/utils/project-store'

const JULIA_BACKEND_URL = 'http://localhost:8080/api/capacity-planning'

export default defineEventHandler(async (event) => {
  const body = await readBody<CreateCapacityPlanningRequest>(event)
  const project = await readProjectById(body.projectId)

  try {
    const response = await $fetch<{ success: boolean; data?: CapacityPlanningTask; message?: string }>(
      JULIA_BACKEND_URL,
      {
        method: 'POST',
        body: {
          ...body,
          projectJson: project
        }
      }
    )
    if (!response.success || !response.data) {
      throw createError({ statusCode: 400, statusMessage: response.message || '创建容量规划任务失败' })
    }
    return apiSuccess(response.data)
  }
  catch (error) {
    if (error && typeof error === 'object' && 'statusCode' in error) throw error
    throw createError({
      statusCode: 502,
      statusMessage: `Julia 后端不可用: ${error instanceof Error ? error.message : String(error)}`
    })
  }
})
