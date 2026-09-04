<script setup lang="ts">
import { MarkerType } from '@vue-flow/core'
import { componentDefinitionMap } from '~~/config/component-meta'
import type { ConfigField, LayerConfig, LayerStatus, PrimitiveValue } from '~~/types/component'
import type { BoundaryItem } from '~~/types/boundary'
import type { CanvasData, CanvasEdgeData, CanvasNodeData, FlowEdge, FlowNode, NodePortConfig } from '~~/types/canvas'
import { updateNodeFromFields } from '~~/utils/canvas'
import PropertySlider from './PropertySlider.vue'
import PropertySelect from './PropertySelect.vue'
import PropertyText from './PropertyText.vue'
import PropertySwitch from './PropertySwitch.vue'
import PropertyColor from './PropertyColor.vue'
import PropertyNumber from './PropertyNumber.vue'
import PropertyMultiSelect from './PropertyMultiSelect.vue'

const props = defineProps<{
  canvas: CanvasData
  selection: { nodeIds: string[]; edgeIds: string[]; primaryNodeId: string | null; primaryEdgeId: string | null }
  collapsed: boolean
  layerConfig?: { layers: { id: string; name: string }[] }
  boundaries?: BoundaryItem[]
}>()

const activeTab = defineModel<string>('activeTab', { required: true })

const emit = defineEmits<{
  'update:canvas': [canvas: CanvasData]
  toggleCollapse: []
}>()

const defaultSectionState: Record<string, boolean> = {
  'page-background': true,
  'page-size': true,
  'page-grid': true,
  'page-labels': true,
  'node-size': true,
  'node-position': true,
  'node-appearance': true,
  'node-text': true,
  'node-ports': true,
  'edge-style': true,
  'model-basic': true,
  'model-common-tech': true,
  'model-common-economic': true,
  'model-boundary': true,
  'model-layer-status': true,
  'model-layer-tech': true,
  'model-layer-economic': true,
  'model-layer-constraint': true,
  'model-layer-objective': true
}

const expandedSections = ref<Record<string, boolean>>({ ...defaultSectionState })

// 获取当前激活的时层ID列表
const activeLayerIds = computed(() => {
  // 优先使用项目级别的时层配置
  if (props.layerConfig?.layers?.length) {
    return props.layerConfig.layers.map(l => l.id)
  }
  // 否则使用节点级别的时层配置
  const configs = selectedNode.value?.data?.business?.layerConfigs
  if (!configs) return ['1']
  return Object.keys(configs)
})

const sizeStep = 10

const selectedNode = computed<FlowNode | null>(() =>
  props.canvas.nodes.find(node => node.id === props.selection.primaryNodeId) ?? null
)

const selectedEdge = computed<FlowEdge | null>(() =>
  props.canvas.edges.find(edge => edge.id === props.selection.primaryEdgeId) ?? null
)

const multipleNodesSelected = computed(() => props.selection.nodeIds.length > 1)

const selectedDefinition = computed(() =>
  selectedNode.value ? componentDefinitionMap[selectedNode.value.data?.componentKey ?? ''] : null
)

// 选中节点是否有关联边界
// boundaryKey 是组件可关联的边界物理含义数组；空 / 缺失 表示该组件不需要边界
const selectedNodeHasBoundary = computed(() => {
  const keys = selectedDefinition.value?.boundaryKey
  return Array.isArray(keys) && keys.length > 0
})

// 选中节点当前的边界ID数组（支持双向绑定）
const selectedNodeBoundaryIds = computed({
  get: () => selectedNode.value?.data?.business?.boundaryIds ?? [],
  set: (val: string[]) => {
    if (selectedNode.value && selectedNode.value.data) {
      const node = selectedNode.value
      updateSelectedNode(() => {
        node.data!.business.boundaryIds = val
        return node
      })
    }
  }
})

// 选中节点关联的边界对象列表
const selectedNodeBoundaries = computed(() =>
  props.boundaries?.filter(b => selectedNodeBoundaryIds.value.includes(b.id)) ?? []
)

// 编辑侧跟边界侧一致：只列出符合 boundaryKey 范围的边界
// 这样可以避免"在编辑器里选了 X，到边界页却看不到关联"的认知不一致
const availableBoundariesForNode = computed(() => {
  const def = selectedDefinition.value
  const acceptedMeanings = new Set<string>(def?.boundaryKey ?? [])
  return (props.boundaries ?? []).filter(b => acceptedMeanings.has(b.meaning))
})

const tabs = computed(() => {
  // 只有连线被选中（包括单选和多选）
  if (selectedEdge.value) {
    return [{ key: 'style', label: '连线样式' }]
  }

  // 没有选中节点时
  if (!selectedNode.value) {
    return [{ key: 'page', label: '页面样式' }]
  }

  // 多选了节点
  if (multipleNodesSelected.value) {
    return [{ key: 'style', label: '图形样式' }]
  }

  if (selectedDefinition.value?.canvasType === 'energy') {
    return [
      { key: 'params', label: '参数配置' },
      { key: 'model', label: '模型配置' },
      { key: 'style', label: '图形样式' }
    ]
  }

  return [
    { key: 'page', label: '页面样式' },
    { key: 'style', label: '图形样式' }
  ]
})

// 当前激活的时层索引（用于翻页器）
const activeLayerIndex = ref(0)

// 当前选中的时层ID
const currentLayerId = computed((): string => {
  const ids = activeLayerIds.value
  if (ids.length === 0) return '1'
  const idx = Math.min(activeLayerIndex.value, ids.length - 1)
  return ids[idx] ?? '1'
})

// 当前选中的时层名称
const currentLayerName = computed((): string => {
  const layer = props.layerConfig?.layers?.find(l => l.id === currentLayerId.value)
  return layer?.name ?? ''
})

// 翻页器相关
const canGoPrevLayer = computed(() => activeLayerIndex.value > 0)
const canGoNextLayer = computed(() => activeLayerIndex.value < activeLayerIds.value.length - 1)

const goToPrevLayer = () => {
  if (canGoPrevLayer.value) {
    activeLayerIndex.value--
  }
}

const goToNextLayer = () => {
  if (canGoNextLayer.value) {
    activeLayerIndex.value++
  }
}

