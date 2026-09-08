import { Metadata } from 'next'
import appwriteService from '../../../appwriteService'
import { extractCandidateIdsFromSlug, extractIdFromSlug } from '../../../lib/slug'

export const dynamic = 'force-dynamic'

type Props = {
  params: { id?: string | string[] } | Promise<{ id?: string | string[] }>
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  try {
    const resolvedParams = await params
    const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || 'https://xapzap.com'
    const toImageAbsoluteUrl = (value?: string) => {
      if (!value) return ''
      if (value.startsWith('http')) return value
      if (value.startsWith('/media/')) return `${siteUrl}/api/image-proxy?path=${value.substring(1)}`
      if (value.startsWith('/')) return `${siteUrl}${value}`
      return `${siteUrl}/${value}`
    }

    const toVideoAbsoluteUrl = (value?: string) => {
      if (!value) return ''
      if (value.startsWith('http')) return value
      if (value.startsWith('/media/')) return `${siteUrl}/api/video-proxy?path=${value.substring(1)}`
      if (value.startsWith('/')) return `${siteUrl}${value}`
      return `${siteUrl}/${value}`
    }

    const normalizeRouteId = (value: unknown): string | null => {
      const raw = Array.isArray(value) ? value[0] : value
      if (typeof raw !== 'string') return null
      const normalized = raw.trim()
      if (!normalized) return null
      if (normalized === 'undefined' || normalized === 'null' || normalized === 'nan') return null
      return normalized
    }

    const slugId = normalizeRouteId(resolvedParams?.id) || ''
    const postId = normalizeRouteId(extractIdFromSlug(slugId))
    const candidateIds = extractCandidateIdsFromSlug(slugId)
      .map((id) => normalizeRouteId(id))
      .filter((id): id is string => Boolean(id))

    let post: any = null
    for (const candidateId of candidateIds.length > 0 ? candidateIds : [postId as string]) {
      try {
        post = await appwriteService.getPost(candidateId)
        if (post) break
      } catch {
        // Try next candidate
      }
    }
    if (!post) throw new Error('Post not found')

    const profile = post.userId ? await appwriteService.getProfileByUserId(post.userId) : null
    const baseTitle = post.seoTitle || post.title || post.caption || 'Reel'
    const title = `${baseTitle} by ${profile?.displayName || 'User'}`
    const description =
      post.seoDescription ||
      post.caption ||
      `Watch ${profile?.displayName || 'User'}'s reel on XapZap. ${post.views || 0} views, ${post.likes || 0} likes.`
    const thumbnailUrl = toImageAbsoluteUrl(post.thumbnailUrl || '/og-image.jpg')
    const videoUrl = toVideoAbsoluteUrl(post.mediaUrl || (post.mediaUrls && post.mediaUrls[0]) || '')
    const url = `${siteUrl}/reels/${slugId}`

    return {
      title,
      description,
      keywords: post.seoKeywords || `reel, short video, ${profile?.displayName}, xapzap, ${post.caption || ''}`,
      authors: [{ name: profile?.displayName || 'XapZap User' }],
      openGraph: {
        title,
        description,
        url,
        siteName: 'XapZap',
        images: [
          {
            url: thumbnailUrl,
            width: 1080,
            height: 1920,
            alt: title,
          },
        ],
        locale: 'en_US',
        type: 'video.other',
        videos: [
          {
            url: videoUrl,
            width: 1080,
            height: 1920,
          },
        ],
      },
      twitter: {
        card: 'player',
        title,
        description,
        images: [thumbnailUrl],
        players: {
          playerUrl: url,
          streamUrl: videoUrl,
          width: 1080,
          height: 1920,
        },
      },
      alternates: {
        canonical: url,
      },
      robots: post.isSeoIndexable === false
        ? {
            index: false,
            follow: false,
          }
        : {
            index: true,
            follow: true,
            'max-video-preview': -1,
            'max-image-preview': 'large',
          },
    }
  } catch (error) {
    return {
      title: 'Reel | XapZap',
      description: 'Watch reels on XapZap',
    }
  }
}
