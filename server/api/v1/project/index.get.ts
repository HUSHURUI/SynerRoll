import { apiSuccess } from '#server/utils/response'
import { readProjects } from '#server/utils/project-store'
import { buildProjectSummary } from '~~/utils/project-factory'

export default defineEventHandler(async () => {
  const projects = await readProjects()

  return apiSuccess({
    projects: projects.map(project => buildProjectSummary(project))
  })
})
