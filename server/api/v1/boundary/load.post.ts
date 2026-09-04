import { apiSuccess } from '#server/utils/response'

const JULIA_BACKEND_URL = 'http://localhost:8080/api/boundary/load'

/**
 * 从 TS 库加载边界转换数据
 * 请求体:
 * - boundaries: Array<{layerId, relatedComponent, meaning}>
 */
export default defineEventHandler(async (event) => {
  const body = await readBody(event)

  try {
    const response = await $fetch<{
      success: boolean
      allFound: boolean
      message?: string
      boundaries?: Array<{
        layerId: string
        found: boolean
        values?: number[]
        timestamps?: string[]
      }>
    }>(JULIA_BACKEND_URL, {
      method: 'POST',
      body
    })

    if (response.success) {
      return apiSuccess({
        allFound: response.allFound,
        boundaries: response.boundaries
      })
    }
    else {
      throw createError({
        statusCode: 400,
        message: response.message || '加载失败'
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