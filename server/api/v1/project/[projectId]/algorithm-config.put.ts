import type { UpdateProjectRequest } from '~~/types/api'

import { apiSuccess } from '#server/utils/response'
import { updateProject } from '#server/utils/project-store'

export default defineEventHandler(async event => {
  const projectId = getRouterParam(event, 'projectId') ?? ''
  const body = await readBody<UpdateProjectRequest>(event)

  const project = await updateProject(projectId, current => ({
    ...current,
    ...body,
    status: 'configured'
  }))

  return apiSuccess({ project }, '算法配置已保存')
})