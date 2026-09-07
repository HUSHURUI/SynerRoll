// ============================================================
// 边界类 (Boundary) 相关类型
// 边界类是一组时序数据，用于综合能源系统运行优化计算
// ============================================================

export type InterpolateType = 'copy' | 'linear' | 'cubic' | 'spline'
export type RandomDistribution = 'normal' | 'uniform' | 'exponential' | 'lognormal'

// 物理含义类型
export type BoundaryMeaning =
  | 'wind_speed'     // 风速
  | 'irradiance'     // 辐照度
  | 'temperature'    // 温度
  | 'factor'         // 转化因子
  | 'power'          // 功率
  | 'humidity'       // 湿度
  | 'pressure'       // 气压
  | 'wind_direction' // 风向
  | 'cloud_cover'    // 云量
  | 'other'          // 其他

// 中英文映射
export const BOUNDARY_MEANING_LABELS: Record<BoundaryMeaning, string> = {
  wind_speed: '风速',
  irradiance: '辐照度',
  temperature: '温度',
  factor: '转化因子',
  power: '功率',
  humidity: '湿度',
  pressure: '气压',
  wind_direction: '风向',
  cloud_cover: '云量',
  other: '其他'
}

// 边界类对象定义
export interface BoundaryItem {
  id: string
  name: string
  filePath: string
  columnName: string
  timeStep: string
  meaning: BoundaryMeaning
  relatedComponents: string[]
  interpolateType: InterpolateType
  randomDistribution: RandomDistribution
  noiseLevel: number
  // 持久化的数据
  rawData?: {
    values: number[]
    timestamps: string[]
    xAxisLabel: string
    yAxisLabel: string
  }
  transformedData?: {
    layers: { layerId: string; layerName: string; values: number[]; timestamps: string[] }[]
  }
  // boundary 元信息（长度和尺度）
  boundaryMeta?: {
    boundaryLength: string
    boundaryStep: string
    dayCount: number
    pointCount: number
  }
}

// 边界数据（原始导入数据）
export interface BoundaryRawData {
  boundaryId: string
  values: number[]
  timestamps: string[]
  xAxisLabel: string
  yAxisLabel: string
}

// 转换后的数据（多时间尺度）
export interface BoundaryTransformedData {
  boundaryId: string
  layers: {
    layerId: string
    layerName: string
    values: number[]
    timestamps: string[]
  }[]
}

// NOTE: 2026-07-07 — 与 boundaryKey 重构配套保留
// BOUNDARY_COMPONENT_MAPPINGS 现在跟 ComponentDefinition.boundaryKey (types/component.ts)
// 重复且发散（前者固定 WT/PV → 1~2 个 meaning，后者每个组件各自声明 3~4 个）。
// 下一步清理应迁移到 componentDefinitionMap[def.key].boundaryKey?.includes(meaning) 的查询。
// 暂时注释保留，避免回归时丢失原始逻辑。

/*
// 边界与组件的映射关系（用于自动创建边界）
export interface BoundaryComponentMapping {
  componentKey: string
  defaultMeanings: BoundaryMeaning[]
}

// WT组件需要的边界：风速
// PV组件需要的边界：辐照度、温度
export const BOUNDARY_COMPONENT_MAPPINGS: BoundaryComponentMapping[] = [
  { componentKey: 'WT', defaultMeanings: ['wind_speed'] },
  { componentKey: 'PV', defaultMeanings: ['irradiance', 'temperature'] }
]
*/

// 边界相关配置的可编辑字段
export interface BoundaryConfigFields {
  interpolateType: InterpolateType
  randomDistribution: RandomDistribution
  noiseLevel: number
}

// 时间步长选项
export const TIME_STEP_OPTIONS = [
  { label: '15分钟', value: '15m' },
  { label: '30分钟', value: '30m' },
  { label: '1小时', value: '1h' },
  { label: '2小时', value: '2h' },
  { label: '4小时', value: '4h' },
  { label: '6小时', value: '6h' },
  { label: '12小时', value: '12h' },
  { label: '1天', value: '24h' }
]

// 插值方式选项
export const INTERPOLATE_OPTIONS: { label: string; value: InterpolateType }[] = [
  { label: '复制', value: 'copy' },
  { label: '线性', value: 'linear' },
]

// 随机分布选项
export const DISTRIBUTION_OPTIONS: { label: string; value: RandomDistribution }[] = [
  { label: '正态分布', value: 'normal' },
  { label: '均匀分布', value: 'uniform' },
]