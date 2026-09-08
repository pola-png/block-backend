'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { playAdcashInstreamAd } from './lib/instream-ads'

interface UseSingleVideoPlaybackOptions {
  postId: string
  shouldLoadVideo: boolean
  muted: boolean
  shouldPause?: boolean
  loop?: boolean
  onDurationChange?: (duration: number) => void
  onTimeUpdate?: (time: number) => void
  onPlay?: () => void
  onPause?: () => void
  onEnded?: () => void
  onCountView?: () => Promise<void> | void
  resetViewCountOnEnded?: boolean
  enableInstreamAds?: boolean
  adPlacement?: string
}

export function useSingleVideoPlayback({
  postId,
  shouldLoadVideo,
  muted,
  shouldPause = false,
  loop = false,
  onDurationChange,
  onTimeUpdate,
  onPlay,
  onPause,
  onEnded,
  onCountView,
  resetViewCountOnEnded = true,
  enableInstreamAds = false,
  adPlacement = 'video-player',
}: UseSingleVideoPlaybackOptions) {
  const [isPageVisible, setIsPageVisible] = useState(true)
  const [isVideoReady, setIsVideoReady] = useState(false)
  const videoRef = useRef<HTMLVideoElement>(null)
  const hasCountedView = useRef(false)
  const userPaused = useRef(false)
  const playTicket = useRef(0)
  const hasAttemptedAdForPost = useRef(false)

  const pauseAllVideos = useCallback((except?: HTMLVideoElement | null) => {
    if (typeof document === 'undefined') return
    document.querySelectorAll('video').forEach((video) => {
      if (video !== except) {
        video.pause()
      }
    })
  }, [])

  const setUserPaused = useCallback((paused: boolean) => {
    userPaused.current = paused
  }, [])

  const playVideo = useCallback(async () => {
    const video = videoRef.current
    if (!video) return
    const ticket = ++playTicket.current
    userPaused.current = false

    if (
      enableInstreamAds &&
      !hasAttemptedAdForPost.current &&
      ticket === playTicket.current
    ) {
      hasAttemptedAdForPost.current = true
      if (ticket !== playTicket.current) return
      await playAdcashInstreamAd({ placement: `${adPlacement}:manual`, videoId: postId })
    }
    if (ticket !== playTicket.current) return
    if (!videoRef.current || videoRef.current !== video) return
    pauseAllVideos(video)
    video.play().catch(() => {})
  }, [adPlacement, enableInstreamAds, pauseAllVideos])

  const pauseVideo = useCallback(() => {
    userPaused.current = true
    videoRef.current?.pause()
  }, [])

  useEffect(() => {
    userPaused.current = false
    setIsVideoReady(false)
    hasCountedView.current = false
    hasAttemptedAdForPost.current = false
    playTicket.current += 1
  }, [postId])

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
  }, [pauseAllVideos])

  useEffect(() => {
    const video = videoRef.current
    if (!video || !shouldLoadVideo) return

    const handleLoadStart = () => setIsVideoReady(false)
    const handleLoadedMetadata = () => {
      onDurationChange?.(video.duration)
      // Metadata is enough to show a visual preview (poster/first frame)
      setIsVideoReady(true)
    }
    const handleCanPlay = () => {
      setIsVideoReady(true)
    }
    const handleCanPlayThrough = () => setIsVideoReady(true)
    const handleTimeUpdate = () => {
      onTimeUpdate?.(video.currentTime)
    }
    const handlePlay = () => {
      onPlay?.()
      if (!hasCountedView.current && onCountView) {
        hasCountedView.current = true
        void Promise.resolve(onCountView())
      }
    }
    const handlePause = () => {
      onPause?.()
    }
    const handleEnded = () => {
      if (resetViewCountOnEnded) {
        hasCountedView.current = false
      }
      userPaused.current = true
      onEnded?.()
    }

    video.addEventListener('loadstart', handleLoadStart)
    video.addEventListener('loadedmetadata', handleLoadedMetadata)
    video.addEventListener('canplay', handleCanPlay)
    video.addEventListener('canplaythrough', handleCanPlayThrough)
    video.addEventListener('timeupdate', handleTimeUpdate)
    video.addEventListener('play', handlePlay)
    video.addEventListener('pause', handlePause)
    video.addEventListener('ended', handleEnded)

    return () => {
      video.pause()
      video.removeEventListener('loadstart', handleLoadStart)
      video.removeEventListener('loadedmetadata', handleLoadedMetadata)
      video.removeEventListener('canplay', handleCanPlay)
      video.removeEventListener('canplaythrough', handleCanPlayThrough)
      video.removeEventListener('timeupdate', handleTimeUpdate)
      video.removeEventListener('play', handlePlay)
      video.removeEventListener('pause', handlePause)
      video.removeEventListener('ended', handleEnded)
    }
  }, [
    onCountView,
    onDurationChange,
    onEnded,
    onPause,
    onPlay,
    onTimeUpdate,
    postId,
    resetViewCountOnEnded,
    shouldLoadVideo,
  ])

  useEffect(() => {
    const video = videoRef.current
    if (!video || !shouldLoadVideo) return
    video.muted = muted
  }, [muted, shouldLoadVideo])

  useEffect(() => {
    const video = videoRef.current
    if (!video || !shouldLoadVideo) return

    video.loop = loop

    const shouldBlockPlay =
      !isPageVisible ||
      shouldPause ||
      userPaused.current ||
      !isVideoReady ||
      video.readyState < 3

    if (shouldBlockPlay) {
      playTicket.current += 1
      video.pause()
      return
    }

    if (!video.paused) return

    const ticket = ++playTicket.current
    const tryPlay = async () => {
      if (
        enableInstreamAds &&
        !hasAttemptedAdForPost.current &&
        ticket === playTicket.current
      ) {
        hasAttemptedAdForPost.current = true
        if (ticket !== playTicket.current) return
        await playAdcashInstreamAd({ placement: `${adPlacement}:autoplay`, videoId: postId })
      }
      if (ticket !== playTicket.current) return
      const latestVideo = videoRef.current
      if (!latestVideo) return

      const blockedNow =
        !isPageVisible ||
        shouldPause ||
        userPaused.current ||
        !isVideoReady ||
        latestVideo.readyState < 3

      if (blockedNow) return

      pauseAllVideos(latestVideo)
      if (latestVideo.paused) {
        latestVideo.play().catch(() => {})
      }
    }

    void tryPlay()
  }, [adPlacement, enableInstreamAds, isPageVisible, isVideoReady, loop, pauseAllVideos, shouldLoadVideo, shouldPause, postId])

  useEffect(() => {
    return () => {
      pauseAllVideos()
    }
  }, [pauseAllVideos])

  return {
    videoRef,
    isVideoReady,
    pauseAllVideos,
    setUserPaused,
    playVideo,
    pauseVideo,
  }
}
