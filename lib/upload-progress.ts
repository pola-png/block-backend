export type UploadProgressStatus = 'uploading' | 'completed' | 'failed'

export interface UploadProgressItem {
  id: string
  userId: string
  postType: 'video' | 'reel' | 'image' | 'news' | 'text'
  title?: string
  content?: string
  progress: number
  status: UploadProgressStatus
  message: string
  error?: string
  updatedAt: number
}

const STORAGE_KEY = 'xapzap_upload_progress_v1'

function canUseStorage() {
  return typeof window !== 'undefined' && typeof window.localStorage !== 'undefined'
}

export function readUploadProgressItems(): UploadProgressItem[] {
  if (!canUseStorage()) return []
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY)
    if (!raw) return []
    const parsed = JSON.parse(raw)
    return Array.isArray(parsed) ? parsed : []
  } catch {
    return []
  }
}

export function writeUploadProgressItems(items: UploadProgressItem[]) {
  if (!canUseStorage()) return
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(items))
  } catch {
    // Ignore storage failures.
  }
}

export function upsertUploadProgressItem(item: UploadProgressItem) {
  const current = readUploadProgressItems()
  const next = current.filter((entry) => entry.id !== item.id)
  next.unshift(item)
  writeUploadProgressItems(next.slice(0, 30))
}

export function removeUploadProgressItem(id: string) {
  const current = readUploadProgressItems()
  writeUploadProgressItems(current.filter((entry) => entry.id !== id))
}

export function getUploadProgressByUser(userId: string) {
  if (!userId) return []
  return readUploadProgressItems()
    .filter((entry) => entry.userId === userId)
    .sort((a, b) => b.updatedAt - a.updatedAt)
}

