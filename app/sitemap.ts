import { MetadataRoute } from 'next'
import appwriteService from '../appwriteService'
import { generateSlug } from '../lib/slug'

export const dynamic = 'force-dynamic'
export const revalidate = 3600 // Revalidate at most every hour

const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL || 'https://xapzap.com'

function toAbsoluteImageUrl(value?: string): string {
  if (!value) return `${SITE_URL}/og-image.jpg`
  if (value.startsWith('http')) return value
  if (value.startsWith('/media/')) return `${SITE_URL}/api/image-proxy?path=${value.substring(1)}`
  if (value.startsWith('/')) return `${SITE_URL}${value}`
  return `${SITE_URL}/${value}`
}

function toAbsoluteVideoUrl(value?: string): string {
  if (!value) return ''
  if (value.startsWith('http')) return value
  if (value.startsWith('/media/')) return `${SITE_URL}/api/video-proxy?path=${value.substring(1)}`
  if (value.startsWith('/')) return `${SITE_URL}${value}`
  return `${SITE_URL}/${value}`
}

function getPrimaryVideoUrl(post: any): string {
  if (typeof post.mediaUrl === 'string' && post.mediaUrl.length > 0) return post.mediaUrl
  if (typeof post.videoUrl === 'string' && post.videoUrl.length > 0) return post.videoUrl
  if (typeof post.mediaURl === 'string' && post.mediaURl.length > 0) return post.mediaURl
  if (Array.isArray(post.mediaUrls) && typeof post.mediaUrls[0] === 'string') return post.mediaUrls[0]
  return ''
}

function normalizeText(value: unknown, fallback: string): string {
  if (typeof value !== 'string') return fallback
  const normalized = value.replace(/\s+/g, ' ').trim()
  return normalized || fallback
}

function getDurationSeconds(post: any): number | undefined {
  const rawDurationMs = post.durationMs
  if (rawDurationMs === null || rawDurationMs === undefined) return undefined
  const durationMs = Number(rawDurationMs)
  if (!Number.isFinite(durationMs) || durationMs <= 0) return undefined
  return Math.max(1, Math.floor(durationMs / 1000))
}

function escapeXml(unsafe: string): string {
  return unsafe
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;')
}

