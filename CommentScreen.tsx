'use client'

import { useState, useEffect } from 'react'
import { ArrowLeft, Heart, Reply, Mic, Send, MoreHorizontal } from 'lucide-react'
import { Post } from './types'
import appwriteService from './appwriteService'
import { cn, formatTimeAgo } from './utils'
import { useAuthStore } from './authStore'
import { hasVerifiedBadge } from './lib/verification'
import { VerifiedBadge } from './components/VerifiedBadge'

interface Comment {
  id: string
  postId: string
  userId: string
  username: string
  isVerified?: boolean
  userAvatar: string
  content: string
  voiceUrl?: string
  parentCommentId?: string
  likes: number
  replies: number
  timestamp: Date
  isLiked: boolean
}

interface CommentScreenProps {
  post: Post
  onClose: () => void
  isGuest?: boolean
  onGuestAction?: () => void
  parentComment?: Comment
}

export function CommentScreen({ post, onClose, isGuest = false, onGuestAction, parentComment }: CommentScreenProps) {
  const [comments, setComments] = useState<Comment[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [newComment, setNewComment] = useState('')
  const [replyTo, setReplyTo] = useState<string | null>(null)
  const [currentUser, setCurrentUser] = useState<any>(null)
  const [swipeStartX, setSwipeStartX] = useState(0)
  const [selectedCommentForReplies, setSelectedCommentForReplies] = useState<Comment | null>(null)
  const [isSubmitting, setIsSubmitting] = useState(false)
  const authStore = useAuthStore()
  const currentUserAvatar = authStore.currentUserAvatar || ''

  useEffect(() => {
    loadComments()
    loadCurrentUser()
  }, [])

  const loadCurrentUser = async () => {
    try {
      const user = await appwriteService.getCurrentUser()
      if (user) {
        const profile = await appwriteService.getProfileByUserId(user.$id)
        setCurrentUser(user)
        authStore.setCurrentUserAvatar(profile?.avatarUrl || '')
      }
    } catch (error) {
      console.error('Failed to load user:', error)
    }
  }

  const loadComments = async () => {
    try {
      setIsLoading(true)
      const result = await appwriteService.fetchComments(post.id)
      const user = await appwriteService.getCurrentUser()
      
      let commentsData = await Promise.all(
        result.documents.map(async (doc: any) => {
          let isLiked = false
          if (user) {
            isLiked = await appwriteService.isCommentLikedBy(user.$id, doc.$id)
          }
          const profile = doc.userId ? await appwriteService.getProfileByUserId(doc.userId) : null
          return {
            id: doc.$id,
            postId: doc.postId,
            userId: doc.userId,
            username: doc.username || 'User',
            isVerified: hasVerifiedBadge(profile || doc),
            userAvatar: doc.userAvatar || '',
            content: doc.content || '',
            voiceUrl: doc.voiceUrl,
            parentCommentId: doc.parentCommentId,
            likes: doc.likes || 0,
            replies: doc.replies || 0,
            timestamp: new Date(doc.timestamp || doc.createdAt || doc.$createdAt),
            isLiked
          }
        })
      )
      
      if (parentComment) {
        commentsData = commentsData.filter(c => c.parentCommentId === parentComment.id)
      }
      
      setComments(commentsData)
    } catch (error) {
      console.error('Failed to load comments:', error)
    } finally {
      setIsLoading(false)
    }
  }

  const handleSubmitComment = async () => {
    if (!newComment.trim() || isSubmitting) return
    if (isGuest) {
      onGuestAction?.()
      return
    }

    setIsSubmitting(true)
    try {
      await appwriteService.createComment(post.id, newComment.trim(), replyTo || undefined)
      setNewComment('')
      setReplyTo(null)
      await loadComments()
    } catch (error) {
      console.error('Failed to post comment:', error)
    } finally {
      setIsSubmitting(false)
    }
  }

  const handleLikeComment = async (commentId: string) => {
    if (isGuest) {
      onGuestAction?.()
      return
    }

    try {
      const comment = comments.find(c => c.id === commentId)
      if (!comment) return

      // Optimistic update
      setComments(prev => prev.map(c => 
        c.id === commentId 
          ? { ...c, isLiked: !c.isLiked, likes: c.isLiked ? Math.max(0, c.likes - 1) : c.likes + 1 }
          : c
      ))

      // Update backend
      if (comment.isLiked) {
        await appwriteService.unlikeComment(commentId)
      } else {
        await appwriteService.likeComment(commentId)
      }
    } catch (error) {
      console.error('Failed to like comment:', error)
      // Revert on error
      setComments(prev => prev.map(c => 
        c.id === commentId 
          ? { ...c, isLiked: !c.isLiked, likes: c.isLiked ? c.likes + 1 : Math.max(0, c.likes - 1) }
          : c
      ))
    }
  }

  const rootComments = comments.filter(c => !c.parentCommentId)
  const getReplies = (commentId: string) => comments.filter(c => c.parentCommentId === commentId)

  const CommentItem = ({ comment, isReply = false }: { comment: Comment; isReply?: boolean }) => (
    <div className={cn("flex gap-3", isReply && "ml-12")}>
      <img 
        src={comment.userAvatar.startsWith('/media/') ? `/api/image-proxy?path=${comment.userAvatar.substring(1)}` : comment.userAvatar || ''} 
        alt={comment.username} 
        className="w-10 h-10 rounded-full object-cover flex-shrink-0 cursor-pointer" 
        onClick={(e) => {
          e.stopPropagation()
          window.location.href = `/profile/${comment.userId}`
        }}
      />
      
      <div className="flex-1 min-w-0">
        <div 
          className="bg-muted rounded-2xl px-4 py-3 cursor-pointer"
          onTouchStart={(e) => setSwipeStartX(e.touches[0].clientX)}
          onTouchEnd={(e) => {
            const swipeEndX = e.changedTouches[0].clientX
            if (swipeStartX - swipeEndX > 50) {
              setReplyTo(comment.id)
              setNewComment(`${comment.username} `)
            }
          }}
          onClick={() => handleLikeComment(comment.id)}
        >
          <div className="flex items-center gap-2 mb-1.5">
            <span 
              className="font-semibold text-base cursor-pointer hover:underline"
              onClick={(e) => {
                e.stopPropagation()
                window.location.href = `/profile/${comment.userId}`
              }}
            >
              <span className="inline-flex items-center gap-1">
                {comment.username}
                {comment.isVerified && <VerifiedBadge className="h-4 w-4 shrink-0" />}
              </span>
            </span>
            <span className="text-sm text-muted-foreground">
              {formatTimeAgo(comment.timestamp)}
            </span>
          </div>
          
          {comment.voiceUrl ? (
            <div className="bg-background rounded-lg p-2">
              <audio controls className="w-full h-8">
                <source src={comment.voiceUrl} type="audio/mpeg" />
                Voice message
              </audio>
            </div>
          ) : (
            <p className="text-base leading-relaxed">{comment.content.split(' ').map((word, i) => 
              word.startsWith('@') ? (
                <span key={i} className="text-blue-500">{word} </span>
              ) : (
                word + ' '
              )
            )}</p>
          )}
        </div>
        
        <div className="flex items-center gap-5 mt-3 ml-3">
          <button
            onClick={(e) => {
              e.stopPropagation()
              handleLikeComment(comment.id)
            }}
            className="flex items-center gap-2 text-base text-muted-foreground hover:text-foreground"
          >
            <Heart size={20} />
            <span>Like</span>
          </button>
          <button
            onClick={(e) => {
              e.stopPropagation()
              setReplyTo(comment.id)
              setNewComment(`${comment.username} `)
            }}
            className="flex items-center gap-2 text-base text-muted-foreground hover:text-foreground"
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M15 7l5 5-5 5M4 6v2a4 4 0 0 0 4 4h12"/>
            </svg>
            <span>Reply</span>
          </button>
          <div className="flex items-center gap-5 ml-auto">
            {comment.isLiked && (
              <span className="flex items-center gap-2 text-base text-red-500">
                <Heart size={20} className="fill-red-500" />
                <span>{comment.likes}</span>
              </span>
            )}
            {comment.replies > 0 && (
              <button
                onClick={(e) => {
                  e.stopPropagation()
                  setSelectedCommentForReplies(comment)
                }}
                className="flex items-center gap-2 text-base text-blue-500 hover:text-blue-600 font-medium"
              >
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M15 7l5 5-5 5M4 6v2a4 4 0 0 0 4 4h12"/>
                </svg>
                <span>View {comment.replies} {comment.replies === 1 ? 'reply' : 'replies'}</span>
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  )

  if (selectedCommentForReplies) {
    return <CommentScreen post={post} onClose={() => setSelectedCommentForReplies(null)} parentComment={selectedCommentForReplies} />
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
        <h1 className="text-lg font-semibold">Comments</h1>
        <div className="w-10" />
      </div>

      {/* Comments List */}
      <div className="flex-1 overflow-y-auto">
        {isLoading ? (
          <div className="flex items-center justify-center py-8">
            <div className="w-6 h-6 border-2 border-xapzap-blue border-t-transparent rounded-full animate-spin" />
          </div>
        ) : (
          <div className="px-4">
            {parentComment && (
              <div className="border-b border-border pb-4 mb-4">
                <CommentItem comment={parentComment} />
              </div>
            )}
            {comments.length === 0 ? (
              <div className="text-center py-8">
                <p className="text-muted-foreground">No {parentComment ? 'replies' : 'comments'} yet</p>
                <p className="text-sm text-muted-foreground mt-1">Be the first to {parentComment ? 'reply' : 'comment'}!</p>
              </div>
            ) : (
              comments.map(comment => (
                <CommentItem key={comment.id} comment={comment} />
              ))
            )}
          </div>
        )}
      </div>

      {/* Comment Input */}
      <div className="border-t border-border p-4">
        <div className="flex items-center space-x-3">
          {currentUserAvatar ? (
            <img src={currentUserAvatar.startsWith('/media/') ? `/api/image-proxy?path=${currentUserAvatar.substring(1)}` : currentUserAvatar} alt="You" className="w-8 h-8 rounded-full object-cover flex-shrink-0" />
          ) : (
            <div className="w-8 h-8 rounded-full bg-muted flex items-center justify-center flex-shrink-0">
              <span className="text-xs font-medium">U</span>
            </div>
          )}
          
          <div className="flex-1 flex items-center space-x-2">
            <input
              type="text"
              value={newComment}
              onChange={(e) => setNewComment(e.target.value)}
              placeholder={replyTo ? "Write a reply..." : "Add a comment..."}
              className="flex-1 bg-muted rounded-full px-4 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-xapzap-blue"
              onKeyPress={(e) => e.key === 'Enter' && handleSubmitComment()}
            />
            
            <button
              onMouseDown={(e) => e.preventDefault()}
              onClick={handleSubmitComment}
              disabled={!newComment.trim() || isSubmitting}
              className="p-2 text-xapzap-blue hover:bg-accent rounded-full transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            >
              <Send size={16} />
            </button>
          </div>
        </div>
        
        {replyTo && (
          <div className="mt-2 ml-11">
            <button
              onClick={() => setReplyTo(null)}
              className="text-xs text-muted-foreground hover:text-foreground"
            >
              Cancel reply
            </button>
          </div>
        )}
      </div>
    </div>
  )
}