// 重置时层索引当选择变化时
watch(activeLayerIds, () => {
  if (activeLayerIndex.value >= activeLayerIds.value.length) {
    activeLayerIndex.value = Math.max(0, activeLayerIds.value.length - 1)
  }
})

const sectionOpen = (key: string) => expandedSections.value[key] ?? true

const toggleSection = (key: string) => {
  expandedSections.value[key] = !sectionOpen(key)
}

// 将旋转角度规约为 0, 90, 180, -90 四种之一
const normalizeRotation = (value: number): number => {
  const normalized = ((value % 360) + 360) % 360
  const rounded = Math.round(normalized / 90) * 90
  return rounded
}

// 获取通用技术参数字段值
const getCommonTechFieldValue = (field: ConfigField): PrimitiveValue => {
  const business = selectedNode.value?.data?.business
  return business?.commonTechParams[field.key] ?? field.defaultValue
}

// 获取通用经济参数字段值
const getCommonEconomicFieldValue = (field: ConfigField): PrimitiveValue => {
  const business = selectedNode.value?.data?.business
  return business?.commonEconomicParams[field.key] ?? field.defaultValue
}

// 获取时层技术参数字段值
const getLayerTechFieldValue = (layerId: string, field: ConfigField): PrimitiveValue => {
  const layerConfig = selectedNode.value?.data?.business?.layerConfigs[layerId]
  return layerConfig?.techParams[field.key] ?? field.defaultValue
}

// 获取时层经济参数字段值
const getLayerEconomicFieldValue = (layerId: string, field: ConfigField): PrimitiveValue => {
  const layerConfig = selectedNode.value?.data?.business?.layerConfigs[layerId]
  return layerConfig?.economicParams[field.key] ?? field.defaultValue
}

// 获取时层状态
const getLayerStatus = (layerId: string): LayerStatus => {
  return selectedNode.value?.data?.business?.layerConfigs[layerId]?.status ?? 'stand_alone'
}

// 获取时层约束启用状态
const getLayerConstraintEnabled = (layerId: string, field: ConfigField): boolean => {
  const layerConfig = selectedNode.value?.data?.business?.layerConfigs[layerId]
  return layerConfig?.constraints[field.key]?.enabled ?? false
}

// 获取时层目标启用状态
const getLayerObjectiveEnabled = (layerId: string, field: ConfigField): boolean => {
  const layerConfig = selectedNode.value?.data?.business?.layerConfigs[layerId]
  return layerConfig?.objectives[field.key]?.enabled ?? false
}

watchEffect(() => {
  Object.entries(defaultSectionState).forEach(([key, isOpen]) => {
    if (!(key in expandedSections.value)) {
      expandedSections.value[key] = isOpen
    }
  })

  if (!tabs.value.some(tab => tab.key === activeTab.value)) {
    activeTab.value = tabs.value[0]?.key ?? 'page'
  }
})

const updateCanvas = (nextCanvas: CanvasData) => {
  emit('update:canvas', {
    ...nextCanvas,
    updatedAt: new Date().toISOString()
  })
}

const updatePageConfig = <K extends keyof CanvasData['pageConfig']>(key: K, value: CanvasData['pageConfig'][K]) => {
  updateCanvas({
    ...props.canvas,
    pageConfig: {
      ...props.canvas.pageConfig,
      [key]: value
    }
  })
}

const updateBackgroundPattern = (pattern: 'grid' | 'dots' | 'hidden') => {
  updateCanvas({
    ...props.canvas,
    pageConfig: {
      ...props.canvas.pageConfig,
      gridVisible: pattern !== 'hidden',
      backgroundPattern: pattern
    }
  })
}

const updateSelectedNode = (mutator: (node: FlowNode) => FlowNode) => {
  if (!selectedNode.value && !multipleNodesSelected.value) {
    return
  }

  const selectedIds = new Set(props.selection.nodeIds)

  updateCanvas({
    ...props.canvas,
    nodes: props.canvas.nodes.map(node => (selectedIds.has(node.id) ? mutator(node) : node))
  })
}

const updateSelectedEdge = (mutator: (edge: FlowEdge) => FlowEdge) => {
  if (!selectedEdge.value) {
    return
  }

  const selectedEdgeIds = new Set(props.selection.edgeIds)
  updateCanvas({
    ...props.canvas,
    edges: props.canvas.edges.map(edge => (selectedEdgeIds.has(edge.id) ? mutator(edge) : edge))
  })
}

const updateNodeStyleField = (key: keyof CanvasNodeData['style'], value: string | number) => {
  updateSelectedNode(node =>
    updateNodeFromFields(node, {
      [key]: value
    })
  )
}

const updateNodePositionField = (key: 'x' | 'y', value: number) => {
  updateSelectedNode(node => ({
    ...node,
    position: {
      ...node.position,
      [key]: value
    }
  }))
}

const updateNodeLabel = (label: string) => {
  updateSelectedNode(node => updateNodeFromFields(node, {}, label))
}

const updateCommonTechField = (key: string, value: string | number | boolean) => {
  updateSelectedNode(node => ({
    ...node,
    data: {
      ...node.data!,
      business: {
        ...node.data!.business,
        commonTechParams: {
          ...node.data!.business.commonTechParams,
          [key]: value
        }
      }
    }
  }))
}

const updateCommonEconomicField = (key: string, value: string | number | boolean) => {
  updateSelectedNode(node => ({
    ...node,
    data: {
      ...node.data!,
      business: {
        ...node.data!.business,
        commonEconomicParams: {
          ...node.data!.business.commonEconomicParams,
          [key]: value
        }
      }
    }
  }))
}

const updateBoundaryId = (boundaryId: string, checked: boolean) => {
  updateSelectedNode(node => {
    const currentIds = node.data?.business?.boundaryIds || []
    const newIds = checked
      ? [...currentIds, boundaryId]
      : currentIds.filter(id => id !== boundaryId)
    return {
      ...node,
      data: {
        ...node.data!,
        business: {
          ...node.data!.business,
          boundaryIds: newIds
        }
      }
    }
  })
}

