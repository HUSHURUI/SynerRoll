import { apiSuccess } from '#server/utils/response'

const JULIA_BACKEND_URL_BASE = 'http://localhost:8080/api/task'

/**
 * 拉任务的总线→变量映射（connection.json）
 * Path: /api/v1/task/:id/connection
 */
export default defineEventHandler(async (event) => {
  const id = getRouterParam(event, 'id')
  if (!id) {
    throw createError({ statusCode: 400, message: '缺少 task id' })
  }

  try {
    const url = `${JULIA_BACKEND_URL_BASE}/${id}/connection`

    const response = await $fetch<{
      success: boolean
      data?: Array<{ busLabel: string; busCode: string; variables: string[] }>
      message?: string
    }>(url, { method: 'GET' })

    if (response.success) {
      return apiSuccess(response.data ?? [], response.message)
    }
    else {
      throw createError({
        statusCode: 400,
        message: response.message || '拉连接数据失败'
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
