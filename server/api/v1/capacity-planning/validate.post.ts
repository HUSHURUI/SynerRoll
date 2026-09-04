import type {
  CapacityVariableDraft,
  CapacityVariableValidationResult
} from '~~/types/capacity-planning'

import { apiSuccess } from '#server/utils/response'
import { readProjectById } from '#server/utils/project-store'

const JULIA_BACKEND_URL = 'http://localhost:8080/api/capacity-planning/validate'

export default defineEventHandler(async (event) => {
  const body = await readBody<{
    projectId?: string
    canvasId?: string
    variables?: CapacityVariableDraft[]
  }>(event)
  const projectId = body.projectId?.trim()
  const canvasId = body.canvasId?.trim()

  if (!projectId || !canvasId || !Array.isArray(body.variables)) {
    throw createError({ statusCode: 400, statusMessage: '容量变量配置不完整' })
  }

  const project = await readProjectById(projectId)

  try {
    const response = await $fetch<{
      success: boolean
      data?: CapacityVariableValidationResult
      message?: string
    }>(JULIA_BACKEND_URL, {
      method: 'POST',
      body: {
        canvasId,
        variables: body.variables,
        projectJson: project
      }
    })

    if (!response.success || !response.data) {
      throw createError({ statusCode: 400, statusMessage: response.message || '容量变量配置校验失败' })
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
