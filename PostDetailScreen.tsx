'use client'

import { useState, useEffect } from 'react'
import { ArrowLeft, MessageCircle } from 'lucide-react'
import { Post } from './types'
import { PostCard } from './PostCard'
import { CommentScreen } from './CommentScreen'

interface PostDetailScreenProps {
  post: Post
  onClose: () => void
  isGuest?: boolean
  onGuestAction?: () => void
}

export function PostDetailScreen({ post, onClose, isGuest = false, onGuestAction }: PostDetailScreenProps) {
  const [showComments, setShowComments] = useState(false)

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

  return (
    <div className="fixed inset-0 bg-background z-50 flex flex-col">
      {/* Header */}
      <div className="flex items-center justify-between p-4 border-b border-border">
        <button
          onClick={onClose}
          className="p-2 hover:bg-accent rounded-full transition-colors"
        >
          <ArrowLeft size={20} />
        </button>
        <h1 className="text-lg font-semibold">Post</h1>
        <div className="w-10" />
      </div>

      {/* Post Content */}
      <div className="flex-1 overflow-y-auto">
        <div className="max-w-2xl mx-auto">
          <PostCard
            post={post}
            isGuest={isGuest}
            onGuestAction={onGuestAction}
          />
          
          {/* Comments Preview */}
          <div className="border-t border-border p-4">
            <button
              onClick={() => setShowComments(true)}
              className="flex items-center space-x-2 text-muted-foreground hover:text-foreground transition-colors"
            >
              <MessageCircle size={16} />
              <span>View all comments</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}