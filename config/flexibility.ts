import type {
  FlexibilityOperationMode,
  FlexibilityRequirementSource
} from '~~/types/api'

export interface FlexibilityOption<T extends string> {
  label: string
  value: T
  description: string
}

export const FLEXIBILITY_OPERATION_OPTIONS: FlexibilityOption<FlexibilityOperationMode>[] = [
  { label: '经济运行', value: 'economic_operation', description: '以运行经济性为主要优化目标。' },
  { label: '新能源消纳', value: 'renewable_consumption', description: '优先减少弃风、弃光。' },
  { label: '平抑新能源波动', value: 'renewable_smoothing', description: '降低新能源出力波动对并网点的影响。' },
  { label: '计划/AGC 跟踪', value: 'agc_tracking', description: '跟踪给定计划或 AGC 并网功率目标。' },
  { label: '灵活性增强', value: 'flexibility_enhancement', description: '以提高系统上下调裕度为目标。' }
]

export const FLEXIBILITY_REQUIREMENT_OPTIONS: FlexibilityOption<FlexibilityRequirementSource>[] = [
  { label: '净负荷变化', value: 'net_load_change', description: '根据相邻时段净负荷变化自动计算上下调需求。' },
  { label: '计划/AGC 目标', value: 'agc_or_schedule', description: '根据目标并网功率与基准并网功率的偏差计算需求。' },
  { label: '用户自定义', value: 'user_defined', description: '直接输入上调和下调需求。' }
]

const toLabelMap = <T extends string>(options: FlexibilityOption<T>[]): Record<T, string> =>
  Object.fromEntries(options.map(option => [option.value, option.label])) as Record<T, string>

export const FLEXIBILITY_OPERATION_LABELS = toLabelMap(FLEXIBILITY_OPERATION_OPTIONS)
export const FLEXIBILITY_REQUIREMENT_LABELS = toLabelMap(FLEXIBILITY_REQUIREMENT_OPTIONS)
