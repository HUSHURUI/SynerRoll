import type { FlowNode } from '~~/types/canvas'
import type { Project } from '~~/types/project'
import { VARIABLE_DISPLAY_NAMES, componentDefinitionMap } from '~~/config/component-meta'

export interface DeviceOutputPoint {
  ts: string
  value: number
}

export type DeviceOutputLiveData = Record<string, Record<string, DeviceOutputPoint[]>>

export type DeviceOutputMedium = 'electric' | 'thermal' | 'hydrogen' | 'fuel' | 'bus' | 'other'

export interface DeviceOutputVariable {
  key: string
  sourceId: string
  varName: string
  baseVarName: string
  deviceId: string
  deviceCode: string
  deviceName: string
  componentType: string
  componentLabel: string
  variableName: string
  displayName: string
  originalUnit: string
  dimension: string
  dimensionLabel: string
  medium: DeviceOutputMedium
  mediumLabel: string
  layerIds: string[]
}

export interface DeviceOutputDevice {
  id: string
  code: string
  name: string
  componentType: string
  componentLabel: string
  medium: DeviceOutputMedium
  mediumLabel: string
  variables: DeviceOutputVariable[]
}

export interface UnitOption {
  label: string
  value: string
  factor: number
}

const EXTRA_VARIABLE_NAMES: Record<string, string> = {
  E_GRID_in: '购电功率',
  E_GRID_out: '上网功率',
  E_HYDRO: '输出功率',
  AVAILABLE_HYDRO: '可用功率',
  MINIMUM_HYDRO: '最小运行功率',
  Q_EXCESS: '过剩热功率',
  Q_SHORTAGE: '缺额热功率',
  E_EXCESS: '过剩功率',
  E_SHORTAGE: '缺额功率',
  E_ELOAD: '电负荷',
  Q_QLOAD: '热负荷',
  H_HLOAD: '氢负荷'
}

const MEDIUM_LABELS: Record<DeviceOutputMedium, string> = {
  electric: '电能流',
  thermal: '热能流',
  hydrogen: '氢能流',
  fuel: '燃料',
  bus: '各类总线',
  other: '其他'
}

const UNIT_GROUPS: Record<string, UnitOption[]> = {
  power: [
    { label: 'W', value: 'W', factor: 1 },
    { label: 'kW', value: 'kW', factor: 1_000 },
    { label: 'MW', value: 'MW', factor: 1_000_000 }
  ],
  energy: [
    { label: 'Wh', value: 'Wh', factor: 1 },
    { label: 'kWh', value: 'kWh', factor: 1_000 },
    { label: 'MWh', value: 'MWh', factor: 1_000_000 }
  ],
  mass: [
    { label: 'kg', value: 'kg', factor: 1 },
    { label: 't', value: 't', factor: 1_000 }
  ],
  massFlow: [
    { label: 'kg/h', value: 'kg/h', factor: 1 },
    { label: 't/h', value: 't/h', factor: 1_000 }
  ],
  ratio: [{ label: '%', value: '%', factor: 1 }]
}

function canvasNodes(project: Project | null, canvasId: string): FlowNode[] {
  if (!project?.workspace?.canvases?.length) return []
  const canvas = project.workspace.canvases.find(item => item.id === canvasId)
  return canvas?.nodes ?? []
}

function nodeCode(node: FlowNode): string {
  return String(node.id ?? '').replace(/^node-/, '').slice(0, 4)
}

function findNode(nodes: FlowNode[], sourceId: string, varName: string): FlowNode | undefined {
  return nodes.find((node) => {
    const code = nodeCode(node)
    return Boolean(code) && (varName.endsWith(`_${code}`) || sourceId.endsWith(`_${code}`))
  })
}

function normalizeComponentType(node: FlowNode | undefined, sourceId: string, varName: string): string {
  const nodeType = String(node?.data?.componentKey ?? '')
  if (nodeType.endsWith('_BUS')) return 'BUS'
  if (nodeType) return nodeType
  if (sourceId === 'BUS') return 'BUS'
  if (sourceId === 'E_ELOAD' || varName.startsWith('E_ELOAD')) return 'ELOAD'
  if (sourceId === 'Q_QLOAD' || varName.startsWith('Q_QLOAD')) return 'QLOAD'
  if (sourceId === 'H_HLOAD' || varName.startsWith('H_HLOAD')) return 'HLOAD'
  return sourceId.split('_')[0] ?? sourceId
}

function baseVariableName(varName: string, code: string): string {
  if (code && varName.endsWith(`_${code}`)) {
    return varName.slice(0, -(code.length + 1))
  }
  return varName
}

function variableDisplayName(componentType: string, baseVarName: string): string {
  return VARIABLE_DISPLAY_NAMES[componentType]?.[baseVarName]
    ?? EXTRA_VARIABLE_NAMES[baseVarName]
    ?? baseVarName
}

function inferMedium(componentType: string, baseVarName: string): DeviceOutputMedium {
  if (componentType === 'BUS') return 'bus'
  if (baseVarName.startsWith('Q_')) return 'thermal'
  if (baseVarName.startsWith('H_')) return 'hydrogen'
  if (baseVarName.startsWith('F_')) return 'fuel'
  if (baseVarName.startsWith('E_') || baseVarName.startsWith('AVAILABLE_') || baseVarName.startsWith('MINIMUM_')) return 'electric'
  return 'other'
}

