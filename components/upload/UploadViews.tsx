import { CheckCircle2, ChevronLeft, Image as ImageIcon, Loader2, Plus, Sparkles, Upload, X } from 'lucide-react'
import type { LucideIcon } from 'lucide-react'

export type UploadKind = 'video' | 'reel' | 'image' | 'news'

export interface UploadTypeOption {
  id: UploadKind
  label: string
  description: string
  icon: LucideIcon
  disabled: boolean
  requires: 'free' | 'basic' | 'business'
}

interface TypeSelectorProps {
  isDark: boolean
  contentTypes: UploadTypeOption[]
  onSelect: (type: UploadTypeOption) => void
  onClose: () => void
}

export function UploadTypeSelector({ isDark, contentTypes, onSelect, onClose }: TypeSelectorProps) {
  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center p-4">
      <div className={`w-full max-w-sm rounded-2xl shadow-2xl ${isDark ? 'bg-gray-900 text-white' : 'bg-white text-gray-900'}`}>
        <div className="p-5">
          <div className="mb-5 flex items-center justify-between">
            <h2 className="text-lg font-semibold">Create Post</h2>
            <button
              onClick={onClose}
              className={`rounded-full p-2 ${isDark ? 'hover:bg-gray-800' : 'hover:bg-gray-100'}`}
              aria-label="Close upload"
            >
              <X size={20} />
            </button>
          </div>
          <div className="grid grid-cols-2 gap-2">
            {contentTypes.map((type) => {
              const Icon = type.icon
              return (
                <button
                  key={type.id}
                  onClick={() => onSelect(type)}
                  className={`rounded-xl p-4 text-center transition ${
                    type.disabled
                      ? 'cursor-not-allowed opacity-55'
                      : isDark
                        ? 'hover:bg-gray-800'
                        : 'hover:bg-gray-100'
                  }`}
                >
                  <Icon size={30} className={`mx-auto mb-2 ${isDark ? 'text-gray-300' : 'text-gray-700'}`} />
                  <p className="text-sm font-semibold">{type.label}</p>
                  <p className={`mt-1 text-xs ${isDark ? 'text-gray-400' : 'text-gray-500'}`}>{type.description}</p>
                </button>
              )
            })}
          </div>
        </div>
      </div>
    </div>
  )
}

interface VideoSelectStepProps {
  isDark: boolean
  selectedType: UploadKind | null
  videoPreviewUrl: string | null
  videoDuration: number | null
  durationError: string | null
  overDurationLimit: boolean
  durationGuardMessage: string
  hasSelectedVideo: boolean
  onBack: () => void
  onClose: () => void
  onChooseVideo: () => void
  onNext: () => void
  onVideoMetadata: (duration: number) => void
}

