import { isProxy, toRaw } from 'vue'

const unwrapCloneValue = <T>(value: T, seen = new WeakMap<object, unknown>()): T => {
  if (value === null || typeof value !== 'object') {
    return value
  }

  const rawValue = isProxy(value) ? toRaw(value) : value

  if (rawValue instanceof Date) {
    return new Date(rawValue.getTime()) as T
  }

  if (rawValue instanceof Map) {
    const clonedMap = new Map()
    seen.set(rawValue, clonedMap)

    for (const [key, entryValue] of rawValue.entries()) {
      clonedMap.set(unwrapCloneValue(key, seen), unwrapCloneValue(entryValue, seen))
    }

    return clonedMap as T
  }

  if (rawValue instanceof Set) {
    const clonedSet = new Set()
    seen.set(rawValue, clonedSet)

    for (const entryValue of rawValue.values()) {
      clonedSet.add(unwrapCloneValue(entryValue, seen))
    }

    return clonedSet as T
  }

  if (seen.has(rawValue)) {
    return seen.get(rawValue) as T
  }

  if (Array.isArray(rawValue)) {
    const clonedArray: unknown[] = []
    seen.set(rawValue, clonedArray)

    for (const entryValue of rawValue) {
      clonedArray.push(unwrapCloneValue(entryValue, seen))
    }

    return clonedArray as T
  }

  const clonedObject: Record<string, unknown> = {}
  seen.set(rawValue, clonedObject)

  for (const [key, entryValue] of Object.entries(rawValue)) {
    clonedObject[key] = unwrapCloneValue(entryValue, seen)
  }

  return clonedObject as T
}

export const deepClone = <T>(value: T): T => {
  const normalizedValue = unwrapCloneValue(value)

  if (typeof structuredClone === 'function') {
    try {
      return structuredClone(normalizedValue)
    }
    catch {
      return JSON.parse(JSON.stringify(normalizedValue)) as T
    }
  }

  return JSON.parse(JSON.stringify(normalizedValue)) as T
}
