import type { CapacityPlanningTask } from '~~/types/capacity-planning'

import { apiSuccess } from '#server/utils/response'
import { readProjectById } from '#server/utils/project-store'

const JULIA_BACKEND_URL = 'http://localhost:8080/api/capacity-planning'

export default defineEventHandler(async (event) => {
  const { projectId = '' } = getQuery(event)
  const normalizedProjectId = String(projectId)
  if (normalizedProjectId) await readProjectById(normalizedProjectId)

  try {
    const response = await $fetch<{
      success: boolean
      data?: { tasks: CapacityPlanningTask[] }
      message?: string
    }>(JULIA_BACKEND_URL, {
      query: normalizedProjectId ? { projectId: normalizedProjectId } : undefined
    })
    if (!response.success || !response.data) {
      throw createError({ statusCode: 400, statusMessage: response.message || '查询容量规划任务失败' })
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
