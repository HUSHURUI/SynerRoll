# SynerRoll 前端代码规范

## 1. 项目概述

- **项目名称**: SynerRoll Workbench
- **技术栈**: Nuxt 4 + Vue 3 + TypeScript + Tailwind CSS v4 + Vue Flow
- **包管理**: pnpm
- **Node 版本**: >= 18

## 2. 目录结构规范

```
├── app/                    # 前端页面和组件
│   ├── assets/            # 静态资源（图标等）
│   ├── components/        # 业务组件
│   ├── composables/       # 组合式函数
│   ├── config/           # 前端配置
│   ├── pages/            # 页面路由
│   └── state/            # 全局状态
├── assets/               # 全局样式
├── composables/          # API 相关 composables
├── config/              # 主题配置
├── public/              # 静态文件
├── server/              # 服务端 API
│   ├── api/             # API 路由（RESTful 结构）
│   └── utils/           # 服务端工具
├── state/               # 全局状态
├── types/               # TypeScript 类型定义
└── utils/               # 工具函数
```

## 3. TypeScript 规范

### 3.1 类型导入

- 使用 `import type` 导入类型，避免类型被编译进 JavaScript
- 使用 `~~/` 作为项目根路径别名

```typescript
// ✅ 正确
import type { Project, ProjectSummary } from '~~/types/project'
import { deepClone } from '~~/utils/clone'

// ❌ 错误
import { Project } from '~~/types/project'
```

### 3.2 Props 定义

使用 `defineProps` 结合泛型定义 props：

```typescript
// ✅ 正确 - 组合式函数风格的 props
const props = defineProps<{
  title: string
  items: Array<{ label: string; value: number; color: string }>
}>()

// ✅ 正确 - 组件使用 withDefaults 提供默认值
const props = withDefaults(
  defineProps<{
    label?: string
    icon?: string
    tone?: 'primary' | 'neutral' | 'ghost' | 'danger'
  }>(),
  {
    label: '',
    tone: 'neutral'
  }
)
```

### 3.3 接口命名

- 接口使用 PascalCase 命名
- 类型定义文件按功能模块拆分（`api.ts`, `project.ts`, `simulation.ts` 等）

```typescript
// types/api.ts
export interface ApiResponse<T> {
  success: boolean
  data: T
  message?: string
}

export interface ProjectDetailResponse {
  project: Project
}
```

## 4. Vue 组件规范

### 4.1 组件结构

```
<script setup lang="ts">
// 1. 类型导入
// 2. Props 和 Emits
// 3. Composables
// 4. 响应式状态
// 5. 计算属性
// 6. 方法
// 7. 生命周期
</script>

<template>
  <!-- 模板内容 -->
</template>
```

### 4.2 组件命名

- 使用 PascalCase 命名组件文件（`AppButton.vue`, `ProjectCard.vue`）
- 组件名应包含实际功能（而非通用名称）

### 4.3 模板规范

- 使用 Vue 3.3+ 的 defineProps 语法
- 使用 `v-if` / `v-else` 而非 `v-show` 处理条件渲染
- 列表渲染使用 `v-for` 配合 `:key`

```vue
<!-- ✅ 正确 -->
<div v-for="item in items" :key="item.label">
  {{ item.label }}
</div>

<!-- ❌ 避免 -->
<div v-for="item in items">
  {{ item.label }}
</div>
```

## 5. 样式规范

### 5.1 Tailwind CSS v4

项目使用 Tailwind CSS v4，通过 CSS `@theme` 变量定义设计系统：

```css
@theme {
  --color-primary: #0a4da2;
  --color-app-surface: #f5f7fa;
  --color-app-panel: #ffffff;
  --color-app-border: #dde1e6;
  --color-app-text: #1d2129;
}
```

### 5.2 设计令牌

| 令牌 | 用途 |
|------|------|
| `primary` | 主色调 |
| `app-surface` | 页面背景 |
| `app-panel` | 卡片/面板背景 |
| `app-panel-soft` | 内部区块背景 |
| `app-border` | 边框色 |
| `app-text` | 主文本色 |
| `app-muted` | 次要文本色 |

### 5.3 预定义组件类

```css
.panel-card    /* 卡片容器 */
.field-input   /* 表单输入框 */
.field-select  /* 下拉选择框 */
.field-label    /* 表单标签 */
```

### 5.4 Tone 语义化

按钮等组件使用 `tone` 属性表达语义：

