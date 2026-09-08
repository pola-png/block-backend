'use client'

import { useState, useEffect, useRef, useCallback } from 'react'
import { ArrowLeft, Play, Pause, Volume2, VolumeX, Heart, MessageCircle, Repeat2, Share, Bookmark, MoreHorizontal, BarChart2, Eye, Loader2 } from 'lucide-react'
import { Post } from './types'
import appwriteService from './appwriteService'
import { normalizeWasabiImage, normalizeWasabiVideo } from './lib/wasabi'
import { parseHashtags } from './lib/hashtag'
import { formatCount, formatTimeAgo } from './utils'
import { CommentModal } from './CommentModal'
import { CommentScreen } from './CommentScreen'
import { useAuthStore } from './authStore'
import { useSingleVideoPlayback } from './useSingleVideoPlayback'
import type { VideoDetailScreenProps } from './WatchVideoDetailScreen'
import { VerifiedBadge } from './components/VerifiedBadge'

// Vertical video detail screen (for Reels)
export function ReelsDetailScreen({ post, onClose, isGuest = false, onGuestAction }: VideoDetailScreenProps) {
  const [isPlaying, setIsPlaying] = useState(false)
  const [isMuted, setIsMuted] = useState(false)
  const [currentTime, setCurrentTime] = useState(0)
  const [duration, setDuration] = useState(0)
  const [hasEnded, setHasEnded] = useState(false)
  const [showControls, setShowControls] = useState(false)
  const [liked, setLiked] = useState(post.isLiked || false)
  const [likes, setLikes] = useState(post.likes || 0)
  const [reposts, setReposts] = useState(post.reposts || 0)
  const [reposted, setReposted] = useState(post.isReposted || false)
  const [comments, setComments] = useState(post.comments || 0)
  const [saved, setSaved] = useState(post.isSaved || false)
  const [views, setViews] = useState(post.views || 0)
  const [showComments, setShowComments] = useState(false)
  const [showFullComments, setShowFullComments] = useState(false)
  const [shouldLoadVideo, setShouldLoadVideo] = useState(false)

  const controlsTimeoutRef = useRef<NodeJS.Timeout | undefined>(undefined)

  const toImageProxyUrl = (url?: string) => {
    if (!url) return ''
    return normalizeWasabiImage(url) || url
  }

  const toVideoProxyUrl = (url?: string) => {
    if (!url) return ''
    return normalizeWasabiVideo(url) || url
  }

  useEffect(() => {
    setShouldLoadVideo(true)
  }, [])

  const handleDurationChange = useCallback((value: number) => {
    setDuration(value)
  }, [])

  const handleTimeProgress = useCallback((value: number) => {
    setCurrentTime(value)
  }, [])

  const handlePlaybackPlay = useCallback(() => {
    setIsPlaying(true)
    setHasEnded(false)
  }, [])

  const handlePlaybackPause = useCallback(() => {
    setIsPlaying(false)
  }, [])

  const handlePlaybackEnded = useCallback(() => {
    setHasEnded(true)
    setIsPlaying(false)
  }, [])

  const handleCountView = useCallback(async () => {
    try {
      await appwriteService.incrementPostField(post.id, 'views', 1)
    } catch (error) {
      console.error('Failed to track reel view:', error)
    }
  }, [post.id])

  const {
    videoRef,
    isVideoReady,
    playVideo,
    pauseVideo,
  } = useSingleVideoPlayback({
    postId: post.id,
    shouldLoadVideo,
    muted: isMuted,
    enableInstreamAds: true,
    adPlacement: 'reels-detail',
    shouldPause: showComments || showFullComments,
    onDurationChange: handleDurationChange,
    onTimeUpdate: handleTimeProgress,
    onPlay: handlePlaybackPlay,
    onPause: handlePlaybackPause,
    onEnded: handlePlaybackEnded,
    onCountView: handleCountView,
    loop: false,
  })

  useEffect(() => {
    const handlePopState = () => {
      if (showFullComments) setShowFullComments(false)
      else if (showComments) setShowComments(false)
    }
    
    if (showFullComments || showComments) {
      window.history.pushState(null, '', window.location.href)
      window.addEventListener('popstate', handlePopState)
      return () => window.removeEventListener('popstate', handlePopState)
    }
  }, [showFullComments, showComments])

  // Subscribe to realtime updates for this post
  useEffect(() => {
    if (!post.id) return

    const unsubscribe = appwriteService.subscribeToDocument('posts', post.id, (payload) => {
      if (payload.events.includes('databases.*.collections.posts.documents.*.update')) {
        const updatedPost = payload.payload
        setLikes(updatedPost.likes || 0)
        setReposts(updatedPost.reposts || 0)
        setComments(updatedPost.comments || 0)
        setViews(updatedPost.views || 0)
      }
    })

    return unsubscribe
  }, [post.id])

  const togglePlay = () => {
    const video = videoRef.current
    if (!video) return

    if (hasEnded) {
      video.currentTime = 0
      setHasEnded(false)
    }

    if (video.paused) {
      playVideo()
    } else {
      pauseVideo()
    }
  }

  const toggleMute = () => {
    const video = videoRef.current
    if (!video) return

    video.muted = !video.muted
    setIsMuted(video.muted)
  }

  const videoSource = toVideoProxyUrl(
    post.mediaUrls?.[0] ||
    (post as any).mediaUrl ||
    (post as any).mediaURl ||
    (post as any).videoUrl
  )
  const videoPoster = toImageProxyUrl(
    post.thumbnailUrl ||
    (post as any).thumbnailUrl ||
    (post as any).thumbnail
  )

  const handleVideoClick = () => {
    togglePlay()
    setShowControls(true)

    if (controlsTimeoutRef.current) {
      clearTimeout(controlsTimeoutRef.current)
    }

    controlsTimeoutRef.current = setTimeout(() => {
      setShowControls(false)
    }, 2000)
  }

  const handleLike = async () => {
    try {
      if (liked) {
        await appwriteService.unlikePost(post.id)
        setLiked(false)
        setLikes(Math.max(0, likes - 1))
      } else {
        await appwriteService.likePost(post.id)
        setLiked(true)
        setLikes(likes + 1)
      }
    } catch (error) {
      console.error('Failed to toggle like:', error)
    }
  }



  const handleSave = async () => {
    try {
      await appwriteService.savePost(post.id)
      setSaved(!saved)
    } catch (error) {
      console.error('Failed to toggle save:', error)
    }
  }

  const handleRepost = async () => {
    try {
      await appwriteService.repostPost(post.id)
      setReposted(!reposted)
      setReposts(reposted ? Math.max(0, reposts - 1) : reposts + 1)
    } catch (error) {
      console.error('Failed to toggle repost:', error)
    }
  }

  const handleShare = async () => {
    try {
      if (navigator.share) {
        await navigator.share({
          title: post.title || 'Check out this reel',
          text: post.content || '',
          url: window.location.href
        })
      }
    } catch (error) {
      console.error('Failed to share:', error)
    }
  }

  if (showFullComments) {
    return <CommentScreen post={post} onClose={() => setShowFullComments(false)} />
  }

  return (
    <>
      {showComments && <CommentModal post={post} onClose={() => setShowComments(false)} />}
      <div className="fixed inset-0 bg-black lg:bg-black/85 z-50 lg:flex lg:items-center lg:justify-center">
      {/* Full screen vertical video */}
      <div className="relative w-full h-full lg:w-[450px] lg:h-[calc(100vh-80px)] lg:max-h-[800px] lg:rounded-2xl lg:overflow-hidden lg:shadow-2xl bg-black border border-transparent lg:border-gray-800">
        {shouldLoadVideo ? (
        <>
        <video
          ref={videoRef}
          src={videoSource}
          poster={videoPoster || undefined}
          className="w-full h-full object-cover"
          onClick={handleVideoClick}
          playsInline
          preload="auto"
        />
        {!isVideoReady && (
          <div className="absolute inset-0 flex items-center justify-center bg-black/50">
            <div className="animate-spin rounded-full h-12 w-12 border-4 border-white/30 border-t-white" />
          </div>
        )}
        </>
        ) : (
          <div className="w-full h-full bg-gray-900" />
        )}

        {/* Top Controls */}
        <div className="absolute top-0 left-0 right-0 z-20 p-4">
          <div className="flex items-center justify-between">
            <button
              onClick={onClose}
              className="w-10 h-10 bg-black/50 backdrop-blur-sm rounded-full flex items-center justify-center text-white hover:bg-black/70 transition-colors"
              aria-label="Close reel"
            >
              <ArrowLeft size={20} />
            </button>
            <button
              onClick={toggleMute}
              className="w-10 h-10 bg-black/50 backdrop-blur-sm rounded-full flex items-center justify-center text-white hover:bg-black/70 transition-colors"
              aria-label={isMuted ? "Unmute reel" : "Mute reel"}
            >
              {isMuted ? <VolumeX size={20} /> : <Volume2 size={20} />}
            </button>
          </div>
        </div>

        {/* Center Play Button */}
        {!isPlaying && duration > 0 && (
          <div className="absolute inset-0 flex items-center justify-center z-10">
            <button
              onClick={(e) => {
                e.stopPropagation()
                togglePlay()
              }}
              className="w-16 h-16 bg-white/20 backdrop-blur-sm rounded-full flex items-center justify-center text-white hover:bg-white/30 transition-all transform hover:scale-110"
              aria-label={hasEnded ? "Rewatch reel" : "Play reel"}
            >
              {hasEnded ? (
                <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8" />
                  <path d="M3 3v5h5" />
                </svg>
              ) : (
                <Play size={32} fill="white" />
              )}
            </button>
          </div>
        )}

        {/* Right Side Reactions (Vertical) */}
        <div className="absolute right-3 bottom-24 flex flex-col items-center gap-4 z-20">
          <button
            onClick={handleLike}
            className={`flex flex-col items-center gap-1 transition-all ${liked ? 'text-red-500' : 'text-white'}`}
            aria-label={liked ? "Unlike reel" : "Like reel"}
          >
            <div className="w-12 h-12 bg-white/10 backdrop-blur-sm rounded-full flex items-center justify-center hover:bg-white/20 transition-all">
              <Heart size={24} className={liked ? 'fill-red-500' : ''} />
            </div>
            <span className="text-sm font-bold">{formatCount(likes)}</span>
          </button>

          <button
            onClick={() => {
              setShowComments(true)
              pauseVideo()
            }}
            className="flex flex-col items-center gap-1 text-white"
            aria-label="View comments"
          >
            <div className="w-12 h-12 bg-white/10 backdrop-blur-sm rounded-full flex items-center justify-center hover:bg-white/20 transition-all">
              <MessageCircle size={24} />
            </div>
            <span className="text-sm font-bold">{formatCount(comments)}</span>
          </button>

          <button
            onClick={handleRepost}
            className={`flex flex-col items-center gap-1 transition-all ${reposted ? 'text-green-500' : 'text-white'}`}
            aria-label="Repost reel"
          >
            <div className="w-12 h-12 bg-white/10 backdrop-blur-sm rounded-full flex items-center justify-center hover:bg-white/20 transition-all">
              <Repeat2 size={24} className={reposted ? 'fill-green-500' : ''} />
            </div>
            <span className="text-sm font-bold">{formatCount(reposts)}</span>
          </button>

          <button
            onClick={handleSave}
            className={`flex flex-col items-center gap-1 transition-all ${saved ? 'text-yellow-500' : 'text-white'}`}
            aria-label="Save reel"
          >
            <div className="w-12 h-12 bg-white/10 backdrop-blur-sm rounded-full flex items-center justify-center hover:bg-white/20 transition-all">
              <Bookmark size={24} className={saved ? 'fill-yellow-500' : ''} />
            </div>
            <span className="text-sm font-bold">Save</span>
          </button>

          <button
            onClick={handleShare}
            className="flex flex-col items-center gap-1 text-white"
            aria-label="Share reel"
          >
            <div className="w-12 h-12 bg-white/10 backdrop-blur-sm rounded-full flex items-center justify-center hover:bg-white/20 transition-all">
              <Share size={24} />
            </div>
            <span className="text-sm font-bold">Share</span>
          </button>
        </div>

        {/* Bottom Content Overlay */}
        <div className="absolute bottom-0 left-0 right-20 bg-gradient-to-t from-black/90 via-black/60 to-transparent p-6 z-20">
          <div className="max-w-md">
            <div className="flex items-center gap-3 mb-3">
              {post.userAvatar ? (
                <img src={toImageProxyUrl(post.userAvatar)} alt={post.displayName} className="w-14 h-14 rounded-full object-cover border-2 border-white" />
              ) : (
                <div className="w-14 h-14 rounded-full bg-gray-600 border-2 border-white flex items-center justify-center text-white font-semibold text-lg">
                  {(post.displayName || 'U')[0].toUpperCase()}
                </div>
              )}
              <div className="flex-1">
                <div className="flex items-center gap-2">
                  <span className="text-white font-bold text-lg flex items-center gap-1">
                    {post.displayName || 'User'}
                    {post.isVerified && <VerifiedBadge className="h-4 w-4" />}
                  </span>
                  <span className="flex items-center gap-1 text-gray-300 text-sm">
                    <Eye size={14} />
                    {formatCount(views)}
                  </span>
                </div>
                <span className="text-gray-300 text-sm">{formatTimeAgo(post.createdAt)}</span>
              </div>
            </div>
            {post.title && (
              <p className="text-white text-[15px] font-medium leading-[1.85] tracking-[0.03em] line-clamp-3">
                {post.title}
              </p>
            )}
          </div>
        </div>

        {/* Progress Bar */}
        <div className="absolute bottom-0 left-0 right-0 z-20">
          <div className="w-full h-0.5 bg-white/30 rounded-full overflow-hidden">
            <div
              className="h-full bg-white rounded-full transition-all duration-100"
              style={{ width: duration ? `${(currentTime / duration) * 100}%` : '0%' }}
            />
          </div>
        </div>
      </div>
    </div>
    </>
  )
}