export function VideoSelectStep({
  isDark,
  selectedType,
  videoPreviewUrl,
  videoDuration,
  durationError,
  overDurationLimit,
  durationGuardMessage,
  hasSelectedVideo,
  onBack,
  onClose,
  onChooseVideo,
  onNext,
  onVideoMetadata,
}: VideoSelectStepProps) {
  return (
    <div className={`min-h-screen ${isDark ? 'bg-gray-950 text-white' : 'bg-white text-gray-900'}`}>
      <div className="mx-auto flex min-h-screen w-full max-w-3xl flex-col px-4 pb-28">
        <div className="flex items-center justify-between py-4">
          <button onClick={onBack} className={`rounded-full p-2 ${isDark ? 'hover:bg-gray-800' : 'hover:bg-gray-100'}`}>
            <ChevronLeft size={20} />
          </button>
          <h1 className="text-lg font-semibold">{selectedType === 'reel' ? 'New Reel' : 'New Video'}</h1>
          <button onClick={onClose} className={`rounded-full p-2 ${isDark ? 'hover:bg-gray-800' : 'hover:bg-gray-100'}`}>
            <X size={20} />
          </button>
        </div>

        <div className="flex flex-1 flex-col justify-center">
          <button
            onClick={onChooseVideo}
            className={`relative h-[60vh] w-full overflow-hidden rounded-2xl border transition ${
              isDark ? 'border-gray-800 bg-gray-900 hover:bg-gray-800' : 'border-gray-200 bg-gray-50 hover:bg-gray-100'
            }`}
          >
            {videoPreviewUrl ? (
              <video
                src={videoPreviewUrl}
                className="h-full w-full object-contain"
                controls
                playsInline
                onLoadedMetadata={(e) => onVideoMetadata((e.currentTarget as HTMLVideoElement).duration || 0)}
              />
            ) : (
              <div className="flex h-full w-full flex-col items-center justify-center">
                <Upload size={48} className={isDark ? 'text-gray-500' : 'text-gray-400'} />
                <p className="mt-3 text-base font-semibold">Choose a video from your device</p>
                <p className={`mt-1 text-sm ${isDark ? 'text-gray-400' : 'text-gray-500'}`}>Upload first, then continue to details</p>
              </div>
            )}
          </button>

          {videoDuration !== null && (
            <div className={`mt-3 rounded-xl px-3 py-2 text-sm ${isDark ? 'bg-gray-900 text-gray-300' : 'bg-gray-100 text-gray-600'}`}>
              Duration: {(videoDuration / 60).toFixed(2)} min
            </div>
          )}

          {(durationError || overDurationLimit) && (
            <div className={`mt-3 rounded-xl px-3 py-2 text-sm ${isDark ? 'bg-red-500/10 text-red-200' : 'bg-red-50 text-red-700'}`}>
            {durationGuardMessage}
          </div>
        )}
        </div>
      </div>

      <div className={`fixed bottom-0 left-0 right-0 border-t p-4 safe-area-inset-bottom-p4 ${isDark ? 'border-gray-800 bg-gray-950' : 'border-gray-200 bg-white'}`}>
        <div className="mx-auto flex w-full max-w-3xl items-center gap-3">
          <button
            onClick={onChooseVideo}
            className={`flex-1 rounded-xl px-4 py-3 text-sm font-semibold ${
              isDark ? 'bg-gray-800 hover:bg-gray-700' : 'bg-gray-100 hover:bg-gray-200'
            }`}
          >
            Choose Video
          </button>
          <button
            onClick={onNext}
            disabled={!hasSelectedVideo || overDurationLimit}
            className="flex-1 rounded-xl bg-blue-600 px-4 py-3 text-sm font-semibold text-white disabled:cursor-not-allowed disabled:opacity-50"
          >
            Next
          </button>
        </div>
      </div>
    </div>
  )
}

interface VideoDetailsStepProps {
  isDark: boolean
  selectedType: UploadKind | null
  videoPreviewUrl: string | null
  activeThumbnailPreviewUrl: string | null
  durationError: string | null
  overDurationLimit: boolean
  durationGuardMessage: string
  title: string
  description: string
  seoTitle: string
  seoDescription: string
  seoKeywords: string
  seoCategory: string
  aiBrief: string
  aiAudience: string
  aiFocusKeywords: string
  canUseAi: boolean
  isGeneratingAi: boolean
  uploading: boolean
  hasSelectedVideo: boolean
  onBack: () => void
  onClose: () => void
  onPickVideo: () => void
  onPickThumbnail: () => void
  onVideoMetadata: (duration: number) => void
  onChangeTitle: (value: string) => void
  onChangeDescription: (value: string) => void
  onChangeSeoTitle: (value: string) => void
  onChangeSeoDescription: (value: string) => void
  onChangeSeoKeywords: (value: string) => void
  onChangeSeoCategory: (value: string) => void
  onChangeAiBrief: (value: string) => void
  onChangeAiAudience: (value: string) => void
  onChangeAiFocusKeywords: (value: string) => void
  onGenerateSeo: () => void
  onUpload: () => void
}

