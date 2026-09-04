import type { PrimitiveValue } from '~~/types/component'

export type ProjectTemplateId =
  | 'blank'
  | 'large_renewable_base'
  | 'regional_renewable_system'
  | 'distributed_industrial_park'

export interface ProjectTemplateNodePreset {
  componentKey: string
  position: { x: number; y: number }
  techParams?: Record<string, PrimitiveValue>
}

export interface ProjectTemplateDefinition {
  id: ProjectTemplateId
  label: string
  shortLabel: string
  description: string
  componentSummary: string
  tags: string[]
  recommended: boolean
  nodes: ProjectTemplateNodePreset[]
}

export const PROJECT_TEMPLATE_OPTIONS: ProjectTemplateDefinition[] = [
  {
    id: 'blank',
    label: '空白项目',
    shortLabel: '空白',
    description: '从空白画布开始，自行添加组件、连接拓扑并配置容量。',
    componentSummary: '不预置组件',
    tags: ['综合能源'],
    recommended: false,
    nodes: []
  },
  {
    id: 'large_renewable_base',
    label: '大型集中式新能源基地',
    shortLabel: '大型基地',
    description: '预置大规模风光、常规电源、储能、负荷和明确的外送并网点。',
    componentSummary: '电网、风机、光伏、燃煤机组、电化学储能、分时电负荷',
    tags: ['综合能源', '推荐模板', '大型新能源基地'],
    recommended: true,
    nodes: [
      { componentKey: 'WT', position: { x: 120, y: 90 }, techParams: { capacity: 600000 } },
      { componentKey: 'PV', position: { x: 120, y: 280 }, techParams: { capacity: 400000 } },
      { componentKey: 'CP', position: { x: 120, y: 470 }, techParams: { capacity: 350000 } },
      { componentKey: 'ELEC_BUS', position: { x: 560, y: 285 } },
      { componentKey: 'ES', position: { x: 820, y: 90 }, techParams: { capacity: 300000 } },
      { componentKey: 'ELOAD', position: { x: 820, y: 300 }, techParams: { rated_demand: 500000 } },
      { componentKey: 'GRID', position: { x: 820, y: 500 }, techParams: { capacity: 1000000, sell_ratio: 1, buy_ratio: 1 } }
    ]
  },
  {
    id: 'regional_renewable_system',
    label: '中型新能源区域系统',
    shortLabel: '区域系统',
    description: '预置本地风光、气电、储能和负荷，并给出受限的电网交换参数。',
    componentSummary: '电网、风机、光伏、气电机组、电化学储能、分时电负荷',
    tags: ['综合能源', '推荐模板', '新能源区域系统'],
    recommended: true,
    nodes: [
      { componentKey: 'WT', position: { x: 120, y: 90 }, techParams: { capacity: 120000 } },
      { componentKey: 'PV', position: { x: 120, y: 280 }, techParams: { capacity: 80000 } },
      { componentKey: 'GP', position: { x: 120, y: 470 }, techParams: { capacity: 100000 } },
      { componentKey: 'ELEC_BUS', position: { x: 560, y: 285 } },
      { componentKey: 'ES', position: { x: 820, y: 90 }, techParams: { capacity: 100000 } },
      { componentKey: 'ELOAD', position: { x: 820, y: 300 }, techParams: { rated_demand: 200000 } },
      { componentKey: 'GRID', position: { x: 820, y: 500 }, techParams: { capacity: 300000, sell_ratio: 0.2, buy_ratio: 0.2 } }
    ]
  },
  {
    id: 'distributed_industrial_park',
    label: '小型分布式新能源工业园区',
    shortLabel: '工业园区',
    description: '预置园区光伏、储能、负荷和购售电接口，适合继续配置峰谷电价。',
    componentSummary: '电网、光伏、电化学储能、分时电负荷',
    tags: ['综合能源', '推荐模板', '分布式工业园区'],
    recommended: true,
    nodes: [
      { componentKey: 'PV', position: { x: 150, y: 180 }, techParams: { capacity: 50000 } },
      { componentKey: 'ELEC_BUS', position: { x: 560, y: 285 } },
      { componentKey: 'ES', position: { x: 820, y: 100 }, techParams: { capacity: 40000 } },
      { componentKey: 'ELOAD', position: { x: 820, y: 300 }, techParams: { rated_demand: 60000 } },
      { componentKey: 'GRID', position: { x: 820, y: 500 }, techParams: { capacity: 100000, sell_ratio: 0.3, buy_ratio: 1 } }
    ]
  }
]

export const PROJECT_TEMPLATE_MAP = Object.fromEntries(
  PROJECT_TEMPLATE_OPTIONS.map(template => [template.id, template])
) as Record<ProjectTemplateId, ProjectTemplateDefinition>
