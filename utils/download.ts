export const downloadText = (filename: string, content: string, mimeType = 'text/plain;charset=utf-8'): void => {
  if (!import.meta.client) {
    return
  }

  const blob = new Blob([content], { type: mimeType })
  const url = URL.createObjectURL(blob)
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = filename
  anchor.click()
  URL.revokeObjectURL(url)
}

export const downloadJson = (filename: string, payload: unknown): void => {
  downloadText(filename, JSON.stringify(payload, null, 2), 'application/json;charset=utf-8')
}