export function VideoDetailsStep({
  isDark,
  selectedType,
  videoPreviewUrl,
  activeThumbnailPreviewUrl,
  durationError,
  overDurationLimit,
  durationGuardMessage,
  title,
  description,
  seoTitle,
  seoDescription,
  seoKeywords,
  seoCategory,
  aiBrief,
  aiAudience,
  aiFocusKeywords,
  canUseAi,
  isGeneratingAi,
  uploading,
  hasSelectedVideo,
  onBack,
  onClose,
  onPickVideo,
  onPickThumbnail,
  onVideoMetadata,
  onChangeTitle,
  onChangeDescription,
  onChangeSeoTitle,
  onChangeSeoDescription,
  onChangeSeoKeywords,
  onChangeSeoCategory,
  onChangeAiBrief,
  onChangeAiAudience,
  onChangeAiFocusKeywords,
  onGenerateSeo,
  onUpload,
}: VideoDetailsStepProps) {
  return (
    <div className={`min-h-screen ${isDark ? 'bg-gray-950 text-white' : 'bg-white text-gray-900'}`}>
      <div className="mx-auto flex min-h-screen w-full max-w-3xl flex-col px-4 pb-28">
        <div className="flex items-center justify-between py-4">
          <button onClick={onBack} className={`rounded-full p-2 ${isDark ? 'hover:bg-gray-800' : 'hover:bg-gray-100'}`}>
            <ChevronLeft size={20} />
          </button>
          <h1 className="text-lg font-semibold">{selectedType === 'reel' ? 'Reel Details' : 'Video Details'}</h1>
          <button onClick={onClose} className={`rounded-full p-2 ${isDark ? 'hover:bg-gray-800' : 'hover:bg-gray-100'}`}>
            <X size={20} />
          </button>
        </div>

        <div className={`rounded-2xl p-3 ${isDark ? 'bg-gray-900' : 'bg-gray-100'}`}>
          <div className="flex items-start gap-3">
            <button
              onClick={onPickVideo}
              className={`relative h-28 w-40 overflow-hidden rounded-xl border ${
                isDark ? 'border-gray-700 bg-black' : 'border-gray-200 bg-black'
              }`}
            >
              {videoPreviewUrl ? (
                <video
                  src={videoPreviewUrl}
                  className="h-full w-full object-cover"
                  poster={activeThumbnailPreviewUrl || undefined}
                  muted
                  playsInline
                  preload="metadata"
                  onLoadedMetadata={(e) => onVideoMetadata((e.currentTarget as HTMLVideoElement).duration || 0)}
                />
              ) : (
                <div className="flex h-full w-full items-center justify-center text-xs text-white/70">No preview</div>
              )}
              <span className="absolute left-1 top-1 rounded bg-black/75 px-1.5 py-0.5 text-[10px] text-white">Video</span>
              <span className="absolute bottom-1 left-1 rounded bg-black/75 px-1.5 py-0.5 text-[10px] text-white">Change</span>
            </button>

            <button
              onClick={onPickThumbnail}
              className={`relative h-28 w-28 overflow-hidden rounded-xl border ${
                isDark ? 'border-gray-700 bg-gray-800' : 'border-gray-200 bg-white'
              }`}
            >
              {activeThumbnailPreviewUrl ? (
                <img src={activeThumbnailPreviewUrl} alt="Thumbnail preview" className="h-full w-full object-cover" />
              ) : (
                <div className="flex h-full w-full flex-col items-center justify-center">
                  <ImageIcon size={20} />
                  <span className="mt-1 text-[11px]">Thumbnail</span>
                </div>
              )}
              <span className="absolute left-1 top-1 rounded bg-black/75 px-1.5 py-0.5 text-[10px] text-white">Thumbnail</span>
              <span className="absolute bottom-1 left-1 rounded bg-black/75 px-1.5 py-0.5 text-[10px] text-white">Change</span>
            </button>
          </div>
        </div>

        {(durationError || overDurationLimit) && (
          <div className={`mt-3 rounded-xl px-3 py-2 text-sm ${isDark ? 'bg-red-500/10 text-red-200' : 'bg-red-50 text-red-700'}`}>
            {durationGuardMessage}
          </div>
        )}

        <div className="mt-4 space-y-3">
          <input
            type="text"
            value={title}
            onChange={(e) => onChangeTitle(e.target.value)}
            placeholder="Title"
            className={`w-full rounded-xl border px-3 py-3 text-sm ${
              isDark ? 'border-gray-700 bg-gray-900 text-white placeholder:text-gray-500' : 'border-gray-200 bg-white text-gray-900'
            }`}
          />
          <textarea
            value={description}
            onChange={(e) => onChangeDescription(e.target.value)}
            placeholder="Description"
            rows={4}
            className={`w-full resize-none rounded-xl border px-3 py-3 text-sm ${
              isDark ? 'border-gray-700 bg-gray-900 text-white placeholder:text-gray-500' : 'border-gray-200 bg-white text-gray-900'
            }`}
          />
        </div>

        {canUseAi && (
          <div className={`mt-4 rounded-2xl p-3 ${isDark ? 'bg-gray-900' : 'bg-gray-100'}`}>
            <div className="mb-2 flex items-center justify-between">
              <p className="text-sm font-semibold">SEO</p>
              <button
                onClick={onGenerateSeo}
                disabled={isGeneratingAi}
                className="inline-flex items-center gap-1 rounded-full bg-blue-600 px-3 py-1.5 text-xs font-semibold text-white disabled:opacity-40"
              >
                {isGeneratingAi ? <Loader2 size={14} className="animate-spin" /> : <Sparkles size={14} />}
                {isGeneratingAi ? 'Generating...' : 'Auto Fill'}
              </button>
            </div>
            <div className="mb-3 space-y-2">
              <textarea
                value={aiBrief}
                onChange={(e) => onChangeAiBrief(e.target.value)}
                placeholder="AI Brief: describe what this video is about and what angle you want"
                rows={3}
                className={`w-full resize-none rounded-lg border px-3 py-2 text-sm ${
                  isDark ? 'border-gray-700 bg-gray-950 text-white placeholder:text-gray-500' : 'border-gray-200 bg-white text-gray-900'
                }`}
              />
              <input
                type="text"
                value={aiAudience}
                onChange={(e) => onChangeAiAudience(e.target.value)}
                placeholder="Target Audience (optional)"
                className={`w-full rounded-lg border px-3 py-2 text-sm ${
                  isDark ? 'border-gray-700 bg-gray-950 text-white placeholder:text-gray-500' : 'border-gray-200 bg-white text-gray-900'
                }`}
              />
              <input
                type="text"
                value={aiFocusKeywords}
                onChange={(e) => onChangeAiFocusKeywords(e.target.value)}
                placeholder="Focus Keywords (comma separated)"
                className={`w-full rounded-lg border px-3 py-2 text-sm ${
                  isDark ? 'border-gray-700 bg-gray-950 text-white placeholder:text-gray-500' : 'border-gray-200 bg-white text-gray-900'
                }`}
              />
            </div>
            <div className="space-y-2">
              <input
                type="text"
                value={seoTitle}
                onChange={(e) => onChangeSeoTitle(e.target.value)}
                placeholder="SEO Title"
                className={`w-full rounded-lg border px-3 py-2 text-sm ${
                  isDark ? 'border-gray-700 bg-gray-950 text-white placeholder:text-gray-500' : 'border-gray-200 bg-white text-gray-900'
                }`}
              />
              <textarea
                value={seoDescription}
                onChange={(e) => onChangeSeoDescription(e.target.value)}
                placeholder="SEO Description"
                rows={2}
                className={`w-full resize-none rounded-lg border px-3 py-2 text-sm ${
                  isDark ? 'border-gray-700 bg-gray-950 text-white placeholder:text-gray-500' : 'border-gray-200 bg-white text-gray-900'
                }`}
              />
              <input
                type="text"
                value={seoKeywords}
                onChange={(e) => onChangeSeoKeywords(e.target.value)}
                placeholder="SEO Keywords (comma separated)"
                className={`w-full rounded-lg border px-3 py-2 text-sm ${
                  isDark ? 'border-gray-700 bg-gray-950 text-white placeholder:text-gray-500' : 'border-gray-200 bg-white text-gray-900'
                }`}
              />
              <input
                type="text"
                value={seoCategory}
                onChange={(e) => onChangeSeoCategory(e.target.value)}
                placeholder="SEO Category"
                className={`w-full rounded-lg border px-3 py-2 text-sm ${
                  isDark ? 'border-gray-700 bg-gray-950 text-white placeholder:text-gray-500' : 'border-gray-200 bg-white text-gray-900'
                }`}
              />
            </div>
          </div>
        )}
      </div>

      <div className={`fixed bottom-0 left-0 right-0 border-t p-4 safe-area-inset-bottom-p4 ${isDark ? 'border-gray-800 bg-gray-950' : 'border-gray-200 bg-white'}`}>
        <div className="mx-auto w-full max-w-3xl">
          <button
            onClick={onUpload}
            disabled={uploading || overDurationLimit || !hasSelectedVideo}
            className="flex w-full items-center justify-center gap-2 rounded-xl bg-blue-600 px-4 py-3 text-sm font-semibold text-white disabled:cursor-not-allowed disabled:opacity-50"
          >
            {uploading ? <Loader2 size={16} className="animate-spin" /> : <CheckCircle2 size={16} />}
            {uploading ? 'Uploading...' : 'Post'}
          </button>
        </div>
      </div>
    </div>
  )
}