const updateLayerTechField = (layerId: string, key: string, value: string | number | boolean) => {
  updateSelectedNode(node => {
    const existing = node.data!.business.layerConfigs[layerId]
    const updated: typeof existing = existing ? {
      ...existing,
      techParams: {
        ...existing.techParams,
        [key]: value
      }
    } : {
      layerId,
      status: 'stand_alone',
      techParams: { [key]: value },
      economicParams: {},
      constraints: {},
      objectives: {}
    }
    return {
      ...node,
      data: {
        ...node.data!,
        business: {
          ...node.data!.business,
          layerConfigs: {
            ...node.data!.business.layerConfigs,
            [layerId]: updated
          }
        }
      }
    }
  })
}

const updateLayerEconomicField = (layerId: string, key: string, value: string | number | boolean) => {
  updateSelectedNode(node => {
    const existing = node.data!.business.layerConfigs[layerId]
    const updated: LayerConfig = existing ? {
      ...existing,
      economicParams: {
        ...existing.economicParams,
        [key]: value
      }
    } : {
      layerId,
      status: 'stand_alone',
      techParams: {},
      economicParams: { [key]: value },
      constraints: {},
      objectives: {}
    }
    return {
      ...node,
      data: {
        ...node.data!,
        business: {
          ...node.data!.business,
          layerConfigs: {
            ...node.data!.business.layerConfigs,
            [layerId]: updated
          }
        }
      }
    }
  })
}

const updateLayerStatus = (layerId: string, status: LayerStatus) => {
  updateSelectedNode(node => {
    const existing = node.data!.business.layerConfigs[layerId]
    const updated: LayerConfig = existing ? { ...existing, status } : {
      layerId,
      status,
      techParams: {},
      economicParams: {},
      constraints: {},
      objectives: {}
    }
    return {
      ...node,
      data: {
        ...node.data!,
        business: {
          ...node.data!.business,
          layerConfigs: {
            ...node.data!.business.layerConfigs,
            [layerId]: updated
          }
        }
      }
    }
  })
}

const updateLayerConstraint = (layerId: string, key: string, enabled: boolean) => {
  updateSelectedNode(node => {
    const existing = node.data!.business.layerConfigs[layerId]
    const updated: LayerConfig = existing ? {
      ...existing,
      constraints: { ...existing.constraints, [key]: { enabled } }
    } : {
      layerId,
      status: 'stand_alone',
      techParams: {},
      economicParams: {},
      constraints: { [key]: { enabled } },
      objectives: {}
    }
    return {
      ...node,
      data: {
        ...node.data!,
        business: {
          ...node.data!.business,
          layerConfigs: {
            ...node.data!.business.layerConfigs,
            [layerId]: updated
          }
        }
      }
    }
  })
}

const updateLayerObjective = (layerId: string, key: string, enabled: boolean) => {
  updateSelectedNode(node => {
    const existing = node.data!.business.layerConfigs[layerId]
    const updated: LayerConfig = existing ? {
      ...existing,
      objectives: { ...existing.objectives, [key]: { enabled } }
    } : {
      layerId,
      status: 'stand_alone',
      techParams: {},
      economicParams: {},
      constraints: {},
      objectives: { [key]: { enabled } }
    }
    return {
      ...node,
      data: {
        ...node.data!,
        business: {
          ...node.data!.business,
          layerConfigs: {
            ...node.data!.business.layerConfigs,
            [layerId]: updated
          }
        }
      }
    }
  })
}

const updateEdgeLabel = (label: string) => {
  updateSelectedEdge(edge => ({
    ...edge,
    data: {
      ...edge.data!,
      label
    }
  }))
}

const updateEdgeStyleField = (key: keyof CanvasEdgeData['style'], value: string | number) => {
  updateSelectedEdge(edge => {
    const edgeData = edge.data!
    const updatedStyle = { ...edgeData.style, [key]: value }
    return {
      ...edge,
      data: {
        ...edgeData,
        style: updatedStyle
      }
    } as FlowEdge
  })
}

const updateEdgeArrowType = (arrowType: 'none' | 'start' | 'end' | 'both') => {
  updateSelectedEdge(edge => ({
    ...edge,
    markerStart: arrowType === 'start' || arrowType === 'both' ? MarkerType.ArrowClosed : undefined,
    markerEnd: arrowType === 'end' || arrowType === 'both' ? MarkerType.ArrowClosed : undefined,
    data: {
      ...edge.data!,
      style: {
        ...edge.data!.style,
        arrowType
      }
    }
  }))
}

const updateDeviceCount = (value: number) => {
  updateSelectedNode(node => ({
    ...node,
    data: {
      ...node.data!,
      business: {
        ...node.data!.business,
        deviceCount: value
      }
    }
  }))
}

// 端口配置相关
const getPortConfig = (portId: string): NodePortConfig[string] | undefined => {
  return selectedNode.value?.data?.portConfig?.[portId]
}

const updatePortConfig = (portId: string, config: Partial<NodePortConfig[string]>) => {
  updateSelectedNode(node => ({
    ...node,
    data: {
      ...node.data!,
      portConfig: {
        ...node.data!.portConfig,
        [portId]: {
          ...node.data!.portConfig?.[portId],
          ...config
        }
      }
    }
  }))
}

const getPortLabel = (portId: string, defaultLabel?: string): string => {
  return getPortConfig(portId)?.label ?? defaultLabel ?? ''
}

const getPortOffset = (portId: string, defaultOffset?: number): number => {
  return getPortConfig(portId)?.offset ?? defaultOffset ?? 50
}

// 时层状态选项
const layerStatusOptions = [
  { label: '独立运行', value: 'stand_alone' as LayerStatus },
  { label: '禁用', value: 'disabled' as LayerStatus },
  { label: '固定状态', value: 'fixed_state' as LayerStatus },
  { label: '调节计划', value: 'adjust_power' as LayerStatus },
  { label: '完全跟随计划', value: 'full_follow' as LayerStatus }
]

</script>

