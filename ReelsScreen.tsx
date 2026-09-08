'use client'

import { useState, useEffect, useRef, useCallback } from 'react'
import { Post } from './types'
import appwriteService from './appwriteService'
import { useFeedStore } from './feedStore'
import { Heart, MessageCircle, Share2, Bookmark, Repeat2, Eye, Play, Pause } from 'lucide-react'
import { useRouter } from 'next/navigation'
import { generateSlug } from './lib/slug'
import { CommentModal } from './CommentModal'
import { formatCount, formatTimeAgo } from './utils'
import { playAdcashInstreamAd } from './lib/instream-ads'
import { VerifiedBadge } from './components/VerifiedBadge'
import { hasVerifiedBadge, isPremiumBadge } from './lib/verification'
import { normalizeWasabiImage, normalizeWasabiVideo } from './lib/wasabi'

export function ReelsScreen() {
  const feedStore = useFeedStore()
  const [posts, setPosts] = useState<Post[]>([])
  const [currentIndex, setCurrentIndex] = useState(0)
  const [loading, setLoading] = useState(false)
  const [initialLoadComplete, setInitialLoadComplete] = useState(false)
  const [hasLoadedInitial, setHasLoadedInitial] = useState(false)
  const [isPageVisible, setIsPageVisible] = useState(true)
  const [viewportHeight, setViewportHeight] = useState(0)
  const [showControls, setShowControls] = useState(false)
  const [isDesktop, setIsDesktop] = useState(false)
  const [showNav, setShowNav] = useState(false)
  const containerRef = useRef<HTMLDivElement>(null)
  const videoRefs = useRef<(HTMLVideoElement | null)[]>([])
  const touchStartY = useRef(0)
  const impressionTracked = useRef<Set<string>>(new Set())
  const hasCountedView = useRef<Map<string, boolean>>(new Map())
  const hasEnded = useRef<Map<string, boolean>>(new Map())
  const userPaused = useRef<Map<string, boolean>>(new Map())
  const navTimeoutRef = useRef<NodeJS.Timeout | null>(null)
  const controlsTimeoutRef = useRef<NodeJS.Timeout | null>(null)
  const router = useRouter()
  const [commentModalPost, setCommentModalPost] = useState<Post | null>(null)
  const [shouldLoadMedia, setShouldLoadMedia] = useState<Map<string, boolean>>(new Map())
  const [videoReadyMap, setVideoReadyMap] = useState<Map<string, boolean>>(new Map())
  const mediaRefs = useRef<Map<string, HTMLDivElement>>(new Map())
  const currentIndexRef = useRef(0)
  const playTicketRef = useRef(0)

  const toImageProxyUrl = (url?: string) => {
    if (!url) return ''
    return normalizeWasabiImage(url) || url
  }

  const toVideoProxyUrl = (url?: string) => {
    if (!url) return ''
    return normalizeWasabiVideo(url) || url
  }

  const getVideoSource = (post: Post) => {
    const rawMediaUrls = (post as any).mediaUrls
    const mediaUrls = Array.isArray(rawMediaUrls)
      ? rawMediaUrls
      : (typeof rawMediaUrls === 'string' && rawMediaUrls ? [rawMediaUrls] : [])
    const primaryMedia = mediaUrls.find((url: string) => typeof url === 'string' && url.length > 0)
    const legacyVideoUrl = (post as any).videoUrl as string | undefined
    return toVideoProxyUrl(primaryMedia || legacyVideoUrl)
  }

  const pauseAllVideos = (except?: HTMLVideoElement | null) => {
    if (typeof document === 'undefined') return
    document.querySelectorAll('video').forEach((video) => {
      if (video !== except && !video.paused) {
        video.pause()
      }
    })
  }

  const playVideoWithAd = useCallback(async (video: HTMLVideoElement, postId: string, reason: 'manual' | 'autoplay') => {
    const ticket = ++playTicketRef.current
    await playAdcashInstreamAd({ placement: `reels-feed:${reason}`, videoId: postId })

    if (ticket !== playTicketRef.current) return
    if (commentModalPost || !isPageVisible) return
    if (userPaused.current.get(postId)) return
    if (video.readyState < 3) return
    if (video !== videoRefs.current[currentIndexRef.current]) return

    pauseAllVideos(video)
    if (video.paused) {
      video.play().catch(() => {})
    }
  }, [commentModalPost, isPageVisible])

  useEffect(() => {
    const cached = feedStore.getFeed('reels')
    if (cached && cached.posts.length > 0) {
      setPosts(cached.posts)
      setHasLoadedInitial(true)
      setInitialLoadComplete(true)
    } else {
      loadReels(1, true)
    }

    const unsubscribe = appwriteService.subscribeToCollection('posts', (payload) => {
      if (payload.events.includes('databases.*.collections.posts.documents.*.create')) {
        const newPost = payload.payload
        if (newPost.postType === 'reel') {
          setPosts(prev => {
            const updated = [{
              ...newPost,
              id: newPost.$id,
              timestamp: new Date(newPost.$createdAt || newPost.createdAt),
            }, ...prev]
            feedStore.setFeed('reels', updated)
            return updated
          })
        }
      }
    })

    return unsubscribe
  }, [])

  useEffect(() => {
    const updateViewportHeight = () => {
      setViewportHeight(window.innerHeight)
      setIsDesktop(window.innerWidth >= 1024)
    }
    updateViewportHeight()
    window.addEventListener('resize', updateViewportHeight)
    return () => window.removeEventListener('resize', updateViewportHeight)
  }, [])

  useEffect(() => {
    currentIndexRef.current = currentIndex
  }, [currentIndex])

  useEffect(() => {
    const pauseEverything = () => {
      pauseAllVideos()
    }

    const handleVisibilityChange = () => {
      const visible = !document.hidden
      setIsPageVisible(visible)
      if (!visible) pauseEverything()
    }

    setIsPageVisible(!document.hidden)
    document.addEventListener('visibilitychange', handleVisibilityChange)
    window.addEventListener('pagehide', pauseEverything)
    window.addEventListener('blur', pauseEverything)
    return () => {
      document.removeEventListener('visibilitychange', handleVisibilityChange)
      window.removeEventListener('pagehide', pauseEverything)
      window.removeEventListener('blur', pauseEverything)
    }
  }, [])

  useEffect(() => {
    if (showNav) {
      document.body.classList.remove('hide-bottom-nav')
    } else {
      document.body.classList.add('hide-bottom-nav')
    }

    return () => {
      document.body.classList.remove('hide-bottom-nav')
    }
  }, [showNav])

  useEffect(() => {
    const observers = new Map<string, IntersectionObserver>()
    
    posts.forEach(post => {
      const element = mediaRefs.current.get(post.id)
      if (!element || shouldLoadMedia.get(post.id)) return
      
      const observer = new IntersectionObserver(
        ([entry]) => {
          if (entry.isIntersecting) {
            setShouldLoadMedia(prev => new Map(prev).set(post.id, true))
            observer.disconnect()
          }
        },
        { rootMargin: '200px' }
      )
      observer.observe(element)
      observers.set(post.id, observer)
    })
    
    return () => observers.forEach(obs => obs.disconnect())
  }, [posts])

  useEffect(() => {
    if (posts.length === 0) return
    setShouldLoadMedia(prev => {
      const next = new Map(prev)
      const indicesToPreload = [currentIndex - 1, currentIndex, currentIndex + 1]
      indicesToPreload.forEach(index => {
        const post = posts[index]
        if (post) next.set(post.id, true)
      })
      return next
    })
  }, [currentIndex, posts])

  useEffect(() => {
    setVideoReadyMap(prev => {
      const next = new Map<string, boolean>()
      posts.forEach(post => {
        if (prev.has(post.id)) {
          next.set(post.id, prev.get(post.id) || false)
        }
      })
      return next
    })
  }, [posts])

  const activePost = posts[currentIndex]
  const activePostId = activePost?.id

  useEffect(() => {
    const activeVideo = videoRefs.current[currentIndex]
    if (!activePost || !activeVideo) return
    activeVideo.loop = true

    if (
      commentModalPost ||
      !isPageVisible ||
      userPaused.current.get(activePost.id) ||
      activeVideo.readyState < 3
    ) {
      playTicketRef.current += 1
      activeVideo.pause()
      return
    }

    if (activeVideo.paused) {
      void playVideoWithAd(activeVideo, activePost.id, 'autoplay')
    }
  }, [currentIndex, commentModalPost, activePostId, isPageVisible, playVideoWithAd])

  useEffect(() => {
    if (!activePost || impressionTracked.current.has(activePost.id)) return
    const impressionTimer = setTimeout(async () => {
      await appwriteService.incrementPostField(activePost.id, 'impressions', 1)
      impressionTracked.current.add(activePost.id)
      
      const user = await appwriteService.getCurrentUser()
      if (user && activePost.userId) {
        await appwriteService.logFeedEvent({
          userId: user.$id,
          postId: activePost.id,
          creatorId: activePost.userId,
          feed: 'reels',
          eventType: 'impression',
          position: currentIndex + 1
        })
      }
    }, 1000)
    return () => clearTimeout(impressionTimer)
  }, [activePostId, currentIndex])

  useEffect(() => {
    if (!hasLoadedInitial && currentIndex === 0 && posts.length === 1) {
      setHasLoadedInitial(true)
      loadReels(5)
      return
    }

    if (hasLoadedInitial && currentIndex >= posts.length - 2) {
      loadReels(5)
    }
  }, [currentIndex, posts.length, hasLoadedInitial])

  const handleVideoPlay = async (postId: string) => {
    if (!hasCountedView.current.get(postId)) {
      hasCountedView.current.set(postId, true)
      await appwriteService.incrementPostField(postId, 'views', 1)
      
      const user = await appwriteService.getCurrentUser()
      const post = posts.find(p => p.id === postId)
      if (user && post?.userId) {
        await appwriteService.logFeedEvent({
          userId: user.$id,
          postId,
          creatorId: post.userId,
          feed: 'reels',
          eventType: 'view_start',
          position: currentIndex + 1
        })
      }
    }
  }

  const handleVideoEnded = async (postId: string) => {
    hasEnded.current.set(postId, true)
    hasCountedView.current.set(postId, false)
    
    const user = await appwriteService.getCurrentUser()
    const post = posts.find(p => p.id === postId)
    if (user && post?.userId) {
      await appwriteService.logFeedEvent({
        userId: user.$id,
        postId,
        creatorId: post.userId,
        feed: 'reels',
        eventType: 'view_complete',
        position: currentIndex + 1
      })
    }
  }

  const handleScreenTap = () => {
    setShowNav(true)
    if (navTimeoutRef.current) clearTimeout(navTimeoutRef.current)
    navTimeoutRef.current = setTimeout(() => setShowNav(false), 3500)
  }

  useEffect(() => {
    return () => {
      pauseAllVideos()
    }
  }, [])

  const loadReels = async (count: number = 5, markInitialComplete: boolean = false) => {
    if (loading) return
    setLoading(true)
    try {
      const result = await appwriteService.fetchReelsFeed(count)
      const user = await appwriteService.getCurrentUser()
      
      const newPosts: Post[] = []
      for (const d of result.documents) {
        const doc: any = d
        if (posts.some(p => p.id === doc.$id)) continue
        
        const profile = await appwriteService.getProfileByUserId(doc.userId)
        const interactions = user ? await Promise.all([
          appwriteService.isPostLikedBy(user.$id, doc.$id),
          appwriteService.isPostSavedBy(user.$id, doc.$id),
          appwriteService.isPostRepostedBy(user.$id, doc.$id)
        ]) : [false, false, false]
        
        const enrichedPost = {
          ...doc,
          id: doc.$id,
          timestamp: new Date(doc.$createdAt || doc.createdAt),
          displayName: profile?.displayName || 'User',
          avatarUrl: profile?.avatarUrl || '',
          isVerified: hasVerifiedBadge(profile),
          isLiked: interactions[0],
          isSaved: interactions[1],
          isReposted: interactions[2]
        }
        
        newPosts.push(enrichedPost as Post)
      }
      
      setPosts(prev => [...prev, ...newPosts])
      feedStore.setFeed('reels', [...posts, ...newPosts])
    } catch (error) {
      console.error('Failed to load reels:', error)
    } finally {
      setLoading(false)
      if (markInitialComplete) {
        setInitialLoadComplete(true)
      }
    }
  }

  const handleWheel = (e: React.WheelEvent) => {
    if (Math.abs(e.deltaY) > 10) {
      if (e.deltaY > 0 && currentIndex < posts.length - 1) {
        setCurrentIndex(prev => prev + 1)
      } else if (e.deltaY < 0 && currentIndex > 0) {
        setCurrentIndex(prev => prev - 1)
      }
    }
  }

  const handleTouchStart = (e: React.TouchEvent) => {
    handleScreenTap()
    touchStartY.current = e.touches[0].clientY
  }

  const handleTouchEnd = (e: React.TouchEvent) => {
    const touchEndY = e.changedTouches[0].clientY
    const diff = touchStartY.current - touchEndY
    
    if (Math.abs(diff) > 50) {
      if (diff > 0 && currentIndex < posts.length - 1) {
        setCurrentIndex(prev => prev + 1)
      } else if (diff < 0 && currentIndex > 0) {
        setCurrentIndex(prev => prev - 1)
      }
    }
  }

  const handleReaction = async (postId: string, action: 'like' | 'comment' | 'save' | 'share' | 'repost') => {
    try {
      const user = await appwriteService.getCurrentUser()
      if (!user) {
        router.push('/auth/signin')
        return
      }

      const post = posts.find(p => p.id === postId)
      if (!post) return

      if (action === 'like') {
        const wasLiked = post.isLiked
        const prevLikes = post.likes || 0
        
        setPosts(prev => prev.map(p => 
          p.id === postId ? { 
            ...p, 
            isLiked: !wasLiked,
            likes: wasLiked ? Math.max(0, prevLikes - 1) : prevLikes + 1
          } : p
        ))
        
        try {
          if (wasLiked) {
            await appwriteService.unlikePost(postId)
          } else {
            await appwriteService.likePost(postId)
            if (post.userId) {
              await appwriteService.logFeedEvent({
                userId: user.$id,
                postId,
                creatorId: post.userId,
                feed: 'reels',
                eventType: 'like',
                position: currentIndex + 1
              })
            }
          }
        } catch (error) {
          console.error('Failed to toggle like:', error)
          setPosts(prev => prev.map(p => 
            p.id === postId ? { ...p, isLiked: wasLiked, likes: prevLikes } : p
          ))
        }
      } else if (action === 'save') {
        const wasSaved = post.isSaved
        
        setPosts(prev => prev.map(p => 
          p.id === postId ? { ...p, isSaved: !wasSaved } : p
        ))
        
        try {
          await appwriteService.savePost(postId)
          if (!wasSaved && post.userId) {
            await appwriteService.logFeedEvent({
              userId: user.$id,
              postId,
              creatorId: post.userId,
              feed: 'reels',
              eventType: 'save',
              position: currentIndex + 1
            })
          }
        } catch (error) {
          console.error('Failed to toggle save:', error)
          setPosts(prev => prev.map(p => 
            p.id === postId ? { ...p, isSaved: wasSaved } : p
          ))
        }
      } else if (action === 'comment') {
        setCommentModalPost(post)
        if (post.userId) {
          await appwriteService.logFeedEvent({
            userId: user.$id,
            postId,
            creatorId: post.userId,
            feed: 'reels',
            eventType: 'comment',
            position: currentIndex + 1
          })
        }
      } else if (action === 'repost') {
        const wasReposted = post.isReposted
        const prevReposts = post.reposts || 0
        
        setPosts(prev => prev.map(p => 
          p.id === postId ? { 
            ...p, 
            isReposted: !wasReposted,
            reposts: wasReposted ? Math.max(0, prevReposts - 1) : prevReposts + 1
          } : p
        ))
        
        try {
          await appwriteService.repostPost(postId)
          if (!wasReposted && post.userId) {
            await appwriteService.logFeedEvent({
              userId: user.$id,
              postId,
              creatorId: post.userId,
              feed: 'reels',
              eventType: 'repost',
              position: currentIndex + 1
            })
          }
        } catch (error) {
          console.error('Failed to toggle repost:', error)
          setPosts(prev => prev.map(p => 
            p.id === postId ? { ...p, isReposted: wasReposted, reposts: prevReposts } : p
          ))
        }
      } else if (action === 'share') {
        if (navigator.share) {
          await navigator.share({
            title: post.content || 'Check out this reel',
            url: window.location.origin + `/reels/${generateSlug(post.content || 'reel', postId)}`
          })
          if (post.userId) {
            await appwriteService.logFeedEvent({
              userId: user.$id,
              postId,
              creatorId: post.userId,
              feed: 'reels',
              eventType: 'share',
              position: currentIndex + 1
            })
          }
        }
      }
    } catch (error) {
      console.error('Reaction failed:', error)
    }
  }

  useEffect(() => {
    if (!commentModalPost) return
    pauseAllVideos()
  }, [commentModalPost])

  if (!initialLoadComplete || (loading && posts.length === 0)) {
    return (
      <div className="fixed inset-0 flex items-center justify-center bg-black">
        <div className="animate-spin rounded-full h-12 w-12 border-4 border-white/30 border-t-white" />
      </div>
    )
  }

  if (initialLoadComplete && posts.length === 0) {
    return (
      <div className="fixed inset-0 flex items-center justify-center bg-black text-white">
        <div className="text-center px-6">
          <p className="text-xl mb-2">No reels yet</p>
          <p className="text-sm text-gray-400">Upload a vertical video to create your first reel!</p>
        </div>
      </div>
    )
  }

  const slideHeight = isDesktop ? Math.min(800, viewportHeight - 100) : viewportHeight

  return (
    <div>
      <style jsx global>{`
        body:has(.reels-fullscreen) nav,
        body:has(.reels-fullscreen) .safe-area-inset-bottom {
          display: ${showNav ? 'block' : 'none'} !important;
        }
        body:has(.reels-fullscreen) {
          overscroll-behavior: none;
          overflow: hidden;
        }
      `}</style>
      <div 
        ref={containerRef}
        className="reels-fullscreen fixed inset-0 lg:left-[200px] lg:top-[60px] bg-black lg:bg-[rgb(18,18,18)] overflow-hidden touch-none lg:flex lg:items-center lg:justify-center"
        onWheel={handleWheel}
        onPointerDown={handleScreenTap}
        onTouchStart={handleTouchStart}
        onTouchEnd={handleTouchEnd}
        onClick={handleScreenTap}
        style={{ 
          overscrollBehavior: 'none',
          height: isDesktop ? `${viewportHeight - 60}px` : (viewportHeight ? `${viewportHeight}px` : '100vh')
        }}
      >
      <div 
        className="h-full transition-transform duration-300 ease-out lg:w-[450px]"
        style={{
          transform: `translateY(-${currentIndex * slideHeight}px)`
        }}
      >
        {posts.map((post, index) => {
          const videoSource = getVideoSource(post)
          const canRenderVideo = Boolean(videoSource)
          const isVideoReady = Boolean(videoReadyMap.get(post.id))
          const isVideoFrameReady = (videoRefs.current[index]?.readyState ?? 0) >= 3
          const shouldRenderMedia = Boolean(shouldLoadMedia.get(post.id) || index === currentIndex)

          if (!canRenderVideo) {
            videoRefs.current[index] = null
          }

          return (
          <div
            key={post.id}
            className="w-full lg:w-[450px] relative lg:mx-auto lg:rounded-2xl lg:overflow-hidden lg:shadow-2xl bg-black border border-transparent lg:border-gray-800 flex-shrink-0 flex items-center justify-center"
            style={{ height: `${slideHeight}px` }}
            ref={el => { if (el) mediaRefs.current.set(post.id, el) }}
          >
            {shouldRenderMedia ? (
            <>
            {canRenderVideo ? (
            <video
              ref={el => { videoRefs.current[index] = el }}
              src={videoSource}
              className="h-full w-full object-cover"
              playsInline
              onPlay={(e) => {
                const video = e.currentTarget
                if (
                  index !== currentIndexRef.current ||
                  commentModalPost ||
                  !isPageVisible
                ) {
                  video.pause()
                  return
                }
                pauseAllVideos(video)
                void handleVideoPlay(post.id)
              }}
              onEnded={() => handleVideoEnded(post.id)}
              onLoadStart={() => {
                setVideoReadyMap(prev => new Map(prev).set(post.id, false))
              }}
              onCanPlay={() => {
                setVideoReadyMap(prev => new Map(prev).set(post.id, true))
              }}
              preload={index === currentIndex ? "auto" : (Math.abs(index - currentIndex) === 1 ? "metadata" : "none")}
              onClick={(e) => {
                e.stopPropagation()
                handleScreenTap()
                const video = e.currentTarget
                if (index !== currentIndexRef.current) return
                if (video.paused) {
                  userPaused.current.set(post.id, false)
                  void playVideoWithAd(video, post.id, 'manual')
                  setShowControls(true)
                  if (controlsTimeoutRef.current) clearTimeout(controlsTimeoutRef.current)
                  controlsTimeoutRef.current = setTimeout(() => setShowControls(false), 2000)
                } else {
                  userPaused.current.set(post.id, true)
                  video.pause()
                  setShowControls(true)
                }
              }}
            />
            ) : (
              <div className="h-full w-full bg-black flex items-center justify-center">
                <div className="text-white/80 text-sm">Reel media unavailable</div>
              </div>
            )}
            {index === currentIndex && (!isVideoReady || !isVideoFrameReady) && (
              <div className="absolute inset-0 flex items-center justify-center bg-black/50 pointer-events-none">
                <div className="animate-spin rounded-full h-12 w-12 border-4 border-white/30 border-t-white" />
              </div>
            )}
            </>
            ) : (
              <div className="h-full w-full bg-gray-900" />
            )}

            {/* Center Play/Pause Button */}
            {showControls && (
              <div className="absolute inset-0 flex items-center justify-center z-10 pointer-events-none">
                <div className="w-20 h-20 rounded-full bg-black/25 flex items-center justify-center text-white animate-in fade-in duration-200">
                  {videoRefs.current[index]?.paused ? (
                    <Play size={40} fill="white" className="ml-1" />
                  ) : (
                    <Pause size={40} fill="white" />
                  )}
                </div>
              </div>
            )}

            {/* Right Side Reactions */}
            <div
              className="absolute right-3 flex flex-col items-center gap-4 z-10"
              style={{ bottom: 'calc(env(safe-area-inset-bottom) + 6rem)' }}
            >
              {/* Like */}
              <button 
                onClick={(e) => {
                  e.stopPropagation()
                  handleReaction(post.id, 'like')
                }}
                className="flex flex-col items-center gap-1"
              >
                <div className="w-12 h-12 rounded-full bg-white/10 backdrop-blur-sm flex items-center justify-center hover:bg-white/20 transition-all">
                  <Heart 
                    size={24}
                    className={post.isLiked ? 'fill-red-500 text-red-500' : 'text-white'}
                  />
                </div>
                <span className="text-white text-sm font-bold">
                  {formatCount(post.likes || 0)}
                </span>
              </button>

              {/* Comment */}
              <button 
                onClick={(e) => {
                  e.stopPropagation()
                  handleReaction(post.id, 'comment')
                }}
                className="flex flex-col items-center gap-1"
              >
                <div className="w-12 h-12 rounded-full bg-white/10 backdrop-blur-sm flex items-center justify-center hover:bg-white/20 transition-all">
                  <MessageCircle size={24} className="text-white" />
                </div>
                <span className="text-white text-sm font-bold">
                  {formatCount(post.comments || 0)}
                </span>
              </button>

              {/* Repost */}
              <button 
                onClick={(e) => {
                  e.stopPropagation()
                  handleReaction(post.id, 'repost')
                }}
                className="flex flex-col items-center gap-1"
              >
                <div className="w-12 h-12 rounded-full bg-white/10 backdrop-blur-sm flex items-center justify-center hover:bg-white/20 transition-all">
                  <Repeat2 
                    size={24}
                    className={post.isReposted ? 'text-green-500' : 'text-white'}
                  />
                </div>
                <span className="text-white text-sm font-bold">
                  {formatCount(post.reposts || 0)}
                </span>
              </button>

              {/* Save */}
              <button 
                onClick={(e) => {
                  e.stopPropagation()
                  handleReaction(post.id, 'save')
                }}
                className="flex flex-col items-center gap-1"
              >
                <div className="w-12 h-12 rounded-full bg-white/10 backdrop-blur-sm flex items-center justify-center hover:bg-white/20 transition-all">
                  <Bookmark 
                    size={24}
                    className={post.isSaved ? 'fill-yellow-500 text-yellow-500' : 'text-white'}
                  />
                </div>
                <span className="text-white text-sm font-bold">Save</span>
              </button>

              {/* Share */}
              <button 
                onClick={(e) => {
                  e.stopPropagation()
                  handleReaction(post.id, 'share')
                }}
                className="flex flex-col items-center gap-1"
              >
                <div className="w-12 h-12 rounded-full bg-white/10 backdrop-blur-sm flex items-center justify-center hover:bg-white/20 transition-all">
                  <Share2 size={24} className="text-white" />
                </div>
                <span className="text-white text-sm font-bold">Share</span>
              </button>
            </div>

            {/* Bottom Info */}
            <div
              className="absolute bottom-0 left-0 right-20 bg-gradient-to-t from-black/90 via-black/60 to-transparent px-6 pt-6 z-10"
              style={{ paddingBottom: 'calc(env(safe-area-inset-bottom) + 1.5rem)' }}
            >
              <div className="max-w-md">
                <div className="flex items-center gap-3 mb-3">
                  {post.avatarUrl ? (
                    <img 
                      src={toImageProxyUrl(post.avatarUrl)}
                      alt={post.displayName} 
                      className="w-14 h-14 rounded-full object-cover border-2 border-white" 
                    />
                  ) : (
                    <div className="w-14 h-14 rounded-full bg-gray-600 border-2 border-white flex items-center justify-center text-white font-semibold text-lg">
                      {(post.displayName || 'U')[0].toUpperCase()}
                    </div>
                  )}
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="text-white font-bold text-lg flex items-center gap-1">
                        {post.displayName || 'User'}
                        {post.isVerified && <VerifiedBadge className="h-4 w-4" isPremium={isPremiumBadge(post)} />}
                      </span>
                      <span className="flex items-center gap-1 text-gray-300 text-sm">
                        <Eye size={14} />
                        {formatCount(post.views || 0)}
                      </span>
                    </div>
                    <span className="text-gray-300 text-sm">{formatTimeAgo(post.timestamp)}</span>
                  </div>
                </div>
                {post.content && (
                  <p className="text-white text-[15px] font-medium leading-[1.85] tracking-[0.03em] line-clamp-2">{post.content}</p>
                )}
              </div>
            </div>
          </div>
          )})}
      </div>
      {commentModalPost && (
        <CommentModal
          post={commentModalPost}
          onClose={() => setCommentModalPost(null)}
        />
      )}
      </div>
    </div>
  )
}