interface LocalImageViewItem {
  id: string
  url: string
}

interface TextImageComposerProps {
  isDark: boolean
  avatarUrl: string
  displayName: string
  content: string
  textBgColor: string
  textColors: string[]
  imageItems: LocalImageViewItem[]
  uploading: boolean
  onBack: () => void
  onClose: () => void
  onChangeContent: (value: string) => void
  onChooseImages: () => void
  onChangeTextBgColor: (value: string) => void
  onClearTextBgColor: () => void
  onRemoveImage: (id: string) => void
  onUpload: () => void
}

export function TextImageComposer({
  isDark,
  avatarUrl,
  displayName,
  content,
  textBgColor,
  textColors,
  imageItems,
  uploading,
  onBack,
  onClose,
  onChangeContent,
  onChooseImages,
  onChangeTextBgColor,
  onClearTextBgColor,
  onRemoveImage,
  onUpload,
}: TextImageComposerProps) {
  return (
    <div className={`min-h-screen ${isDark ? 'bg-gray-950 text-white' : 'bg-white text-gray-900'}`}>
      <div className="mx-auto flex min-h-screen w-full max-w-3xl flex-col px-4 pb-28">
        <div className="flex items-center justify-between py-4">
          <button onClick={onBack} className={`rounded-full p-2 ${isDark ? 'hover:bg-gray-800' : 'hover:bg-gray-100'}`}>
            <ChevronLeft size={20} />
          </button>
          <h1 className="text-lg font-semibold">Text/Image Post</h1>
          <button onClick={onClose} className={`rounded-full p-2 ${isDark ? 'hover:bg-gray-800' : 'hover:bg-gray-100'}`}>
            <X size={20} />
          </button>
        </div>

        <div className={`rounded-2xl p-3 ${isDark ? 'bg-gray-900' : 'bg-gray-100'}`}>
          <div className="flex items-center gap-3">
            {avatarUrl ? (
              <img src={avatarUrl} alt={displayName} className="h-11 w-11 rounded-full object-cover" />
            ) : (
              <div className="flex h-11 w-11 items-center justify-center rounded-full bg-blue-600 text-sm font-semibold text-white">
                {(displayName || 'U').slice(0, 1).toUpperCase()}
              </div>
            )}
            <div>
              <p className="text-sm font-semibold">{displayName}</p>
              <p className={`text-xs ${isDark ? 'text-gray-400' : 'text-gray-500'}`}>Create a text or photo post</p>
            </div>
          </div>

          <textarea
            value={content}
            onChange={(e) => onChangeContent(e.target.value)}
            placeholder="What is in your mind?"
            rows={6}
            className={`mt-3 w-full resize-none rounded-xl border px-3 py-3 text-base ${
              isDark ? 'border-gray-700 bg-gray-950 text-white placeholder:text-gray-500' : 'border-gray-200 bg-white text-gray-900'
            }`}
          />

          <div className="mt-3">
            <div className="mb-2 flex items-center justify-between">
              <p className="text-sm font-semibold">Text Background</p>
              {imageItems.length > 0 && (
                <span className={`text-xs ${isDark ? 'text-yellow-200' : 'text-yellow-700'}`}>Disabled because image is selected</span>
              )}
            </div>
            <div className="overflow-x-auto">
              <div className="flex min-w-max items-center gap-2 pb-1">
                {textColors.map((color) => (
                  <button
                    key={color}
                    onClick={() => {
                      if (imageItems.length > 0) return
                      onChangeTextBgColor(color)
                    }}
                    disabled={imageItems.length > 0}
                    className={`h-8 w-8 rounded-full border-2 ${textBgColor === color ? 'border-blue-500' : 'border-transparent'} disabled:opacity-40`}
                    style={{ backgroundColor: color }}
                    aria-label={`Select ${color}`}
                  />
                ))}
                {textBgColor && imageItems.length === 0 && (
                  <button onClick={onClearTextBgColor} className={`rounded-full px-3 py-1 text-xs font-semibold ${isDark ? 'bg-gray-800' : 'bg-gray-200'}`}>
                    Clear
                  </button>
                )}
              </div>
            </div>
          </div>

          <div className="mt-3">
            <p className="mb-2 text-sm font-semibold">Upload List</p>
            <button
              onClick={onChooseImages}
              className={`inline-flex items-center gap-2 rounded-xl px-3 py-2 text-sm font-semibold ${
                isDark ? 'bg-gray-800 hover:bg-gray-700' : 'bg-gray-200 hover:bg-gray-300'
              }`}
            >
              <Plus size={16} />
              {imageItems.length > 0 ? 'Add more images' : 'Choose image'}
            </button>
          </div>

          {imageItems.length > 0 && (
            <div className="mt-3 overflow-x-auto">
              <div className="flex min-w-max gap-3 pb-1">
                {imageItems.map((item) => (
                  <div key={item.id} className="relative h-20 w-20 overflow-hidden rounded-lg">
                    <img src={item.url} alt="Selected" className="h-full w-full object-cover" />
                    <button onClick={() => onRemoveImage(item.id)} className="absolute right-1 top-1 rounded-full bg-black/70 p-1 text-white">
                      <X size={12} />
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}

          {imageItems.length === 0 && textBgColor && content.trim() && (
            <div className="mt-3 rounded-xl p-4" style={{ backgroundColor: textBgColor }}>
              <p className="text-sm font-semibold text-white">{content}</p>
            </div>
          )}
        </div>

        <div className={`fixed bottom-0 left-0 right-0 border-t p-4 safe-area-inset-bottom-p4 ${isDark ? 'border-gray-800 bg-gray-950' : 'border-gray-200 bg-white'}`}>
          <div className="mx-auto w-full max-w-3xl">
            <button
              onClick={onUpload}
              disabled={uploading || (!content.trim() && imageItems.length === 0)}
              className="flex w-full items-center justify-center gap-2 rounded-xl bg-blue-600 px-4 py-3 text-sm font-semibold text-white disabled:cursor-not-allowed disabled:opacity-50"
            >
              {uploading ? <Loader2 size={16} className="animate-spin" /> : <CheckCircle2 size={16} />}
              {uploading ? 'Uploading...' : 'Upload'}
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}

interface NewsComposerProps {
  isDark: boolean
  title: string
  content: string
  uploading: boolean
  onBack: () => void
  onClose: () => void
  onChangeTitle: (value: string) => void
  onChangeContent: (value: string) => void
  onUpload: () => void
}

export function NewsComposer({
  isDark,
  title,
  content,
  uploading,
  onBack,
  onClose,
  onChangeTitle,
  onChangeContent,
  onUpload,
}: NewsComposerProps) {
  return (
    <div className={`min-h-screen ${isDark ? 'bg-gray-950 text-white' : 'bg-white text-gray-900'}`}>
      <div className="mx-auto flex min-h-screen w-full max-w-3xl flex-col px-4 pb-28">
        <div className="flex items-center justify-between py-4">
          <button onClick={onBack} className={`rounded-full p-2 ${isDark ? 'hover:bg-gray-800' : 'hover:bg-gray-100'}`}>
            <ChevronLeft size={20} />
          </button>
          <h1 className="text-lg font-semibold">News Post</h1>
          <button onClick={onClose} className={`rounded-full p-2 ${isDark ? 'hover:bg-gray-800' : 'hover:bg-gray-100'}`}>
            <X size={20} />
          </button>
        </div>

        <div className={`rounded-2xl p-3 ${isDark ? 'bg-gray-900' : 'bg-gray-100'}`}>
          <input
            type="text"
            value={title}
            onChange={(e) => onChangeTitle(e.target.value)}
            placeholder="News title"
            className={`w-full rounded-xl border px-3 py-3 text-sm ${
              isDark ? 'border-gray-700 bg-gray-950 text-white placeholder:text-gray-500' : 'border-gray-200 bg-white text-gray-900'
            }`}
          />
          <textarea
            value={content}
            onChange={(e) => onChangeContent(e.target.value)}
            placeholder="Write your news..."
            rows={8}
            className={`mt-3 w-full resize-none rounded-xl border px-3 py-3 text-sm ${
              isDark ? 'border-gray-700 bg-gray-950 text-white placeholder:text-gray-500' : 'border-gray-200 bg-white text-gray-900'
            }`}
          />
        </div>

        <div className={`fixed bottom-0 left-0 right-0 border-t p-4 safe-area-inset-bottom-p4 ${isDark ? 'border-gray-800 bg-gray-950' : 'border-gray-200 bg-white'}`}>
          <div className="mx-auto w-full max-w-3xl">
            <button
              onClick={onUpload}
              disabled={uploading || (!title.trim() && !content.trim())}
              className="flex w-full items-center justify-center gap-2 rounded-xl bg-blue-600 px-4 py-3 text-sm font-semibold text-white disabled:cursor-not-allowed disabled:opacity-50"
            >
              {uploading ? <Loader2 size={16} className="animate-spin" /> : <CheckCircle2 size={16} />}
              {uploading ? 'Uploading...' : 'Upload'}
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
