import { apiSuccess } from '#server/utils/response'

const JULIA_BACKEND_URL_BASE = 'http://localhost:8080/api/ingest/ts'

/**
 * 第三方写任务级 TS DB
 * Path: /api/v1/ingest/ts/:taskId
 * Body: { sourceId, varName, layerId, remark?, ts, value }
 */
export default defineEventHandler(async (event) => {
  const taskId = getRouterParam(event, 'taskId')
  if (!taskId) {
    throw createError({ statusCode: 400, message: '缺少 taskId' })
  }

  const body = await readBody(event)

  try {
    const response = await $fetch<{
      success: boolean
      data?: { label?: string }
      message?: string
    }>(`${JULIA_BACKEND_URL_BASE}/${taskId}`, {
      method: 'POST',
      body
    })

    if (response.success) {
      return apiSuccess(response.data ?? {}, response.message)
    }
    else {
      throw createError({
        statusCode: 400,
        message: response.message || '写入任务 TS 失败'
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