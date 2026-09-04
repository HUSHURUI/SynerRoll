import type { LayerConfigSet } from '~~/types/simulation'

import { apiSuccess } from '#server/utils/response'
import { updateProject } from '#server/utils/project-store'

/**
 * 保存项目时层配置。projects.json 是唯一真实数据源，写入即覆盖整个 layerConfig。
 */
export default defineEventHandler(async (event) => {
  const projectId = getRouterParam(event, 'projectId') ?? ''
  const body = await readBody<{ layerConfig: LayerConfigSet }>(event)

  const project = await updateProject(projectId, current => ({
    ...current,
    layerConfig: body.layerConfig
  }))

  return apiSuccess({ project }, '时层配置已保存')
})
