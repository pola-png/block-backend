'use client'

import { useEffect, useLayoutEffect, useRef } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import {
  NewsComposer,
  TextImageComposer,
  UploadKind,
  VideoDetailsStep,
  VideoSelectStep,
} from './components/upload/UploadViews'
import { DURATION_GUARD_MESSAGE, useUploadFlow } from './useUploadFlow'

interface UploadScreenProps {
  onClose?: () => void
}

export function UploadScreen({ onClose }: UploadScreenProps) {
  const router = useRouter()
  const searchParams = useSearchParams()
  const videoInputRef = useRef<HTMLInputElement>(null)
  const imageInputRef = useRef<HTMLInputElement>(null)
  const thumbnailInputRef = useRef<HTMLInputElement>(null)

  const handleCloseUpload = () => {
    if (onClose) {
      onClose()
      return
    }
    if (window.history.length > 1) {
      router.back()
      return
    }
    router.push('/')
  }

  const flow = useUploadFlow({
    onUploadSuccess: (userId) => {
      if (userId) {
        router.push(`/profile/${userId}`)
        return
      }
      router.push('/profile')
    },
  })

  const requestedType = searchParams.get('type') as UploadKind | null
  const hasRequestedType = !!requestedType && ['video', 'reel', 'image', 'news'].includes(requestedType)

  useLayoutEffect(() => {
    if (flow.selectedType) return
    if (!hasRequestedType) return
    if (!requestedType) return
    if (requestedType === 'news') return

    flow.selectType(requestedType, false, 'free')
  }, [flow.selectedType, flow.selectType, hasRequestedType, requestedType])

  useEffect(() => {
    if (flow.selectedType) return
    if (!flow.hasLoadedUser) return
    if (!hasRequestedType) return
    if (!requestedType) return
    if (requestedType !== 'news') return

    const disabled = !(flow.isAdmin || flow.creatorPlan === 'business')
    flow.selectType(requestedType, disabled, 'business')
  }, [
    flow.selectedType,
    flow.hasLoadedUser,
    flow.isAdmin,
    flow.creatorPlan,
    flow.selectType,
    hasRequestedType,
    requestedType,
  ])

  useEffect(() => {
    if (!flow.selectedType) return
    if (flow.selectedType === 'video' || flow.selectedType === 'reel') {
      flow.setVideoStep('select')
      setTimeout(() => videoInputRef.current?.click(), 60)
    }
  }, [flow.selectedType, flow.setVideoStep])

  if (!flow.selectedType && hasRequestedType) {
    return (
      <>
        <div className={`min-h-screen ${flow.isDark ? 'bg-gray-950 text-white' : 'bg-white text-gray-900'}`}>
          <div className="mx-auto flex min-h-screen w-full max-w-3xl flex-col px-4 pb-6">
            <div className="flex items-center justify-between py-4">
              <button
                onClick={() => router.back()}
                className={`rounded-full p-2 ${flow.isDark ? 'hover:bg-gray-800' : 'hover:bg-gray-100'}`}
                aria-label="Back"
              >
                Back
              </button>
              <h1 className="text-lg font-semibold">Create Post</h1>
              <button
                onClick={handleCloseUpload}
                className={`rounded-full p-2 ${flow.isDark ? 'hover:bg-gray-800' : 'hover:bg-gray-100'}`}
                aria-label="Close upload"
              >
                Close
              </button>
            </div>

            <div className="flex flex-1 flex-col items-center justify-center">
              <div className="h-10 w-10 animate-spin rounded-full border-2 border-gray-300 border-t-blue-600" aria-label="Loading" />
              <p className={`mt-4 text-sm ${flow.isDark ? 'text-gray-300' : 'text-gray-600'}`}>Preparing {requestedType} upload...</p>
            </div>
          </div>
        </div>

        <input ref={videoInputRef} type="file" accept="video/*" onChange={flow.handleVideoSelect} className="hidden" />
        <input ref={imageInputRef} type="file" accept="image/*" multiple onChange={flow.handleImagesSelect} className="hidden" />
        <input ref={thumbnailInputRef} type="file" accept="image/*" onChange={flow.handleThumbnailSelect} className="hidden" />
      </>
    )
  }

  if (!flow.selectedType) {
    return null
  }

  return (
    <>
      {flow.isVideoType && flow.videoStep === 'select' && (
        <VideoSelectStep
          isDark={flow.isDark}
          selectedType={flow.selectedType}
          videoPreviewUrl={flow.videoPreviewUrl}
          videoDuration={flow.videoDuration}
          durationError={flow.durationError}
          overDurationLimit={flow.overDurationLimit}
          durationGuardMessage={DURATION_GUARD_MESSAGE}
          hasSelectedVideo={!!flow.selectedVideoFile}
          onBack={() => {
            flow.clearVideo()
            flow.setSelectedType(null)
          }}
          onClose={handleCloseUpload}
          onChooseVideo={() => videoInputRef.current?.click()}
          onNext={() => flow.setVideoStep('details')}
          onVideoMetadata={flow.handleVideoMetadata}
        />
      )}

      {flow.isVideoType && flow.videoStep === 'details' && (
        <VideoDetailsStep
          isDark={flow.isDark}
          selectedType={flow.selectedType}
          videoPreviewUrl={flow.videoPreviewUrl}
          activeThumbnailPreviewUrl={flow.activeThumbnailPreviewUrl}
          durationError={flow.durationError}
          overDurationLimit={flow.overDurationLimit}
          durationGuardMessage={DURATION_GUARD_MESSAGE}
          title={flow.title}
          description={flow.description}
          seoTitle={flow.seoTitle}
          seoDescription={flow.seoDescription}
          seoKeywords={flow.seoKeywords}
          seoCategory={flow.seoCategory}
          aiBrief={flow.aiBrief}
          aiAudience={flow.aiAudience}
          aiFocusKeywords={flow.aiFocusKeywords}
          canUseAi={flow.canUseAi}
          isGeneratingAi={flow.isGeneratingAi}
          uploading={flow.uploading}
          hasSelectedVideo={!!flow.selectedVideoFile}
          onBack={() => flow.setVideoStep('select')}
          onClose={handleCloseUpload}
          onPickVideo={() => videoInputRef.current?.click()}
          onPickThumbnail={() => thumbnailInputRef.current?.click()}
          onVideoMetadata={flow.handleVideoMetadata}
          onChangeTitle={flow.setTitle}
          onChangeDescription={flow.setDescription}
          onChangeSeoTitle={flow.setSeoTitle}
          onChangeSeoDescription={flow.setSeoDescription}
          onChangeSeoKeywords={flow.setSeoKeywords}
          onChangeSeoCategory={flow.setSeoCategory}
          onChangeAiBrief={flow.setAiBrief}
          onChangeAiAudience={flow.setAiAudience}
          onChangeAiFocusKeywords={flow.setAiFocusKeywords}
          onGenerateSeo={flow.handleGenerateSeo}
          onUpload={flow.handleUpload}
        />
      )}

      {flow.isTextImageType && (
        <TextImageComposer
          isDark={flow.isDark}
          avatarUrl={flow.avatarUrl}
          displayName={flow.displayName}
          content={flow.content}
          textBgColor={flow.textBgColor}
          textColors={flow.textColors}
          imageItems={flow.imageItems}
          uploading={flow.uploading}
          onBack={() => flow.setSelectedType(null)}
          onClose={handleCloseUpload}
          onChangeContent={flow.setContent}
          onChooseImages={() => imageInputRef.current?.click()}
          onChangeTextBgColor={flow.setTextBgColor}
          onClearTextBgColor={() => flow.setTextBgColor('')}
          onRemoveImage={flow.removeImageItem}
          onUpload={flow.handleUpload}
        />
      )}

      {flow.selectedType === 'news' && (
        <NewsComposer
          isDark={flow.isDark}
          title={flow.title}
          content={flow.content}
          uploading={flow.uploading}
          onBack={() => flow.setSelectedType(null)}
          onClose={handleCloseUpload}
          onChangeTitle={flow.setTitle}
          onChangeContent={flow.setContent}
          onUpload={flow.handleUpload}
        />
      )}

      <input ref={videoInputRef} type="file" accept="video/*" onChange={flow.handleVideoSelect} className="hidden" />
      <input ref={imageInputRef} type="file" accept="image/*" multiple onChange={flow.handleImagesSelect} className="hidden" />
      <input ref={thumbnailInputRef} type="file" accept="image/*" onChange={flow.handleThumbnailSelect} className="hidden" />
    </>
  )
}
