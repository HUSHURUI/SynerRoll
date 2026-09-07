import type { BoundaryItem } from '~~/types/boundary'

import { apiSuccess } from '#server/utils/response'
import { updateProject } from '#server/utils/project-store'

/**
 * 保存项目边界配置
 */
export default defineEventHandler(async (event) => {
  const projectId = getRouterParam(event, 'projectId') ?? ''
  const body = await readBody<{ boundaries: BoundaryItem[] }>(event)

  const project = await updateProject(projectId, current => ({
    ...current,
    boundaries: body.boundaries
  }))

  return apiSuccess({ project }, '边界配置已保存')
})
