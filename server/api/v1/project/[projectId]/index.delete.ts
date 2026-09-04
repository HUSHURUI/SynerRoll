import { apiSuccess } from '#server/utils/response'
import { removeProject } from '#server/utils/project-store'

export default defineEventHandler(async event => {
  const projectId = getRouterParam(event, 'projectId') ?? ''
  await removeProject(projectId)

  return apiSuccess({ projectId }, '项目已删除')
})
