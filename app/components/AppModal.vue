<script setup lang="ts">
interface Props {
  open: boolean
  title: string
  size?: 'sm' | 'md' | 'lg'
}

const props = withDefaults(defineProps<Props>(), {
  size: 'md'
})

const emit = defineEmits<{
  close: []
}>()

const sizeClassMap = {
  sm: 'max-w-[400px]',
  md: 'max-w-[560px]',
  lg: 'max-w-[720px]'
}

const handleOverlayClick = (event: MouseEvent) => {
  if (event.target === event.currentTarget) {
    emit('close')
  }
}

const handleEscape = (event: KeyboardEvent) => {
  if (event.key === 'Escape') {
    emit('close')
  }
}

onMounted(() => {
  document.addEventListener('keydown', handleEscape)
})

onBeforeUnmount(() => {
  document.removeEventListener('keydown', handleEscape)
})
</script>

<template>
  <Teleport to="body">
    <Transition name="modal">
      <div
        v-if="open"
        class="modal-overlay fixed inset-0 z-50 flex items-center justify-center bg-black/50 px-4"
        @click="handleOverlayClick"
      >
        <div
          class="modal-content w-full rounded-[16px] bg-white shadow-xl"
          :class="sizeClassMap[size]"
        >
          <div class="flex items-center justify-between border-b border-app-border px-5 py-4">
            <h2 class="text-lg font-semibold text-app-text">{{ title }}</h2>
            <button
              type="button"
              class="inline-flex h-8 w-8 items-center justify-center rounded-[8px] text-app-muted transition hover:bg-app-panel-soft hover:text-app-text"
              @click="emit('close')"
            >
              <svg class="h-4 w-4" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M12 4L4 12M4 4L12 12" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
            </button>
          </div>
          <div class="max-h-[60vh] overflow-y-auto p-2">
            <slot />
          </div>
          <div v-if="$slots.footer" class="flex items-center justify-end gap-3 px-5 py-2">
            <slot name="footer" />
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.modal-enter-active,
.modal-leave-active {
  transition: opacity 0.2s ease;
}

.modal-enter-active .modal-content,
.modal-leave-active .modal-content {
  transition: transform 0.2s ease, opacity 0.2s ease;
}

.modal-enter-from,
.modal-leave-to {
  opacity: 0;
}

.modal-enter-from .modal-content,
.modal-leave-to .modal-content {
  transform: scale(0.95);
  opacity: 0;
}
</style>
