/**
 * 计算任务 WebSocket 订阅 composable
 * 文档：docs/compute-task-architecture.md § 14
 *
 * 直连 Julia 后端（不走 BFF，BFF 不代理 WebSocket）。
 * Julia 默认监听在 8080 端口（与 HTTP 共享），路径 /ws/task/:id。
 */

export type TaskWsEvent =
  | { type: 'status'; taskId: string; status: string; currentTime?: string | null }
  | { type: 'data'; taskId: string; currentTime: string; rows: Array<Record<string, unknown>> }
  | { type: 'paused'; taskId: string; currentTime: string }
  | { type: 'resumed'; taskId: string; currentTime: string }
  | { type: 'completed'; taskId: string; finalTime?: string; solvedSteps?: number }
  | { type: 'failed'; taskId: string; error: string }
  | { type: 'cancelled'; taskId: string; currentTime: string }
  | { type: 'error'; message: string }

export const useTaskWebSocket = () => {
  /**
   * 建立到 Julia 的 WS 连接
   * @returns { close: () => void, send: (msg: object) => void }
   */
  const connect = (taskId: string, onEvent: (evt: TaskWsEvent) => void) => {
    const config = useRuntimeConfig()
    // 直连 Julia HTTP 服务，从 HTTP 升级到 WS
    const wsBase = (config.public.juliaWsBase as string) || 'ws://localhost:8080'
    const url = `${wsBase}/ws/task/${taskId}`

    let ws: WebSocket | null = null
    let closed = false

    if (import.meta.client) {
      ws = new WebSocket(url)
      ws.onopen = () => {
        console.log('[TaskWS] connected:', url)
      }
      ws.onmessage = (ev) => {
        try {
          const data = JSON.parse(ev.data)
          onEvent(data as TaskWsEvent)
        }
        catch (err) {
          console.warn('[TaskWS] parse error:', err, ev.data)
        }
      }
      ws.onerror = (err) => {
        console.warn('[TaskWS] error:', err)
        onEvent({ type: 'error', message: 'WebSocket 连接错误' })
      }
      ws.onclose = () => {
        console.log('[TaskWS] disconnected:', url)
        if (!closed) {
          // 可选：自动重连
        }
      }
    }

    const close = () => {
      closed = true
      if (ws) {
        try { ws.close() } catch {}
        ws = null
      }
    }

    const send = (msg: object) => {
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify(msg))
      }
    }

    return { close, send, ws }
  }

  /**
   * 客户端发送指令（pause / resume / cancel）
   */
  const buildCommand = (type: 'pause' | 'resume' | 'cancel') => ({ type })

  return { connect, buildCommand }
}