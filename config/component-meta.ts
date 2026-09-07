import type {
  AppearancePreset,
  ComponentCategory,
  ComponentDefinition,
  ComponentGroup,
  ComponentGroupKey,
  ConfigField,
  LayerConfig,
  LayerStatus,
  MediumType,
  PortDefinition,
  PortDirection,
  PrimitiveValue
} from '~~/types/component'
import type { BoundaryMeaning } from '~~/types/boundary'

import componentLibraryData from './component-library.json'
import { componentUIConfigs } from './component-ui-config'

// ============================================================
// 组件分组定义
// ============================================================

export const componentGroups: ComponentGroup[] = [
  { key: 'bus', label: '总线', description: '能源总线' },
  { key: 'power-external-source', label: '外部源', description: '外部能源来源' },
  { key: 'power-converter', label: '转换设备', description: '能源转换设备' },
  { key: 'power-transmission', label: '传输设备', description: '能源传输设备' },
  { key: 'thermal-external-source', label: '外部源', description: '外部冷热来源' },
  { key: 'thermal-converter', label: '转换设备', description: '冷热转换设备' },
  { key: 'thermal-transmission', label: '传输设备', description: '冷热传输设备' },
  { key: 'fuel-external-source', label: '外部源', description: '燃料来源' },
  { key: 'fuel-converter', label: '转换设备', description: '燃料转换设备' },
  { key: 'hydrogen-external-source', label: '外部源', description: '氢能来源' },
  { key: 'hydrogen-converter', label: '转换设备', description: '氢能转换设备' },
  { key: 'hydrogen-storage', label: '氢储能', description: '氢气储能设备' },
  { key: 'carbon-external-source', label: '外部源', description: '碳排放来源' },
  { key: 'carbon-converter', label: '转换设备', description: '碳排放处理设备' },
  { key: 'electric-storage', label: '电储能', description: '电力储能设备' },
  { key: 'gas-storage', label: '气储能', description: '气体储能设备' },
  { key: 'thermal-storage', label: '冷热储能', description: '冷热储能设备' },
  { key: 'chemical-storage', label: '化工储能', description: '化工储能设备' },
  { key: 'time-shift-load', label: '分时负荷', description: '分时电价负荷' },
  { key: 'flexible-load', label: '柔性负荷', description: '可调节柔性负荷' },
  { key: 'dr-load', label: '需求响应负荷', description: '需求响应负荷' },
  { key: 'trading-market', label: '交易市场', description: '能源交易市场' },
  { key: 'green-certificate', label: '绿证', description: '绿色证书' }
]

export const componentCategories: ComponentCategory[] = [
  { key: 'bus', label: '总线', description: '能源总线', icon: 'bus', groups: ['bus'] },
  { key: 'power', label: '电力系统', description: '电力生产与传输', icon: 'power', groups: ['power-external-source', 'power-converter', 'power-transmission'] },
  { key: 'thermal', label: '冷热系统', description: '冷热供应系统', icon: 'thermal', groups: ['thermal-external-source', 'thermal-converter', 'thermal-transmission'] },
  { key: 'fuel', label: '燃料系统', description: '燃料供应系统', icon: 'fuel', groups: ['fuel-external-source', 'fuel-converter'] },
  { key: 'hydrogen', label: '氢能系统', description: '氢能系统', icon: 'hydrogen', groups: ['hydrogen-external-source', 'hydrogen-converter', 'hydrogen-storage'] },
  { key: 'carbon', label: '碳排放', description: '碳排放系统', icon: 'carbon', groups: ['carbon-external-source', 'carbon-converter'] },
  { key: 'storage', label: '储能', description: '储能系统', icon: 'storage', groups: ['electric-storage', 'gas-storage', 'thermal-storage', 'chemical-storage'] },
  { key: 'load', label: '负荷', description: '能源负荷', icon: 'load', groups: ['time-shift-load', 'flexible-load', 'dr-load'] },
  { key: 'market', label: '市场', description: '能源市场', icon: 'market', groups: ['trading-market', 'green-certificate'] }
]

export const componentGroupMap = Object.fromEntries(
  componentGroups.map(group => [group.key, group])
) as Record<ComponentGroupKey, ComponentGroup>

// ============================================================
// 优化变量中文名映射（用于结果分析页面图表显示）
// key = 组件类型代码，value = { 变量基础名: 中文显示名 }
// 变量基础名不含组件实例 code 后缀（如 E_WT_abc123 → E_WT）
// ============================================================

