import type { CapacityPlanningTask } from '~~/types/capacity-planning'

import { apiSuccess } from '#server/utils/response'

const JULIA_BACKEND_URL = 'http://localhost:8080/api/capacity-planning'

export default defineEventHandler(async (event) => {
  const id = getRouterParam(event, 'id') ?? ''
  try {
    const response = await $fetch<{ success: boolean; data?: CapacityPlanningTask; message?: string }>(
      `${JULIA_BACKEND_URL}/${encodeURIComponent(id)}`
    )
    if (!response.success || !response.data) {
      throw createError({ statusCode: 404, statusMessage: response.message || '容量规划任务不存在' })
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
