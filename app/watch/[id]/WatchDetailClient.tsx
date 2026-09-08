'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { VideoDetailScreen } from '../../../VideoDetailScreen'
import { ImageDetailScreen } from '../../../ImageDetailScreen'
import { Post } from '../../../types'
import appwriteService from '../../../appwriteService'
import { extractCandidateIdsFromSlug } from '../../../lib/slug'
import { hasVerifiedBadge } from '../../../lib/verification'
import { cacheRoutePost, getCachedRoutePost } from '../../../lib/route-post-cache'

interface WatchDetailClientProps {
  initialPost?: Post | null
  slugId: string
}

export default function WatchDetailClient({ initialPost = null, slugId }: WatchDetailClientProps) {
  const [resolvedSlugId, setResolvedSlugId] = useState(slugId)
  const [post, setPost] = useState<Post | null>(() => initialPost || getCachedRoutePost(slugId))
  const [error, setError] = useState<string | null>(null)
  const router = useRouter()

  useEffect(() => {
    if (resolvedSlugId) return
    if (typeof window === 'undefined') return

    const match = window.location.pathname.match(/\/watch\/([^/?#]+)/i)
    const fromPath = match?.[1]?.trim()
    if (fromPath) {
      setResolvedSlugId(fromPath)
    }
  }, [resolvedSlugId])

  useEffect(() => {
    const activeSlugId = resolvedSlugId || slugId

    if (initialPost) {
      setPost(initialPost)
      setError(null)
      return
    }

    const cachedPost = getCachedRoutePost(activeSlugId)
    if (cachedPost) {
      setPost(cachedPost)
      setError(null)
      return
    }

    let active = true
    const loadPost = async () => {
      try {
        const candidateIds = extractCandidateIdsFromSlug(activeSlugId)
        if (candidateIds.length === 0) {
          throw new Error(`No candidate IDs resolved for slug: ${activeSlugId}`)
        }
        let postData: any = null

        for (const candidateId of candidateIds) {
          try {
            postData = await appwriteService.getPost(candidateId)
            if (postData) break
          } catch {
            // Try next candidate
          }
        }

        if (!postData) {
          throw new Error(`Post lookup failed for slug: ${activeSlugId}`)
        }

        const postDocId = String(postData.$id || postData.id || '').trim()
        let profile: any = null
        try {
          profile = postData.userId
            ? await appwriteService.getProfileByUserId(postData.userId)
            : null
        } catch {
          profile = null
        }

        const user = await appwriteService.getCurrentUser()
        let interactions: [boolean, boolean, boolean] = [false, false, false]
        if (user && postDocId) {
          try {
            interactions = await Promise.all([
              appwriteService.isPostLikedBy(user.$id, postDocId),
              appwriteService.isPostSavedBy(user.$id, postDocId),
              appwriteService.isPostRepostedBy(user.$id, postDocId),
            ])
          } catch {
            interactions = [false, false, false]
          }
        }

        const enrichedPost = {
          ...postData,
          id: postDocId || postData.postId || '',
          postId: postData.postId || postDocId,
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
          thumbnailUrl: postData.thumbnailUrl || '',
          mediaUrls: Array.isArray(postData.mediaUrls)
            ? postData.mediaUrls
            : typeof postData.mediaUrls === 'string' && postData.mediaUrls
              ? [postData.mediaUrls]
              : (postData.videoUrl
                  ? [postData.videoUrl]
                  : (postData.mediaUrl
                      ? [postData.mediaUrl]
                      : (postData.mediaURl ? [postData.mediaURl] : []))),
          timestamp: new Date(postData.$createdAt || postData.createdAt),
          createdAt: postData.$createdAt || postData.createdAt,
          likes: postData.likes || 0,
          comments: postData.comments || 0,
          reposts: postData.reposts || 0,
          shares: postData.shares || 0,
          impressions: postData.impressions || 0,
          views: postData.views || 0,
          isLiked: interactions[0],
          isSaved: interactions[1],
          isReposted: interactions[2],
          isBoosted: postData.isBoosted || false,
          activeBoostId: postData.activeBoostId || '',
        } as Post

        if (active) {
          setPost(enrichedPost)
          setError(null)
          cacheRoutePost(activeSlugId, enrichedPost)
        }
      } catch (loadError) {
        console.error('Watch detail fallback load failed:', loadError)
        if (active) {
          const cached = getCachedRoutePost(activeSlugId)
          if (cached) {
            setPost(cached)
            setError(null)
          } else {
            setError('Video not found or access denied.')
          }
        }
      }
    }

    void loadPost()
    return () => {
      active = false
    }
  }, [initialPost, resolvedSlugId, slugId])

  useEffect(() => {
    if (!post?.id) return
    let active = true

    const loadViewerInteractions = async () => {
      try {
        const user = await appwriteService.getCurrentUser()
        if (!user || !active) return

        const [isLiked, isSaved, isReposted] = await Promise.all([
          appwriteService.isPostLikedBy(user.$id, post.id),
          appwriteService.isPostSavedBy(user.$id, post.id),
          appwriteService.isPostRepostedBy(user.$id, post.id),
        ])

        if (!active) return
        setPost((prev) => (prev ? { ...prev, isLiked, isSaved, isReposted } : prev))
      } catch {
        // Keep initial interaction flags if user state fails to resolve.
      }
    }

    void loadViewerInteractions()

    return () => {
      active = false
    }
  }, [post?.id])

  if (error) {
    return (
      <div className="min-h-screen bg-black flex items-center justify-center">
        <div className="text-white text-center">
          <p className="text-xl mb-4">{error}</p>
          <button
            onClick={() => router.back()}
            className="px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600"
          >
            Go Back
          </button>
        </div>
      </div>
    )
  }

  if (!post) {
    return (
      <div className="min-h-screen bg-black flex items-center justify-center">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-white" />
      </div>
    )
  }

  if (post.postType === 'image') {
    return <ImageDetailScreen post={post} onClose={() => router.back()} />
  }

  return <VideoDetailScreen post={post} onClose={() => router.back()} />
}
