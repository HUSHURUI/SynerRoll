import type { ConfigField, LayerStatus } from '~~/types/component'

export type EditorMenuKey = 'canvas' | 'style' | 'model'

export interface EditorMenuItem {
  key: EditorMenuKey
  label: string
}

export interface ToolbarActionConfig {
  key: string
  label: string
  icon?: string
  type: 'button' | 'number' | 'toggle' | 'select' | 'color'
  placeholder?: string
  options?: { label: string; value: string }[]
}

export interface ToolbarGroupConfig {
  key: string
  label: string
  actions: ToolbarActionConfig[]
}

export interface ProjectCategoryFilter {
  key: 'all' | 'recent' | 'favorite'
  label: string
  description: string
}

export const editorMenus: EditorMenuItem[] = [
  { key: 'canvas', label: '画布' },
  { key: 'style', label: '样式' },
  { key: 'model', label: '建模' }
]

export const toolbarConfig: Record<EditorMenuKey, ToolbarGroupConfig[]> = {
  canvas: [
    {
      key: 'background',
      label: '背景',
      actions: [
        { key: 'canvas-bg-color', label: '背景颜色', type: 'color', icon: 'background' }
      ]
    },
    {
      key: 'canvas-size',
      label: '画布大小',
      actions: [
        {
          key: 'canvas-size-type',
          label: '页面大小',
          type: 'select',
          icon: 'portrait',
          options: [
            { label: '竖版', value: 'portrait' },
            { label: '横版', value: 'landscape' },
            { label: '正方形', value: 'square' }
          ]
        },
        { key: 'canvas-width', label: 'W', type: 'number', placeholder: '1500', icon: 'width' },
        { key: 'canvas-height', label: 'H', type: 'number', placeholder: '1050', icon: 'height' }
      ]
    },
    {
      key: 'grid-settings',
      label: '网格设置',
      actions: [
        {
          key: 'grid-size',
          label: '网格大小',
          type: 'select',
          icon: 'grid',
          options: [
            { label: '小', value: '10' },
            { label: '正常', value: '15' },
            { label: '大', value: '20' },
            { label: '很大', value: '30' }
          ]
        },
        {
          key: 'grid-type',
          label: '网格类型',
          type: 'select',
          icon: 'grid-type',
          options: [
            { label: '隐藏', value: 'hidden' },
            { label: '点状', value: 'dots' },
            { label: '网状', value: 'grid' }
          ]
        }
      ]
    },
    {
      key: 'display',
      label: '显示',
      actions: [
        {
          key: 'label-language',
          label: '元件标签',
          type: 'select',
          icon: 'show-label',
          options: [
            { label: '中文', value: 'chinese' },
            { label: '英文', value: 'english' },
            { label: '隐藏', value: 'hidden' }
          ]
        },
        { key: 'show-component-name', label: '元件名称', type: 'toggle', icon: 'show-label' },
        { key: 'show-parameter-tag', label: '参数标签', type: 'toggle', icon: 'show-label' },
        { key: 'show-ports', label: '接口标签', type: 'toggle', icon: 'show-ports' }
      ]
    },
    {
      key: 'view',
      label: '视图',
      actions: [
        { key: 'zoom-in', label: '放大', icon: 'zoom-in', type: 'button' },
        { key: 'zoom-out', label: '缩小', icon: 'zoom-out', type: 'button' }
      ]
    }
  ],
  style: [
    {
      key: 'layer',
      label: '层级',
      actions: [
        { key: 'bring-forward', label: '上移', icon: 'layer-up', type: 'button' },
        { key: 'send-backward', label: '下移', icon: 'layer-down', type: 'button' },
        { key: 'bring-front', label: '置顶', icon: 'to-front', type: 'button' },
        { key: 'send-back', label: '置底', icon: 'to-back', type: 'button' },
        { key: 'rotate-left', label: '逆时针', icon: 'rotate-left', type: 'button' },
        { key: 'rotate-right', label: '顺时针', icon: 'rotate-right', type: 'button' },
      ]
    },
    {
      key: 'align',
      label: '对齐',
      actions: [
        { key: 'align-left', label: '左对齐', icon: 'align-left', type: 'button' },
        { key: 'align-center', label: '居中', icon: 'align-center', type: 'button' },
        { key: 'align-right', label: '右对齐', icon: 'align-right', type: 'button' },
        { key: 'align-top', label: '上对齐', icon: 'align-top', type: 'button' },
        { key: 'align-middle', label: '垂直居中', icon: 'align-middle', type: 'button' },
        { key: 'align-bottom', label: '底对齐', icon: 'align-bottom', type: 'button' }
      ]
    },
    {
      key: 'distribute',
      label: '分布',
      actions: [
        { key: 'distribute-horizontal', label: '水平分布', icon: 'distribute-h', type: 'button' },
        { key: 'distribute-vertical', label: '垂直分布', icon: 'distribute-v', type: 'button' }
      ]
    },
    {
      key: 'match',
      label: '尺寸',
      actions: [
        { key: 'match-width', label: '同宽', icon: 'width', type: 'button' },
        { key: 'match-height', label: '同高', icon: 'height', type: 'button' },
        { key: 'match-size', label: '同尺寸', icon: 'size', type: 'button' }
      ]
    },
    {
      key: 'bounds',
      label: '坐标',
      actions: [
        { key: 'x-input', label: 'X', icon: 'axis-x', type: 'number', placeholder: '0' },
        { key: 'y-input', label: 'Y', icon: 'axis-y', type: 'number', placeholder: '0' },
        { key: 'width-input', label: 'W', icon: 'width', type: 'number', placeholder: '0' },
        { key: 'height-input', label: 'H', icon: 'height', type: 'number', placeholder: '0' }
      ]
    }
  ],
  model: [
    {
      key: 'project-config',
      label: '项目配置',
      actions: [
        { key: 'layer-config', label: '时层配置', icon: 'show-label', type: 'button' },
        { key: 'boundary-config', label: '边界配置', icon: 'show-label', type: 'button' },
        { key: 'algorithm-config', label: '算法配置', icon: 'show-label', type: 'button' },
        { key: 'simulation-parse', label: '仿真计算', icon: 'play', type: 'button' },
        { key: 'capacity-planning', label: '容量规划', icon: 'chart', type: 'button' }
      ]
    }
  ]
}

