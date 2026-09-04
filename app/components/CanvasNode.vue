<script setup lang="ts">
import type { NodeProps } from '@vue-flow/core'
import { Handle, Position } from '@vue-flow/core'
import { computed, inject, ref,type ComputedRef } from 'vue'

import { componentDefinitionMap, componentDefinitions } from '~~/config/component-meta'
import type { ComponentDefinition, PortDefinition } from '~~/types/component'
import type { CanvasNodeData, PageConfig } from '~~/types/canvas'
import { getNodePorts, getPortPositionOffset, getRotatedPortSide } from '~~/utils/canvas'

const props = defineProps<NodeProps<CanvasNodeData>>()

const pageConfig = inject<ComputedRef<PageConfig>>('pageConfig')
const isHovered = ref(false)

const showPorts = computed(() => {
  if (pageConfig?.value?.showPorts) {
    return true
  }

  return props.selected || isHovered.value
})

const definition = computed<ComponentDefinition>(() => (
  componentDefinitionMap[props.data.componentKey] ?? componentDefinitionMap.rect!
))

const parameterTag = computed(() => {
  const capacity = props.data.business?.commonTechParams?.capacity
  return capacity ? `${capacity}kW` : ''
})

const fullIconMode = computed(() => {
  const labelHidden = pageConfig?.value?.labelLanguage === 'hidden'
  const componentNameHidden = !pageConfig?.value?.showComponentName
  const parameterTagHidden = !pageConfig?.value?.showParameterTag

  return labelHidden && componentNameHidden && parameterTagHidden
})

const isBusNode = computed(() => definition.value?.category === 'bus')
const ports = computed<PortDefinition[]>(() => getNodePorts(props.data))
const mergedPorts = ports

const handleTypeMap = computed(() => ({
  in: 'target' as const,
  out: 'source' as const
}))

const handlePositionMap: Record<PortDefinition['side'], Position> = {
  top: Position.Top,
  right: Position.Right,
  bottom: Position.Bottom,
  left: Position.Left
}

const nodeWidth = computed(() => props.data.style.width)
const nodeHeight = computed(() => props.data.style.height)

const getRotatedPort = (port: PortDefinition) => ({
  ...port,
  side: getRotatedPortSide(port.side, props.data.style.rotation || 0)
})

const getHandleOffsetStyle = (port: PortDefinition): Record<string, string> => {
  const rotatedSide = getRotatedPort(port).side
  const { x, y } = getPortPositionOffset(
    rotatedSide,
    port.offset ?? 50,
    nodeWidth.value,
    nodeHeight.value
  )

  switch (rotatedSide) {
    case 'top':
    case 'bottom':
      return { marginLeft: `${x}px !important` }
    case 'left':
    case 'right':
      return { marginTop: `${y}px !important` }
    default:
      return {}
  }
}

const getHandleStyle = (port: PortDefinition): Record<string, string> => ({
  ...getHandleOffsetStyle(port),
  ...(showPorts.value ? {} : {
    opacity: '0',
    pointerEvents: 'none'
  })
})

const getPortLabelClass = (port: PortDefinition) => {
  const rotatedSide = getRotatedPort(port).side
  const baseClass = 'absolute pointer-events-none text-[10px] text-primary/70 whitespace-nowrap transition-opacity z-99'

  switch (rotatedSide) {
    case 'top':
      return `${baseClass} top-[-20px] left-3/5`
    case 'bottom':
      return `${baseClass} bottom-[-20px] left-3/5`
    case 'left':
      return `${baseClass} top-2/5 -translate-y-1/2 right-full mr-2`
    case 'right':
      return `${baseClass} top-2/5 -translate-y-1/2 left-full ml-2`
  }

  return baseClass
}

const getLabelOffsetStyle = (port: PortDefinition): Record<string, string> => {
  const rotatedSide = getRotatedPort(port).side
  const { x, y } = getPortPositionOffset(
    rotatedSide,
    port.offset ?? 50,
    nodeWidth.value,
    nodeHeight.value
  )

  switch (rotatedSide) {
    case 'top':
    case 'bottom':
      return { marginLeft: `${x}px` }
    case 'left':
    case 'right':
      return { marginTop: `${y}px` }
    default:
      return {}
  }
}

const wrapperStyle = computed(() => {
  const style = props.data.style

  return {
    width: `${style.width}px`,
    height: `${style.height}px`,
    background: style.fillColor,
    border: `${style.strokeWidth}px solid ${style.strokeColor}`,
    borderRadius: `${style.borderRadius}px`,
    color: style.textColor,
    fontSize: `${style.fontSize}px`,
    opacity: `${style.opacity}`
  }
})
</script>

