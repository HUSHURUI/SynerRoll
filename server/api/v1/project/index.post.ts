import type { CreateProjectRequest } from '~~/types/api'

import { apiSuccess } from '#server/utils/response'
import { createProjectRecord } from '#server/utils/project-store'
import { createEmptyProject } from '~~/utils/project-factory'

export default defineEventHandler(async event => {
  const body = await readBody<CreateProjectRequest>(event)
  const name = body.name?.trim() || '未命名项目'
  const project = createEmptyProject(name, body.description)

  project.name = name
  if (body.description) {
    project.description = body.description
  }

  const created = await createProjectRecord(project)

  return apiSuccess({ project: created }, '项目已创建')
})
