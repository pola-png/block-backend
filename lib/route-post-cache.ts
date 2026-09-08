import { Post } from '../types'
import { extractCandidateIdsFromSlug, extractIdFromSlug } from './slug'

const CACHE_PREFIX = 'xapzap:route-post:'
const CACHE_TTL_MS = 15 * 60 * 1000

type CachedPayload = {
  savedAt: number
  post: Omit<Post, 'timestamp'> & { timestamp: string | Date }
}

function getResolvedPostId(post: Partial<Post> & { $id?: string }): string {
  return String(post.id || post.postId || post.$id || '').trim()
}

function serializePost(post: Post): CachedPayload {
  const timestampValue =
    post.timestamp instanceof Date ? post.timestamp.toISOString() : post.timestamp

  return {
    savedAt: Date.now(),
    post: {
      ...post,
      timestamp: timestampValue,
    },
  }
}

function deserializePost(payload: CachedPayload): Post | null {
  if (!payload?.post) return null
  const asDate =
    payload.post.timestamp instanceof Date
      ? payload.post.timestamp
      : new Date(payload.post.timestamp)
  return {
    ...payload.post,
    timestamp: asDate,
  } as Post
}

function readByKey(key: string): Post | null {
  if (typeof window === 'undefined') return null
  try {
    const raw = window.sessionStorage.getItem(`${CACHE_PREFIX}${key}`)
    if (!raw) return null
    const parsed = JSON.parse(raw) as CachedPayload
    if (!parsed?.savedAt || Date.now() - parsed.savedAt > CACHE_TTL_MS) {
      window.sessionStorage.removeItem(`${CACHE_PREFIX}${key}`)
      return null
    }
    return deserializePost(parsed)
  } catch {
    return null
  }
}

function writeByKey(key: string, post: Post) {
  if (typeof window === 'undefined') return
  try {
    const payload = serializePost(post)
    window.sessionStorage.setItem(`${CACHE_PREFIX}${key}`, JSON.stringify(payload))
  } catch {
    // Ignore cache write failures.
  }
}

export function cacheRoutePost(slugId: string, post: Post) {
  if (!slugId) return
  const resolvedId = getResolvedPostId(post)
  const keys = Array.from(
    new Set([slugId, ...extractCandidateIdsFromSlug(slugId), extractIdFromSlug(slugId), resolvedId].filter(Boolean))
  )
  keys.forEach((key) => writeByKey(key, post))
}

export function getCachedRoutePost(slugId: string): Post | null {
  const keys = Array.from(
    new Set([slugId, ...extractCandidateIdsFromSlug(slugId), extractIdFromSlug(slugId)].filter(Boolean))
  )
  for (const key of keys) {
    const cached = readByKey(key)
    if (cached) return cached
  }
  return null
}
