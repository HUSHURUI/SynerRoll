import type { Project } from '~~/types/project'
import type { BackendComponentRecord, BackendExportPayload, BackendNodeRecord } from '~~/types/simulation'

import { componentDefinitionMap } from '~~/config/component-meta'
import componentLibraryData from '~~/config/component-library.json'

// 前端组件 key 到后端组件 type 的映射
const getBackendType = (frontendKey: string): string => {
  const comp = (componentLibraryData.components as Record<string, any>)[frontendKey]
  return comp?.backendKey ?? frontendKey
}

const networkTypeMap: Record<string, string> = {
  electric: 'E',
  thermal: 'H',
  gas: 'G',
  hydrogen: 'H2',
  material: 'M',
  carbon: 'C',
  general: 'X'
}

export const buildBackendPayload = (project: Project): BackendExportPayload => {
  const activeCanvas = project.workspace.canvases.find(c => c.id === project.workspace.activeCanvasId)
    ?? project.workspace.canvases[0]

  if (!activeCanvas) {
    throw createError({ statusCode: 400, statusMessage: 'No active canvas found in project' })
  }

  // 按介质类型对节点进行分组，介质类型取自节点第一个出口端口
  const nodeGroups = activeCanvas.nodes.reduce<Record<string, string[]>>((groups, node) => {
    const data = node.data
    if (!data) return groups
    const def = componentDefinitionMap[data.componentKey]
    if (!def) return groups

    // 取节点的第一个出口端口的介质类型作为该节点的介质
    const outPort = def.ports.find(port => port.direction === 'out')
    const medium = outPort?.medium ?? 'general'
    const mappedType = networkTypeMap[medium] ?? 'X'

    if (mappedType === 'X') return groups // 跳过 general 类型

    groups[mappedType] = groups[mappedType]
      ? [...groups[mappedType], data.componentKey]
      : [data.componentKey]
    return groups
  }, {})

  const component: BackendComponentRecord[] = activeCanvas.nodes
    .filter(node => node.data && componentDefinitionMap[node.data.componentKey])
    .map(node => {
      const data = node.data!
      return {
        type: getBackendType(data.componentKey),
        paras: data.business.commonTechParams as Record<string, string | number | boolean>,
        costs: data.business.commonEconomicParams as Record<string, number>,
        layer: data.business.layerConfigs as unknown as Record<string, Record<string, string | number | boolean>>
      }
    })

  const node: BackendNodeRecord[] = Object.entries(nodeGroups).map(([Type, Component]) => ({
    Type,
    Component
  }))

  const layer = project.layerConfig.layers.reduce<BackendExportPayload['layer']>((result, item) => {
    result[item.id] = {
      id: item.id,
      name: item.name,
      length: item.length,
      step: item.step,
      forward: item.forward
    }
    return result
  }, {})

  return {
    algorithm: {
      electricityLoadPrediction: project.algorithm.electricityLoadPrediction,
      heatLoadPrediction: project.algorithm.heatLoadPrediction,
      windTurbinePrediction: project.algorithm.windTurbinePrediction,
      optimizationAlgorithm: project.algorithm.optimizationAlgorithm,
      slackEnabled: project.algorithm.slackEnabled,
      slackPenalty: project.algorithm.slackPenalty
    },
    boundary: project.boundaries,
    component,
    layer,
    node
  }
}