function createVideoSitemapEntry(
  post: any,
  pathPrefix: '/watch' | '/reels',
  slug: string,
): MetadataRoute.Sitemap[number] {
  const pageUrl = `${SITE_URL}${pathPrefix}/${slug}`
  const thumbnailUrl = toAbsoluteImageUrl(post.thumbnailUrl)
  const videoUrl = toAbsoluteVideoUrl(getPrimaryVideoUrl(post))
  const title = normalizeText(post.seoTitle || post.title || post.caption, pathPrefix === '/reels' ? 'XapZap Reel' : 'XapZap Video')
  const description = normalizeText(
    post.seoDescription || post.content || post.caption,
    pathPrefix === '/reels' ? 'Watch this reel on XapZap.' : 'Watch this video on XapZap.',
  )
  const duration = getDurationSeconds(post)

  return {
    url: pageUrl,
    lastModified: new Date(post.$updatedAt || post.$createdAt),
    changeFrequency: 'weekly',
    priority: 1.0,
    videos: videoUrl
      ? [
          {
            title: escapeXml(title),
            description: escapeXml(description),
            thumbnail_loc: escapeXml(thumbnailUrl),
            content_loc: escapeXml(videoUrl),
            publication_date: new Date(post.$createdAt || post.createdAt || post.$updatedAt || Date.now()).toISOString(),
            family_friendly: 'yes',
            live: 'no',
            ...(duration ? { duration } : {}),
          },
        ]
      : undefined,
  }
}

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  // Static routes with high priority
  const routes = [
    { url: `${SITE_URL}`, priority: 1.0, changeFrequency: 'hourly' as const },
    { url: `${SITE_URL}/for-you`, priority: 1.0, changeFrequency: 'hourly' as const },
    { url: `${SITE_URL}/watch`, priority: 1.0, changeFrequency: 'hourly' as const },
    { url: `${SITE_URL}/reels`, priority: 1.0, changeFrequency: 'hourly' as const },
    { url: `${SITE_URL}/news`, priority: 1.0, changeFrequency: 'hourly' as const },
    { url: `${SITE_URL}/jobs`, priority: 0.9, changeFrequency: 'daily' as const },
    { url: `${SITE_URL}/chinese-drama-movies`, priority: 1.0, changeFrequency: 'daily' as const },
    { url: `${SITE_URL}/about`, priority: 0.8, changeFrequency: 'monthly' as const },
    { url: `${SITE_URL}/premium`, priority: 0.8, changeFrequency: 'weekly' as const },
    { url: `${SITE_URL}/monetization`, priority: 0.8, changeFrequency: 'weekly' as const },
    { url: `${SITE_URL}/following`, priority: 0.8, changeFrequency: 'hourly' as const },
    { url: `${SITE_URL}/live`, priority: 0.9, changeFrequency: 'always' as const },
    { url: `${SITE_URL}/search`, priority: 0.7, changeFrequency: 'daily' as const },
    { url: `${SITE_URL}/auth/signin`, priority: 0.5, changeFrequency: 'monthly' as const },
    { url: `${SITE_URL}/auth/signup`, priority: 0.5, changeFrequency: 'monthly' as const },
  ].map((route) => ({
    ...route,
    lastModified: new Date(),
  }))

  // Dynamic content - fetch ALL posts (Next.js will handle pagination automatically)
  try {
    const allUrls: MetadataRoute.Sitemap = [...routes]

    // Fetch videos in batches
    let videoCursor: string | undefined
    let videoCount = 0
    const maxVideos = 50000 // Per sitemap file limit

    while (videoCount < maxVideos) {
      const videos = await appwriteService.fetchWatchFeed(500, videoCursor)
      if (videos.documents.length === 0) break

      videos.documents.forEach((post: any) => {
        if (post.isSeoIndexable === false) {
          return
        }
        const slug = post.slug || generateSlug(post.caption || post.title || 'video', post.$id)
        allUrls.push(createVideoSitemapEntry(post, '/watch', slug))
      })

      videoCount += videos.documents.length
      if (videos.documents.length < 500) break
      videoCursor = videos.documents[videos.documents.length - 1].$id
    }

    // Fetch reels in batches
    let reelsCursor: string | undefined
    let reelsCount = 0
    const maxReels = 50000

    while (reelsCount < maxReels) {
      const reels = await appwriteService.fetchReelsFeed(500, reelsCursor)
      if (reels.documents.length === 0) break

      reels.documents.forEach((post: any) => {
        if (post.isSeoIndexable === false) {
          return
        }
        const slug = post.slug || generateSlug(post.caption || 'reel', post.$id)
        allUrls.push(createVideoSitemapEntry(post, '/reels', slug))
      })

      reelsCount += reels.documents.length
      if (reels.documents.length < 500) break
      reelsCursor = reels.documents[reels.documents.length - 1].$id
    }

    // Fetch news articles in batches
    let newsCursor: string | undefined
    let newsCount = 0
    const maxNews = 50000

    while (newsCount < maxNews) {
      const news = await appwriteService.fetchNewsArticles(500, newsCursor)
      if (news.documents.length === 0) break

      news.documents.forEach((post: any) => {
        if (post.isSeoIndexable === false) {
          return
        }
        const imageUrl = post.thumbnailUr || post.thumbnailUrl || '';
        const slug = generateSlug(post.title || post.caption || 'news', post.$id)
        allUrls.push({
          url: `${SITE_URL}/news/${slug}`,
          lastModified: new Date(post.$updatedAt || post.$createdAt),
          changeFrequency: 'daily',
          priority: 1.0,
          images: imageUrl ? [escapeXml(imageUrl)] : undefined,
          news: {
            title: escapeXml(post.title || 'News Update'),
            publication: {
              name: 'XapZap News',
              language: 'en',
            },
            publication_date: new Date(post.$createdAt || post.createdAt || Date.now()).toISOString(),
          }
        } as any)
      })

      newsCount += news.documents.length
      if (news.documents.length < 500) break
      newsCursor = news.documents[news.documents.length - 1].$id
    }

    console.log(`Sitemap generated: ${routes.length} static + ${videoCount} videos + ${reelsCount} reels + ${newsCount} news = ${allUrls.length} total URLs`)
    return allUrls
  } catch (error) {
    console.error('Sitemap generation error:', error)
    return routes
  }
}
