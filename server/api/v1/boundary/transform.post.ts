import { apiSuccess } from '#server/utils/response'

const JULIA_BACKEND_URL = 'http://localhost:8080/api/boundary/transform'

/**
 * 转换边界数据 - 基于原始数据生成各个时间尺度的数据
 * 请求体:
 * - rawValues: number[] - 原始数据值数组
 * - rawTimestamps: string[] - 原始时间戳数组
 * - xAxisLabel: string - X轴标签
 * - yAxisLabel: string - Y轴标签
 * - interpolateType: string - 插值方式
 * - randomDistribution: string - 随机分布类型
 * - noiseLevel: number - 噪声水平
 * - layerConfig: LayerConfigSet - 时层配置
 * - projectId: string - 项目ID
 *
 * 返回:
 * - layers: Array<{layerId, layerName, values, timestamps}>
 */
export default defineEventHandler(async (event) => {
  const body = await readBody(event)

  try {
    const response = await $fetch<{
      success: boolean
      data?: {
        layers: Array<{
          layerId: string
          layerName: string
          values: number[]
          timestamps: string[]
        }>
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
        message: response.message || '转换失败'
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