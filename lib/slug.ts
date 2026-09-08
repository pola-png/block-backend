export function generateSlug(title: string, id: string): string {
  const slug = title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .substring(0, 50)
  
  return `${slug}-${id}`
}

function normalizeSlugInput(value: unknown): string {
  if (typeof value !== 'string') return ''
  const trimmed = value.trim()
  if (!trimmed) return ''

  try {
    return decodeURIComponent(trimmed)
  } catch {
    return trimmed
  }
}

export function extractIdFromSlug(slug: string): string {
  const normalized = normalizeSlugInput(slug)
  if (!normalized) return ''

  // Default slug format is "title-part-id", where id is the last segment.
  const lastSegment = normalized.split('-').pop()?.trim() || ''
  if (lastSegment) return lastSegment

  return normalized
}

export function extractCandidateIdsFromSlug(slug: string): string[] {
  const normalized = normalizeSlugInput(slug)
  if (!normalized) return []

  const ids = new Set<string>()
  const pushSafe = (value?: string | null) => {
    if (!value) return
    const v = value.trim()
    if (!v) return
    const lower = v.toLowerCase()
    if (lower === 'undefined' || lower === 'null' || lower === 'nan') return
    ids.add(v)
  }

  pushSafe(extractIdFromSlug(normalized))

  // Try every trailing suffix after "-" so IDs with embedded hyphens can resolve.
  // Example: "title-part-id-with-hyphen" => tries:
  // "part-id-with-hyphen", "id-with-hyphen", "with-hyphen", "hyphen".
  const segments = normalized.split('-').filter(Boolean)
  for (let i = 1; i < segments.length; i += 1) {
    pushSafe(segments.slice(i).join('-'))
  }

  // Accept variable-length alphanumeric candidates.
  const dynamicIdMatches = normalized.match(/[a-z0-9]{6,4096}/gi) || []
  dynamicIdMatches.forEach((value) => pushSafe(value))

  const uuidMatches =
    normalized.match(/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/gi) || []
  uuidMatches.forEach((value) => pushSafe(value))

  pushSafe(normalized)

  return Array.from(ids)
}
