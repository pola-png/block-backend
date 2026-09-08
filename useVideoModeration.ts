import { useEffect, useRef, useState } from 'react'
import { checkVideoForNudity, flagPost } from './lib/contentModeration'

export function useVideoModeration(postId: string, videoRef: React.RefObject<HTMLVideoElement>) {
  const [isChecked, setIsChecked] = useState(false)
  const hasChecked = useRef(false)

  useEffect(() => {
    if (!videoRef.current || hasChecked.current || isChecked) return

    const checkVideo = async () => {
      try {
        const video = videoRef.current
        if (!video) return

        // Wait for video to load metadata
        if (video.readyState < 2) {
          video.addEventListener('loadedmetadata', checkVideo, { once: true })
          return
        }

        hasChecked.current = true
        const result = await checkVideoForNudity(video)

        if (!result.isSafe) {
          console.warn('Inappropriate content detected:', result.flagReason)
          await flagPost(postId, result.flagReason || 'Sexual policy violation')
          
          // Pause and hide video
          video.pause()
          video.style.display = 'none'
        }

        setIsChecked(true)
      } catch (error) {
        console.error('Video moderation error:', error)
        setIsChecked(true)
      }
    }

    checkVideo()
  }, [postId, videoRef, isChecked])

  return { isChecked }
}
