import { mkdir, readFile, rm, writeFile } from 'node:fs/promises'
import { join } from 'node:path'

import type { Project } from '~~/types/project'
import { createInitialProjects, normalizeProject } from '~~/utils/project-factory'

const dataDirectory = join(process.cwd(), 'server', 'data')
const dataFile = join(dataDirectory, 'projects.json')

// 项目 boundary 时序数据库目录：backend/data/projects/<project_id>/boundary.db
// 由计算任务方案阶段 0 引入，每个项目独立一份
const projectsBoundaryRoot = join(process.cwd(), '..', 'backend', 'data', 'projects')

// Serialize store access so requests never read a half-written JSON file.
let storeOperationQueue: Promise<void> = Promise.resolve()

const withStoreLock = async <T>(operation: () => Promise<T>): Promise<T> => {
  const nextOperation = storeOperationQueue.then(operation, operation)
  storeOperationQueue = nextOperation.then(() => undefined, () => undefined)
  return nextOperation
}

const buildSeedProjects = (): Project[] =>
  createInitialProjects().map(project => normalizeProject(project))

const writeProjectsUnlocked = async (projects: Project[]): Promise<void> => {
  await mkdir(dataDirectory, { recursive: true })
  await writeFile(dataFile, JSON.stringify(projects, null, 2), 'utf8')
}

// 确保某项目的 boundary 时序库文件存在（空文件即可，Julia 后端打开时会自动建表）
const ensureProjectBoundaryDb = async (projectId: string): Promise<void> => {
  const dir = join(projectsBoundaryRoot, projectId)
  await mkdir(dir, { recursive: true })
  const dbPath = join(dir, 'boundary.db')
  // touch 空文件：仅当文件不存在时创建；存在则跳过
  try {
    await readFile(dbPath)
  }
  catch (error) {
    const isMissing = typeof error === 'object' && error !== null && 'code' in error && error.code === 'ENOENT'
    if (!isMissing) throw error
    await writeFile(dbPath, '', 'utf8')
  }
}

// 删除某项目的整个 boundary 目录（含 boundary.db 和未来可能扩展的文件）
const removeProjectBoundaryDb = async (projectId: string): Promise<void> => {
  const dir = join(projectsBoundaryRoot, projectId)
  await rm(dir, { recursive: true, force: true })
}

const ensureStoreUnlocked = async (): Promise<Project[]> => {
  await mkdir(dataDirectory, { recursive: true })

  let content: string
  try {
    content = await readFile(dataFile, 'utf8')
  }
  catch (error) {
    const isMissingFile = typeof error === 'object' && error !== null && 'code' in error && error.code === 'ENOENT'

    if (isMissingFile) {
      const projects = buildSeedProjects()
      await writeProjectsUnlocked(projects)
      return projects
    }

    throw createError({
      statusCode: 500,
      statusMessage: `Failed to read project store: ${dataFile}`,
      data: {
        cause: error instanceof Error ? error.message : String(error)
      }
    })
  }

  const trimmedContent = content.trim()
  if (!trimmedContent) {
    throw createError({
      statusCode: 500,
      statusMessage: `Project store is empty: ${dataFile}`
    })
  }

  let parsed: unknown
  try {
    parsed = JSON.parse(trimmedContent)
  }
  catch (error) {
    throw createError({
      statusCode: 500,
      statusMessage: `Project store is corrupted. Refusing to overwrite ${dataFile}.`,
      data: {
        cause: error instanceof Error ? error.message : String(error)
      }
    })
  }

  if (!Array.isArray(parsed)) {
    throw createError({
      statusCode: 500,
      statusMessage: `Project store must be an array: ${dataFile}`
    })
  }

  return parsed.map(project => normalizeProject(project as Project))
}

export const readProjects = async (): Promise<Project[]> =>
  withStoreLock(() => ensureStoreUnlocked())

export const writeProjects = async (projects: Project[]): Promise<void> => {
  await withStoreLock(() => writeProjectsUnlocked(projects))
}

export const readProjectById = async (projectId: string): Promise<Project> => {
  const projects = await readProjects()
  const project = projects.find(item => item.id === projectId)

  if (!project) {
    throw createError({ statusCode: 404, statusMessage: `Project ${projectId} not found` })
  }

  return normalizeProject(project)
}

export const updateProject = async (
  projectId: string,
  updater: (project: Project) => Project
): Promise<Project> =>
  withStoreLock(async () => {
    const projects = await ensureStoreUnlocked()
    const projectIndex = projects.findIndex(project => project.id === projectId)

    if (projectIndex === -1) {
      throw createError({ statusCode: 404, statusMessage: `Project ${projectId} not found` })
    }

    const nextProject = updater(normalizeProject(projects[projectIndex]!))
    const persistedProject = {
      ...nextProject,
      updateTime: new Date().toISOString()
    }

    const nextProjects = [...projects]
    nextProjects[projectIndex] = persistedProject

    await writeProjectsUnlocked(nextProjects)

    return normalizeProject(persistedProject)
  })

export const createProjectRecord = async (project: Project): Promise<Project> =>
  withStoreLock(async () => {
    const normalizedProject = normalizeProject(project)
    const projects = await ensureStoreUnlocked()
    const nextProjects = [...projects, normalizedProject]

    await writeProjectsUnlocked(nextProjects)

    // 计算任务方案：项目创建时自动建立 boundary 时序库目录 + 空 DB 文件
    await ensureProjectBoundaryDb(normalizedProject.id)

    return normalizedProject
  })

export const removeProject = async (projectId: string): Promise<void> =>
  withStoreLock(async () => {
    const projects = await ensureStoreUnlocked()
    const nextProjects = projects.filter(project => project.id !== projectId)

    await writeProjectsUnlocked(nextProjects)

    // 删除项目对应的 boundary 时序库目录
    await removeProjectBoundaryDb(projectId)
  })