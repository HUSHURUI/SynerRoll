import { apiSuccess } from '#server/utils/response'

const JULIA_BACKEND_URL_BASE = 'http://localhost:8080/api/task'

/**
 * 拉任务的时序数据
 * Path: /api/v1/task/:id/data
 * Query: layerId?, varName?, sourceId?, remark?
 */
export default defineEventHandler(async (event) => {
  const id = getRouterParam(event, 'id')
  if (!id) {
    throw createError({ statusCode: 400, message: '缺少 task id' })
  }

  const query = getQuery(event)
  const params: Record<string, string> = {}
  for (const k of ['layerId', 'varName', 'sourceId', 'remark']) {
    const v = query[k]
    if (typeof v === 'string' && v) params[k] = v
  }

  try {
    const url = new URL(`${JULIA_BACKEND_URL_BASE}/${id}/data`)
    for (const [k, v] of Object.entries(params)) {
      url.searchParams.set(k, v)
    }

    const response = await $fetch<{
      success: boolean
      data?: { label?: string; rows?: Record<string, unknown>[] }
      message?: string
    }>(url.toString(), { method: 'GET' })

    if (response.success) {
      return apiSuccess(response.data ?? {}, response.message)
    }
    else {
      throw createError({
        statusCode: 400,
        message: response.message || '拉数据失败'
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