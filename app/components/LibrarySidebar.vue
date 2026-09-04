<script setup lang="ts">
import { componentLibrary, componentDefinitions } from '~~/config/component-meta'
import type { ComponentCategoryKey, ComponentDefinition } from '~~/types/component'

const props = defineProps<{
  activeCategory: ComponentCategoryKey
  collapsed: boolean
}>()

const emit = defineEmits<{
  selectCategory: [categoryKey: ComponentCategoryKey]
  toggleCollapse: []
}>()

const libraryTab = ref<'library' | 'mine'>('library')
const expandedGroupKeys = ref<Record<string, boolean>>({})
const isGlobalSearch = ref(false)
const globalSearchKeyword = ref('')
const selectedComponent = ref<ComponentDefinition | null>(null)
const hoveredComponentKey = ref<string | null>(null)

watchEffect(() => {
  componentLibrary.forEach(category => {
    category.groups.forEach(group => {
      if (!(group.key in expandedGroupKeys.value)) {
        expandedGroupKeys.value[group.key] = true
      }
    })
  })
})

const activeCategoryConfig = computed(
  () => componentLibrary.find(category => category.key === props.activeCategory) ?? componentLibrary[0]!
)

const visibleGroups = computed(() => {
  if (libraryTab.value !== 'library' || isGlobalSearch.value) {
    return []
  }

  return activeCategoryConfig.value.groups
})

const globalSearchResults = computed(() => {
  if (!isGlobalSearch.value || !globalSearchKeyword.value.trim()) {
    return []
  }

  const keyword = globalSearchKeyword.value.trim().toLowerCase()

  // Filter components that match the keyword
  const matchedComponents = componentDefinitions.filter(item => {
    return [item.label, item.key, item.description, ...item.tags].some(text =>
      text.toLowerCase().includes(keyword)
    )
  })

  // Organize by category only
  const organizedResults: Array<{
    key: string
    label: string
    items: ComponentDefinition[]
  }> = []

  for (const category of componentLibrary) {
    const categoryMatches = matchedComponents.filter(c => c.category === category.key)
    if (categoryMatches.length === 0) continue

    organizedResults.push({
      key: category.key,
      label: category.label,
      items: categoryMatches
    })
  }

  return organizedResults
})

const currentDescription = computed(() => {
  if (selectedComponent.value) {
    return selectedComponent.value.description
  }
  if (isGlobalSearch.value) {
    return '全局搜索模式：输入关键词搜索所有组件'
  }
  return activeCategoryConfig.value.description || '选择一个组件查看详情'
})

const onDragStart = (event: DragEvent, componentKey: string) => {
  event.dataTransfer?.setData('application/synerroll-component', componentKey)
  event.dataTransfer!.effectAllowed = 'copy'
  selectedComponent.value = componentDefinitions.find(c => c.key === componentKey) ?? null
}

const onComponentHover = (component: ComponentDefinition) => {
  hoveredComponentKey.value = component.key
}

const onComponentLeave = () => {
  hoveredComponentKey.value = null
}

const onComponentClick = (component: ComponentDefinition) => {
  selectedComponent.value = component
}

const toggleGlobalSearch = () => {
  isGlobalSearch.value = !isGlobalSearch.value
  if (!isGlobalSearch.value) {
    globalSearchKeyword.value = ''
    selectedComponent.value = null
  }
}

const onSelectCategory = (categoryKey: ComponentCategoryKey) => {
  isGlobalSearch.value = false
  selectedComponent.value = null
  emit('selectCategory', categoryKey)
}
</script>

