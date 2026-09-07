import { apiSuccess } from '#server/utils/response'

const JULIA_BACKEND_URL_BASE = 'http://localhost:8080/api/task'

/** 读取任务已有的滚动求解批次列表，不触发新的求解。 */
export default defineEventHandler(async (event) => {
  const id = getRouterParam(event, 'id')
  if (!id) {
    throw createError({ statusCode: 400, message: '缺少 task id' })
  }

  try {
    const response = await $fetch<{
      success: boolean
      data?: { steps?: Record<string, unknown>[] }
      message?: string
    }>(`${JULIA_BACKEND_URL_BASE}/${id}/trace`, { method: 'GET' })

    if (response.success) {
      return apiSuccess(response.data ?? { steps: [] }, response.message)
    }
    throw createError({
      statusCode: 400,
      message: response.message || '拉取滚动求解批次失败'
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
