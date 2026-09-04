import type { BoundaryDatasetSummary } from '~~/types/capacity-planning'

import { apiSuccess } from '#server/utils/response'
import { readProjectById } from '#server/utils/project-store'

export default defineEventHandler(async (event) => {
  const projectId = String(getQuery(event).projectId ?? '')
  await readProjectById(projectId)

  const JULIA_BACKEND_URL = `http://localhost:8080/api/capacity-planning/datasets?projectId=${encodeURIComponent(projectId)}`

  const response = await $fetch<{
    success: boolean
    data?: { datasets: BoundaryDatasetSummary[] }
    message?: string
  }>(JULIA_BACKEND_URL)

  if (!response.success || !response.data) {
    throw createError({ statusCode: 400, statusMessage: response.message || '查询历史边界数据集失败' })
  }
  return apiSuccess(response.data)
})
