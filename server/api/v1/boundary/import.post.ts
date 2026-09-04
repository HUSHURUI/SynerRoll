import { apiSuccess } from '#server/utils/response'

const JULIA_BACKEND_URL = 'http://localhost:8080/api/boundary/import'

/**
 * 导入边界原始数据
 * 请求体:
 * - filePath: string - CSV文件路径
 * - columnName: string - 列名
 * - timeStep: string - 时间尺度
 * - projectId: string - 项目ID
 *
 * 返回:
 * - values: number[] - 数据数组
 * - timestamps: string[] - 时间戳数组
 * - xAxisLabel: string - X轴标签
 * - yAxisLabel: string - Y轴标签
 */
export default defineEventHandler(async (event) => {
  const body = await readBody(event)

  try {
    const response = await $fetch<{
      success: boolean
      data?: {
        values: number[]
        timestamps: string[]
        xAxisLabel: string
        yAxisLabel: string
      }
      message?: string
    }>(JULIA_BACKEND_URL, {
      method: 'POST',
      body
    })

    if (response.success && response.data) {
      return apiSuccess(response.data)
    }
    else {
      throw createError({
        statusCode: 400,
        message: response.message || '导入失败'
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
