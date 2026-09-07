import { apiSuccess } from '#server/utils/response'

const JULIA_BACKEND_URL_BASE = 'http://localhost:8080/api/task'

/** 拉取任务的经济性评价结果。 */
export default defineEventHandler(async (event) => {
  const id = getRouterParam(event, 'id')
  if (!id) {
    throw createError({ statusCode: 400, message: '缺少 task id' })
  }

  try {
    const response = await $fetch<{
      success: boolean
      data?: Record<string, unknown>
      message?: string
    }>(`${JULIA_BACKEND_URL_BASE}/${id}/economy`, { method: 'GET' })

    if (response.success) {
      return apiSuccess(response.data ?? {}, response.message)
    }
    throw createError({
      statusCode: 400,
      message: response.message || '拉经济性评价结果失败'
    })
  }
  catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    throw createError({
      statusCode: 500,
      message: `Julia backend error: ${message}`
    })
  }
})
