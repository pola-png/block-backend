'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import appwriteService from './appwriteService'
import { CreatorPlan, getUploadAccess } from './lib/creator-plan'
import { upsertUploadProgressItem } from './lib/upload-progress'

export const VIDEO_DURATION_LIMIT_SECONDS = 126
export const DURATION_GUARD_MESSAGE =
  'Free users can upload up to 2.1 minutes. Upgrade or verify to upload longer videos.'

export type UploadKind = 'video' | 'reel' | 'image' | 'news'
export type VideoStep = 'select' | 'details'

interface LocalImageItem {
  id: string
  file: File
  url: string
}

function makeLocalId() {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 9)}`
}

interface UseUploadFlowOptions {
  onUploadSuccess: (userId?: string) => void
}

export function useUploadFlow({ onUploadSuccess }: UseUploadFlowOptions) {
  const router = useRouter()

  const [selectedType, setSelectedType] = useState<UploadKind | null>(null)
  const [videoStep, setVideoStep] = useState<VideoStep>('select')
  const [uploading, setUploading] = useState(false)

  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [content, setContent] = useState('')
  const [textBgColor, setTextBgColor] = useState('')

  const [seoTitle, setSeoTitle] = useState('')
  const [seoDescription, setSeoDescription] = useState('')
  const [seoKeywords, setSeoKeywords] = useState('')
  const [seoCategory, setSeoCategory] = useState('')
  const [aiBrief, setAiBrief] = useState('')
  const [aiAudience, setAiAudience] = useState('')
  const [aiFocusKeywords, setAiFocusKeywords] = useState('')
  const [isGeneratingAi, setIsGeneratingAi] = useState(false)

  const [selectedVideoFile, setSelectedVideoFile] = useState<File | null>(null)
  const [videoPreviewUrl, setVideoPreviewUrl] = useState<string | null>(null)
  const [videoDuration, setVideoDuration] = useState<number | null>(null)
  const [durationError, setDurationError] = useState<string | null>(null)

  const [customThumbnail, setCustomThumbnail] = useState<File | null>(null)
  const [customThumbnailPreviewUrl, setCustomThumbnailPreviewUrl] = useState<string | null>(null)
  const [generatedThumbnail, setGeneratedThumbnail] = useState<File | null>(null)
  const [generatedThumbnailPreviewUrl, setGeneratedThumbnailPreviewUrl] = useState<string | null>(null)

  const [imageItems, setImageItems] = useState<LocalImageItem[]>([])

  const [isDark, setIsDark] = useState(false)
  const [isAdmin, setIsAdmin] = useState(false)
  const [currentUserId, setCurrentUserId] = useState('')
  const [creatorPlan, setCreatorPlan] = useState<CreatorPlan>('free')
  const [canUploadLongVideo, setCanUploadLongVideo] = useState(false)
  const [canUseAi, setCanUseAi] = useState(false)
  const [avatarUrl, setAvatarUrl] = useState('')
  const [displayName, setDisplayName] = useState('You')
  const [hasLoadedUser, setHasLoadedUser] = useState(false)

  const textColors = [
    '#111827',
    '#EF4444',
    '#F97316',
    '#F59E0B',
    '#10B981',
    '#0EA5E9',
    '#3B82F6',
    '#6366F1',
    '#8B5CF6',
    '#EC4899',
  ]

  const isVideoType = selectedType === 'video' || selectedType === 'reel'
  const isTextImageType = selectedType === 'image'
  const overDurationLimit =
    isVideoType &&
    !canUploadLongVideo &&
    (videoDuration ?? 0) > VIDEO_DURATION_LIMIT_SECONDS

  const activeThumbnailPreviewUrl = customThumbnailPreviewUrl || generatedThumbnailPreviewUrl

  useEffect(() => {
    const savedTheme = localStorage.getItem('theme')
    const systemDark = window.matchMedia('(prefers-color-scheme: dark)').matches
    const shouldBeDark = savedTheme === 'dark' || (!savedTheme && systemDark)
    setIsDark(shouldBeDark)
  }, [])

  useEffect(() => {
    const loadUser = async () => {
      try {
        const user = await appwriteService.getCurrentUser()
        if (!user) return

        const [admin, profile] = await Promise.all([
          appwriteService.isCurrentUserAdmin().catch(() => false),
          appwriteService.getProfileByUserId(user.$id).catch(() => null),
        ])

        setCurrentUserId(user.$id)
        const access = getUploadAccess(profile, admin)
        setIsAdmin(admin)
        setCreatorPlan(access.plan)
        setCanUploadLongVideo(access.canUploadLongVideo)
        setCanUseAi(admin || access.plan === 'business')
        setAvatarUrl(profile?.avatarUrl || '')
        setDisplayName(profile?.displayName || profile?.username || user.name || 'You')
      } catch {
        setIsAdmin(false)
        setCreatorPlan('free')
        setCanUploadLongVideo(false)
        setCanUseAi(false)
      } finally {
        setHasLoadedUser(true)
      }
    }

    void loadUser()
  }, [])

  useEffect(() => {
    return () => {
      if (videoPreviewUrl) URL.revokeObjectURL(videoPreviewUrl)
      if (customThumbnailPreviewUrl) URL.revokeObjectURL(customThumbnailPreviewUrl)
      if (generatedThumbnailPreviewUrl) URL.revokeObjectURL(generatedThumbnailPreviewUrl)
      imageItems.forEach((item) => URL.revokeObjectURL(item.url))
    }
  }, [videoPreviewUrl, customThumbnailPreviewUrl, generatedThumbnailPreviewUrl, imageItems])

  const clearImages = () => {
    setImageItems((prev) => {
      prev.forEach((item) => URL.revokeObjectURL(item.url))
      return []
    })
  }

  const clearVideo = () => {
    if (videoPreviewUrl) URL.revokeObjectURL(videoPreviewUrl)
    if (customThumbnailPreviewUrl) URL.revokeObjectURL(customThumbnailPreviewUrl)
    if (generatedThumbnailPreviewUrl) URL.revokeObjectURL(generatedThumbnailPreviewUrl)

    setSelectedVideoFile(null)
    setVideoPreviewUrl(null)
    setVideoDuration(null)
    setDurationError(null)
    setCustomThumbnail(null)
    setCustomThumbnailPreviewUrl(null)
    setGeneratedThumbnail(null)
    setGeneratedThumbnailPreviewUrl(null)
  }

  const clearComposer = () => {
    setTitle('')
    setDescription('')
    setContent('')
    setTextBgColor('')
    setSeoTitle('')
    setSeoDescription('')
    setSeoKeywords('')
    setSeoCategory('')
    setAiBrief('')
    setAiAudience('')
    setAiFocusKeywords('')
    clearVideo()
    clearImages()
  }

  const selectType = (type: UploadKind, disabled: boolean, requires: CreatorPlan) => {
    if (disabled) {
      alert(
        requires === 'business'
          ? 'Business plan is required for this upload type.'
          : 'This upload type is not available for your account.'
      )
      router.push('/premium')
      return
    }
    clearComposer()
    setSelectedType(type)
  }

  const generateVideoThumbnail = (videoFile: File): Promise<{ file: File; url: string } | null> => {
    return new Promise((resolve) => {
      const video = document.createElement('video')
      const canvas = document.createElement('canvas')
      const ctx = canvas.getContext('2d')

      video.preload = 'metadata'
      video.src = URL.createObjectURL(videoFile)
      video.muted = true
      video.currentTime = 1

      video.onloadedmetadata = () => {
        canvas.width = 480
        canvas.height = Math.round((video.videoHeight / Math.max(video.videoWidth, 1)) * 480)
        video.onseeked = () => {
          if (!ctx) {
            URL.revokeObjectURL(video.src)
            resolve(null)
            return
          }

          ctx.drawImage(video, 0, 0, canvas.width, canvas.height)
          canvas.toBlob(
            (blob) => {
              URL.revokeObjectURL(video.src)
              if (!blob) {
                resolve(null)
                return
              }
              const file = new File([blob], `thumbnail_${Date.now()}.jpg`, { type: 'image/jpeg' })
              const url = URL.createObjectURL(file)
              resolve({ file, url })
            },
            'image/jpeg',
            0.82
          )
        }
      }

      video.onerror = () => {
        URL.revokeObjectURL(video.src)
        resolve(null)
      }
    })
  }

  const handleVideoMetadata = (durationSeconds: number) => {
    setVideoDuration(durationSeconds)
    if (!canUploadLongVideo && durationSeconds > VIDEO_DURATION_LIMIT_SECONDS) {
      setDurationError(DURATION_GUARD_MESSAGE)
      return
    }
    setDurationError(null)
  }

  const handleVideoSelect = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0]
    event.target.value = ''
    if (!file) return
    if (!file.type.startsWith('video/')) {
      alert('Please choose a valid video file.')
      return
    }

    clearVideo()
    setSelectedVideoFile(file)
    setVideoPreviewUrl(URL.createObjectURL(file))

    const generated = await generateVideoThumbnail(file)
    if (generated) {
      setGeneratedThumbnail(generated.file)
      setGeneratedThumbnailPreviewUrl(generated.url)
    }
  }

  const handleThumbnailSelect = (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0]
    event.target.value = ''
    if (!file) return
    if (!file.type.startsWith('image/')) {
      alert('Please choose an image file for thumbnail.')
      return
    }
    if (file.size > 11 * 1024 * 1024) {
      alert('Thumbnail must be below 11MB.')
      return
    }

    if (customThumbnailPreviewUrl) URL.revokeObjectURL(customThumbnailPreviewUrl)
    setCustomThumbnail(file)
    setCustomThumbnailPreviewUrl(URL.createObjectURL(file))
  }

  const handleImagesSelect = (event: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(event.target.files || []).filter((file) => file.type.startsWith('image/'))
    event.target.value = ''
    if (files.length === 0) return

    const newItems = files.map((file) => ({
      id: makeLocalId(),
      file,
      url: URL.createObjectURL(file),
    }))
    setImageItems((prev) => [...prev, ...newItems])
    setTextBgColor('')
  }

  const removeImageItem = (id: string) => {
    setImageItems((prev) => {
      const item = prev.find((entry) => entry.id === id)
      if (item) URL.revokeObjectURL(item.url)
      return prev.filter((entry) => entry.id !== id)
    })
  }

  const applyLocalSeoFallback = () => {
    if (!canUseAi) return
    if (!isVideoType) return

    const baseText = `${title} ${description} ${content}`.trim()
    const hashtags = (baseText.match(/#\w+/g) || []).map((tag) => tag.replace('#', '').toLowerCase())
    const focusHints = aiFocusKeywords
      .split(',')
      .map((item) => item.trim().toLowerCase())
      .filter(Boolean)
    const keywordFallback = Array.from(new Set([...focusHints, ...hashtags])).slice(0, 10).join(', ')

    setSeoTitle((prev) => prev || title || `${selectedType === 'reel' ? 'Reel' : 'Video'} update`)
    setSeoDescription((prev) => prev || description || content.slice(0, 160))
    setSeoKeywords((prev) => prev || keywordFallback)
    setSeoCategory((prev) => prev || 'Entertainment')
  }

  const handleGenerateSeo = async () => {
    if (!canUseAi) return
    if (!isVideoType) return
    if (isGeneratingAi) return

    setIsGeneratingAi(true)
    try {
      const response = await fetch('/api/ai/upload-metadata', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${(await appwriteService.createJWT()).jwt}`,
        },
        body: JSON.stringify({
          postType: selectedType,
          title,
          description,
          content,
          seoTitle,
          seoDescription,
          seoKeywords,
          seoCategory,
          aiBrief,
          aiAudience,
          aiFocusKeywords,
        }),
      })

      if (!response.ok) {
        throw new Error('AI generation request failed.')
      }

      const payload = await response.json()
      if (payload?.title) setTitle(String(payload.title))
      if (payload?.description) setDescription(String(payload.description))
      if (payload?.seoTitle) setSeoTitle(String(payload.seoTitle))
      if (payload?.seoDescription) setSeoDescription(String(payload.seoDescription))
      if (payload?.seoKeywords) setSeoKeywords(String(payload.seoKeywords))
      if (payload?.seoCategory) setSeoCategory(String(payload.seoCategory))
    } catch {
      applyLocalSeoFallback()
      alert('AI service is unavailable right now. Applied local SEO suggestions.')
    } finally {
      setIsGeneratingAi(false)
    }
  }

  const uploadToAppwrite = async (file: File) => {
    const result = await appwriteService.uploadFile(file)
    return `appwrite://6915baaa00381391d7b2/${result.id}/${encodeURIComponent(file.name)}`
  }

  const validateBeforeUpload = () => {
    if (!selectedType) return 'Please select an upload type.'

    if (selectedType === 'news' && !(isAdmin || creatorPlan === 'business')) {
      return 'News upload requires Business plan.'
    }

    if (isVideoType) {
      if (!selectedVideoFile) return 'Please choose a video first.'
      if (overDurationLimit) return DURATION_GUARD_MESSAGE
    }

    if (selectedType === 'image') {
      if (!content.trim() && imageItems.length === 0) {
        return 'Write text or choose at least one image.'
      }
    }

    if (selectedType === 'news' && !title.trim() && !content.trim()) {
      return 'Please add title or content for news.'
    }

    return null
  }

  const handleUpload = async () => {
    const validationError = validateBeforeUpload()
    if (validationError) {
      alert(validationError)
      return
    }

    setUploading(true)
    const uploadId = `${Date.now()}-${Math.random().toString(36).slice(2, 9)}`
    const ownerId = currentUserId || 'unknown-user'
    const effectivePostTypeSeed =
      selectedType === 'image' && imageItems.length === 0 ? 'text' : selectedType

    const totalAssets =
      (selectedVideoFile ? 1 : 0) +
      (customThumbnail || generatedThumbnail ? 1 : 0) +
      imageItems.length
    const totalSteps = Math.max(1, totalAssets + 1) // +1 create post
    let completedSteps = 0

    const updateProgress = (message: string, status: 'uploading' | 'completed' | 'failed' = 'uploading', error?: string) => {
      const percent =
        status === 'completed'
          ? 100
          : status === 'failed'
            ? Math.min(99, Math.max(5, Math.round((completedSteps / totalSteps) * 100)))
            : Math.min(99, Math.max(5, Math.round((completedSteps / totalSteps) * 100)))
      upsertUploadProgressItem({
        id: uploadId,
        userId: ownerId,
        postType: (effectivePostTypeSeed || 'text') as 'video' | 'reel' | 'image' | 'news' | 'text',
        title: title.trim() || undefined,
        content: content.trim() || undefined,
        progress: percent,
        status,
        message,
        error,
        updatedAt: Date.now(),
      })
    }

    updateProgress('Preparing upload...')
    onUploadSuccess(currentUserId || undefined)

    try {
      const effectivePostType =
        selectedType === 'image' && imageItems.length === 0 ? 'text' : selectedType

      const formData = new FormData()
      formData.append('postType', effectivePostType || 'text')
      if (content.trim()) formData.append('content', content.trim())
      if (title.trim()) formData.append('title', title.trim())
      if (description.trim()) formData.append('description', description.trim())

      if (effectivePostType === 'text' && textBgColor && content.trim()) {
        formData.append('textBgColor', textBgColor)
      }

      if (isVideoType) {
        if (seoTitle.trim()) formData.append('seoTitle', seoTitle.trim())
        if (seoDescription.trim()) formData.append('seoDescription', seoDescription.trim())
        if (seoKeywords.trim()) formData.append('seoKeywords', seoKeywords.trim())
        if (seoCategory.trim()) formData.append('seoCategory', seoCategory.trim())

        if (selectedVideoFile) {
          const videoUrl = await uploadToAppwrite(selectedVideoFile)
          formData.append('mediaUrl', videoUrl)
          completedSteps += 1
          updateProgress('Video uploaded')
        }

        const thumbnailFile = customThumbnail || generatedThumbnail
        if (thumbnailFile) {
          const thumbnailUrl = await uploadToAppwrite(thumbnailFile)
          formData.append('thumbnailUrl', thumbnailUrl)
          completedSteps += 1
          updateProgress('Thumbnail uploaded')
        }
      }

      if (selectedType === 'image' && imageItems.length > 0) {
        let imageIndex = 0
        for (const item of imageItems) {
          const imageUrl = await uploadToAppwrite(item.file)
          formData.append('mediaUrl', imageUrl)
          imageIndex += 1
          completedSteps += 1
          updateProgress(`Uploaded image ${imageIndex}/${imageItems.length}`)
        }
      }

      const jwt = await appwriteService.createJWT()
      if (!jwt?.jwt) {
        throw new Error('Failed to create auth token.')
      }

      const response = await fetch('/api/posts/create', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${jwt.jwt}`,
        },
        credentials: 'include',
        body: formData,
      })

      const isJson = response.headers.get('content-type')?.includes('application/json')
      if (!isJson) {
        throw new Error('Server returned an invalid response.')
      }

      const payload = await response.json()
      if (!response.ok) {
        throw new Error(payload?.error || 'Failed to create post.')
      }
      completedSteps += 1
      updateProgress('Upload completed', 'completed')

      alert('Post uploaded successfully.')
      clearComposer()
      setSelectedType(null)
      setVideoStep('select')
    } catch (error: any) {
      updateProgress('Upload failed', 'failed', error?.message || 'Unknown error')
      alert(error?.message || 'Upload failed. Please try again.')
    } finally {
      setUploading(false)
    }
  }

  return {
    selectedType,
    setSelectedType,
    videoStep,
    setVideoStep,
    uploading,

    title,
    setTitle,
    description,
    setDescription,
    content,
    setContent,
    textBgColor,
    setTextBgColor,

    seoTitle,
    setSeoTitle,
    seoDescription,
    setSeoDescription,
    seoKeywords,
    setSeoKeywords,
    seoCategory,
    setSeoCategory,
    aiBrief,
    setAiBrief,
    aiAudience,
    setAiAudience,
    aiFocusKeywords,
    setAiFocusKeywords,
    isGeneratingAi,

    selectedVideoFile,
    videoPreviewUrl,
    videoDuration,
    durationError,
    customThumbnail,
    generatedThumbnail,
    imageItems,

    isDark,
    isAdmin,
    currentUserId,
    creatorPlan,
    hasLoadedUser,
    canUseAi,
    textColors,
    avatarUrl,
    displayName,

    isVideoType,
    isTextImageType,
    overDurationLimit,
    activeThumbnailPreviewUrl,

    clearVideo,
    selectType,
    handleVideoMetadata,
    handleVideoSelect,
    handleThumbnailSelect,
    handleImagesSelect,
    removeImageItem,
    handleGenerateSeo,
    handleUpload,
  }
}
