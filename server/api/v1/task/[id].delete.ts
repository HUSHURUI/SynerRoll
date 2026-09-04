import { apiSuccess } from '#server/utils/response'

const JULIA_BACKEND_URL_BASE = 'http://localhost:8080/api/task'

/**
 * 清理任务（删除任务 DB + tasks.db 记录）
 * Path: /api/v1/task/:id
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
    }>(`${JULIA_BACKEND_URL_BASE}/${id}`, { method: 'DELETE' })

    if (response.success) {
      return apiSuccess({}, response.message)
    }
    else {
      throw createError({
        statusCode: 400,
        message: response.message || '清理失败'
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