<template>
  <aside
    class="flex h-full overflow-hidden rounded-[12px] bg-app-panel-soft shadow-sm"
    :class="collapsed ? 'w-[54px]' : 'w-[320px]'"
  >
    <div v-if="collapsed" class="flex w-full flex-col items-center px-2 py-3">
      <button
        type="button"
        class="inline-flex h-9 w-9 items-center justify-center rounded-[10px] text-app-muted transition hover:bg-white hover:text-primary"
        title="展开参数面板"
        @click="$emit('toggleCollapse')"
      >
        <svg class="h-4 w-4" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M10 3L5 8L10 13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
        </svg>
      </button>
    </div>

    <div v-else class="flex min-w-0 flex-1 flex-col bg-app-panel-soft">
      <div class="flex items-center justify-between px-3">
        <div class="flex min-w-0 items-center gap-6 overflow-x-auto">
          <button
            v-for="tab in tabs"
            :key="tab.key"
            type="button"
            class="editor-tab shrink-0"
            :class="activeTab === tab.key ? 'editor-tab-active' : 'hover:text-primary'"
            @click="activeTab = tab.key"
          >
            {{ tab.label }}
            <span v-if="activeTab === tab.key" class="editor-tab-underline" />
          </button>
        </div>

        <button
          type="button"
          class="inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-[10px] text-app-muted transition hover:bg-white hover:text-primary"
          title="收起参数面板"
          @click="$emit('toggleCollapse')"
        >
          <svg class="h-4 w-4" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M6 3L11 8L6 13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
          </svg>
        </button>
      </div>

      <div class="min-h-0 flex-1 overflow-y-auto px-3 py-3">
        <template v-if="activeTab === 'page'">
          <section class="property-section">
            <button type="button" class="property-section-toggle" @click="toggleSection('page-background')">
              <svg class="property-section-arrow" :class="sectionOpen('page-background') ? 'rotate-90' : ''" viewBox="0 0 16 16" fill="none">
                <path d="M6 3L11 8L6 13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
              <span>背景</span>
            </button>

            <div v-if="sectionOpen('page-background')" class="space-y-2">
              <div class="property-row">
                <label class="property-label">背景颜色</label>
                <PropertyColor
                  :model-value="canvas.pageConfig.backgroundColor"
                  @update:model-value="updatePageConfig('backgroundColor', $event)"
                />
              </div>
            </div>
          </section>

          <section class="property-section">
            <button type="button" class="property-section-toggle" @click="toggleSection('page-size')">
              <svg class="property-section-arrow" :class="sectionOpen('page-size') ? 'rotate-90' : ''" viewBox="0 0 16 16" fill="none">
                <path d="M6 3L11 8L6 13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
              <span>画布大小</span>
            </button>

            <div v-if="sectionOpen('page-size')" class="space-y-2">
              <div class="property-row">
                <label class="property-label">宽度</label>
                <PropertyNumber
                  :model-value="canvas.pageConfig.width"
                  unit="px"
                  :step="sizeStep"
                  @update:model-value="updatePageConfig('width', $event)"
                />
              </div>

              <div class="property-row">
                <label class="property-label">高度</label>
                <PropertyNumber
                  :model-value="canvas.pageConfig.height"
                  unit="px"
                  :step="sizeStep"
                  @update:model-value="updatePageConfig('height', $event)"
                />
              </div>
            </div>
          </section>

          <section class="property-section">
            <button type="button" class="property-section-toggle" @click="toggleSection('page-grid')">
              <svg class="property-section-arrow" :class="sectionOpen('page-grid') ? 'rotate-90' : ''" viewBox="0 0 16 16" fill="none">
                <path d="M6 3L11 8L6 13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
              <span>网格</span>
            </button>

            <div v-if="sectionOpen('page-grid')" class="space-y-2">
              
              <div class="property-row">
                <label class="property-label">网格大小</label>
                <PropertySelect
                  :model-value="canvas.pageConfig.gridSize"
                  :options="[
                    { label: '小', value: 10 },
                    { label: '正常', value: 15 },
                    { label: '大', value: 20 },
                    { label: '很大', value: 30 }
                  ]"
                  @update:model-value="updatePageConfig('gridSize', $event as number)"
                />
              </div>

              <div class="property-row">
                <label class="property-label">网格类型</label>
                <PropertySelect
                  :model-value="canvas.pageConfig.backgroundPattern"
                  :options="[
                    { label: '网状', value: 'grid' },
                    { label: '点状', value: 'dots' },
                    { label: '隐藏', value: 'hidden' }
                  ]"
                  @update:model-value="updateBackgroundPattern($event as 'grid' | 'dots' | 'hidden')"
                />
              </div>

              <div class="property-row">
                <label class="property-label">吸附网格</label>
                <PropertySwitch
                  :model-value="canvas.pageConfig.snapToGrid"
                  @update:model-value="updatePageConfig('snapToGrid', $event)"
                />
              </div>
            </div>
          </section>

          <section class="property-section">
            <button type="button" class="property-section-toggle" @click="toggleSection('page-labels')">
              <svg class="property-section-arrow" :class="sectionOpen('page-labels') ? 'rotate-90' : ''" viewBox="0 0 16 16" fill="none">
                <path d="M6 3L11 8L6 13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
              <span>显示标签</span>
            </button>

            <div v-if="sectionOpen('page-labels')" class="space-y-2">
              <div class="property-row">
                <label class="property-label">元件标签</label>
                <PropertySelect
                  :model-value="canvas.pageConfig.labelLanguage"
                  :options="[
                    { label: '中文', value: 'chinese' },
                    { label: '英文', value: 'english' },
                    { label: '隐藏', value: 'hidden' }
                  ]"
                  @update:model-value="updatePageConfig('labelLanguage', $event as 'chinese' | 'english' | 'hidden')"
                />
              </div>

              <div class="property-row">
                <label class="property-label">显示元件名称</label>
                <PropertySwitch
                  :model-value="canvas.pageConfig.showComponentName"
                  @update:model-value="updatePageConfig('showComponentName', $event)"
                />
              </div>

              <div class="property-row">
                <label class="property-label">显示参数标签</label>
                <PropertySwitch
                  :model-value="canvas.pageConfig.showParameterTag"
                  @update:model-value="updatePageConfig('showParameterTag', $event)"
                />
              </div>

              <div class="property-row">
                <label class="property-label">显示接口标签</label>
                <PropertySwitch
                  :model-value="canvas.pageConfig.showPorts"
                  @update:model-value="updatePageConfig('showPorts', $event)"
                />
              </div>
            </div>
          </section>
        </template>

        <template v-else-if="activeTab === 'style' && selectedNode">
          <section class="property-section">
            <button type="button" class="property-section-toggle" @click="toggleSection('node-size')">
              <svg class="property-section-arrow" :class="sectionOpen('node-size') ? 'rotate-90' : ''" viewBox="0 0 16 16" fill="none">
                <path d="M6 3L11 8L6 13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
              <span>大小</span>
            </button>

            <div v-if="sectionOpen('node-size')" class="space-y-2">
              <div class="property-row">
                <label class="property-label">宽度</label>
                <PropertyNumber
                  :model-value="selectedNode!.data!.style.width"
                  unit="px"
                  :step="10"
                  @update:model-value="updateNodeStyleField('width', $event)"
                />
              </div>

              <div class="property-row">
                <label class="property-label">高度</label>
                <PropertyNumber
                  :model-value="selectedNode.data.style.height"
                  unit="px"
                  :step="10"
                  @update:model-value="updateNodeStyleField('height', $event)"
                />
              </div>

              <div class="property-row">
                <label class="property-label">旋转</label>
                <PropertyNumber
                  :model-value="selectedNode.data.style.rotation"
                  unit="°"
                  :min="0"
                  :max="360"
                  :step="90"
                  @update:model-value="updateNodeStyleField('rotation', normalizeRotation($event))"
                />
              </div>
            </div>
          </section>

          <section class="property-section">
            <button type="button" class="property-section-toggle" @click="toggleSection('node-position')">
              <svg class="property-section-arrow" :class="sectionOpen('node-position') ? 'rotate-90' : ''" viewBox="0 0 16 16" fill="none">
                <path d="M6 3L11 8L6 13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
              <span>位置</span>
            </button>

            <div v-if="sectionOpen('node-position')" class="space-y-2">
              <div class="property-row">
                <label class="property-label">水平位置</label>
                <PropertyNumber
                  :model-value="Math.round(selectedNode.position.x)"
                  unit="px"
                  :step="10"
                  @update:model-value="updateNodePositionField('x', $event)"
                />
              </div>

              <div class="property-row">
                <label class="property-label">垂直位置</label>
                <PropertyNumber
                  :model-value="Math.round(selectedNode.position.y)"
                  unit="px"
                  :step="10"
                  @update:model-value="updateNodePositionField('y', $event)"
                />
              </div>
            </div>
          </section>

          <section class="property-section">
            <button type="button" class="property-section-toggle" @click="toggleSection('node-appearance')">
              <svg class="property-section-arrow" :class="sectionOpen('node-appearance') ? 'rotate-90' : ''" viewBox="0 0 16 16" fill="none">
                <path d="M6 3L11 8L6 13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
              <span>外观</span>
            </button>

            <div v-if="sectionOpen('node-appearance')" class="space-y-2">
              <div class="property-row">
                <label class="property-label">填充颜色</label>
                <PropertyColor
                  :model-value="selectedNode.data.style.fillColor"
                  @update:model-value="updateNodeStyleField('fillColor', $event)"
                />
              </div>

              <div class="property-row">
                <label class="property-label">描边颜色</label>
                <PropertyColor
                  :model-value="selectedNode.data.style.strokeColor"
                  @update:model-value="updateNodeStyleField('strokeColor', $event)"
                />
              </div>
            </div>
          </section>

          <section class="property-section">
            <button type="button" class="property-section-toggle" @click="toggleSection('node-text')">
              <svg class="property-section-arrow" :class="sectionOpen('node-text') ? 'rotate-90' : ''" viewBox="0 0 16 16" fill="none">
                <path d="M6 3L11 8L6 13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
              <span>文本</span>
            </button>

            <div v-if="sectionOpen('node-text')" class="space-y-2">
              <div class="text-xs font-medium text-app-muted mb-1">元件标签</div>
              <div class="property-row">
                <label class="property-label">字号</label>
                <PropertyNumber
                  :model-value="selectedNode.data.style.fontSize"
                  unit="px"
                  @update:model-value="updateNodeStyleField('fontSize', $event)"
                />
              </div>

              <div class="property-row">
                <label class="property-label">颜色</label>
                <PropertyColor
                  :model-value="selectedNode.data.style.textColor"
                  @update:model-value="updateNodeStyleField('textColor', $event)"
                />
              </div>

              <div class="text-xs font-medium text-app-muted mb-1 mt-3">元件名称</div>
              <div class="property-row">
                <label class="property-label">字号</label>
                <PropertyNumber
                  :model-value="selectedNode.data.style.nameFontSize ?? selectedNode.data.style.fontSize"
                  unit="px"
                  @update:model-value="updateNodeStyleField('nameFontSize', $event)"
                />
              </div>

              <div class="property-row">
                <label class="property-label">颜色</label>
                <PropertyColor
                  :model-value="selectedNode.data.style.nameTextColor ?? '#1D2939'"
                  @update:model-value="updateNodeStyleField('nameTextColor', $event)"
                />
              </div>

              <div class="text-xs font-medium text-app-muted mb-1 mt-3">参数标签</div>
              <div class="property-row">
                <label class="property-label">字号</label>
                <PropertyNumber
                  :model-value="selectedNode.data.style.paramFontSize ?? selectedNode.data.style.fontSize"
                  unit="px"
                  @update:model-value="updateNodeStyleField('paramFontSize', $event)"
                />
              </div>

              <div class="property-row">
                <label class="property-label">颜色</label>
                <PropertyColor
                  :model-value="selectedNode.data.style.paramTextColor ?? '#0a4da2'"
                  @update:model-value="updateNodeStyleField('paramTextColor', $event)"
                />
              </div>
            </div>
          </section>

          <section class="property-section">
            <button type="button" class="property-section-toggle" @click="toggleSection('node-ports')">
              <svg class="property-section-arrow" :class="sectionOpen('node-ports') ? 'rotate-90' : ''" viewBox="0 0 16 16" fill="none">
                <path d="M6 3L11 8L6 13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
              <span>端口配置</span>
            </button>

            <div v-if="sectionOpen('node-ports')" class="space-y-2">
              <template v-for="port in selectedDefinition?.ports ?? []" :key="port.id">
                <div class="text-xs font-medium text-app-muted mb-1 mt-3">
                  {{ port.label || port.id }} ({{ port.side }})
                </div>

                <div class="property-row">
                  <label class="property-label">标签</label>
                  <PropertyText
                    :model-value="getPortLabel(port.id, port.label)"
                    placeholder="请输入标签："
                    @update:model-value="updatePortConfig(port.id, { label: $event as string })"
                  />
                </div>

                <div class="property-row">
                  <label class="property-label">位置</label>
                  <PropertySlider
                    :model-value="getPortOffset(port.id, port.offset)"
                    :min="0"
                    :max="100"
                    unit="%"
                    @update:model-value="updatePortConfig(port.id, { offset: $event })"
                  />
                </div>

              </template>

              <div v-if="!selectedDefinition?.ports?.length" class="text-xs text-app-muted text-center py-2">
                该组件无固定端口
              </div>
            </div>
          </section>
        </template>
        <template v-else-if="activeTab === 'style' && selectedEdge">
          <section class="property-section">
            <button type="button" class="property-section-toggle" @click="toggleSection('edge-style')">
              <svg class="property-section-arrow" :class="sectionOpen('edge-style') ? 'rotate-90' : ''" viewBox="0 0 16 16" fill="none">
                <path d="M6 3L11 8L6 13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
              <span>连线</span>
            </button>

            <div v-if="sectionOpen('edge-style')" class="space-y-2">
              <div class="property-row">
                <label class="property-label">颜色</label>
                <PropertyColor
                  :model-value="selectedEdge.data.style.strokeColor"
                  @update:model-value="updateEdgeStyleField('strokeColor', $event)"
                />
              </div>

              <div class="property-row">
                <label class="property-label">宽度</label>
                <PropertyNumber
                  :model-value="selectedEdge.data.style.strokeWidth"
                  unit="px"
                  @update:model-value="updateEdgeStyleField('strokeWidth', $event)"
                />
              </div>

              <div class="property-row">
                <label class="property-label">线型</label>
                <PropertySelect
                  :model-value="selectedEdge.data.style.strokeDasharray"
                  :options="[
                    { label: '实线', value: '0' },
                    { label: '虚线', value: '6 4' }
                  ]"
                  @update:model-value="updateEdgeStyleField('strokeDasharray', $event)"
                />
              </div>

              <div class="property-row">
                <label class="property-label">箭头</label>
                <PropertySelect
                  :model-value="selectedEdge.data.style.arrowType"
                  :options="[
                    { label: '无箭头', value: 'none' },
                    { label: '左箭头', value: 'end' },
                    { label: '右箭头', value: 'start' },
                    { label: '双箭头', value: 'both' }
                  ]"
                  @update:model-value="updateEdgeArrowType($event as 'none' | 'start' | 'end' | 'both')"
                />
              </div>
            </div>
          </section>
        </template>

        <template v-else-if="activeTab === 'params' && selectedNode && selectedDefinition">
          <!-- 基础信息 -->
          <section class="property-section">
            <button type="button" class="property-section-toggle" @click="toggleSection('model-basic')">
              <svg class="property-section-arrow" :class="sectionOpen('model-basic') ? 'rotate-90' : ''" viewBox="0 0 16 16" fill="none">
                <path d="M6 3L11 8L6 13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
              <span>基础信息</span>
            </button>

            <div v-if="sectionOpen('model-basic')" class="space-y-2">
              <div class="property-row">
                <label class="property-label">组件名称</label>
                <PropertyText
                  :model-value="selectedNode.data.label"
                  @update:model-value="updateNodeLabel($event as string)"
                />
              </div>

              <div class="property-row">
                <label class="property-label">设备台数</label>
                <PropertyNumber
                  :model-value="selectedNode.data.business.deviceCount"
                  @update:model-value="updateDeviceCount($event)"
                />
              </div>
            </div>
          </section>

          <!-- 通用技术参数 -->
          <section v-if="selectedDefinition.commonTechParamFields.length > 0" class="property-section">
            <button type="button" class="property-section-toggle" @click="toggleSection('model-common-tech')">
              <svg class="property-section-arrow" :class="sectionOpen('model-common-tech') ? 'rotate-90' : ''" viewBox="0 0 16 16" fill="none">
                <path d="M6 3L11 8L6 13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
              <span>技术参数</span>
            </button>

            <div v-if="sectionOpen('model-common-tech')" class="space-y-2">
              <div v-for="field in selectedDefinition.commonTechParamFields" :key="field.key" class="property-row items-start">
                <label class="property-label pt-1.5">{{ field.label }}</label>
                <div class="min-w-0">
                  <PropertyNumber
                    v-if="field.type === 'number'"
                    :model-value="getCommonTechFieldValue(field) as number"
                    :unit="field.unit"
                    :min="field.min"
                    :max="field.max"
                    :step="field.step ?? 1"
                    @update:model-value="updateCommonTechField(field.key, $event)"
                  />
                  <PropertyText
                    v-else-if="field.type === 'text'"
                    :model-value="getCommonTechFieldValue(field) as string"
                    :placeholder="field.placeholder"
                    @update:model-value="updateCommonTechField(field.key, $event)"
                  />
                  <PropertySelect
                    v-else-if="field.type === 'select'"
                    :model-value="getCommonTechFieldValue(field) as string | number"
                    :options="(field.options ?? []) as any"
                    @update:model-value="updateCommonTechField(field.key, $event)"
                  />
                  <PropertySwitch
                    v-else-if="field.type === 'boolean'"
                    :model-value="Boolean(getCommonTechFieldValue(field))"
                    @update:model-value="updateCommonTechField(field.key, $event)"
                  />
                </div>
              </div>
            </div>
          </section>

          <!-- 边界类参数 -->
          <section v-if="selectedNodeHasBoundary" class="property-section">
            <button type="button" class="property-section-toggle" @click="toggleSection('model-boundary')">
              <svg class="property-section-arrow" :class="sectionOpen('model-boundary') ? 'rotate-90' : ''" viewBox="0 0 16 16" fill="none">
                <path d="M6 3L11 8L6 13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
              <span>边界配置</span>
            </button>

            <div v-if="sectionOpen('model-boundary')" class="space-y-2">
              <div class="property-row items-start">
                <label class="property-label pt-1.5">边界</label>
                <div class="min-w-0 flex-1">
                  <PropertyMultiSelect
                    v-model="selectedNodeBoundaryIds"
                    :options="availableBoundariesForNode.map(b => ({ label: b.name, value: b.id }))"
                    placeholder="请选择边界..."
                  />
                  <p v-if="selectedNodeHasBoundary && selectedNodeBoundaryIds.length === 0" class="mt-1 text-xs text-red-500">
                    请配置边界
                  </p>
                </div>
              </div>
            </div>
          </section>

          <!-- 通用经济参数 -->
          <section v-if="selectedDefinition.commonEconomicParamFields.length > 0" class="property-section">
            <button type="button" class="property-section-toggle" @click="toggleSection('model-common-economic')">
              <svg class="property-section-arrow" :class="sectionOpen('model-common-economic') ? 'rotate-90' : ''" viewBox="0 0 16 16" fill="none">
                <path d="M6 3L11 8L6 13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
              <span>经济参数</span>
            </button>

            <div v-if="sectionOpen('model-common-economic')" class="space-y-2">
              <div v-for="field in selectedDefinition.commonEconomicParamFields" :key="field.key" class="property-row items-start">
                <label class="property-label pt-1.5">{{ field.label }}</label>
                <div class="min-w-0">
                  <PropertyNumber
                    v-if="field.type === 'number'"
                    :model-value="getCommonEconomicFieldValue(field) as number"
                    :unit="field.unit"
                    :min="field.min"
                    :max="field.max"
                    :step="field.step ?? 1"
                    @update:model-value="updateCommonEconomicField(field.key, $event)"
                  />
                  <PropertyText
                    v-else-if="field.type === 'text'"
                    :model-value="getCommonEconomicFieldValue(field) as string"
                    :placeholder="field.placeholder"
                    @update:model-value="updateCommonEconomicField(field.key, $event)"
                  />
                  <PropertySelect
                    v-else-if="field.type === 'select'"
                    :model-value="getCommonEconomicFieldValue(field) as string | number"
                    :options="(field.options ?? []) as any"
                    @update:model-value="updateCommonEconomicField(field.key, $event)"
                  />
                  <PropertySwitch
                    v-else-if="field.type === 'boolean'"
                    :model-value="Boolean(getCommonEconomicFieldValue(field))"
                    @update:model-value="updateCommonEconomicField(field.key, $event)"
                  />
                </div>
              </div>
            </div>
          </section>
        </template>

        <template v-else-if="activeTab === 'model' && selectedNode && selectedDefinition">
          <!-- 时层翻页器 -->
          <div class="flex items-center justify-between px-2 py-2 mb-3 bg-app-panel rounded-[10px]">
            <button
              type="button"
              class="inline-flex h-7 w-7 items-center justify-center rounded-[6px] text-app-muted transition hover:bg-white hover:text-primary disabled:opacity-30 disabled:cursor-not-allowed"
              :disabled="!canGoPrevLayer"
              @click="goToPrevLayer"
            >
              <svg class="h-3.5 w-3.5" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M10 3L5 8L10 13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
            </button>
            <span class="text-sm font-medium text-app-text">时层 {{ currentLayerId }}：{{ currentLayerName }}</span>
            <button
              type="button"
              class="inline-flex h-7 w-7 items-center justify-center rounded-[6px] text-app-muted transition hover:bg-white hover:text-primary disabled:opacity-30 disabled:cursor-not-allowed"
              :disabled="!canGoNextLayer"
              @click="goToNextLayer"
            >
              <svg class="h-3.5 w-3.5" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M6 3L11 8L6 13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
            </button>
          </div>

          <!-- 时层配置（当前选中时层） -->
          <section class="property-section">
            <button type="button" class="property-section-toggle" @click="toggleSection('model-layer-status')">
              <svg class="property-section-arrow" :class="sectionOpen('model-layer-status') ? 'rotate-90' : ''" viewBox="0 0 16 16" fill="none">
                <path d="M6 3L11 8L6 13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
              <span>运行状态</span>
            </button>

            <div v-if="sectionOpen('model-layer-status')" class="space-y-2">
              <div class="property-row">
                <label class="property-label">运行状态</label>
                <PropertySelect
                  :model-value="getLayerStatus(currentLayerId)"
                  :options="layerStatusOptions"
                  @update:model-value="updateLayerStatus(currentLayerId, $event as LayerStatus)"
                />
              </div>
            </div>
          </section>

          <section class="property-section">
            <button type="button" class="property-section-toggle" @click="toggleSection('model-layer-tech')">
              <svg class="property-section-arrow" :class="sectionOpen('model-layer-tech') ? 'rotate-90' : ''" viewBox="0 0 16 16" fill="none">
                <path d="M6 3L11 8L6 13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
              <span>技术参数</span>
            </button>

            <div v-if="sectionOpen('model-layer-tech')" class="space-y-2">
              <template v-if="selectedDefinition.layerTechParamFields.length > 0">
                <div v-for="field in selectedDefinition.layerTechParamFields" :key="field.key" class="property-row items-start">
                  <label class="property-label pt-1.5">{{ field.label }}</label>
                  <div class="min-w-0">
                    <PropertyNumber
                      v-if="field.type === 'number'"
                      :model-value="getLayerTechFieldValue(currentLayerId, field) as number"
                      :unit="field.unit"
                      :min="field.min"
                      :max="field.max"
                      :step="field.step ?? 1"
                      @update:model-value="updateLayerTechField(currentLayerId, field.key, $event)"
                    />
                    <PropertyText
                      v-else-if="field.type === 'text'"
                      :model-value="getLayerTechFieldValue(currentLayerId, field) as string"
                      :placeholder="field.placeholder"
                      @update:model-value="updateLayerTechField(currentLayerId, field.key, $event)"
                    />
                    <PropertySelect
                      v-else-if="field.type === 'select'"
                      :model-value="getLayerTechFieldValue(currentLayerId, field) as string | number"
                      :options="(field.options ?? []) as any"
                      @update:model-value="updateLayerTechField(currentLayerId, field.key, $event)"
                    />
                    <PropertySwitch
                      v-else-if="field.type === 'boolean'"
                      :model-value="Boolean(getLayerTechFieldValue(currentLayerId, field))"
                      @update:model-value="updateLayerTechField(currentLayerId, field.key, $event)"
                    />
                  </div>
                </div>
              </template>
              <div v-else class="text-xs text-app-muted text-center py-2">该组件无时层技术参数</div>
            </div>
          </section>

          <section class="property-section">
            <button type="button" class="property-section-toggle" @click="toggleSection('model-layer-economic')">
              <svg class="property-section-arrow" :class="sectionOpen('model-layer-economic') ? 'rotate-90' : ''" viewBox="0 0 16 16" fill="none">
                <path d="M6 3L11 8L6 13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
              <span>经济参数</span>
            </button>

            <div v-if="sectionOpen('model-layer-economic')" class="space-y-2">
              <template v-if="selectedDefinition.layerEconomicParamFields.length > 0">
                <div v-for="field in selectedDefinition.layerEconomicParamFields" :key="field.key" class="property-row items-start">
                  <label class="property-label pt-1.5">{{ field.label }}</label>
                  <div class="min-w-0">
                    <PropertyNumber
                      v-if="field.type === 'number'"
                      :model-value="getLayerEconomicFieldValue(currentLayerId, field) as number"
                      :unit="field.unit"
                      :min="field.min"
                      :max="field.max"
                      :step="field.step ?? 1"
                      @update:model-value="updateLayerEconomicField(currentLayerId, field.key, $event)"
                    />
                    <PropertyText
                      v-else-if="field.type === 'text'"
                      :model-value="getLayerEconomicFieldValue(currentLayerId, field) as string"
                      :placeholder="field.placeholder"
                      @update:model-value="updateLayerEconomicField(currentLayerId, field.key, $event)"
                    />
                    <PropertySelect
                      v-else-if="field.type === 'select'"
                      :model-value="getLayerEconomicFieldValue(currentLayerId, field) as string | number"
                      :options="(field.options ?? []) as any"
                      @update:model-value="updateLayerEconomicField(currentLayerId, field.key, $event)"
                    />
                    <PropertySwitch
                      v-else-if="field.type === 'boolean'"
                      :model-value="Boolean(getLayerEconomicFieldValue(currentLayerId, field))"
                      @update:model-value="updateLayerEconomicField(currentLayerId, field.key, $event)"
                    />
                  </div>
                </div>
              </template>
              <div v-else class="text-xs text-app-muted text-center py-2">该组件无时层经济参数</div>
            </div>
          </section>

          <section class="property-section">
            <button type="button" class="property-section-toggle" @click="toggleSection('model-layer-constraint')">
              <svg class="property-section-arrow" :class="sectionOpen('model-layer-constraint') ? 'rotate-90' : ''" viewBox="0 0 16 16" fill="none">
                <path d="M6 3L11 8L6 13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
              <span>约束条件</span>
            </button>

            <div v-if="sectionOpen('model-layer-constraint')" class="space-y-2">
              <template v-if="selectedDefinition.layerConstraintFields.length > 0">
                <div v-for="field in selectedDefinition.layerConstraintFields" :key="field.key" class="property-row">
                  <label class="property-label">{{ field.label }}</label>
                  <PropertySwitch
                    :model-value="getLayerConstraintEnabled(currentLayerId, field)"
                    @update:model-value="updateLayerConstraint(currentLayerId, field.key, $event)"
                  />
                </div>
              </template>
              <div v-else class="text-xs text-app-muted text-center py-2">该组件无约束条件</div>
            </div>
          </section>

          <section class="property-section">
            <button type="button" class="property-section-toggle" @click="toggleSection('model-layer-objective')">
              <svg class="property-section-arrow" :class="sectionOpen('model-layer-objective') ? 'rotate-90' : ''" viewBox="0 0 16 16" fill="none">
                <path d="M6 3L11 8L6 13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
              <span>目标函数</span>
            </button>

            <div v-if="sectionOpen('model-layer-objective')" class="space-y-2">
              <template v-if="selectedDefinition.layerObjectiveFields.length > 0">
                <div v-for="field in selectedDefinition.layerObjectiveFields" :key="field.key" class="property-row">
                  <label class="property-label">{{ field.label }}</label>
                  <PropertySwitch
                    :model-value="getLayerObjectiveEnabled(currentLayerId, field)"
                    @update:model-value="updateLayerObjective(currentLayerId, field.key, $event)"
                  />
                </div>
              </template>
              <div v-else class="text-xs text-app-muted text-center py-2">该组件无目标函数</div>
            </div>
          </section>
        </template>
      </div>
    </div>
  </aside>
