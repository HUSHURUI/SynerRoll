import type { ApiResponse } from '~~/types/api'

const unwrapResponse = <T>(payload: ApiResponse<T> | null | undefined): T => {
  if (!payload?.success) {
    throw new Error(payload?.message ?? '接口请求失败')
  }

  return payload.data
}

export const useApiClient = () => {
  const runtimeConfig = useRuntimeConfig()
  const apiBase = runtimeConfig.public.apiBase
  const requestFetch = import.meta.server ? useRequestFetch() : $fetch

  const request = async <T>(
    path: string,
    options?: { method?: 'GET' | 'POST' | 'PUT' | 'DELETE'; body?: unknown }
  ): Promise<T> => {
    const response = await requestFetch<ApiResponse<T>>(`${apiBase}${path}`, {
      method: options?.method ?? 'GET',
      body: options?.body
    })

    return unwrapResponse(response)
  }

  const get = async <T>(path: string): Promise<T> => request<T>(path)

  const mutate = async <T>(
    path: string,
    options: { method: 'POST' | 'PUT' | 'DELETE'; body?: unknown }
  ): Promise<T> => request<T>(path, options)

  return {
    get,
    mutate
  }
}
