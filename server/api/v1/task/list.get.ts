import { apiSuccess } from '#server/utils/response'

const JULIA_BACKEND_URL = 'http://localhost:8080/api/task/list'

/**
 * 列计算任务
 * Query: projectId?, status?
 */
export default defineEventHandler(async (event) => {
  const query = getQuery(event)
  const projectId = (query.projectId as string) || undefined
  const status = (query.status as string) || undefined

  try {
    const url = new URL(JULIA_BACKEND_URL)
    if (projectId) url.searchParams.set('projectId', projectId)
    if (status) url.searchParams.set('status', status)

    const response = await $fetch<{
      success: boolean
      data?: { tasks?: Record<string, unknown>[] }
      message?: string
    }>(url.toString(), { method: 'GET' })

    if (response.success) {
      return apiSuccess(response.data ?? {}, response.message)
    }
    else {
      throw createError({
        statusCode: 400,
        message: response.message || '列任务失败'
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