<template>
  <aside
    class="flex h-full overflow-hidden rounded-[12px] bg-app-panel-soft shadow-sm"
    :class="collapsed ? 'w-[54px]' : 'w-[320px]'"
  >
    <div
      class="flex shrink-0 flex-col items-center gap-2 bg-app-panel-soft px-2 py-3"
      :class="collapsed ? 'w-full' : 'w-[54px] border-r border-app-border'"
    >
      <button
        type="button"
        class="inline-flex h-9 w-9 items-center justify-center rounded-[10px] text-app-muted transition hover:bg-white hover:text-primary"
        :title="collapsed ? '展开组件库' : '折叠组件库'"
        @click="emit('toggleCollapse')"
      >
        <svg
          class="h-4 w-4"
          viewBox="0 0 16 16"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
        >
          <path
            :d="collapsed ? 'M6 3L11 8L6 13' : 'M10 3L5 8L10 13'"
            stroke="currentColor"
            stroke-width="1.6"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
        </svg>
      </button>

      <button
        type="button"
        class="inline-flex h-9 w-9 items-center justify-center rounded-[10px] transition"
        :class="isGlobalSearch
          ? 'bg-white text-primary'
          : 'text-app-muted hover:bg-white hover:text-primary'"
        title="全局搜索"
        @click="toggleGlobalSearch"
      >
        <svg class="h-4 w-4" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path
            d="M7.5 3C5.015 3 3 5.015 3 7.5S5.015 12 7.5 12 12 9.985 12 7.5 9.985 3 7.5 3Z"
            stroke="currentColor"
            stroke-width="1.4"
          />
          <path
            d="m13 13 2.5 2.5"
            stroke="currentColor"
            stroke-width="1.4"
            stroke-linecap="round"
          />
        </svg>
      </button>

      <div class="mt-1 flex min-h-0 flex-1 flex-col items-center gap-2 overflow-y-auto">
        <button
          v-for="category in componentLibrary"
          :key="category.key"
          type="button"
          class="inline-flex h-9 w-9 items-center justify-center rounded-[8px] transition"
          :class="activeCategory === category.key && !isGlobalSearch
            ? 'bg-white text-primary'
            : 'bg-transparent text-app-text hover:bg-white hover:text-primary'"
          :title="category.label"
          @click="onSelectCategory(category.key)"
        >
          <AppIcon :name="category.icon" :size="18" :fallback-text="category.label.slice(0, 1)" />
        </button>
      </div>
    </div>

    <template v-if="!collapsed">
      <div class="flex min-w-0 flex-1 flex-col bg-app-panel-soft">
        <AppTabs
          v-model="libraryTab"
          :tabs="[
            { key: 'library', label: '组件库' },
            { key: 'mine', label: '自定义' }
          ]"
        />

        <template v-if="libraryTab === 'mine'">
          <div class="flex h-full min-h-[220px] items-center justify-center px-4 text-center text-xs leading-6 text-app-muted">
            我的组件暂未开放独立管理，当前阶段请先从图形库拖拽基础组件。
          </div>
        </template>

        <template v-else>
          <div class="py-2">
            <p class="text-sm font-semibold text-app-text px-4">{{ isGlobalSearch ? '全局搜索' : activeCategoryConfig.label }}</p>
            <p v-if="!isGlobalSearch" class="text-xs text-app-muted px-4 mt-1">{{ currentDescription }}</p>

            <div v-if="isGlobalSearch" class="px-2 mt-2">
              <input
                v-model="globalSearchKeyword"
                class="field-input h-8 text-xs"
                placeholder="输入关键词搜索所有组件"
              >
            </div>
          </div>

          <div class="min-h-0 flex-1 overflow-y-auto px-2 pt-3">
            <template v-if="isGlobalSearch">
              <div v-if="globalSearchResults.length === 0 && globalSearchKeyword" class="flex min-h-[220px] items-center justify-center rounded-[12px] bg-app-panel-soft px-4 text-center text-xs leading-6 text-app-muted">
                没有找到匹配的组件
              </div>
              <div v-else-if="globalSearchResults.length > 0" class="space-y-3">
                <section v-for="category in globalSearchResults" :key="category.key" class="space-y-2">
                  <div class="text-sm font-medium text-app-text px-2">{{ category.label }}</div>
                  <div class="grid grid-cols-3 gap-2">
                    <button
                      v-for="item in category.items"
                      :key="item.key"
                      type="button"
                      class="flex min-h-[64px] cursor-grab flex-col items-center justify-center gap-2 border border-transparent text-center transition hover:bg-white"
                      :class="{ 'bg-white': hoveredComponentKey === item.key }"
                      :title="item.label"
                      draggable="true"
                      @mouseenter="onComponentHover(item)"
                      @mouseleave="onComponentLeave"
                      @click="onComponentClick(item)"
                      @dragstart="onDragStart($event, item.key)"
                    >
                      <span class="inline-flex h-10 w-10 items-center justify-center rounded-[10px] text-app-text">
                        <AppIcon :name="item.icon" :size="36" :fallback-text="item.label.slice(0, 1)" />
                      </span>
                      <span class="text-xs leading-4 text-app-text">{{ item.label }}</span>
                    </button>
                  </div>
                </section>
              </div>
              <div v-else class="flex min-h-[220px] items-center justify-center rounded-[12px] bg-app-panel-soft px-4 text-center text-xs leading-6 text-app-muted">
                输入关键词搜索所有分类下的组件
              </div>
            </template>

            <template v-else>
              <div v-if="visibleGroups.length === 0" class="flex min-h-[220px] items-center justify-center rounded-[12px] bg-app-panel-soft px-4 text-center text-xs leading-6 text-app-muted">
                当前分类下没有组件
              </div>

              <div v-else class="space-y-3">
                <section v-for="group in visibleGroups" :key="group.key" class="space-y-2">
                  <button
                    type="button"
                    class="flex w-full items-center gap-2 text-left text-sm font-medium text-app-text"
                    @click="expandedGroupKeys[group.key] = !expandedGroupKeys[group.key]"
                  >
                    <span class="text-xs text-app-muted">{{ expandedGroupKeys[group.key] ? '⏷' : '⏵' }}</span>
                    <span>{{ group.label }}</span>
                  </button>

                  <div
                    v-if="expandedGroupKeys[group.key]"
                    class="grid grid-cols-3 gap-2"
                  >
                    <button
                      v-for="item in group.items"
                      :key="item.key"
                      type="button"
                      class="flex min-h-[64px] cursor-grab flex-col items-center justify-center gap-2 border border-transparent text-center transition hover:bg-white"
                      :class="{ 'bg-white': hoveredComponentKey === item.key }"
                      :title="item.label"
                      draggable="true"
                      @mouseenter="onComponentHover(item)"
                      @mouseleave="onComponentLeave"
                      @click="onComponentClick(item)"
                      @dragstart="onDragStart($event, item.key)"
                    >
                      <span class="inline-flex h-10 w-10 items-center justify-center rounded-[10px] text-app-text">
                        <AppIcon :name="item.icon" :size="36" :fallback-text="item.label.slice(0, 1)" />
                      </span>
                      <span class="text-xs leading-4 text-app-text">{{ item.label }}</span>
                    </button>
                  </div>
                </section>
              </div>
            </template>
          </div>
        </template>
      </div>
    </template>
  </aside>
</template>