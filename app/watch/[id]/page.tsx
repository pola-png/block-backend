import appwriteService from '../../../appwriteService'
import { Post } from '../../../types'
import { extractCandidateIdsFromSlug, extractIdFromSlug } from '../../../lib/slug'
import { generateVideoStructuredData } from '../../../lib/structured-data'
import { hasVerifiedBadge } from '../../../lib/verification'
import { toWasabiProxyPath, toWasabiVideoProxyPath } from '../../../lib/wasabi'
import WatchDetailClient from './WatchDetailClient'

export const dynamic = 'force-dynamic'

const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL || 'https://xapzap.com'

function toImageProxyUrl(url?: string): string {
  if (!url) return ''
  const resolved = toWasabiProxyPath(url) || url
  if (resolved.startsWith('http')) return resolved
  if (resolved.startsWith('/')) return `${SITE_URL}${resolved}`
  return `${SITE_URL}/${resolved}`
}

function toVideoProxyUrl(url?: string): string {
  if (!url) return ''
  const resolved = toWasabiVideoProxyPath(url) || url
  if (resolved.startsWith('http')) return resolved
  if (resolved.startsWith('/')) return `${SITE_URL}${resolved}`
  return `${SITE_URL}/${resolved}`
}

function normalizeMediaUrls(postData: any): string[] {
  if (Array.isArray(postData.mediaUrls)) {
    return postData.mediaUrls.filter((url: unknown) => typeof url === 'string' && url.length > 0)
  }

  if (typeof postData.mediaUrls === 'string' && postData.mediaUrls.length > 0) {
    try {
      const parsed = JSON.parse(postData.mediaUrls)
      if (Array.isArray(parsed)) {
        return parsed.filter((url: unknown) => typeof url === 'string' && url.length > 0)
      }
      return [postData.mediaUrls]
    } catch {
      return [postData.mediaUrls]
    }
  }

  if (typeof postData.videoUrl === 'string' && postData.videoUrl.length > 0) {
    return [postData.videoUrl]
  }

  if (typeof postData.mediaUrl === 'string' && postData.mediaUrl.length > 0) {
    return [postData.mediaUrl]
  }

  // Some legacy records use this typo key.
  if (typeof postData.mediaURl === 'string' && postData.mediaURl.length > 0) {
    return [postData.mediaURl]
  }

  return []
}

function buildInitialPost(postData: any, profile: any): Post {
  const mediaUrls = normalizeMediaUrls(postData)

  return {
    ...postData,
    id: postData.$id,
    postId: postData.postId || postData.$id,
    userId: postData.userId || '',
    username: postData.username || 'User',
    userAvatar: postData.userAvatar || '',
    displayName: profile?.displayName || 'User',
    avatarUrl: profile?.avatarUrl || '',
    isVerified: hasVerifiedBadge(profile || postData),
    content: postData.content || '',
    postType: postData.postType || 'video',
    title: postData.title || '',
    caption: postData.caption || '',
    thumbnailUrl: toImageProxyUrl(postData.thumbnailUrl || ''),
    mediaUrls: mediaUrls.map((url) => postData.postType === 'image' ? toImageProxyUrl(url) : toVideoProxyUrl(url)),
    timestamp: new Date(postData.$createdAt || postData.createdAt || new Date().toISOString()),
    createdAt: postData.$createdAt || postData.createdAt || new Date().toISOString(),
    likes: postData.likes || 0,
    comments: postData.comments || 0,
    reposts: postData.reposts || 0,
    shares: postData.shares || 0,
    impressions: postData.impressions || 0,
    views: postData.views || 0,
    isLiked: false,
    isReposted: false,
    isSaved: false,
    sourcePostId: postData.sourcePostId,
    sourceUserId: postData.sourceUserId,
    sourceUsername: postData.sourceUsername,
    textBgColor: postData.textBgColor,
    isBoosted: postData.isBoosted || false,
    activeBoostId: postData.activeBoostId || '',
  }
}

type WatchDetailPageProps = {
  params: { id?: string | string[] } | Promise<{ id?: string | string[] }>
}

function normalizeRouteId(value: unknown): string | null {
  const raw = Array.isArray(value) ? value[0] : value
  if (typeof raw !== 'string') return null
  const normalized = raw.trim()
  if (!normalized) return null
  if (normalized === 'undefined' || normalized === 'null' || normalized === 'nan') return null
  return normalized
}

export default async function WatchDetailPage({ params }: WatchDetailPageProps) {
  const resolvedParams = await params
  const slugId = normalizeRouteId(resolvedParams?.id) || ''
  const postId = normalizeRouteId(extractIdFromSlug(slugId))
  const candidateIds = extractCandidateIdsFromSlug(slugId)
    .map((id) => normalizeRouteId(id))
    .filter((id): id is string => Boolean(id))

  if (!slugId || (!postId && candidateIds.length === 0)) {
    return <WatchDetailClient initialPost={null} slugId={slugId || ''} />
  }

  try {
    let postData: any = null

    for (const candidateId of candidateIds.length > 0 ? candidateIds : [postId as string]) {
      try {
        postData = await appwriteService.getPost(candidateId)
        if (postData) break
      } catch {
        // Try next candidate
      }
    }

    if (!postData || typeof postData !== 'object') {
      return <WatchDetailClient initialPost={null} slugId={slugId} />
    }

    const safeUserId = normalizeRouteId(postData.userId)
    const profile = safeUserId
      ? await appwriteService.getProfileByUserId(safeUserId)
      : null
    const initialPost = buildInitialPost(postData, profile)
    const videoUrl = initialPost.mediaUrls[0] || ''
    let structuredData: Record<string, unknown> | null = null
    try {
      structuredData = generateVideoStructuredData(initialPost)
    } catch (error) {
      console.error('Watch structured data generation failed:', error)
    }

    return (
      <>
        {structuredData && (
          <script
            type="application/ld+json"
            dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData) }}
          />
        )}
        {videoUrl ? (
          <div className="sr-only" aria-hidden="true">
            <video
              preload="metadata"
              controls
              poster={initialPost.thumbnailUrl || undefined}
            >
              <source src={videoUrl} />
            </video>
          </div>
        ) : null}
        <WatchDetailClient initialPost={initialPost} slugId={slugId} />
      </>
    )
  } catch (error) {
    console.error('Watch page data load failed:', error)
    return <WatchDetailClient initialPost={null} slugId={slugId} />
  }
}
