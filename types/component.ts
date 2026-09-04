import type { BoundaryMeaning } from './boundary'

export type PrimitiveValue = string | number | boolean

export type FieldType = 'text' | 'textarea' | 'number' | 'select' | 'boolean' | 'color'

// 介质类型：用于定义端口和连线的介质属性
export type MediumType = 'electric' | 'thermal' | 'gas' | 'hydrogen' | 'material' | 'general' | 'ammonia' | 'methanol' | 'carbon'

export type ComponentCategoryKey =
  | 'bus'        // 总线
  | 'power'      // 电力系统
  | 'thermal'    // 冷热系统
  | 'fuel'       // 燃料系统
  | 'hydrogen'   // 氢能系统
  | 'carbon'     // 碳排放
  | 'storage'    // 储能
  | 'load'       // 负荷
  | 'market'     // 市场

export type ComponentGroupKey =
  // 总线（通过 busType 属性区分类型）
  | 'bus'
  // 电力系统
  | 'power-external-source'
  | 'power-converter'
  | 'power-transmission'
  // 冷热系统
  | 'thermal-external-source'
  | 'thermal-converter'
  | 'thermal-transmission'
  // 燃料系统
  | 'fuel-external-source'
  | 'fuel-converter'
  // 氢能系统
  | 'hydrogen-external-source'
  | 'hydrogen-converter'
  // 碳排放
  | 'carbon-external-source'
  | 'carbon-converter'
  // 储能
  | 'electric-storage'
  | 'gas-storage'
  | 'thermal-storage'
  | 'chemical-storage'
  // 负荷
  | 'time-shift-load'
  | 'flexible-load'
  | 'dr-load'
  // 市场
  | 'trading-market'
  | 'green-certificate'

export interface SelectOption<T extends PrimitiveValue = PrimitiveValue> {
  label: string
  value: T
}

export interface ConfigField<T extends PrimitiveValue = PrimitiveValue> {
  key: string
  label: string
  type: FieldType
  defaultValue: T
  unit?: string
  placeholder?: string
  description?: string
  min?: number
  max?: number
  step?: number
  options?: SelectOption<T>[]
}

export interface SizePreset {
  width: number
  height: number
}

export interface AppearancePreset {
  fillColor: string
  strokeColor: string
  strokeWidth: number
  fontSize: number
  textColor: string
  borderRadius: number
  rotation: number
  opacity: number
}

// 端口方向类型：in表示流入（被连接时介质进入节点），out表示流出
export type PortDirection = 'in' | 'out'

export type PortSide = 'top' | 'right' | 'bottom' | 'left'

export interface PortDefinition {
  id: string
  label?: string
  direction: PortDirection
  side: PortSide
  // offset 表示端口在该侧的相对位置（0-100），表示该端口占该侧的百分比位置
  // 例如：left侧offset=30表示在左侧30%高度的位置（即从顶部30%处）
  offset: number
  // 介质类型：用于判断端口能否连接以及连线样式
  medium: MediumType
}

// ============================================================
// 时层(Layer)相关类型
// ============================================================

// 时层状态枚举
export type LayerStatus =
  | 'stand_alone'   // 独立运行
  | 'disabled'       // 禁用
  | 'fixed_state'   // 固定状态
  | 'adjust_power'  // 调节计划
  | 'full_follow'   // 完全跟随计划

// 约束条件配置
export interface ConstraintConfig {
  enabled: boolean
}

export interface ObjectiveConfig {
  enabled: boolean
}

// 单个时层的配置
export interface LayerConfig {
  // 时层ID，对应TimeScaleConfig.id
  layerId: string
  // 状态
  status: LayerStatus
  // 技术参数（运行时参数）
  techParams: Record<string, PrimitiveValue>
  // 经济参数
  economicParams: Record<string, PrimitiveValue>
  // 约束条件
  constraints: Record<string, ConstraintConfig>
  // 目标函数
  objectives: Record<string, ObjectiveConfig>
}

