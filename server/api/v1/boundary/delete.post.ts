import { apiSuccess } from '#server/utils/response'

const JULIA_BACKEND_URL = 'http://localhost:8080/api/boundary/delete'

/**
 * 删除边界的全部层数据
 * 请求体:
 * - boundaryId: string  （即 TS 库的 source_id，对应 projects.json 中的 BoundaryID）
 */
export default defineEventHandler(async (event) => {
  const body = await readBody(event)

  try {
    const response = await $fetch<{
      success: boolean
      message?: string
      deletedLayers?: number
    }>(JULIA_BACKEND_URL, {
      method: 'POST',
      body
    })

    if (response.success) {
      return apiSuccess(
        { deletedLayers: response.deletedLayers ?? 0 },
        response.message
      )
    }
    else {
      throw createError({
        statusCode: 400,
        message: response.message || '删除失败'
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