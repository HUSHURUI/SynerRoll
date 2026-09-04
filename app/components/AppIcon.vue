<script setup lang="ts">
const props = withDefaults(
  defineProps<{
    name: string
    size?: number
    strokeWidth?: number
    fallbackText?: string
  }>(),
  {
    size: 18,
    strokeWidth: 1.8,
    fallbackText: ''
  }
)

const paths: Record<string, string[]> = {
  undo: ['M9 14 4 9l5-5', 'M4 9h9a7 7 0 1 1 0 14h-1'],
  redo: ['M15 14l5-5-5-5', 'M20 9h-9a7 7 0 1 0 0 14h1'],
  docs: ['M8 3h6l4 4v14H8z', 'M14 3v4h4'],
  github: ['M9 19c-4.5 1.4-4.5-2.5-6-3', 'M15 21v-3.7a3.2 3.2 0 0 0-.9-2.5c3-.3 6.1-1.5 6.1-6.6a5.2 5.2 0 0 0-1.4-3.6A4.8 4.8 0 0 0 18.7 2S17.6 1.7 15 3.5a13.4 13.4 0 0 0-6 0C6.4 1.7 5.3 2 5.3 2a4.8 4.8 0 0 0-.1 3.6A5.2 5.2 0 0 0 3.8 9.2c0 5.1 3.1 6.3 6.1 6.6A3.2 3.2 0 0 0 9 18.3V22'],
  fullscreen: ['M8 3H3v5', 'M16 3h5v5', 'M3 16v5h5', 'M21 16v5h-5'],
  settings: ['M12 3.5v3', 'M12 17.5v3', 'M4.6 7.8l2.6 1.5', 'M16.8 14.7l2.6 1.5', 'M4.6 16.2l2.6-1.5', 'M16.8 9.3l2.6-1.5', 'M12 15.2a3.2 3.2 0 1 0 0-6.4 3.2 3.2 0 0 0 0 6.4'],
  user: ['M12 12a4 4 0 1 0-4-4 4 4 0 0 0 4 4', 'M4 20a8 8 0 0 1 16 0'],
  search: ['m21 21-4.4-4.4', 'a7.6 7.6 0 1 1-10.7-10.7 7.6 7.6 0 0 1 10.7 10.7Z'],
  power: ['M12 2v7', 'M9 12H6l6 10 6-10h-3'],
  thermal: ['M12 2c4 4 4 8 0 12-4-4-4-8 0-12', 'M12 14v8'],
  gas: ['M12 3c3 4.5 6 6.8 6 10a6 6 0 1 1-12 0c0-3.2 3-5.5 6-10Z'],
  hydrogen: ['M7 4v16', 'M17 4v16', 'M7 12h10'],
  chemical: ['M8 3v6l-4 8a4 4 0 0 0 3.6 6h8.8A4 4 0 0 0 20 17l-4-8V3', 'M8 9h8'],
  bus: ['M4 8h16v8H4z', 'M7 8v8', 'M17 8v8'],
  carbon: ['M12 4v16', 'M8 8h8', 'M6 12h12', 'M12 4a4 4 0 0 1 4 4', 'M12 4a4 4 0 0 0-4 4'],
  storage: ['M6 8h12v8H6z', 'M18 10h2v4', 'M8 10h2v4', 'M12 10h2v4'],
  market: ['M4 4h16v16H4z', 'M8 8h8v8H8z', 'M10 10v6', 'M14 10v6'],
  shape: ['M5 5h14v14H5z'],
  flowchart: ['M6 5h12v5H6z', 'M12 10v4', 'M8 18h8v-4H8z'],
  rect: ['M4 6h16v12H4z'],
  circle: ['M12 4a8 8 0 1 1-8 8 8 8 0 0 1 8-8Z'],
  triangle: ['M12 4 20 19H4Z'],
  line: ['M4 12h16'],
  arrow: ['M4 12h14', 'm14 8 4 4-4 4'],
  diamond: ['M12 3 21 12 12 21 3 12Z'],
  parallelogram: ['M7 5h12l-2 14H5Z'],
  document: ['M7 4h8l4 4v12H7z', 'M15 4v4h4'],
  terminator: ['M8 5h8a4 4 0 0 1 0 14H8a4 4 0 0 1 0-14Z'],
  manual: ['M5 8h14l-2 10H3Z'],
  wind: ['M12 5v14', 'M12 8c2-4 7-3 7 1s-4 4-7 3', 'M12 12c-2-4-7-3-7 1s4 4 7 3'],
  solar: ['M5 14h14', 'M7 14l1-5h8l1 5', 'M12 3v3', 'M4 6l2 2', 'M20 6l-2 2'],
  flame: ['M12 3c3 4 5 6 5 9a5 5 0 0 1-10 0c0-2 1-4 3-6 0 3 1 4 2 5 1-1 2-3 0-8Z'],
  turbine: ['M12 12 6 6', 'M12 12 18 6', 'M12 12 12 20', 'M12 12a2 2 0 1 0-2-2 2 2 0 0 0 2 2Z'],
  grid: ['M6 4v16', 'M18 4v16', 'M4 8h16', 'M4 16h16'],
  'fuel-cell': ['M7 6h10v12H7z', 'M10 9h4', 'M10 15h4', 'M12 6v12'],
  link: ['M8 12h8'],
  converter: ['M6 8h6', 'M12 8 9 5', 'M12 8 9 11', 'M18 16h-6', 'M12 16 15 13', 'M12 16 15 19'],
  switch: ['M4 12h7', 'M13 7l7 5-7 5Z'],
  transformer: ['M6 8a2 2 0 1 1 0 8', 'M18 8a2 2 0 1 0 0 8', 'M8 8h8', 'M8 16h8'],
  load: ['M7 7h10v10H7z', 'M12 7v10', 'M7 12h10'],
  'heat-load': ['M12 4c3 4 3 6 0 9', 'M9 13h6', 'M7 17h10'],
  'cool-load': ['M12 4v16', 'M7 9h10', 'M8 15h8'],
  'gas-load': ['M12 4c2.5 3.2 4 5.1 4 7a4 4 0 1 1-8 0c0-1.9 1.5-3.8 4-7Z'],
  factory: ['M4 20V10l6 4v-4l6 4V6l4 2v12Z'],
  battery: ['M6 8h12v8H6z', 'M18 10h2v4', 'M8 10h2v4', 'M12 10h2v4'],
  'water-storage': ['M12 3c3 4.5 6 6.8 6 10a6 6 0 1 1-12 0c0-3.2 3-5.5 6-10Z', 'M8 16h8'],
  'heat-storage': ['M10 3v7', 'M14 3v7', 'M8 11h8v10H8z'],
  'cool-storage': ['M12 4v14', 'M8 8h8', 'M8 14h8'],
  'hydrogen-storage': ['M7 5h10v14H7z', 'M10 9v6', 'M14 9v6', 'M10 12h4'],
  'air-storage': ['M6 18V8l6-4 6 4v10Z'],
  'heat-pump': ['M12 4v16', 'M7 9h10', 'M9 15h6'],
  boiler: ['M7 4h10v10H7z', 'M9 18h6', 'M10 7c1 1 1 2 0 3'],
  collector: ['M5 14h14', 'M7 14l2-6h6l2 6'],
  chiller: ['M7 7h10v10H7z', 'M12 9v6', 'M9 12h6'],
  pump: ['M12 6a4 4 0 1 0 4 4', 'M12 10v8'],
  'bus-electric': ['M4 8h16v8H4z', 'M7 8v8', 'M12 8v8', 'M17 8v8'],
  'bus-thermal': ['M4 8h16v8H4z', 'M7 8v8', 'M12 8v8', 'M17 8v8'],
  'bus-cold': ['M4 8h16v8H4z', 'M7 8v8', 'M12 8v8', 'M17 8v8'],
  'dc-transformer': ['M6 8a2 2 0 1 1 0 8', 'M18 8a2 2 0 1 0 0 8', 'M8 8h8', 'M8 16h8', 'M12 8l-2-2', 'M12 16l-2 2'],
  'heat-source': ['M12 2c4 4 4 8 0 12-4-4-4-8 0-12', 'M12 14v8'],
  'cold-source': ['M12 2v20', 'M7 7h10', 'M8 15h8'],
  'air-heat-pump': ['M12 4v16', 'M7 9h10', 'M9 15h6', 'M12 4a3 3 0 0 1 3 3', 'M12 4a3 3 0 0 0-3 3'],
  'ground-heat-pump': ['M12 4v16', 'M7 9h10', 'M9 15h6', 'M6 20h12', 'M8 18h8'],
  'water-heat-pump': ['M12 4v16', 'M7 9h10', 'M9 15h6', 'M12 20c3 0 6-2 6-6s-3-6-6-6-6 2-6 6 3 6 6 6'],
  'absorption-chiller': ['M7 7h10v10H7z', 'M10 10l4 4', 'M14 10l-4 4'],
  'gas-boiler': ['M7 4h10v10H7z', 'M9 18h6', 'M10 7c1 1 1 2 0 3', 'M14 7c1 1 1 2 0 3'],
  'coal-boiler': ['M7 4h10v10H7z', 'M9 18h6', 'M7 6l2 2', 'M9 9l2-2', 'M12 9l2-2', 'M15 9l2 2'],
  'waste-heat-boiler': ['M7 4h10v10H7z', 'M9 18h6', 'M8 4l2 3', 'M12 4l2 3', 'M10 10h4'],
  'electric-boiler': ['M7 4h10v10H7z', 'M9 18h6', 'M12 8v6', 'M9 11h6', 'M9 14h6'],
  chp: ['M7 4h10v10H7z', 'M9 18h6', 'M12 7v5', 'M9 10h6'],
  cchp: ['M5 4h14v10H5z', 'M7 18h10', 'M12 7v5', 'M9 10h6', 'M15 10h4', 'M15 14h4'],
  'fuel-cell-chp': ['M7 6h10v12H7z', 'M10 9h4', 'M10 15h4', 'M12 6v12', 'M9 18h6'],
  'heat-exchanger': ['M12 6a4 4 0 1 0 4 4', 'M16 10v8', 'M12 14a4 4 0 1 0-4 4', 'M8 14v-4'],
  bio: ['M12 4c4 4 4 8 0 12-4-4-4-8 0-12', 'M8 14c2 2 4 2 6 0', 'M10 17c1 1 2 1 3 0'],
  'solar-thermal': ['M5 14h14', 'M7 14l2-6h6l2 6', 'M12 8v-2', 'M8 12l-2-2', 'M16 12l2-2'],
  nuclear: ['M12 4v4', 'M8 8h8l2 10H6l2-10z', 'M12 12v2'],
  hydro: ['M12 4v16', 'M8 8h8', 'M6 12h12', 'M8 16h8'],
  'waste-heat-recovery': ['M12 4v16', 'M8 8h8', 'M6 12h12', 'M10 16h4'],
  pipe: ['M4 10h10v4H4z', 'M14 12h6'],
  valve: ['M6 8l6 4-6 4', 'M18 8l-6 4 6 4'],
  'gas-source': ['M12 3c3 4.5 6 6.8 6 10a6 6 0 1 1-12 0c0-3.2 3-5.5 6-10Z'],
  electrolyzer: ['M7 6h10v12H7z', 'M9 9h6', 'M9 15h6'],
  reactor: ['M8 4h8v5l4 8H4l4-8Z'],
  'layer-up': ['M12 4l4 4h-3v8h-2V8H8z', 'M6 20h12'],
  'layer-down': ['M12 20l-4-4h3V8h2v8h3z', 'M6 4h12'],
  'to-front': ['M7 9h10v10H7z', 'M10 5h9v9'],
  'to-back': ['M5 10h9v9H5z', 'M8 5h10v10H8z'],
  'align-left': ['M6 4v16', 'M10 8h8', 'M10 14h6'],
  'align-center': ['M12 4v16', 'M6 8h12', 'M8 14h8'],
  'align-right': ['M18 4v16', 'M6 8h8', 'M8 14h6'],
  'align-top': ['M4 6h16', 'M8 10v8', 'M14 10v6'],
  'align-middle': ['M4 12h16', 'M8 6v12', 'M14 8v8'],
  'align-bottom': ['M4 18h16', 'M8 6v8', 'M14 8v6'],
  'distribute-h': ['M4 6v12', 'M10 8v8', 'M16 5v14', 'M20 6v12'],
  'distribute-v': ['M6 4h12', 'M8 10h8', 'M5 16h14', 'M6 20h12'],
  width: ['M4 12h16', 'M8 9l-4 3 4 3', 'M16 9l4 3-4 3'],
  height: ['M12 4v16', 'M9 8l3-4 3 4', 'M9 16l3 4 3-4'],
  size: ['M5 5h6v6H5z', 'M13 13h6v6h-6z'],
  rotate: ['M12 5V2l4 4-4 4V7a5 5 0 1 0 5 5'],
  'rotate-left': ['M12 5V2L8 6l4 4V7a5 5 0 1 1-5 5'],
  'rotate-right': ['M12 5V2l4 4-4 4V7a5 5 0 1 0 5 5'],
  'axis-x': ['M4 18 18 4', 'M14 4h4v4'],
  'axis-y': ['M6 4v16', 'M6 4l-2 2', 'M6 4l2 2'],
  copy: ['M9 9h10v11H9z', 'M5 5h10v2'],
  paste: ['M8 4h8v4H8z', 'M6 8h12v12H6z'],
  delete: ['M5 7h14', 'M9 7V5h6v2', 'M8 10v7', 'M12 10v7', 'M16 10v7'],
  fit: ['M8 4H4v4', 'M16 4h4v4', 'M4 16v4h4', 'M20 16v4h-4'],
  'zoom-in': ['M11 8v6', 'M8 11h6', 'm21 21-4.3-4.3', 'M 16.7 16.7 m0 0'],
  'zoom-out': ['M8 11h6', 'm21 21-4.3-4.3', 'M 16.7 16.7 m0 0'],
  plus: ['M12 5v14', 'M5 12h14'],
  close: ['M6 6l12 12', 'M18 6L6 18'],
  minus: ['M5 12h14'],
  add: ['M12 5v14', 'M5 12h14'],
  'grid-pattern': ['M4 4h16v16H4z', 'M4 10h16', 'M10 4v16'],
  pattern: ['M5 5h4v4H5z', 'M15 5h4v4h-4z', 'M5 15h4v4H5z', 'M15 15h4v4h-4z'],
  download: ['M12 4v10', 'm8 10 4 4 4-4', 'M5 20h14'],
  package: ['M12 3 4 7l8 4 8-4-8-4Z', 'M4 7v10l8 4 8-4V7', 'M12 11v10'],
  play: ['M8 6l10 6-10 6Z'],
  chart: ['M5 18h14', 'M7 16V9', 'M12 16V5', 'M17 16v-4']
}

const pathSet = computed(() => paths[props.name] ?? [])

const fallback = computed(() => props.fallbackText || props.name.slice(0, 1).toUpperCase())
</script>

<template>
  <svg
    v-if="pathSet.length > 0"
    :width="size"
    :height="size"
    viewBox="0 0 24 24"
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
    class="shrink-0"
  >
    <path
      v-for="path in pathSet"
      :key="path"
      :d="path"
      stroke="currentColor"
      stroke-linecap="round"
      stroke-linejoin="round"
      :stroke-width="strokeWidth"
    />
  </svg>
  <div
    v-else
    :style="{ width: `${size}px`, height: `${size}px` }"
    class="inline-flex items-center justify-center rounded bg-current/10 text-[10px] font-semibold leading-none"
  >
    {{ fallback }}
  </div>
</template>