<template>
  <div
    class="group relative cursor-grab"
    :style="{
      width: `${data.style.width}px`,
      height: `${data.style.height}px`
    }"
    @mouseenter="isHovered = true"
    @mouseleave="isHovered = false"
  >
    <template v-if="mergedPorts.length > 0">
      <template v-for="port in mergedPorts" :key="port.id">
        <template v-if="isBusNode">
          <Handle
            :id="port.id"
            type="source"
            :position="handlePositionMap[getRotatedPort(port).side]"
            :connectable="connectable"
            class="canvas-node-handle"
            :style="getHandleStyle(port)"
            :data-port-id="port.id"
            :data-side-original="port.side"
            :data-side-rotated="getRotatedPort(port).side"
            :data-offset="port.offset"
            :data-rotation="data.style.rotation || 0"
            :data-node-rotation="data.style.rotation || 0"
          />
          <Handle
            :id="port.id"
            type="target"
            :position="handlePositionMap[getRotatedPort(port).side]"
            :connectable="connectable"
            class="canvas-node-handle"
            :style="getHandleStyle(port)"
            :data-port-id="port.id"
            :data-side-original="port.side"
            :data-side-rotated="getRotatedPort(port).side"
            :data-offset="port.offset"
            :data-rotation="data.style.rotation || 0"
            :data-node-rotation="data.style.rotation || 0"
          />
        </template>

        <template v-else>
          <Handle
            :id="port.id"
            :type="handleTypeMap[port.direction]"
            :position="handlePositionMap[getRotatedPort(port).side]"
            :connectable="connectable"
            class="canvas-node-handle"
            :style="getHandleStyle(port)"
            :data-port-id="port.id"
            :data-side-original="port.side"
            :data-side-rotated="getRotatedPort(port).side"
            :data-offset="port.offset"
            :data-rotation="data.style.rotation || 0"
            :data-node-rotation="data.style.rotation || 0"
          />
        </template>

        <div
          v-show="showPorts"
          :class="getPortLabelClass(port)"
          :style="getLabelOffsetStyle(port)"
        >
          {{ port.label }}
        </div>
      </template>
    </template>

    <div
      class="absolute inset-0 flex items-center justify-center overflow-hidden"
      :style="{
        ...wrapperStyle,
        transform: `scaleX(${data.style.flipX ? -1 : 1}) scaleY(${data.style.flipY ? -1 : 1})`,
        ...(selected ? { filter: 'drop-shadow(0 0 8px rgba(0, 26, 255, 0.5))' } : {})
      }"
    >
      <div
        v-if="definition.canvasType === 'energy'"
        class="flex h-full w-full flex-col items-center justify-center gap-1 px-3 py-2 text-center"
      >
        <span
          :class="fullIconMode ? 'h-full w-full' : 'h-1/2 w-1/2'"
          class="inline-flex items-center justify-center rounded-xl bg-white/90 text-app-text shadow-sm"
        >
          <AppIcon :name="definition.icon" :size="fullIconMode ? 72 : 36" :fallback-text="definition.label.slice(0, 1)" />
        </span>
        <div v-if="!fullIconMode" class="max-w-full">
          <p v-if="pageConfig?.labelLanguage !== 'hidden'" class="truncate font-semibold leading-tight" :style="{ fontSize: data.style.fontSize + 'px', color: data.style.textColor }">
            {{ pageConfig?.labelLanguage === 'english' ? definition.key : definition.label }}
          </p>
          <p v-if="pageConfig?.showComponentName" class="truncate font-normal leading-tight" :style="{ fontSize: (data.style.nameFontSize ?? data.style.fontSize) + 'px', color: data.style.nameTextColor || '#1D2939' }">{{ data.label }}</p>
          <p v-if="pageConfig?.showParameterTag && parameterTag" class="truncate font-normal leading-tight" :style="{ fontSize: (data.style.paramFontSize ?? data.style.fontSize) + 'px', color: data.style.paramTextColor || '#0a4da2' }">{{ parameterTag }}</p>
        </div>
      </div>

      <div
        v-else
        class="flex h-full w-full items-center justify-center px-3 text-center font-medium leading-snug"
        :class="definition.key === 'text' ? 'justify-start px-0 text-left font-normal' : ''"
      >
        <div class="max-w-full">
          <p class="truncate">{{ data.label }}</p>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.canvas-node-handle {
  z-index: 20 !important;
  height: 10px !important;
  width: 10px !important;
  border: 2px solid #ffffff !important;
  background: #0a4da2 !important;
  border-radius: 999px !important;
  box-shadow: 0 0 1px rgba(10, 77, 162, 0.12);
}

.canvas-node-handle.connecting,
.canvas-node-handle.valid {
  background: #083b7c !important;
}
</style>
