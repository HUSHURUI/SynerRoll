import type { Project } from '~~/types/project'

export const useProjectCache = () => {
  const cache = useState<Record<string, Project>>('project-cache', () => ({}))

  const setProject = (project: Project): void => {
    cache.value = {
      ...cache.value,
      [project.id]: project
    }
  }

  const getProject = (projectId: string): Project | null => cache.value[projectId] ?? null

  return {
    cache,
    setProject,
    getProject
  }
}
