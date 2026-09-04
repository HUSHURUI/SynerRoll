import type { BoundaryDataset } from '~~/types/capacity-planning'

import { apiSuccess } from '#server/utils/response'
import { readProjectById } from '#server/utils/project-store'

export default defineEventHandler(async (event) => {
  const projectId = String(getQuery(event).projectId ?? '')
  const datasetId = getRouterParam(event, 'id') ?? ''
  await readProjectById(projectId)

  const JULIA_BACKEND_URL = `http://localhost:8080/api/capacity-planning/datasets/${encodeURIComponent(datasetId)}?projectId=${encodeURIComponent(projectId)}`

  const response = await $fetch<{ success: boolean; data?: BoundaryDataset; message?: string }>(JULIA_BACKEND_URL)
  if (!response.success || !response.data) {
    throw createError({ statusCode: 404, statusMessage: response.message || '历史边界数据集不存在' })
  }
  return apiSuccess(response.data)
})