export const VARIABLE_DISPLAY_NAMES: Record<string, Record<string, string>> = {
  WT: { E_WT: '输出功率', E_WT_cut: '弃风功率', AVAILABLE_WT: '可用功率' },
  PV: { E_PV: '输出功率', E_PV_cut: '弃光功率' },
  ES: { E_ES: '储量', E_ES_in: '充电功率', E_ES_out: '放电功率' },
  HS: { H_HS: '储量', H_HS_in: '充氢功率', H_HS_out: '放氢功率' },
  PS: { E_PS: '储量', E_PS_in: '充电功率', E_PS_out: '放电功率' },
  FS: { E_FS: '储量', E_FS_in: '充电功率', E_FS_out: '放电功率' },
  CS: { E_CS: '储量', E_CS_in: '充气功率', E_CS_out: '放气功率' },
  GP: { E_GP: '输出功率', F_GP: '消耗燃料' },
  CP: { E_CP: '输出功率', F_CP: '消耗燃料' },
  CHP: { E_CHP: '发电功率', Q_CHP: '供热功率', F_CHP: '消耗燃料' },
  ET: { E_ET: '耗电功率', H_ET: '产氢功率' },
  ELOAD: { E_ELOAD: '电负荷' },
  HLOAD: { H_HLOAD: '氢负荷' },
  QLOAD: { Q_QLOAD: '热负荷' },
  // 松弛变量
  BUS: { E_SHORTAGE: '缺额功率', E_EXCESS: '过剩功率' },
}

/**
 * 从 sourceId|varName 的 key 中解析出组件类型和基础变量名
 * 例如 "ES|E_ES_out_7e77" → { componentType: "ES", baseVarName: "E_ES_out" }
 * @param knownCodes 可选，已知的节点 code 集合（如 ["7e8a", "7e77"]），用于从 varName 中剥离 code 后缀
 */
export function parseVariableKey(key: string, knownCodes?: string[]): { componentType: string; baseVarName: string } {
  const [sourceId, varName] = key.split('|')
  // sourceId 格式: "WT" 或 "ELOAD" 或 "ES_7e77" 或 "BUS" 或 "b_xxx"
  // varName 格式: "E_WT_7e8a" 或 "E_ES_out_7e77" 或 "E_ELOAD_d0a4" 或 "irradiance"

  // 智能匹配 sourceId → componentType：
  // 1) 先试完整 sourceId（"WT", "ELOAD", "BUS"）
  // 2) 再逐级缩短前缀（"ES_7e77" → 试 "ES_7e77" 失败 → 试 "ES"）
  let sourceType = ''
  const idParts = sourceId?.split('_') ?? []
  for (let len = idParts.length; len >= 1; len--) {
    const candidate = idParts.slice(0, len).join('_')
    if (candidate in VARIABLE_DISPLAY_NAMES) {
      sourceType = candidate
      break
    }
  }
  // 兜底：取第一段
  if (!sourceType) sourceType = idParts[0] ?? ''

  // 提取 code：优先从 sourceId 尾部（旧格式 "ES_7e77"），否则从 varName 尾部匹配
  let sourceCode = ''
  if (sourceType && sourceId !== sourceType) {
    // sourceId 比 sourceType 长，多余部分就是 code（如 "ES_7e77" → sourceType="ES", code="7e77"）
    sourceCode = sourceId.slice(sourceType.length + 1)
  }
  if (!sourceCode && knownCodes?.length && varName) {
    for (const code of knownCodes) {
      if (varName.endsWith(`_${code}`)) {
        sourceCode = code
        break
      }
    }
  }

  const baseVarName = sourceCode && varName?.endsWith(`_${sourceCode}`)
    ? varName.slice(0, -sourceCode.length - 1)
    : (varName ?? '')
  return { componentType: sourceType, baseVarName }
}

/**
 * 获取变量的中文显示名
 * @param componentType 组件类型代码 (如 "ES")
 * @param baseVarName 基础变量名 (如 "E_ES_out")
 * @returns 中文显示名，未找到时返回原始 baseVarName
 */
export function getVariableDisplayName(componentType: string, baseVarName: string): string {
  console.log(componentType, baseVarName, VARIABLE_DISPLAY_NAMES[componentType])
  const typeMap = VARIABLE_DISPLAY_NAMES[componentType]
  if (!typeMap) return baseVarName
  return typeMap[baseVarName] ?? baseVarName
}

// ============================================================
// 解析器：从 JSON + UI config 生成 ComponentDefinition
// ============================================================

interface LibraryComponent {
  label: string
  description: string
  category: string
  group: ComponentGroupKey
  tags: string[]
  // 该组件可关联的边界物理含义集合（可选项范围）。
  // 选择 0/1/多个边界对象由用户在实例侧（boundaryIds[]）决定，
  // schema 不做任何选择约束，由后端计算模块校验合理性。
  boundaryKey?: BoundaryMeaning[]
  ports: Array<{ id: string; side: string; direction: string; medium: string; offset: number; label?: string }>
  layerStatuses: Record<string, string[]>
  commonTechFields: Array<Record<string, unknown>>
  commonEconomicFields: Array<Record<string, unknown>>
  layerTechFields: Array<Record<string, unknown>>
  layerEconomicFields: Array<Record<string, unknown>>
  constraintFields: Array<Record<string, unknown>>
  objectiveFields: Array<Record<string, unknown>>
}

const extractDefaults = (fields: Array<Record<string, unknown>>): Record<string, PrimitiveValue> => {
  const result: Record<string, PrimitiveValue> = {}
  for (const field of fields) {
    if ('defaultValue' in field && field.defaultValue !== undefined) {
      result[field.key as string] = field.defaultValue as PrimitiveValue
    }
  }
  return result
}

