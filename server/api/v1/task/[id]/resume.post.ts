import { apiSuccess } from '#server/utils/response'

const JULIA_BACKEND_URL_BASE = 'http://localhost:8080/api/task'

/**
 * 恢复任务（仅 paused 状态可用）
 * Path: /api/v1/task/:id/resume
 */
export default defineEventHandler(async (event) => {
  const id = getRouterParam(event, 'id')
  if (!id) {
    throw createError({ statusCode: 400, message: '缺少 task id' })
  }

  try {
    const response = await $fetch<{
      success: boolean
      message?: string
    }>(`${JULIA_BACKEND_URL_BASE}/${id}/resume`, { method: 'POST' })

    if (response.success) {
      return apiSuccess({}, response.message)
    }
    else {
      throw createError({
        statusCode: 400,
        message: response.message || '恢复失败'
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