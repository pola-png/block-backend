'use client'

import { useState, useEffect, useRef } from 'react'
import { useRouter } from 'next/navigation'
import { Heart, MessageCircle, Repeat2, Share, Bookmark, MoreHorizontal, BarChart2, Play, ArrowLeft, ChevronLeft, ChevronRight } from 'lucide-react'
import { Post } from './types'
import appwriteService from './appwriteService'
import { OptimizedImage } from './components/OptimizedImage'
import { normalizeWasabiImageArray, normalizeWasabiImage, normalizeWasabiVideo } from './lib/wasabi'
import { feedCache } from './lib/cache'
import { generateSlug } from './lib/slug'
import { parseHashtags } from './lib/hashtag'
import { formatCount, formatTimeAgo } from './utils'
import { CommentModal } from './CommentModal'
import { CommentScreen } from './CommentScreen'
import { ReelsDetailScreen } from './VideoDetailScreen'
import { VerifiedBadge } from './components/VerifiedBadge'
import { hasVerifiedBadge, isPremiumBadge } from './lib/verification'
import { cacheRoutePost } from './lib/route-post-cache'

interface PostCardProps {
  post: Post
  isGuest?: boolean
  onGuestAction?: () => void
  currentUserId?: string
  feedType?: 'home' | 'watch' | 'following' | 'news' | 'reels' | 'detail'
  onVideoClick?: (post: Post) => void
  onCommentClick?: () => void
}

