import { apiSuccess } from '#server/utils/response'

const JULIA_BACKEND_URL_BASE = 'http://localhost:8080/api/ingest/project'

/**
 * 第三方写项目级 boundary DB
 * Path: /api/v1/ingest/project/:projectId/boundary
 * Body: { sourceId, varName, layerId, remark?, ts, value }
 */
export default defineEventHandler(async (event) => {
  const projectId = getRouterParam(event, 'projectId')
  if (!projectId) {
    throw createError({ statusCode: 400, message: '缺少 projectId' })
  }

  const body = await readBody(event)

  try {
    const response = await $fetch<{
      success: boolean
      data?: { label?: string }
      message?: string
    }>(`${JULIA_BACKEND_URL_BASE}/${projectId}/boundary`, {
      method: 'POST',
      body
    })

    if (response.success) {
      return apiSuccess(response.data ?? {}, response.message)
    }
    else {
      throw createError({
        statusCode: 400,
        message: response.message || '写入项目 boundary 失败'
      })
    }
  }
  catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    throw createError({
      statusCode: 500,
      message: `Julia backend error: ${message}`
    })
  }
})