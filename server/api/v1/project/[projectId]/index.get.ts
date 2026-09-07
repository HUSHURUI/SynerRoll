import { apiSuccess } from '#server/utils/response'
import { readProjectById } from '#server/utils/project-store'

export default defineEventHandler(async event => {
  const projectId = getRouterParam(event, 'projectId') ?? ''
  const project = await readProjectById(projectId)

  return apiSuccess({ project })
})