export const projectCategoryFilters: ProjectCategoryFilter[] = [
  { key: 'all', label: '全部项目', description: '显示当前工作区全部项目' },
  { key: 'recent', label: '最近更新', description: '按最近更新时间优先显示' },
  { key: 'favorite', label: '我的收藏', description: '仅显示已标记收藏的项目' }
]

// 时层状态选项
export const LAYER_STATUS_OPTIONS: { label: string; value: LayerStatus }[] = [
  { label: '独立运行', value: 'stand_alone' },
  { label: '禁用', value: 'disabled' },
  { label: '固定状态', value: 'fixed_state' },
  { label: '调节计划', value: 'adjust_power' },
  { label: '完全跟随计划', value: 'full_follow' }
]

// 通用（组件级别）目标函数字段预设
export const commonObjectiveFieldsPreset: ConfigField[] = [
  {
    key: 'dispatchPriority',
    label: '调度优先级',
    type: 'select',
    defaultValue: 'balanced',
    options: [
      { label: '平衡', value: 'balanced' },
      { label: '经济优先', value: 'economic' },
      { label: '低碳优先', value: 'low-carbon' }
    ]
  },
  {
    key: 'participateOptimization',
    label: '参与优化',
    type: 'boolean',
    defaultValue: true
  }
]

// 通用（组件级别）约束条件字段预设
export const commonConstraintFieldsPreset: ConfigField[] = [
  {
    key: 'minLoadRatio',
    label: '最小出力',
    type: 'number',
    defaultValue: 0.1,
    min: 0,
    max: 1,
    step: 0.05
  },
  {
    key: 'maxLoadRatio',
    label: '最大出力',
    type: 'number',
    defaultValue: 1,
    min: 0,
    max: 1,
    step: 0.05
  },
  {
    key: 'rampRate',
    label: '爬坡率',
    type: 'number',
    defaultValue: 0,
    unit: '%/min',
    step: 1
  }
]

// 通用（组件级别）经济参数字段预设
export const commonEconomicFieldsPreset: ConfigField[] = [
  {
    key: 'initialCost',
    label: '初始投资',
    type: 'number',
    defaultValue: 0,
    unit: '元/kW',
    step: 100
  },
  {
    key: 'replaceCost',
    label: '更换成本',
    type: 'number',
    defaultValue: 0,
    unit: '元/kW',
    step: 100
  },
  {
    key: 'maintainCost',
    label: '运维成本',
    type: 'number',
    defaultValue: 0,
    unit: '元/kWh',
    step: 10
  }
]

export const settingsSections = [
  {
    title: '系统参数',
    fields: [
      { key: 'autosaveInterval', label: '自动保存间隔', type: 'number', defaultValue: 30, unit: 's' },
      { key: 'defaultZoom', label: '默认缩放', type: 'number', defaultValue: 100, unit: '%' }
    ]
  },
  {
    title: '接口预留',
    fields: [
      { key: 'apiBaseUrl', label: 'API 基地址', type: 'text', defaultValue: '/api/v1' },
      { key: 'socketPath', label: 'WebSocket 路径', type: 'text', defaultValue: '/ws/simulation' }
    ]
  }
]
