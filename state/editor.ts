import type { HistorySnapshot } from '~~/types/canvas'

import { deepClone } from '~~/utils/clone'

export const useEditorHistory = (projectId: string) => {
  const past = useState<HistorySnapshot[]>(`editor-history-past-${projectId}`, () => [])
  const future = useState<HistorySnapshot[]>(`editor-history-future-${projectId}`, () => [])
  const lastFingerprint = useState<string>(`editor-history-fingerprint-${projectId}`, () => '')
  const syncLastFingerprint = () => {
    lastFingerprint.value = past.value.length
      ? JSON.stringify(past.value[past.value.length - 1].workspace)
      : ''
  }

  const commit = (workspace: import('~~/types/canvas').CanvasWorkspace, label: string): void => {
    const fingerprint = JSON.stringify(workspace)

    if (fingerprint === lastFingerprint.value) {
      return
    }

    past.value = [
      ...past.value,
      {
        label,
        workspace: deepClone(workspace),
        capturedAt: new Date().toISOString()
      }
    ].slice(-40)
    future.value = []
    syncLastFingerprint()
  }

  const undo = (currentWorkspace: import('~~/types/canvas').CanvasWorkspace): import('~~/types/canvas').CanvasWorkspace | null => {
    const previous = past.value[past.value.length - 1]

    if (!previous) {
      return null
    }

    future.value = [
      {
        label: 'redo',
        workspace: deepClone(currentWorkspace),
        capturedAt: new Date().toISOString()
      },
      ...future.value
    ]
    past.value = past.value.slice(0, -1)
    syncLastFingerprint()

    return deepClone(previous.workspace)
  }

  const redo = (currentWorkspace: import('~~/types/canvas').CanvasWorkspace): import('~~/types/canvas').CanvasWorkspace | null => {
    const next = future.value[0]

    if (!next) {
      return null
    }

    past.value = [
      ...past.value,
      {
        label: 'undo',
        workspace: deepClone(currentWorkspace),
        capturedAt: new Date().toISOString()
      }
    ]
    future.value = future.value.slice(1)
    syncLastFingerprint()

    return deepClone(next.workspace)
  }

  return {
    past,
    future,
    commit,
    undo,
    redo
  }
}
