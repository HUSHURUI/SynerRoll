import type { UpdateProjectRequest } from '~~/types/api'

import { apiSuccess } from '#server/utils/response'
import { updateProject } from '#server/utils/project-store'

export default defineEventHandler(async event => {
  const projectId = getRouterParam(event, 'projectId') ?? ''
  const body = await readBody<UpdateProjectRequest>(event)
  const project = await updateProject(projectId, current => ({
    ...current,
    name: body.name?.trim() || current.name,
    description: body.description ?? current.description,
    favorite: body.favorite ?? current.favorite,
    tags: body.tags ?? current.tags
  }))

  return apiSuccess({ project }, '项目信息已更新')
})