function inferDimension(unit: string): { key: string; label: string } {
  const normalized = unit.trim().toLowerCase()
  if (['w', 'kw', 'mw'].includes(normalized)) return { key: 'power', label: '功率' }
  if (['wh', 'kwh', 'mwh'].includes(normalized)) return { key: 'energy', label: '储能量' }
  if (['kg/h', 't/h'].includes(normalized)) return { key: 'massFlow', label: '质量流量' }
  if (['kg', 't'].includes(normalized)) return { key: 'mass', label: '质量' }
  if (normalized === '%' || normalized === 'pu') return { key: 'ratio', label: '比例' }
  return { key: `unit:${unit || '-'}`, label: unit ? '数值' : '无量纲' }
}

export function buildDeviceOutputCatalog(
  liveData: DeviceOutputLiveData,
  units: Record<string, string>,
  project: Project | null,
  canvasId: string
): DeviceOutputDevice[] {
  const nodes = canvasNodes(project, canvasId)
  const deviceMap = new Map<string, DeviceOutputDevice>()

  for (const [key, layers] of Object.entries(liveData)) {
    const separatorIndex = key.indexOf('|')
    if (separatorIndex < 0) continue
    const sourceId = key.slice(0, separatorIndex)
    const varName = key.slice(separatorIndex + 1)
    const node = findNode(nodes, sourceId, varName)

    // 设备出力分析只呈现画布中的真实设备或总线，跳过边界计划等无设备归属的序列。
    if (!node) continue

    const code = nodeCode(node)
    const componentType = normalizeComponentType(node, sourceId, varName)
    const baseVarName = baseVariableName(varName, code)
    const originalUnit = units[key] || inferDefaultUnit(baseVarName)
    const dimension = inferDimension(originalUnit)
    const medium = inferMedium(componentType, baseVarName)
    const deviceName = String(node.data?.label || node.data?.business?.componentName || componentType)
    const componentLabel = componentDefinitionMap[String(node.data?.componentKey ?? '')]?.label
      ?? componentDefinitionMap[componentType]?.label
      ?? componentType
    const variableName = variableDisplayName(componentType, baseVarName)

    const variable: DeviceOutputVariable = {
      key,
      sourceId,
      varName,
      baseVarName,
      deviceId: String(node.id),
      deviceCode: code,
      deviceName,
      componentType,
      componentLabel,
      variableName,
      displayName: `${deviceName} - ${variableName}`,
      originalUnit,
      dimension: dimension.key,
      dimensionLabel: dimension.label,
      medium,
      mediumLabel: MEDIUM_LABELS[medium],
      layerIds: Object.keys(layers).sort((a, b) => Number(a) - Number(b))
    }

    const existing = deviceMap.get(String(node.id))
    if (existing) {
      existing.variables.push(variable)
    }
    else {
      deviceMap.set(String(node.id), {
        id: String(node.id),
        code,
        name: deviceName,
        componentType,
        componentLabel,
        medium,
        mediumLabel: MEDIUM_LABELS[medium],
        variables: [variable]
      })
    }
  }

  const order = new Map(nodes.map((node, index) => [String(node.id), index]))
  return [...deviceMap.values()]
    .map(device => ({
      ...device,
      variables: device.variables.sort((a, b) => a.variableName.localeCompare(b.variableName, 'zh-CN'))
    }))
    .sort((a, b) => (order.get(a.id) ?? Number.MAX_SAFE_INTEGER) - (order.get(b.id) ?? Number.MAX_SAFE_INTEGER))
}

export function inferDefaultUnit(baseVarName: string): string {
  if (['E_ES', 'E_PS', 'E_FS', 'E_CS'].includes(baseVarName)) return 'kWh'
  if (baseVarName === 'H_HS') return 'kg'
  if (baseVarName.startsWith('H_')) return 'kg/h'
  return 'kW'
}

export function unitOptionsForDimension(dimension: string, originalUnit: string): UnitOption[] {
  return UNIT_GROUPS[dimension] ?? [{ label: originalUnit || '-', value: originalUnit || '-', factor: 1 }]
}

export function defaultDisplayUnit(dimension: string, originalUnit: string): string {
  const options = unitOptionsForDimension(dimension, originalUnit)
  return options.some(option => option.value === originalUnit) ? originalUnit : options[0]!.value
}

export function convertDeviceOutputValue(value: number, fromUnit: string, toUnit: string, dimension: string): number {
  if (!Number.isFinite(value) || fromUnit === toUnit) return value
  const options = unitOptionsForDimension(dimension, fromUnit)
  const from = options.find(option => option.value === fromUnit)
  const to = options.find(option => option.value === toUnit)
  if (!from || !to) return value
  return value * from.factor / to.factor
}

export function timestampToMinutes(timestamp: string): number {
  const [hour = '0', minute = '0'] = timestamp.split(':')
  return Number(hour) * 60 + Number(minute)
}

export function minutesToTimestamp(minutes: number): string {
  const safeMinutes = Math.max(0, Math.round(minutes))
  const hour = Math.floor(safeMinutes / 60)
  const minute = safeMinutes % 60
  return `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`
}
