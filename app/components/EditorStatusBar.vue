<script setup lang="ts">
defineProps<{
  canvases: Array<{ id: string; name: string }>
  activeCanvasId: string
  nodeCount: number
  edgeCount: number
  zoomPercent: number
}>()

defineEmits<{
  selectCanvas: [canvasId: string]
  addCanvas: []
  closeCanvas: [canvasId: string]
  zoomIn: []
  zoomOut: []
  resetZoom: []
  setZoom: [value: number]
}>()

const zoomOptions = [
  { value: 25, label: '25%' },
  { value: 50, label: '50%' },
  { value: 75, label: '75%' },
  { value: 100, label: '100%' },
  { value: 150, label: '150%' },
  { value: 200, label: '200%' }
]
</script>

<template>
  <footer class="flex h-8 items-center justify-between gap-4 px-2 bg-white border-t border-gray-100">
    <!-- Canvas tabs -->
    <div class="flex min-w-0 items-center gap-1 overflow-x-auto">
      <template v-for="(canvas, index) in canvases" :key="canvas.id">
        <div
          class="group inline-flex h-6 items-center gap-1.5 px-3 text-sm transition-all cursor-pointer rounded-sm"
          :class="activeCanvasId === canvas.id
            ? 'bg-primary/10 text-primary font-medium'
            : 'text-app-text hover:bg-gray-100'"
          @click="$emit('selectCanvas', canvas.id)"
        >
          <span class="whitespace-nowrap">{{ canvas.name }}</span>
          <button
            v-if="canvases.length > 1"
            type="button"
            class="flex h-4 w-2 items-center justify-center rounded-sm opacity-0 transition-all text-primary hover:text-red-500 group-hover:opacity-100"
            title="关闭画布"
            @click.stop="$emit('closeCanvas', canvas.id)"
          >
            <AppIcon name="close" :size="12" :stroke-width="2" />
          </button>
        </div>
        <div v-if="index < canvases.length - 1" class="h-4 w-px bg-gray-300"></div>
      </template>

      <button
        type="button"
        class="flex h-6 w-6 items-center justify-center rounded-md text-app-muted transition-all hover:bg-gray-100 hover:text-primary"
        title="新建画布"
        @click="$emit('addCanvas')"
      >
        <AppIcon name="add" :size="16" :stroke-width="2" />
      </button>
    </div>

    <!-- Stats and zoom controls -->
    <div class="flex shrink-0 items-center gap-4 text-[12px]">
      <!-- Node/Edge count -->
      <div class="flex items-center gap-3 text-app-muted">
        <span>组件：{{ nodeCount }} </span>
        <span>连线：{{ edgeCount }} </span>
      </div>

      <!-- Divider -->
      <div class="h-4 w-px bg-gray-200"></div>

      <!-- Zoom controls -->
      <div class="flex items-center gap-2">
        <button
          type="button"
          class="flex h-6 w-6 items-center justify-center rounded-md text-app-muted transition-all hover:bg-gray-100 hover:text-primary"
          title="缩小"
          @click="$emit('zoomOut')"
        >
          <AppIcon name="minus" :size="14" :stroke-width="2" />
        </button>

        <!-- Custom range slider -->
        <div class="relative flex items-center">
          <div class="slider-track">
            <input
              class="slider-input"
              type="range"
              min="10"
              max="200"
              :value="zoomPercent"
              @input="$emit('setZoom', Number(($event.target as HTMLInputElement).value))"
            >
          </div>
        </div>

        <button
          type="button"
          class="flex h-6 w-6 items-center justify-center rounded-md text-app-muted transition-all hover:bg-gray-100 hover:text-primary"
          title="放大"
          @click="$emit('zoomIn')"
        >
          <AppIcon name="plus" :size="14" :stroke-width="2" />
        </button>

        <!-- Zoom percentage select -->
        <select
          class="zoom-select"
          :value="zoomPercent"
          @change="$emit('setZoom', Number(($event.target as HTMLSelectElement).value))"
        >
          <option v-for="opt in zoomOptions" :key="opt.value" :value="opt.value">
            {{ opt.label }}
          </option>
        </select>
      </div>
    </div>
  </footer>
</template>

<style scoped>

.slider-track {
  position: relative;
  height: 4px;
  width: 100px;
  background: linear-gradient(to right, #dde1e6 0%, #dde1e6 100%);
  border-radius: 2px;
}

.slider-input {
  position: absolute;
  top: 50%;
  left: 0;
  width: 100%;
  height: 16px;
  margin: 0;
  transform: translateY(-50%);
  -webkit-appearance: none;
  appearance: none;
  background: transparent;
  cursor: pointer;
}

.slider-input::-webkit-slider-runnable-track {
  height: 4px;
  background: transparent;
  border-radius: 2px;
}

.slider-input::-webkit-slider-thumb {
  -webkit-appearance: none;
  appearance: none;
  width: 12px;
  height: 12px;
  margin-top: -4px;
  background: white;
  border: 2px solid #0a4da2;
  border-radius: 50%;
  cursor: pointer;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.15);
  transition: all 0.15s ease;
}

.slider-input::-webkit-slider-thumb:hover {
  transform: scale(1.15);
  box-shadow: 0 2px 6px rgba(10, 77, 162, 0.3);
}

.slider-input::-moz-range-track {
  height: 4px;
  background: transparent;
  border-radius: 2px;
}

.slider-input::-moz-range-thumb {
  width: 12px;
  height: 12px;
  background: white;
  border: 2px solid #0a4da2;
  border-radius: 50%;
  cursor: pointer;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.15);
  transition: all 0.15s ease;
}

.slider-input::-moz-range-thumb:hover {
  transform: scale(1.15);
  box-shadow: 0 2px 6px rgba(10, 77, 162, 0.3);
}

.slider-input:focus {
  outline: none;
}

.slider-input:focus::-webkit-slider-thumb {
  box-shadow: 0 0 0 3px rgba(10, 77, 162, 0.2), 0 2px 6px rgba(10, 77, 162, 0.3);
}

.zoom-select {
  height: 24px;
  min-width: 64px;
  padding: 0 24px 0 8px;
  font-size: 11px;
  font-weight: 500;
  color: #86909c;
  background: transparent;
  border: 1px solid transparent;
  border-radius: 6px;
  cursor: pointer;
  appearance: none;
  -webkit-appearance: none;
  -moz-appearance: none;
  background-image: url("data:image/svg+xml,%3Csvg width='10' height='10' viewBox='0 0 12 12' fill='none' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath d='M3 4.5L6 7.5L9 4.5' stroke='%2386909C' stroke-width='1.4' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E");
  background-position: right 6px center;
  background-repeat: no-repeat;
  background-size: 10px 10px;
  transition: all 0.15s ease;
}

.zoom-select:hover {
  border-color: #dde1e6;
  color: #1d2129;
}

.zoom-select:focus {
  outline: none;
  border-color: #0a4da2;
  color: #1d2129;
}
</style>
