import tailwindcss from '@tailwindcss/vite'

export default defineNuxtConfig({
  compatibilityDate: '2026-04-13',
  devtools: { enabled: true },
  css: ['~/assets/css/main.css'],
  runtimeConfig: {
    public: {
      apiBase: '/api/v1',
      // 计算任务 WebSocket 直连 Julia（不走 BFF）；端口和 HTTP 共享
      juliaWsBase: 'ws://localhost:8080'
    }
  },
  vite: {
    plugins: [tailwindcss()]
  }
})
