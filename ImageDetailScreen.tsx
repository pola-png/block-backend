'use client'

import { useState } from 'react'
import { ArrowLeft, MessageCircle, X, ChevronLeft, ChevronRight } from 'lucide-react'
import { Post } from './types'
import { PostCard } from './PostCard'
import { CommentScreen } from './CommentScreen'
import { normalizeWasabiImage } from './lib/wasabi'

interface ImageDetailScreenProps {
  post: Post
  onClose: () => void
  isGuest?: boolean
  onGuestAction?: () => void
}

export function ImageDetailScreen({ post, onClose, isGuest = false, onGuestAction }: ImageDetailScreenProps) {
  const [showComments, setShowComments] = useState(false)
  const [showFullImage, setShowFullImage] = useState(false)
  const [currentImageIndex, setCurrentImageIndex] = useState(0)

  if (showComments) {
    return (
      <CommentScreen
        post={post}
        onClose={() => setShowComments(false)}
        isGuest={isGuest}
        onGuestAction={onGuestAction}
      />
    )
  }

  const mediaUrls = post.mediaUrls || []
  const resolvedUrl = normalizeWasabiImage(mediaUrls[currentImageIndex]) || mediaUrls[currentImageIndex]

  const handlePrev = (e: React.MouseEvent) => {
    e.stopPropagation()
    if (currentImageIndex > 0) {
      setCurrentImageIndex(prev => prev - 1)
    }
  }

  const handleNext = (e: React.MouseEvent) => {
    e.stopPropagation()
    if (currentImageIndex < mediaUrls.length - 1) {
      setCurrentImageIndex(prev => prev + 1)
    }
  }

  if (showFullImage) {
    return (
      <div className="fixed inset-0 bg-black z-50 flex items-center justify-center">
        <button
          onClick={() => setShowFullImage(false)}
          className="absolute top-4 right-4 p-2 bg-black/50 rounded-full text-white hover:bg-black/70 transition-colors z-10"
          aria-label="Close full size image"
        >
          <X size={24} />
        </button>

        {mediaUrls.length > 1 && currentImageIndex > 0 && (
          <button
            onClick={handlePrev}
            className="absolute left-4 p-3 bg-black/50 hover:bg-black/70 text-white rounded-full transition-colors z-10"
            aria-label="Previous image"
          >
            <ChevronLeft size={24} />
          </button>
        )}

        <img
          src={resolvedUrl}
          alt={`Full size image ${currentImageIndex + 1}`}
          className="max-w-[80%] max-h-[75vh] object-contain"
          onClick={() => setShowFullImage(false)}
        />

        {mediaUrls.length > 1 && currentImageIndex < mediaUrls.length - 1 && (
          <button
            onClick={handleNext}
            className="absolute right-4 p-3 bg-black/50 hover:bg-black/70 text-white rounded-full transition-colors z-10"
            aria-label="Next image"
          >
            <ChevronRight size={24} />
          </button>
        )}
      </div>
    )
  }

  return (
    <div className="fixed inset-0 bg-[rgb(var(--bg-primary))] text-[rgb(var(--text-primary))] z-50 flex flex-col lg:flex-row animate-in fade-in slide-in-from-bottom-4 duration-300">
      
      {/* Mobile Header (Hidden on Desktop) */}
      <div className="flex lg:hidden items-center justify-between p-4 border-b border-[rgb(var(--border-color))] bg-[rgb(var(--bg-primary))]">
        <button
          onClick={onClose}
          className="p-2 hover:bg-[rgb(var(--bg-secondary))] rounded-full transition-colors text-[rgb(var(--text-primary))]"
          aria-label="Go back"
        >
          <ArrowLeft size={20} />
        </button>
        <h1 className="text-lg font-bold text-[rgb(var(--text-primary))]">Photo</h1>
        <button
          onClick={() => setShowComments(true)}
          className="p-2 hover:bg-[rgb(var(--bg-secondary))] rounded-full transition-colors text-[rgb(var(--text-primary))]"
          aria-label="View comments"
        >
          <MessageCircle size={20} />
        </button>
      </div>

      {/* LEFT PANEL: Responsive Carousel / Image Viewer */}
      <div className="w-full lg:flex-1 bg-black flex items-center justify-center relative min-h-[350px] lg:h-full select-none">
        {/* Desktop Close/Back Button */}
        <button
          onClick={onClose}
          className="hidden lg:flex absolute top-4 left-4 z-30 w-10 h-10 bg-black/60 hover:bg-black/80 text-white rounded-full items-center justify-center transition-all hover:scale-105 active:scale-95"
          aria-label="Back"
        >
          <ArrowLeft size={20} />
        </button>

        {mediaUrls.length > 1 && currentImageIndex > 0 && (
          <button
            onClick={handlePrev}
            className="absolute left-4 p-2 bg-black/50 hover:bg-black/75 text-white rounded-full transition-colors z-20"
            aria-label="Previous image"
          >
            <ChevronLeft size={24} />
          </button>
        )}

        {mediaUrls.length > 0 ? (
          <img
            src={resolvedUrl}
            alt={`Post image ${currentImageIndex + 1}`}
            className="max-w-full max-h-[45vh] lg:max-h-[45vh] object-contain cursor-zoom-in"
            onClick={() => setShowFullImage(true)}
          />
        ) : (
          <div className="text-gray-500">No image available</div>
        )}

        {mediaUrls.length > 1 && currentImageIndex < mediaUrls.length - 1 && (
          <button
            onClick={handleNext}
            className="absolute right-4 p-2 bg-black/50 hover:bg-black/75 text-white rounded-full transition-colors z-20"
            aria-label="Next image"
          >
            <ChevronRight size={24} />
          </button>
        )}

        {/* Carousel Dots Indicator */}
        {mediaUrls.length > 1 && (
          <div className="absolute bottom-4 left-0 right-0 flex justify-center gap-1.5 z-20">
            {mediaUrls.map((_, idx) => (
              <div
                key={idx}
                className={`w-1.5 h-1.5 rounded-full transition-all ${
                  idx === currentImageIndex ? 'bg-white w-6' : 'bg-white/60'
                }`}
              />
            ))}
          </div>
        )}
      </div>

      {/* RIGHT PANEL: Details & Comments */}
      <div className="w-full lg:w-[420px] lg:border-l lg:border-[rgb(var(--border-color))] flex flex-col bg-[rgb(var(--bg-primary))] overflow-y-auto">
        <div className="p-4 border-b border-[rgb(var(--border-color))] hidden lg:block">
          <h2 className="text-lg font-bold text-[rgb(var(--text-primary))]">Photo Detail</h2>
        </div>
        <div className="flex-1">
          <PostCard
            post={post}
            isGuest={isGuest}
            onGuestAction={onGuestAction}
            feedType="detail"
          />
        </div>
      </div>

    </div>
  )
}