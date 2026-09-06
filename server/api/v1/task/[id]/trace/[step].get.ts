import { apiSuccess } from '#server/utils/response'

const JULIA_BACKEND_URL_BASE = 'http://localhost:8080/api/task'

/** 读取指定滚动求解批次保存的完整时序快照，不触发新的求解。 */
export default defineEventHandler(async (event) => {
  const id = getRouterParam(event, 'id')
  const step = getRouterParam(event, 'step')
  if (!id) {
    throw createError({ statusCode: 400, message: '缺少 task id' })
  }
  if (!step || !/^\d+$/.test(step)) {
    throw createError({ statusCode: 400, message: '无效的滚动求解 step' })
  }

  try {
    const response = await $fetch<{
      success: boolean
      data?: { rows?: Record<string, unknown>[] }
      message?: string
    }>(`${JULIA_BACKEND_URL_BASE}/${id}/trace/${step}`, { method: 'GET' })

    if (response.success) {
      return apiSuccess(response.data ?? { rows: [] }, response.message)
    }
    throw createError({
      statusCode: 400,
      message: response.message || '拉取滚动求解快照失败'
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