// 从约束/目标字段提取默认值，包装为 { enabled: value } 结构
const extractToggleDefaults = (fields: Array<Record<string, unknown>>): Record<string, { enabled: boolean }> => {
  const result: Record<string, { enabled: boolean }> = {}
  for (const field of fields) {
    if ('defaultValue' in field && field.defaultValue !== undefined) {
      result[field.key as string] = { enabled: Boolean(field.defaultValue) }
    }
  }
  return result
}

const parseLayerConfigs = (
  layerStatuses: Record<string, string[]>,
  constraintFields: Array<Record<string, unknown>> = [],
  objectiveFields: Array<Record<string, unknown>> = []
): Record<string, LayerConfig> => {
  const constraintDefaults = extractToggleDefaults(constraintFields)
  const objectiveDefaults = extractToggleDefaults(objectiveFields)
  const configs: Record<string, LayerConfig> = {}
  for (const [layerId, statuses] of Object.entries(layerStatuses)) {
    configs[layerId] = {
      layerId,
      status: (statuses.includes('stand_alone') ? 'stand_alone' : statuses[0]) as LayerStatus,
      techParams: {},
      economicParams: {},
      constraints: { ...constraintDefaults },
      objectives: { ...objectiveDefaults }
    }
  }
  return configs
}

const parseComponentDefinition = (key: string, data: LibraryComponent): ComponentDefinition => {
  const ui = componentUIConfigs[key]

  const commonTechDefaults = extractDefaults(data.commonTechFields)
  const commonEconomicDefaults = extractDefaults(data.commonEconomicFields)

  return {
    key,
    label: data.label,
    category: data.category as ComponentDefinition['category'],
    group: data.group,
    icon: ui?.icon ?? 'default',
    description: data.description,
    canvasType: ui?.canvasType ?? 'energy',
    defaultSize: ui?.defaultSize ?? { width: 150, height: 150 },
    appearance: ui?.appearance ?? {
      fillColor: '#F8FAFC', strokeColor: '#98A2B3', strokeWidth: 1.5,
      fontSize: 13, textColor: '#1D2939', borderRadius: 10, rotation: 0, opacity: 1
    },
    ports: data.ports.map(p => ({
      id: p.id,
      label: p.label,
      direction: p.direction as PortDirection,
      side: p.side as PortDefinition['side'],
      offset: p.offset,
      medium: p.medium as MediumType
    })),
    defaultMeta: {
      componentKey: key,
      componentType: data.group,
      componentName: data.label,
      description: data.description,
      deviceCount: 1,
      commonTechParams: commonTechDefaults,
      commonEconomicParams: commonEconomicDefaults,
      layerConfigs: parseLayerConfigs(data.layerStatuses, data.constraintFields, data.objectiveFields),
      // 不再根据 boundaryKey 自动填充边界 id —— 用户手动从可用范围里选
      boundaryIds: []
    },
    commonTechParamFields: data.commonTechFields as unknown as ConfigField[],
    commonEconomicParamFields: data.commonEconomicFields as unknown as ConfigField[],
    layerTechParamFields: data.layerTechFields as unknown as ConfigField[],
    layerEconomicParamFields: data.layerEconomicFields as unknown as ConfigField[],
    layerConstraintFields: data.constraintFields.length > 0
      ? data.constraintFields as unknown as ConfigField[]
      : [
        { key: 'minLoadRatio', label: '最小出力', type: 'number', defaultValue: 0.1, min: 0, max: 1, step: 0.05 },
        { key: 'maxLoadRatio', label: '最大出力', type: 'number', defaultValue: 1, min: 0, max: 1, step: 0.05 },
        { key: 'rampRate', label: '爬坡率', type: 'number', defaultValue: 0, unit: '%/min', step: 1 }
      ],
    layerObjectiveFields: data.objectiveFields.length > 0
      ? data.objectiveFields as unknown as ConfigField[]
      : [
        { key: 'dispatchPriority', label: '调度优先级', type: 'select', defaultValue: 'balanced', options: [{ label: '平衡', value: 'balanced' }, { label: '经济优先', value: 'economic' }, { label: '低碳优先', value: 'low-carbon' }] },
        { key: 'participateOptimization', label: '参与优化', type: 'boolean', defaultValue: true }
      ],
    tags: data.tags,
    boundaryKey: data.boundaryKey
  }
}

// ============================================================
// 导出的组件定义
// ============================================================

export const componentDefinitions: ComponentDefinition[] = Object.entries(
  componentLibraryData.components as unknown as Record<string, LibraryComponent>
).map(([key, data]) => parseComponentDefinition(key, data))

export const componentDefinitionMap = Object.fromEntries(
  componentDefinitions.map(def => [def.key, def])
) as Record<string, ComponentDefinition>

// ============================================================
// 组件库层级结构
// ============================================================

export const componentLibrary = componentCategories.map(category => ({
  ...category,
  groups: category.groups.map(groupKey => ({
    ...componentGroupMap[groupKey],
    items: componentDefinitions.filter(def => def.group === groupKey)
  }))
}))