// ============================================================
// 组件实例元数据
// ============================================================

export interface ComponentMeta {
  componentKey: string
  componentType: string
  componentName: string
  description?: string

  // 设备数量
  deviceCount: number

  // 通用（组件级别）技术参数，不随时层变化
  commonTechParams: Record<string, PrimitiveValue>
  // 通用（组件级别）经济参数，不随时层变化
  commonEconomicParams: Record<string, PrimitiveValue>

  // 各时层配置：key为时层ID，value为该时层的完整配置
  // 根据项目配置的时层动态设置
  layerConfigs: Record<string, LayerConfig>

  // 关联的边界类ID（支持多个）
  boundaryIds?: string[]
}

// ============================================================
// 组件定义
// ============================================================

export interface ComponentDefinition {
  key: string
  label: string
  category: ComponentCategoryKey
  group: ComponentGroupKey
  icon: string
  description: string

  // 画布类型：energy=能源组件，shape=基础图形
  canvasType: 'energy' | 'shape'

  // 默认尺寸
  defaultSize: SizePreset
  appearance: AppearancePreset

  // 端口定义
  ports: PortDefinition[]

  // 默认元数据
  defaultMeta: ComponentMeta

  // 组件级别技术参数字段定义（通用技术参数）
  commonTechParamFields: ConfigField[]
  // 组件级别经济参数字段定义（通用经济参数）
  commonEconomicParamFields: ConfigField[]

  // 各时层技术参数字段定义（各时层共用同一套字段定义，但值独立）
  layerTechParamFields: ConfigField[]
  // 各时层经济参数字段定义
  layerEconomicParamFields: ConfigField[]
  // 各时层约束条件字段定义
  layerConstraintFields: ConfigField[]
  // 各时层目标函数字段定义
  layerObjectiveFields: ConfigField[]

  tags: string[]

  // 该组件可关联的边界物理含义（可选项范围）。
  // 实例侧在 `ComponentMeta.boundaryIds[]` 里选择 0 或多个边界对象；
  // 选的是否合理 / 是否冲突 / 是否必须至少有 1 个——这些校验由后端计算模块负责，
  // schema 只声明可选范围，不做选择约束。
  // 空数组 / 缺失：表示该组件不需要边界。
  boundaryKey?: BoundaryMeaning[]
}

// ============================================================
// 组件分类和分组
// ============================================================

export interface ComponentCategory {
  key: ComponentCategoryKey
  label: string
  description: string
  icon: string
  groups: ComponentGroupKey[]
}

export interface ComponentGroup {
  key: ComponentGroupKey
  label: string
  description: string
}

// ============================================================
// 连线样式预设
// ============================================================

export interface EdgeStylePreset {
  strokeColor: string
  strokeWidth: number
  strokeDasharray: string
}

// 介质类型对应的默认连线样式
export const MEDIUM_EDGE_STYLES: Record<MediumType, EdgeStylePreset> = {
  electric: { strokeColor: '#165DFF', strokeWidth: 2, strokeDasharray: '0' },
  thermal: { strokeColor: '#F97316', strokeWidth: 2, strokeDasharray: '0' },
  gas: { strokeColor: '#EF4444', strokeWidth: 2, strokeDasharray: '0' },
  hydrogen: { strokeColor: '#12B76A', strokeWidth: 2, strokeDasharray: '0' },
  material: { strokeColor: '#8B5CF6', strokeWidth: 2, strokeDasharray: '0' },
  general: { strokeColor: '#98A2B3', strokeWidth: 1.5, strokeDasharray: '0' },
  ammonia: { strokeColor: '#6366F1', strokeWidth: 2, strokeDasharray: '0' },
  methanol: { strokeColor: '#EC4899', strokeWidth: 2, strokeDasharray: '0' },
  carbon: { strokeColor: '#78716C', strokeWidth: 2, strokeDasharray: '0' }
}
