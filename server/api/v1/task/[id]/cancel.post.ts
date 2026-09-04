import { apiSuccess } from '#server/utils/response'

const JULIA_BACKEND_URL_BASE = 'http://localhost:8080/api/task'

/**
 * 取消任务
 * Path: /api/v1/task/:id/cancel
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
    }>(`${JULIA_BACKEND_URL_BASE}/${id}/cancel`, { method: 'POST' })

    if (response.success) {
      return apiSuccess({}, response.message)
    }
    else {
      throw createError({
        statusCode: 400,
        message: response.message || '取消失败'
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