</template>

<style scoped>
.property-section + .property-section {
  margin-top: 14px;
}

.property-section-toggle {
  display: flex;
  width: 30%;
  align-items: center;
  gap: 8px;
  padding: 4px 0;
  text-align: left;
  font-size: 14px;
  font-weight: 600;
  color: #1d2129;
}

.property-section-arrow {
  height: 16px;
  width: 16px;
  flex-shrink: 0;
  color: #86909c;
  transition: transform 0.2s ease;
}

.property-row {
  display: grid;
  grid-template-columns: 84px minmax(0, 1fr);
  align-items: center;
  padding-inline: 20px;
}

.property-label {
  font-size: 14px;
  font-weight: 500;
  color: #1d2129;
}

.property-inline {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 8px;
}

.property-field {
  height: 32px;
  width: 100%;
  border: 1px solid #dde1e6;
  border-radius: 6px;
  background: #ffffff;
  padding: 0 12px;
  font-size: 14px;
  color: #1d2129;
  transition: border-color 0.2s ease;
}

.property-textarea {
  min-height: 72px;
  width: 100%;
  border: 1px solid #dde1e6;
  border-radius: 6px;
  background: #ffffff;
  padding: 8px 12px;
  font-size: 14px;
  color: #1d2129;
  transition: border-color 0.2s ease;
}

.property-check {
  display: flex;
  height: 32px;
  align-items: center;
  gap: 8px;
  font-size: 14px;
  color: #1d2129;
  padding-left: 20px;
}

.property-field:focus,
.property-textarea:focus {
  outline: none;
  border-color: #0a4da2;
}
</style>
