import type { EditorMenuKey } from '~~/config/system-config'
import type { ComponentCategoryKey } from '~~/types/component'

import { createId } from '~~/utils/id'

export interface ToastItem {
  id: string
  title: string
  description?: string
  tone: 'info' | 'success' | 'warning' | 'danger'
}

export interface EditorUiState {
  activeMenu: EditorMenuKey
  activeCategory: ComponentCategoryKey
  searchKeyword: string
  leftCollapsed: boolean
  rightCollapsed: boolean
  activePropertyTab: string
}

export const useToastCenter = () => {
  const toasts = useState<ToastItem[]>('toast-center', () => [])

  const push = (toast: Omit<ToastItem, 'id'>): void => {
    const item: ToastItem = {
      id: createId('toast'),
      ...toast
    }

    toasts.value = [...toasts.value, item]

    setTimeout(() => {
      toasts.value = toasts.value.filter(current => current.id !== item.id)
    }, 3200)
  }

  const remove = (toastId: string): void => {
    toasts.value = toasts.value.filter(toast => toast.id !== toastId)
  }

  return {
    toasts,
    push,
    remove
  }
}

export const useEditorUiState = (projectId: string) =>
  useState<EditorUiState>(`editor-ui-${projectId}`, () => ({
    activeMenu: 'canvas',
    activeCategory: 'basic',
    searchKeyword: '',
    leftCollapsed: false,
    rightCollapsed: false,
    activePropertyTab: 'page'
  }))
