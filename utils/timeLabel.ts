/**
 * 时间标签工具：统一处理 "H:MM" 格式与分钟数的相互转换。
 * 业务中所有时间标签均按 24h 时钟语义解析（允许 >=24 的小时，如 "48:00"）。
 */

/** "H:MM" → 分钟数 */
export function timeLabelToMinutes(ts: string): number {
  const parts = ts.split(':')
  if (parts.length < 2) return 0
  const hour = parseInt(parts[0]!, 10)
  const minute = parseInt(parts[1]!, 10)
  return hour * 60 + minute
}

/** 分钟数 → "H:MM" */
export function minutesToTimeLabel(m: number): string {
  const hour = Math.floor(m / 60)
  const minute = Math.floor(m % 60)
  return `${hour}:${String(minute).padStart(2, '0')}`
}

/** 判断时间标签是否在 [start, end) 范围内；end 为 null 时表示无上界 */
export function isTimeInRange(ts: string, start: string, end: string | null): boolean {
  const m = timeLabelToMinutes(ts)
  return m >= timeLabelToMinutes(start) && (end === null || m < timeLabelToMinutes(end))
}
