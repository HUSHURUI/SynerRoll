import type { ApiResponse } from '~~/types/api'

export const apiSuccess = <T>(data: T, message?: string): ApiResponse<T> => ({
  success: true,
  data,
  message
})
