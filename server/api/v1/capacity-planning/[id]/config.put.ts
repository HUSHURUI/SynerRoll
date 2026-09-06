import type { CapacityPlanningTask } from '~~/types/capacity-planning'

import { apiSuccess } from '#server/utils/response'

const JULIA_BACKEND_URL = 'http://localhost:8080/api/capacity-planning'

export default defineEventHandler(async (event) => {
  const id = getRouterParam(event, 'id') ?? ''
  const body = await readBody(event)

  try {
    const response = await $fetch<{ success: boolean; data?: CapacityPlanningTask; message?: string }>(
      `${JULIA_BACKEND_URL}/${encodeURIComponent(id)}/config`,
      {
        method: 'PUT',
        body,
      }
    )
    if (!response.success || !response.data) {
      throw createError({ statusCode: 400, statusMessage: response.message || '更新任务配置失败' })
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