export const PostCard = ({ post, currentUserId: propCurrentUserId, feedType = 'home', onVideoClick, onCommentClick }: PostCardProps) => {
  const router = useRouter()
  const resolvedPostId = (post as any).$id || post.id || post.postId || ''

  const buildVideoSlug = () => generateSlug(post.title || post.content || 'video', resolvedPostId)

  const cacheWatchRoutePost = (slug: string) => {
    if (!slug || !resolvedPostId) return
    const timestampValue =
      post.timestamp instanceof Date
        ? post.timestamp
        : new Date((post.timestamp as unknown as string) || post.createdAt || Date.now())

    cacheRoutePost(slug, {
      ...post,
      id: resolvedPostId,
      postId: post.postId || resolvedPostId,
      timestamp: timestampValue,
      mediaUrls: Array.isArray(post.mediaUrls) ? post.mediaUrls : [],
      createdAt: post.createdAt || new Date().toISOString(),
    })
  }

  const navigateToVideoDetail = () => {
    if (!resolvedPostId) return
    const slug = buildVideoSlug()
    cacheWatchRoutePost(slug)
    if (onVideoClick) {
      onVideoClick({ ...post, id: resolvedPostId, postId: post.postId || resolvedPostId })
      return
    }
    router.push(`/watch/${slug}`)
  }

  const [liked, setLiked] = useState(post.isLiked || false)
  const [likes, setLikes] = useState(post.likes || 0)
  const [saved, setSaved] = useState(post.isSaved || false)
  const [reposted, setReposted] = useState(post.isReposted || false)
  const [reposts, setReposts] = useState(post.reposts || 0)
  const [userProfile, setUserProfile] = useState<any>(
    post.displayName ? { displayName: post.displayName, avatarUrl: post.avatarUrl, isVerified: (post as any).isVerified } : null
  )
  const [showComments, setShowComments] = useState(false)
  const [showFullComments, setShowFullComments] = useState(false)
  const [showReelDetail, setShowReelDetail] = useState(false)
  const [showFullPost, setShowFullPost] = useState(false)
  const [showMenu, setShowMenu] = useState(false)
  const [currentUserId, setCurrentUserId] = useState<string | null>(propCurrentUserId || null)
  const [isFollowing, setIsFollowing] = useState<boolean | null>(null)
  const [shouldLoadMedia, setShouldLoadMedia] = useState(false)
  const [expandedText, setExpandedText] = useState(false)
  const [currentImageIndex, setCurrentImageIndex] = useState(0)
  const [touchStartX, setTouchStartX] = useState(0)
  const mediaRef = useRef<HTMLDivElement>(null)
  const reelDetailHistoryActiveRef = useRef(false)
  const fullPostHistoryActiveRef = useRef(false)
  const commentsHistoryActiveRef = useRef(false)
  const fullCommentsHistoryActiveRef = useRef(false)
  const ignoreNextOverlayPopStateRef = useRef(false)

  useEffect(() => {
    const hasOpenOverlay = showReelDetail || showFullPost || showFullComments || showComments

    if (!hasOpenOverlay) {
      return
    }

    const scrollY = window.scrollY
    const previousOverflow = document.body.style.overflow
    const previousPosition = document.body.style.position
    const previousTop = document.body.style.top
    const previousWidth = document.body.style.width
    document.body.style.overflow = 'hidden'
    document.body.style.position = 'fixed'
    document.body.style.top = `-${scrollY}px`
    document.body.style.width = '100%'

    return () => {
      document.body.style.overflow = previousOverflow
      document.body.style.position = previousPosition
      document.body.style.top = previousTop
      document.body.style.width = previousWidth
      window.scrollTo(0, scrollY)
    }
  }, [showReelDetail, showFullPost, showFullComments, showComments])

  useEffect(() => {
    const handleOverlayPopState = () => {
      if (ignoreNextOverlayPopStateRef.current) {
        ignoreNextOverlayPopStateRef.current = false
        return
      }

      if (fullCommentsHistoryActiveRef.current && showFullComments) {
        fullCommentsHistoryActiveRef.current = false
        setShowFullComments(false)
        return
      }

      if (commentsHistoryActiveRef.current && showComments) {
        commentsHistoryActiveRef.current = false
        setShowComments(false)
        return
      }

      if (reelDetailHistoryActiveRef.current && showReelDetail) {
        reelDetailHistoryActiveRef.current = false
        setShowReelDetail(false)
        return
      }

      if (fullPostHistoryActiveRef.current && showFullPost) {
        fullPostHistoryActiveRef.current = false
        setShowFullPost(false)
      }
    }

    window.addEventListener('popstate', handleOverlayPopState)
    return () => window.removeEventListener('popstate', handleOverlayPopState)
  }, [showReelDetail, showFullPost, showFullComments, showComments])

  const pushOverlayHistoryState = (stateKey: string) => {
    window.history.pushState({ ...(window.history.state || {}), [stateKey]: true }, '', window.location.href)
  }

  const consumeOverlayHistoryState = (isHistoryActiveRef: { current: boolean }) => {
    if (!isHistoryActiveRef.current) return
    isHistoryActiveRef.current = false
    ignoreNextOverlayPopStateRef.current = true
    window.history.back()
  }

  const openReelDetail = () => {
    if (!reelDetailHistoryActiveRef.current) {
      pushOverlayHistoryState('xapzapReelDetail')
      reelDetailHistoryActiveRef.current = true
    }
    setShowReelDetail(true)
  }

  const closeReelDetail = () => {
    setShowReelDetail(false)
    consumeOverlayHistoryState(reelDetailHistoryActiveRef)
  }

  const openFullPost = () => {
    if (!fullPostHistoryActiveRef.current) {
      pushOverlayHistoryState('xapzapFullPost')
      fullPostHistoryActiveRef.current = true
    }
    setShowFullPost(true)
  }

  const closeFullPost = () => {
    setShowFullPost(false)
    consumeOverlayHistoryState(fullPostHistoryActiveRef)
  }

  const openComments = () => {
    if (!commentsHistoryActiveRef.current) {
      pushOverlayHistoryState('xapzapCommentModal')
      commentsHistoryActiveRef.current = true
    }
    setShowComments(true)
    
    const logCommentEvent = async () => {
      const user = await appwriteService.getCurrentUser()
      if (user && post.userId) {
        await appwriteService.logFeedEvent({
          userId: user.$id,
          postId: post.id,
          creatorId: post.userId,
          feed: feedType === 'detail' ? 'home' : feedType,
          eventType: 'comment',
          position: 0
        })
      }
    }
    logCommentEvent()
  }

  const closeComments = () => {
    setShowComments(false)
    consumeOverlayHistoryState(commentsHistoryActiveRef)
  }

  const closeFullComments = () => {
    setShowFullComments(false)
    consumeOverlayHistoryState(fullCommentsHistoryActiveRef)
  }

  useEffect(() => {
    if (!showFullComments || fullCommentsHistoryActiveRef.current) return
    pushOverlayHistoryState('xapzapFullComments')
    fullCommentsHistoryActiveRef.current = true
  }, [showFullComments])

  // Check if current user has liked/saved/reposted - skip if already in post data
  useEffect(() => {
    const loadUser = async () => {
      const user = await appwriteService.getCurrentUser()
      setCurrentUserId(user?.$id || null)
      if (user && post.userId && user.$id !== post.userId) {
        const following = await appwriteService.isFollowing(user.$id, post.userId)
        setIsFollowing(following)
      }
    }
    loadUser()
  }, [])

  useEffect(() => {
    if (!mediaRef.current) return
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setShouldLoadMedia(true)
          observer.disconnect()
        }
      },
      { rootMargin: '100px' }
    )
    observer.observe(mediaRef.current)
    return () => observer.disconnect()
  }, [])

  useEffect(() => {
    if (post.isLiked !== undefined) return // Already have interaction data
    
    const checkUserInteractions = async () => {
      const user = await appwriteService.getCurrentUser()
      if (!user) return

      // Check cache first
      const cached = feedCache.getInteraction(post.id, user.$id)
      if (cached) {
        setLiked(cached.liked)
        setSaved(cached.saved)
        setReposted(cached.reposted)
        return
      }

      const [isLiked, isSaved, isReposted] = await Promise.all([
        appwriteService.isPostLikedBy(user.$id, post.id),
        appwriteService.isPostSavedBy(user.$id, post.id),
        appwriteService.isPostRepostedBy(user.$id, post.id)
      ])

      setLiked(isLiked)
      setSaved(isSaved)
      setReposted(isReposted)
      
      // Cache the result
      feedCache.setInteraction(post.id, user.$id, { liked: isLiked, saved: isSaved, reposted: isReposted })
    }

    checkUserInteractions()
  }, [post.id, post.isLiked])

  // Fetch user profile data - skip if already in post data
  useEffect(() => {
    if (post.displayName) return // Already have profile data
    
    const fetchUserProfile = async () => {
      if (!post.userId) return

      // Check cache first
      const cached = feedCache.getProfile(post.userId)
      if (cached) {
        setUserProfile(cached)
        return
      }

      try {
        const profile = await appwriteService.getProfileByUserId(post.userId)
        setUserProfile(profile)
        feedCache.setProfile(post.userId, profile)
      } catch (error) {
        console.error('Failed to fetch user profile:', error)
      }
    }

    fetchUserProfile()
  }, [post.userId, post.displayName])

  // Track impression when post is viewed (only once)
  useEffect(() => {
    let tracked = false
    const trackImpression = async () => {
      if (tracked) return
      tracked = true
      try {
        await appwriteService.incrementPostField(post.id, 'impressions', 1)
        
        const user = await appwriteService.getCurrentUser()
        if (user && post.userId) {
          await appwriteService.logFeedEvent({
            userId: user.$id,
            postId: post.id,
            creatorId: post.userId,
            feed: feedType === 'detail' ? 'home' : feedType,
            eventType: 'impression',
            position: 0
          })
        }
      } catch (error) {
        console.error('Failed to track impression:', error)
      }
    }

    const timer = setTimeout(trackImpression, 1000)
    return () => clearTimeout(timer)
  }, [post.id, post.userId, feedType])

  // Subscribe to realtime updates for this post
  useEffect(() => {
    if (!post.id) return

    const unsubscribe = appwriteService.subscribeToDocument('posts', post.id, (payload) => {
      if (payload.events.includes('databases.*.collections.posts.documents.*.update')) {
        const updatedPost = payload.payload
        setLikes(updatedPost.likes || 0)
        setReposts(updatedPost.reposts || 0)
      }
    })

    return unsubscribe
  }, [post.id])

  const handleLike = async () => {
    const currentUser = await appwriteService.getCurrentUser()
    if (!currentUser) return

    const wasLiked = liked
    const prevLikes = likes

    setLiked(!wasLiked)
    setLikes(wasLiked ? Math.max(0, likes - 1) : likes + 1)
    
    const cached = feedCache.getInteraction(post.id, currentUser.$id)
    if (cached) {
      feedCache.setInteraction(post.id, currentUser.$id, { ...cached, liked: !wasLiked })
    }

    try {
      if (wasLiked) {
        await appwriteService.unlikePost(post.id)
      } else {
        await appwriteService.likePost(post.id)
        if (post.userId) {
          await appwriteService.logFeedEvent({
            userId: currentUser.$id,
            postId: post.id,
            creatorId: post.userId,
            feed: feedType === 'detail' ? 'home' : feedType,
            eventType: 'like',
            position: 0
          })
        }
      }
    } catch (error) {
      console.error('Failed to toggle like:', error)
      setLiked(wasLiked)
      setLikes(prevLikes)
      if (cached) {
        feedCache.setInteraction(post.id, currentUser.$id, { ...cached, liked: wasLiked })
      }
    }
  }

  const handleSave = async () => {
    const currentUser = await appwriteService.getCurrentUser()
    if (!currentUser) return

    const wasSaved = saved
    setSaved(!wasSaved)
    
    const cached = feedCache.getInteraction(post.id, currentUser.$id)
    if (cached) {
      feedCache.setInteraction(post.id, currentUser.$id, { ...cached, saved: !wasSaved })
    }

    try {
      await appwriteService.savePost(post.id)
      if (!wasSaved && post.userId) {
        await appwriteService.logFeedEvent({
          userId: currentUser.$id,
          postId: post.id,
          creatorId: post.userId,
          feed: feedType === 'detail' ? 'home' : feedType,
          eventType: 'save',
          position: 0
        })
      }
    } catch (error) {
      console.error('Failed to toggle save:', error)
      setSaved(wasSaved)
      if (cached) {
        feedCache.setInteraction(post.id, currentUser.$id, { ...cached, saved: wasSaved })
      }
    }
  }

  const handleRepost = async () => {
    const currentUser = await appwriteService.getCurrentUser()
    if (!currentUser) return

    const wasReposted = reposted
    const prevReposts = reposts

    setReposted(!wasReposted)
    setReposts(wasReposted ? Math.max(0, reposts - 1) : reposts + 1)
    
    const cached = feedCache.getInteraction(post.id, currentUser.$id)
    if (cached) {
      feedCache.setInteraction(post.id, currentUser.$id, { ...cached, reposted: !wasReposted })
    }

    try {
      await appwriteService.repostPost(post.id)
      if (!wasReposted && post.userId) {
        await appwriteService.logFeedEvent({
          userId: currentUser.$id,
          postId: post.id,
          creatorId: post.userId,
          feed: feedType === 'detail' ? 'home' : feedType,
          eventType: 'repost',
          position: 0
        })
      }
    } catch (error) {
      console.error('Failed to toggle repost:', error)
      setReposted(wasReposted)
      setReposts(prevReposts)
      if (cached) {
        feedCache.setInteraction(post.id, currentUser.$id, { ...cached, reposted: wasReposted })
      }
    }
  }

  const handleShare = async () => {
    try {
      const postUrl = post.postType === 'reel' 
        ? `${window.location.origin}/reels/${generateSlug(post.title || post.content?.substring(0, 30) || 'reel', resolvedPostId)}`
        : `${window.location.origin}/watch/${generateSlug(post.title || 'video', resolvedPostId)}`
      
      if (navigator.share) {
        await navigator.share({
          title: post.title || post.content || 'Check this out',
          text: post.content || '',
          url: postUrl
        })
        
        const user = await appwriteService.getCurrentUser()
        if (user && post.userId) {
          await appwriteService.logFeedEvent({
            userId: user.$id,
            postId: post.id,
            creatorId: post.userId,
            feed: feedType === 'detail' ? 'home' : feedType,
            eventType: 'share',
            position: 0
          })
        }
      }
    } catch (error) {
      console.error('Failed to share:', error)
    }
  }

  const handleDelete = async () => {
    if (!confirm('Delete this post?')) return
    try {
      await appwriteService.deletePost(post.id)
      window.location.reload()
    } catch (error) {
      console.error('Failed to delete post:', error)
    }
  }

  const handleFollow = async () => {
    const currentUser = await appwriteService.getCurrentUser()
    if (!currentUser) return

    const wasFollowing = isFollowing
    setIsFollowing(!wasFollowing)

    try {
      if (wasFollowing) {
        await appwriteService.unfollowUser(post.userId)
      } else {
        await appwriteService.followUser(post.userId)
      }
    } catch (error) {
      console.error('Failed to toggle follow:', error)
      setIsFollowing(wasFollowing)
    }
  }

  const renderMedia = () => {
    if (feedType === 'detail') return null
    if (!post.mediaUrls || post.mediaUrls.length === 0) return null
    if (!shouldLoadMedia) return <div className="w-full aspect-square rounded-xl mb-3 bg-gray-100 dark:bg-gray-800" />

    const toImageProxyUrl = (url: string) => {
      return normalizeWasabiImage(url) || url
    }

    const toVideoProxyUrl = (url: string) => {
      return normalizeWasabiVideo(url) || url
    }

    const imageUrl = toImageProxyUrl(post.mediaUrls[0])

    if (post.postType === 'image') {
      return (
        <div 
          className="w-full rounded-xl mb-3 overflow-hidden bg-gray-100 dark:bg-gray-800 relative max-h-[520px]"
          style={{ aspectRatio: '1/1.2' }}
        >
          <div
            className="w-full h-full cursor-pointer"
            onClick={openFullPost}
            onTouchStart={(e) => setTouchStartX(e.touches[0].clientX)}
            onTouchEnd={(e) => {
              const touchEndX = e.changedTouches[0].clientX
              const diff = touchStartX - touchEndX
              if (Math.abs(diff) > 50) {
                e.stopPropagation()
                if (diff > 0 && currentImageIndex < post.mediaUrls.length - 1) {
                  setCurrentImageIndex(prev => prev + 1)
                } else if (diff < 0 && currentImageIndex > 0) {
                  setCurrentImageIndex(prev => prev - 1)
                }
              }
            }}
          >
            <img
              src={toImageProxyUrl(post.mediaUrls[currentImageIndex])}
              alt="Post"
              className="w-full h-full object-cover object-top"
              loading="lazy"
            />
          </div>
          {post.mediaUrls.length > 1 && (
            <div className="absolute top-3 right-3 flex gap-1.5">
              {post.mediaUrls.map((_, i) => (
                <div 
                  key={i} 
                  className={`w-1.5 h-1.5 rounded-full transition-all ${
                    i === currentImageIndex ? 'bg-white w-6' : 'bg-white/60'
                  }`} 
                />
              ))}
            </div>
          )}
        </div>
      )
    } else if (post.postType === 'video') {
      const thumbnailUrl = toImageProxyUrl(post.thumbnailUrl || post.mediaUrls[0])
      
      return (
        <>
          <div
            className="relative w-full rounded-xl mb-3 bg-gray-900 cursor-pointer overflow-hidden max-h-[480px] flex items-center justify-center"
            onClick={navigateToVideoDetail}
          >
            {thumbnailUrl && (
              <img
                src={thumbnailUrl}
                alt="Video thumbnail"
                className="max-w-full max-h-[480px] object-contain"
                loading="lazy"
              />
            )}
            <div className="absolute inset-0 bg-black/40 flex items-center justify-center">
              <div className="w-16 h-16 bg-white/90 rounded-full flex items-center justify-center shadow-lg">
                <Play className="w-8 h-8 text-black ml-1" fill="currentColor" />
              </div>
            </div>
          </div>
          {post.title && (
            <div className="mb-3 px-2">
              <h3 className="text-gray-900 dark:text-white font-bold text-base leading-snug line-clamp-2">{post.title}</h3>
            </div>
          )}
        </>
      )
    } else if (post.postType === 'reel') {
      const videoUrl = toVideoProxyUrl(post.mediaUrls[0])
      const thumbnailUrl = toImageProxyUrl(post.thumbnailUrl || post.mediaUrls[0])
      
      // Reel display - 1:1 on feeds, 9:16 on reels/details
      if ((feedType as string) === 'reels') {
        // Reels page - 9:16 vertical
        return (
          <div className="relative">
            <video
              ref={(el) => {
                if (el) {
                  el.muted = true
                }
              }}
              src={videoUrl}
              poster={thumbnailUrl}
              className="w-full rounded-xl mb-3 object-cover"
              style={{ aspectRatio: '9/16' }}
              controls
              preload="metadata"
            />
            {/* Title overlay on reels */}
            {post.title && (
              <div className="absolute top-4 left-4 right-4 bg-black/60 rounded-lg p-3">
                <h3 className="text-white font-semibold text-sm line-clamp-2">{post.title}</h3>
              </div>
            )}
          </div>
        )
      } else {
        // Other feeds - 1:1 square
        return (
          <div
            className="relative w-full rounded-xl mb-3 bg-black cursor-pointer overflow-hidden aspect-square max-h-[480px]"
            onClick={openReelDetail}
          >
            <img
              src={thumbnailUrl}
              alt="Reel thumbnail"
              className="w-full h-full object-cover object-top"
            />
            {/* Reel overlay */}
            <div className="absolute inset-0 bg-black/20 flex items-center justify-center">
              <div className="w-12 h-12 bg-white/90 rounded-full flex items-center justify-center shadow-lg">
                <Play className="w-6 h-6 text-black ml-0.5" fill="currentColor" />
              </div>
            </div>
            {/* Title below reel */}
            {post.title && (
              <div className="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/80 to-transparent p-3">
                <h3 className="text-white font-semibold text-sm line-clamp-1">{post.title}</h3>
              </div>
            )}
          </div>
        )
      }
    }

    return null
  }

  return (
    <>
      {showFullPost && post.postType === 'image' && post.mediaUrls && post.mediaUrls.length > 0 && (
        <div className="fixed inset-0 bg-black/90 backdrop-blur-md z-50 flex flex-col items-center justify-center p-4">
          <div className="w-full max-w-4xl flex items-center justify-between p-4 bg-black/40 rounded-t-2xl border-t border-x border-white/10">
            <button onClick={(e) => {
              e.preventDefault()
              e.stopPropagation()
              closeFullPost()
            }} className="p-2 hover:bg-white/10 rounded-full text-white">
              <ArrowLeft size={24} />
            </button>
            <div className="text-white text-sm font-semibold">{currentImageIndex + 1} / {post.mediaUrls.length}</div>
            <div className="w-10" />
          </div>
          <div 
            className="w-full max-w-4xl flex-1 bg-black/60 flex items-center justify-center relative select-none p-6 rounded-b-2xl border-b border-x border-white/10 overflow-hidden"
            onTouchStart={(e) => setTouchStartX(e.touches[0].clientX)}
            onTouchEnd={(e) => {
              const touchEndX = e.changedTouches[0].clientX
              const diff = touchStartX - touchEndX
              if (Math.abs(diff) > 50) {
                if (diff > 0 && currentImageIndex < post.mediaUrls.length - 1) {
                  setCurrentImageIndex(prev => prev + 1)
                } else if (diff < 0 && currentImageIndex > 0) {
                  setCurrentImageIndex(prev => prev - 1)
                }
              }
            }}
          >
            {post.mediaUrls.length > 1 && currentImageIndex > 0 && (
              <button
                onClick={(e) => {
                  e.stopPropagation()
                  setCurrentImageIndex(prev => prev - 1)
                }}
                className="absolute left-4 p-2 bg-black/50 hover:bg-black/75 text-white rounded-full transition-colors z-20"
                aria-label="Previous image"
              >
                <ChevronLeft size={24} />
              </button>
            )}

            {(() => {
              const currentImageUrl = post.mediaUrls[currentImageIndex] || post.mediaUrls[0]
              const resolvedUrl = normalizeWasabiImage(currentImageUrl) || currentImageUrl
              return (
                <img
                  src={resolvedUrl}
                  alt="Post"
                  className="max-w-[95%] max-h-[75vh] md:max-w-[85%] md:max-h-[75vh] object-contain rounded-xl border border-white/10 shadow-2xl transition-all"
                />
              )
            })()}

            {post.mediaUrls.length > 1 && currentImageIndex < post.mediaUrls.length - 1 && (
              <button
                onClick={(e) => {
                  e.stopPropagation()
                  setCurrentImageIndex(prev => prev + 1)
                }}
                className="absolute right-4 p-2 bg-black/50 hover:bg-black/75 text-white rounded-full transition-colors z-20"
                aria-label="Next image"
              >
                <ChevronRight size={24} />
              </button>
            )}
          </div>
        </div>
      )}

      {showReelDetail && post.postType === 'reel' && (
        <ReelsDetailScreen post={post} onClose={closeReelDetail} />
      )}
      {showFullComments && <CommentScreen post={post} onClose={closeFullComments} />}
      {showComments && <CommentModal post={post} onClose={closeComments} />}
      <div className="border-b border-gray-200 dark:border-gray-700 relative font-semibold tracking-[0.02em]">
      {(() => {
        const showVerifiedBadge = hasVerifiedBadge(userProfile || post)
        return (
      <>
      {/* Header */}
      <div className="flex items-center justify-between py-3">
        <div className="flex items-center gap-3 flex-1 min-w-0">
          <button
            onClick={() => router.push(`/profile/${post.userId}`)}
            className="hover:opacity-80 transition-opacity flex-shrink-0"
            aria-label={`View ${userProfile?.displayName || userProfile?.username || post.username}'s profile`}
          >
            {userProfile?.avatarUrl ? (
              <img
                src={normalizeWasabiImage(userProfile.avatarUrl) || userProfile.avatarUrl}
                alt={userProfile.displayName || 'User'}
                className="w-10 h-10 rounded-full object-cover"
              />
            ) : (
              <div className="w-10 h-10 rounded-full bg-gray-100 dark:bg-gray-800 flex items-center justify-center text-gray-900 dark:text-white font-semibold">
                {(userProfile?.displayName || 'U')[0].toUpperCase()}
              </div>
            )}
          </button>
          <div className="flex-1 min-w-0 flex flex-col justify-center">
            <div className="flex items-center gap-1.5 flex-wrap">
              <button
                onClick={() => router.push(`/profile/${post.userId}`)}
                className="text-gray-900 dark:text-white font-bold text-[15px] sm:text-[16px] leading-[1.3] hover:underline transition-all text-left flex items-center gap-1"
                aria-label={`View ${userProfile?.displayName || 'User'}'s profile`}
              >
                {userProfile?.displayName || 'User'}
                {showVerifiedBadge && <VerifiedBadge className="h-3.5 w-3.5 shrink-0" isPremium={isPremiumBadge(userProfile || post)} />}
              </button>
            </div>
            <span className="text-gray-500 dark:text-gray-400 text-[13px] font-medium mt-0.5">{formatTimeAgo(post.createdAt)}</span>
          </div>
        </div>
        <div className="flex items-center gap-2 flex-shrink-0">
          {currentUserId && currentUserId !== post.userId && isFollowing === false && (
            <button
              onClick={handleFollow}
              className="px-3.5 py-1 rounded-full text-xs font-semibold transition-all hover:scale-105 active:scale-95 bg-blue-500 text-white hover:bg-blue-600"
            >
              Follow
            </button>
          )}
          <button onClick={() => setShowMenu(!showMenu)} className="text-gray-500 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white p-1" aria-label="More options">
            <MoreHorizontal size={18} />
          </button>
        </div>
      </div>
      </>
        )
      })()}

      {showMenu && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setShowMenu(false)} />
          <div className="absolute top-12 right-4 bg-background border border-border rounded-xl shadow-2xl z-50 overflow-x-auto whitespace-nowrap max-w-[calc(100vw-2rem)]">
            <div className="flex items-center">
              {currentUserId === post.userId && (
                <>
                  <button onClick={handleDelete} className="px-4 py-3 text-xs font-semibold text-red-600 hover:bg-muted transition-colors">
                    Delete
                  </button>
                  <span className="text-border">•</span>
                </>
              )}
              <button className="px-4 py-3 text-xs font-semibold text-foreground hover:bg-muted transition-colors">
                Report
              </button>
            </div>
          </div>
        </>
      )}

      {/* Content */}
      <div className="pb-2" ref={mediaRef} onClick={(e) => {
        if (post.postType === 'image' && !(e.target as HTMLElement).closest('button') && !expandedText) {
          openFullPost()
        }
      }}>
        {post.textBgColor ? (
          <div
            className={`text-white text-center leading-[1.6] tracking-[0.01em] p-4 rounded-xl mb-3 max-w-sm ${
              (post.content?.length || 0) < 50
                ? 'text-2xl font-extrabold'
                : (post.content?.length || 0) < 100
                ? 'text-xl font-bold'
                : 'text-lg font-semibold'
            }`}
            style={{ backgroundColor: post.textBgColor ? `#${post.textBgColor.toString(16).padStart(6, '0')}` : undefined }}
          >
            {post.content}
          </div>
        ) : (post.content && !(post.postType === 'video' && (feedType === 'home' || feedType === 'watch'))) ? (
          <div className="text-gray-900 dark:text-white text-[15px] sm:text-[16px] leading-[1.6] tracking-[0.015em] mb-2.5 font-normal">
            {(() => {
              const contentLength = post.content.length
              let maxLines = 2
              
              if (post.postType === 'reel') {
                maxLines = 2
              } else if (post.postType === 'video') {
                maxLines = 2
              } else if (contentLength >= 1000) {
                maxLines = 5
              } else if (contentLength >= 400) {
                maxLines = 3
              } else {
                maxLines = 2
              }
              
              const needsTruncation = post.content.split('\n').length > maxLines || contentLength > maxLines * 80
              
              return (
                <>
                  <p className={`leading-[1.6] tracking-[0.015em] ${expandedText ? '' : `line-clamp-${maxLines}`}`}>
                    {parseHashtags(post.content)}
                  </p>
                  {needsTruncation && (
                    <button
                      onClick={(e) => {
                        e.stopPropagation()
                        if (post.postType === 'video') {
                          navigateToVideoDetail()
                        } else if (post.postType === 'reel') {
                          openReelDetail()
                        } else {
                          setExpandedText(!expandedText)
                        }
                      }}
                      className="text-blue-500 hover:underline text-xs font-semibold mt-1"
                    >
                      {expandedText ? 'Show less' : 'more'}
                    </button>
                  )}
                </>
              )
            })()}
          </div>
        ) : null}

        {/* Display media from mediaUrls array */}
        {renderMedia()}

        {post.postType === 'news' && post.title && (
          <div className="border-l-4 border-blue-500 pl-4 mb-3">
            <h3 className="post-title font-extrabold text-lg text-gray-900 dark:text-white leading-snug">
              {post.title}
            </h3>
          </div>
        )}
      </div>

      {/* Reactions */}
      <div className="pb-3 tracking-normal">
        {(feedType as string) === 'reels' ? (
          // Vertical reactions for reels - counts beside icons
          <div className="flex flex-col items-center gap-3">
            <button onClick={handleLike} className={`flex items-center gap-2 hover:text-red-500 transition-colors p-2 text-gray-500 dark:text-gray-400 ${liked ? 'text-red-500' : ''}`} aria-label="Like">
              <Heart size={24} className={liked ? 'fill-red-500' : ''} />
              <span className="text-sm font-bold">{formatCount(likes)}</span>
            </button>
            <button onClick={openComments} className="flex items-center gap-2 hover:text-blue-500 transition-colors p-2 text-gray-500 dark:text-gray-400" aria-label="Comment">
              <MessageCircle size={24} />
              <span className="text-sm font-bold">{formatCount(post.comments || 0)}</span>
            </button>
            <button onClick={handleRepost} className={`flex items-center gap-2 hover:text-green-500 transition-colors p-2 ${reposted ? 'text-green-500' : 'text-gray-500 dark:text-gray-400'}`} aria-label="Repost">
              <Repeat2 size={24} className={reposted ? 'fill-green-500' : ''} />
              <span className="text-sm font-bold">{formatCount(reposts)}</span>
            </button>
            <button onClick={handleSave} className={`flex items-center gap-2 hover:text-yellow-500 transition-colors p-2 ${saved ? 'text-yellow-500' : 'text-gray-500 dark:text-gray-400'}`} aria-label="Bookmark">
              <Bookmark size={24} className={saved ? 'fill-yellow-500' : ''} />
              <span className="text-sm font-bold">Save</span>
            </button>
            <button className="flex items-center gap-2 hover:text-blue-500 transition-colors p-2 text-gray-500 dark:text-gray-400" aria-label="Share">
              <Share size={24} />
              <span className="text-sm font-bold">Share</span>
            </button>
          </div>
        ) : (
          // Horizontal reactions for other feeds - icon only on mobile
          <div className="flex items-center justify-between gap-2">
            <button onClick={handleSave} className={`flex items-center justify-center hover:text-yellow-500 transition-colors p-2 rounded-lg text-gray-500 dark:text-gray-400 ${saved ? 'text-yellow-500' : ''}`} aria-label={`Save post - ${saved ? 'saved' : 'not saved'}`}>
              <Bookmark size={20} className={saved ? 'fill-yellow-500' : ''} />
            </button>
            <button onClick={handleShare} className={`flex items-center justify-center hover:text-blue-500 transition-colors p-2 rounded-lg text-gray-500 dark:text-gray-400`} aria-label="Share post">
              <Share size={20} />
            </button>
            <button onClick={handleRepost} className={`flex items-center gap-2 hover:text-green-500 transition-colors p-2 rounded-lg ${reposted ? 'text-green-500' : 'text-gray-500 dark:text-gray-400'}`} aria-label={`Repost - ${formatCount(reposts)} reposts`}>
              <Repeat2 size={20} className={reposted ? 'fill-green-500' : ''} />
              <span className="text-sm font-bold">{formatCount(reposts)}</span>
            </button>
            <button className={`flex items-center gap-2 hover:text-indigo-500 transition-colors p-2 rounded-lg text-gray-500 dark:text-gray-400`} aria-label={`View impressions - ${formatCount(post.impressions || 0)} impressions`}>
              <BarChart2 size={20} />
              <span className="text-sm font-bold">{formatCount(post.impressions || 0)}</span>
            </button>
            <button onClick={openComments} className={`flex items-center gap-2 hover:text-blue-500 transition-colors p-2 rounded-lg text-gray-500 dark:text-gray-400`} aria-label={`View comments - ${formatCount(post.comments || 0)} comments`}>
              <MessageCircle size={20} />
              <span className="text-sm font-bold">{formatCount(post.comments || 0)}</span>
            </button>
            <button onClick={handleLike} className={`flex items-center gap-2 hover:text-red-500 transition-colors p-2 rounded-lg ${liked ? 'text-red-500' : 'text-gray-500 dark:text-gray-400'}`} aria-label={`Like post - ${formatCount(likes)} likes`}>
              <Heart size={20} className={liked ? 'fill-red-500' : ''} />
              <span className="text-sm font-bold">{formatCount(likes)}</span>
            </button>
          </div>
        )}
      </div>
    </div>
    </>
  )
}
