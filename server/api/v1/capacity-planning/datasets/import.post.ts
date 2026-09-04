import type {
  BoundaryDataset,
  ImportBoundaryDatasetRequest
} from '~~/types/capacity-planning'

import { apiSuccess } from '#server/utils/response'
import { readProjectById } from '#server/utils/project-store'

const JULIA_BACKEND_URL = 'http://localhost:8080/api/capacity-planning/datasets/import'

export default defineEventHandler(async (event) => {
  const body = await readBody<ImportBoundaryDatasetRequest>(event)
  const project = await readProjectById(body.projectId)
  const boundaries = new Map(project.boundaries.map(boundary => [boundary.id, boundary]))

  if (!Array.isArray(body.series) || body.series.length === 0) {
    throw createError({ statusCode: 400, statusMessage: '至少选择一条边界序列' })
  }

  const series = body.series.map((item) => {
    const boundary = boundaries.get(item.boundaryId)
    if (!boundary) {
      throw createError({ statusCode: 400, statusMessage: `项目中不存在边界 ${item.boundaryId}` })
    }
    if (!item.columnName?.trim()) {
      throw createError({ statusCode: 400, statusMessage: `${boundary.name} 缺少 CSV 列名` })
    }
    return {
      boundaryId: boundary.id,
      name: boundary.name,
      meaning: boundary.meaning,
      componentId: boundary.relatedComponents?.[0] ?? '',
      unit: item.unit?.trim() ?? '',
      columnName: item.columnName.trim()
    }
  })

  try {
    const response = await $fetch<{ success: boolean; data?: BoundaryDataset; message?: string }>(
      JULIA_BACKEND_URL,
      {
        method: 'POST',
        body: {
          projectId: project.id,
          name: body.name,
          filePath: body.filePath,
          timezone: body.timezone,
          resolutionMinutes: Number(body.resolutionMinutes),
          timestampColumn: body.timestampColumn ?? '',
          startAt: body.startAt ?? '',
          series
        }
      }
    )
    if (!response.success || !response.data) {
      throw createError({ statusCode: 400, statusMessage: response.message || '导入历史边界数据集失败' })
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
