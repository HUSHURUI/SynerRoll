import { apiSuccess } from '#server/utils/response'

const JULIA_BACKEND_URL = 'http://localhost:8080/api/boundary/submit'

/**
 * 提交边界转换数据到 TS 库
 * 请求体:
 * - boundaries: Array<{layerId, values, timestamps, relatedComponent, meaning}>
 */
export default defineEventHandler(async (event) => {
  const body = await readBody(event)

  try {
    const response = await $fetch<{
      success: boolean
      message?: string
      storedKeys?: string[]
    }>(JULIA_BACKEND_URL, {
      method: 'POST',
      body
    })

    if (response.success) {
      return apiSuccess({ storedKeys: response.storedKeys }, response.message)
    }
    else {
      throw createError({
        statusCode: 400,
        message: response.message || '提交失败'
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