| tone | 用途 |
|------|------|
| `primary` | 主要操作 |
| `neutral` | 次要操作 |
| `ghost` | 极轻量操作 |
| `danger` | 危险/删除操作 |

## 6. API 规范

### 6.1 目录结构

```
server/api/v1/project/
├── index.get.ts          # GET /api/v1/project - 列表
├── index.post.ts         # POST /api/v1/project - 创建
└── [projectId]/
    ├── index.get.ts       # GET /api/v1/project/:id
    ├── index.put.ts       # PUT /api/v1/project/:id
    ├── index.delete.ts    # DELETE /api/v1/project/:id
    └── simulation/
        └── start.post.ts  # POST /api/v1/project/:id/simulation/start
```

### 6.2 响应格式

使用统一的响应工具函数：

```typescript
import { apiSuccess } from '#server/utils/response'

export default defineEventHandler(async () => {
  return apiSuccess({ projects: [...] })
})
```

响应格式：

```typescript
interface ApiResponse<T> {
  success: boolean
  data: T
  message?: string
}
```

### 6.3 前端 API 调用

通过 composable 封装 API：

```typescript
// composables/api/useApiClient.ts
export const useApiClient = () => {
  const request = async <T>(path: string, options?: {...}): Promise<T> => {
    // 统一处理请求
  }

  return { get, mutate }
}

// composables/api/useProjectApi.ts
export const useProjectApi = () => {
  const { get, mutate } = useApiClient()

  return {
    listProjects: () => get<ProjectListResponse>('/project'),
    createProject: (data: CreateProjectRequest) => mutate({ path: '/project', method: 'POST', body: data })
  }
}
```

## 7. 状态管理规范

### 7.1 useState 使用

使用 Nuxt 的 `useState` 进行全局状态管理：

```typescript
// ✅ 正确 - 带前缀的状态名
const past = useState<HistorySnapshot[]>(`editor-history-past-${projectId}`, () => [])
const future = useState<HistorySnapshot[]>(`editor-history-future-${projectId}`, () => [])
```

### 7.2 状态命名

- 数组类型使用复数名词（`projects`, `items`）
- 布尔状态使用 `pending`, `loading`, `error` 等后缀
- 对象状态添加 `_detail` 或具体后缀区分

## 8. 工具函数规范

### 8.1 工具函数位置

| 用途 | 位置 |
|------|------|
| 通用工具 | `utils/` |
| 类型转换 | `utils/clone.ts` |
| 下载功能 | `utils/download.ts` |
| ID 生成 | `utils/id.ts` |
| 后端导出 | `utils/backend-export.ts` |

### 8.2 命名规范

- 文件名使用 kebab-case 或 camelCase
- 函数使用 camelCase 命名
- 纯函数应有良好的输入输出类型标注

## 9. Composables 规范

### 9.1 命名规范

- 目录：`composables/`
- 文件：`useXxx.ts`（以 `use` 前缀开头）
- 导出：`useXxx`（函数形式）

### 9.2 返回值

使用对象形式返回 composable 的 API：

```typescript
export const useEditorHistory = (projectId: string) => {
  // ...

  return {
    past,
    future,
    commit,
    undo,
    redo
  }
}
```

## 10. Git 提交规范

（当前项目未配置 commitlint，可参考以下规范）

### 10.1 提交类型

| 类型 | 描述 |
|------|------|
| `feat` | 新功能 |
| `fix` | 修复 bug |
| `docs` | 文档更新 |
| `style` | 代码格式（不影响功能） |
| `refactor` | 重构 |
| `perf` | 性能优化 |
| `test` | 测试相关 |
| `chore` | 构建/工具相关 |

### 10.2 提交格式

```
<type>: <subject>

<body>（可选）
```

示例：

```
feat: 添加项目导入导出功能

支持 JSON 格式的项目导入和导出
```

## 11. 代码格式

### 11.1 ESLint

项目未配置 ESLint，建议后续添加以确保代码质量。

### 11.2 Tailwind CSS 工具类排序

建议按以下顺序编写 Tailwind 类：

1. 布局类（`flex`, `grid`, `w`, `h`）
2. 定位类（`relative`, `absolute`, `top`, `left`）
3. 间距类（`p`, `m`, `gap`）
4. 尺寸类（`w`, `h`, `min-h`）
5. 外观类（`bg`, `border`, `rounded`）
6. 排版类（`text`, `font`, `leading`）
7. 交互类（`hover`, `focus`, `disabled`）

```vue
<!-- 示例 -->
<div class="flex items-center justify-between p-4 rounded-lg border bg-white">
```
