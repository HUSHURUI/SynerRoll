import type { SaveCanvasRequest } from '~~/types/api'

import { apiSuccess } from '#server/utils/response'
import { updateProject } from '#server/utils/project-store'

export default defineEventHandler(async event => {
  const projectId = getRouterParam(event, 'projectId') ?? ''
  const body = await readBody<SaveCanvasRequest>(event)

  const project = await updateProject(projectId, current => ({
    ...current,
    workspace: body.workspace,
    status: body.workspace.canvases.some(canvas => canvas.nodes.length > 0) ? 'configured' : current.status
  }))

  return apiSuccess({ project }, '画布数据已保存')
})