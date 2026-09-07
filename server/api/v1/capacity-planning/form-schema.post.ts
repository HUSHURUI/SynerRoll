import type { CapacityPlanningFormSchema } from '~~/types/capacity-planning'

import { apiSuccess } from '#server/utils/response'
import { readProjectById } from '#server/utils/project-store'

const JULIA_BACKEND_URL = 'http://localhost:8080/api/capacity-planning/form-schema'

export default defineEventHandler(async (event) => {
  const body = await readBody<{ projectId?: string; canvasId?: string }>(event)
  const projectId = body.projectId?.trim()
  const canvasId = body.canvasId?.trim()

  if (!projectId || !canvasId) {
    throw createError({ statusCode: 400, statusMessage: 'projectId 和 canvasId 不能为空' })
  }

  const project = await readProjectById(projectId)

  try {
    const response = await $fetch<{
      success: boolean
      data?: CapacityPlanningFormSchema
      message?: string
    }>(JULIA_BACKEND_URL, {
      method: 'POST',
      body: { canvasId, projectJson: project }
    })

    if (!response.success || !response.data) {
      throw createError({ statusCode: 400, statusMessage: response.message || '生成容量变量表单失败' })
    }

    return apiSuccess(response.data)
  }
  catch (error) {
    if (error && typeof error === 'object' && 'statusCode' in error) {
      throw error
    }
    throw createError({
      statusCode: 502,
      statusMessage: `Julia 后端不可用: ${error instanceof Error ? error.message : String(error)}`
    })
  }
})
