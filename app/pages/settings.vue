<script setup lang="ts">
import { settingsSections } from '~~/config/system-config'
import { useToastCenter } from '~~/state/ui'

const { push } = useToastCenter()
const settingsState = useState<Record<string, string | number | boolean>>('app-settings', () => ({
  autosaveInterval: 30,
  defaultZoom: 100,
  apiBaseUrl: '/api/v1',
  socketPath: '/ws/simulation'
}))

const saveSettings = () => {
  push({ tone: 'success', title: '设置已保存', description: '当前为前端本地状态保存，可继续对接后台系统设置接口。' })
}
</script>

<template>
  <div class="min-h-screen bg-app-surface">
    <div class="border-b border-app-border bg-white">
      <div class="mx-auto flex max-w-[1200px] items-center justify-between px-6 py-4">
        <div>
          <h1 class="text-2xl font-bold text-app-text">系统设置</h1>
          <p class="mt-1 text-sm text-app-muted">接口占位、全局偏好与运行参数配置</p>
        </div>
        <div class="flex items-center gap-2">
          <AppButton label="返回项目页" icon="arrow" tone="neutral" @click="navigateTo('/project')" />
          <AppButton label="保存设置" icon="docs" tone="primary" @click="saveSettings" />
        </div>
      </div>
    </div>

    <div class="mx-auto max-w-[1200px] space-y-6 px-6 py-6">
      <PanelSection
        v-for="section in settingsSections"
        :key="section.title"
        :title="section.title"
      >
        <div class="grid gap-4 md:grid-cols-2">
          <label v-for="field in section.fields" :key="field.key" class="block">
            <span class="field-label">{{ field.label }}</span>
            <BaseInput
              v-if="field.type === 'text' || field.type === 'number'"
              v-model="settingsState[field.key]"
              :type="field.type === 'number' ? 'number' : 'text'"
            />
          </label>
        </div>
      </PanelSection>
    </div>
  </div>
</template>
