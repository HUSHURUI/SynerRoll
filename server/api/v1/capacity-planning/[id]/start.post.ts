import type { CapacityPlanningTask } from '~~/types/capacity-planning'

import { apiSuccess } from '#server/utils/response'

const JULIA_BACKEND_URL = 'http://localhost:8080/api/capacity-planning'

export default defineEventHandler(async (event) => {
  const id = getRouterParam(event, 'id') ?? ''
  const response = await $fetch<{ success: boolean; data?: CapacityPlanningTask; message?: string }>(
    `${JULIA_BACKEND_URL}/${encodeURIComponent(id)}/start`,
    { method: 'POST', body: {} }
  ).catch(error => ({ success: false, message: error instanceof Error ? error.message : String(error) }))
  if (!response.success || !response.data) {
    throw createError({ statusCode: 400, statusMessage: response.message || '启动容量规划任务失败' })
  }
  return apiSuccess(response.data)
})
