// [废弃 2026-07-14] 仿真解析 BFF 路由
// 功能已迁移到计算任务系统：POST /api/task/create → BFF 自动读取项目 → Julia run_task 内自动 parse
// 保留文件避免 Nuxt 路由扫描报错

export default defineEventHandler(() => {
  throw createError({ statusCode: 410, statusMessage: 'Gone: 仿真解析已迁移到计算任务系统，请使用 POST /api/v1/task/create' })
})
