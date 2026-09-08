'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { ReelsDetailScreen } from '../../../VideoDetailScreen'
import { Post } from '../../../types'
import appwriteService from '../../../appwriteService'
import { extractCandidateIdsFromSlug } from '../../../lib/slug'
import { hasVerifiedBadge } from '../../../lib/verification'

interface ReelDetailClientProps {
  initialPost?: Post | null
  slugId: string
}

export default function ReelDetailClient({ initialPost = null, slugId }: ReelDetailClientProps) {
  const [resolvedSlugId, setResolvedSlugId] = useState(slugId)
  const [post, setPost] = useState<Post | null>(initialPost)
  const [error, setError] = useState<string | null>(null)
  const router = useRouter()

  useEffect(() => {
    if (resolvedSlugId) return
    if (typeof window === 'undefined') return

    const match = window.location.pathname.match(/\/reels\/([^/?#]+)/i)
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
          postType: postData.postType || 'reel',
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
          isReposted: interactions[1],
          isSaved: interactions[2],
          isBoosted: postData.isBoosted || false,
          activeBoostId: postData.activeBoostId || '',
        } as Post

        if (active) {
          setPost(enrichedPost)
          setError(null)
        }
      } catch (loadError) {
        console.error('Reel detail fallback load failed:', loadError)
        if (active) {
          setError('Failed to load reel.')
        }
      }
    }

    void loadPost()
    return () => {
      active = false
    }
  }, [initialPost, resolvedSlugId, slugId])

  useEffect(() => {
    if (!initialPost) return
    let active = true

    const loadViewerInteractions = async () => {
      try {
        const user = await appwriteService.getCurrentUser()
        if (!user || !active) return

        const [isLiked, isSaved, isReposted] = await Promise.all([
          appwriteService.isPostLikedBy(user.$id, initialPost.id),
          appwriteService.isPostSavedBy(user.$id, initialPost.id),
          appwriteService.isPostRepostedBy(user.$id, initialPost.id),
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
  }, [initialPost])

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

  return <ReelsDetailScreen post={post} onClose={() => router.back()} />
}
