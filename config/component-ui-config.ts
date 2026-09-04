import type { AppearancePreset, SizePreset } from '~~/types/component'

export interface ComponentUIConfig {
  icon: string
  canvasType: 'energy' | 'shape'
  defaultSize: SizePreset
  appearance: AppearancePreset
}

const createAppearance = (
  fillColor: string,
  strokeColor = '#475467',
  borderRadius = 10
): AppearancePreset => ({
  fillColor,
  strokeColor,
  strokeWidth: 1.5,
  fontSize: 13,
  textColor: '#1D2939',
  borderRadius,
  rotation: 0,
  opacity: 1
})

export const componentUIConfigs: Record<string, ComponentUIConfig> = {
  // ===== 电力系统 =====
  WT: {
    icon: 'wind',
    canvasType: 'energy',
    defaultSize: { width: 150, height: 150 },
    appearance: createAppearance('#EFF8FF', '#165DFF')
  },
  CP: {
    icon: 'factory',
    canvasType: 'energy',
    defaultSize: { width: 150, height: 150 },
    appearance: createAppearance('#FFF1F0', '#F53F3F')
  },
  CHP: {
    icon: 'factory',
    canvasType: 'energy',
    defaultSize: { width: 150, height: 150 },
    appearance: createAppearance('#FFF7E8', '#FF7D00')
  },
  ES: {
    icon: 'battery',
    canvasType: 'energy',
    defaultSize: { width: 150, height: 150 },
    appearance: createAppearance('#ECFDF3', '#12B76A')
  },
  FS: {
    icon: 'battery',
    canvasType: 'energy',
    defaultSize: { width: 150, height: 150 },
    appearance: createAppearance('#F3F0FF', '#7C3AED')
  },
  PS: {
    icon: 'water',
    canvasType: 'energy',
    defaultSize: { width: 150, height: 150 },
    appearance: createAppearance('#E0F2FE', '#0284C7')
  },
  CS: {
    icon: 'battery',
    canvasType: 'energy',
    defaultSize: { width: 150, height: 150 },
    appearance: createAppearance('#E0F2FE', '#0EA5E9')
  },
  ELOAD: {
    icon: 'load-electric',
    canvasType: 'energy',
    defaultSize: { width: 150, height: 150 },
    appearance: createAppearance('#FEF3F2', '#F04438')
  },
  HLOAD: {
    icon: 'load-hydrogen',
    canvasType: 'energy',
    defaultSize: { width: 150, height: 150 },
    appearance: createAppearance('#F0FDF4', '#16A34A')
  },

  // ===== 总线 =====
  ELEC_BUS: {
    icon: 'bus-electric',
    canvasType: 'shape',
    defaultSize: { width: 10, height: 100 },
    appearance: createAppearance('#EEF4FF', '#155EEF', 1)
  },
  COLD_BUS: {
    icon: 'bus-cold',
    canvasType: 'shape',
    defaultSize: { width: 10, height: 100 },
    appearance: createAppearance('#EFF8FF', '#2E90FA', 1)
  },
  THERMAL_BUS: {
    icon: 'bus-thermal',
    canvasType: 'shape',
    defaultSize: { width: 10, height: 100 },
    appearance: createAppearance('#FFF4ED', '#F97316', 1)
  },
  H2_BUS: {
    icon: 'bus-hydrogen',
    canvasType: 'shape',
    defaultSize: { width: 10, height: 100 },
    appearance: createAppearance('#ECFDF3', '#12B76A', 1)
  },
  GAS_BUS: {
    icon: 'bus-gas',
    canvasType: 'shape',
    defaultSize: { width: 10, height: 100 },
    appearance: createAppearance('#FFF7E8', '#FF7D00', 1)
  },
  CARBON_BUS: {
    icon: 'bus-carbon',
    canvasType: 'shape',
    defaultSize: { width: 10, height: 100 },
    appearance: createAppearance('#F2F4F7', '#78716C', 1)
  },
  OTHER_BUS: {
    icon: 'bus-other',
    canvasType: 'shape',
    defaultSize: { width: 10, height: 100 },
    appearance: createAppearance('#F8FAFC', '#98A2B3', 1)
  }
}
