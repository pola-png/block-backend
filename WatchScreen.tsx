'use client'

import { Fragment, useState, useEffect } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { PostCard } from './PostCard'
import { CommentModal } from './CommentModal'
import { Post } from './types'
import appwriteService from './appwriteService'
import { feedCache } from './lib/cache'
import { generateSlug } from './lib/slug'
import { useFeedStore } from './feedStore'
import { hasVerifiedBadge } from './lib/verification'
import { cacheRoutePost } from './lib/route-post-cache'
import { AdcashBanner300x100 } from './components/AdcashBanner300x100'

export function WatchScreen() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const feedStore = useFeedStore()
  const [posts, setPosts] = useState<Post[]>([])
  const [loading, setLoading] = useState(false)
  const [hasLoaded, setHasLoaded] = useState(false)
  const [selectedPost, setSelectedPost] = useState<Post | null>(null)
  const [showComments, setShowComments] = useState(false)

  useEffect(() => {
    const postId = searchParams.get('post')
    const comments = searchParams.get('comments')
    
    if (postId && comments) {
      const post = posts.find(p => p.id === postId)
      if (post) {
        setSelectedPost(post)
        setShowComments(true)
      }
    }
  }, [searchParams, posts])

  useEffect(() => {
    const cached = feedStore.getFeed('watch')
    if (cached && cached.posts.length > 0) {
      setPosts(cached.posts)
      setHasLoaded(true)
      setTimeout(() => window.scrollTo(0, cached.scrollPosition), 0)
      return
    }

    if (!hasLoaded) {
      loadVideos()
    }

    const unsubscribe = appwriteService.subscribeToCollection('posts', (payload) => {
      if (payload.events.includes('databases.*.collections.posts.documents.*.create')) {
        const newPost = payload.payload
        if (newPost.postType === 'video') {
          setPosts(prev => {
            const updated = [{
              ...newPost,
              id: newPost.$id,
              timestamp: new Date(newPost.$createdAt || newPost.createdAt),
            }, ...prev]
            feedStore.setFeed('watch', updated)
            return updated
          })
        }
      }
    })

    return unsubscribe
  }, [hasLoaded])

  useEffect(() => {
    const handleScroll = () => {
      feedStore.setScrollPosition('watch', window.scrollY)
    }
    window.addEventListener('scroll', handleScroll)
    return () => window.removeEventListener('scroll', handleScroll)
  }, [])

  const loadVideos = async () => {
    const isInitialLoad = posts.length === 0
    if (isInitialLoad) setLoading(true)
    try {
      const result = await appwriteService.fetchWatchFeed()
      const user = await appwriteService.getCurrentUser()
      
      const enrichedPosts = await Promise.all(
        result.documents.map(async (d: any) => {
          const profile = await appwriteService.getProfileByUserId(d.userId)
          const interactions = user ? await Promise.all([
            appwriteService.isPostLikedBy(user.$id, d.$id),
            appwriteService.isPostSavedBy(user.$id, d.$id),
            appwriteService.isPostRepostedBy(user.$id, d.$id)
          ]) : [false, false, false]
          
          return {
            ...d,
            id: d.$id,
            timestamp: new Date(d.$createdAt || d.createdAt),
            displayName: profile?.displayName || 'User',
            avatarUrl: profile?.avatarUrl || '',
            isVerified: hasVerifiedBadge(profile),
            isLiked: interactions[0],
            isSaved: interactions[1],
            isReposted: interactions[2]
          }
        })
      )
      
      setPosts(enrichedPosts as Post[])
      feedStore.setFeed('watch', enrichedPosts as Post[])
      setHasLoaded(true)
    } catch (error) {
      console.error('Failed to load videos:', error)
    } finally {
      if (isInitialLoad) setLoading(false)
    }
  }

  const handleCommentClick = (post: Post) => {
    setSelectedPost(post)
    setShowComments(true)
    router.push(`/watch?post=${post.id}&comments=true`, { scroll: false })
  }

  const handleCloseComments = () => {
    setShowComments(false)
    setSelectedPost(null)
    router.push('/watch', { scroll: false })
  }

  const handleVideoClick = (post: Post) => {
    const resolvedId = post.id || post.postId || (post as any).$id || ''
    if (!resolvedId) return
    const slug = generateSlug(post.title || post.content || 'video', resolvedId)
    cacheRoutePost(slug, {
      ...post,
      id: resolvedId,
      postId: post.postId || resolvedId,
      timestamp: post.timestamp instanceof Date ? post.timestamp : new Date(post.createdAt || Date.now()),
    })
    router.push(`/watch/${slug}`)
  }

  if (showComments && selectedPost) {
    const isFullscreen = searchParams.get('comments') === 'fullscreen'
    
    if (isFullscreen) {
      return (
        <div className="fixed inset-0 bg-background z-50 flex flex-col">
          <div className="flex items-center justify-between p-4 border-b border-border">
            <button
              onClick={handleCloseComments}
              className="p-2 hover:bg-accent rounded-full transition-colors"
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M19 12H5M12 19l-7-7 7-7"/>
              </svg>
            </button>
            <h1 className="text-lg font-semibold">Comments</h1>
            <div className="w-10" />
          </div>
          <div className="flex-1 overflow-y-auto p-4">
            <p className="text-muted-foreground text-sm text-center py-8">Full screen comments</p>
          </div>
          <div className="border-t border-border p-3">
            <div className="flex items-center gap-2 sm:gap-3">
              {selectedPost.avatarUrl ? (
                <img src={selectedPost.avatarUrl} alt={selectedPost.displayName} className="w-8 h-8 rounded-full object-cover ring-2 ring-border" />
              ) : (
                <div className="w-8 h-8 rounded-full bg-gradient-to-br from-primary to-primary/70 flex items-center justify-center text-primary-foreground font-semibold text-xs">
                  {(selectedPost.displayName || 'U')[0].toUpperCase()}
                </div>
              )}
              <input
                type="text"
                placeholder="Add a comment..."
                className="flex-1 bg-background border border-border rounded-full px-3 sm:px-4 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent transition-all"
              />
              <button className="px-3 sm:px-4 py-2 bg-primary text-primary-foreground rounded-full text-xs sm:text-sm font-medium hover:bg-primary/90 transition-all hover:scale-105 active:scale-95 shadow-md">
                Post
              </button>
            </div>
          </div>
        </div>
      )
    }
    
    return (
      <>
        <div className="max-w-2xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="space-y-4 pb-20 sm:pb-24">
            {posts.map((post, index) => (
              <Fragment key={post.id}>
                <PostCard
                  post={post}
                  feedType="watch"
                  onVideoClick={handleVideoClick}
                  onCommentClick={() => handleCommentClick(post)}
                />
                {index < posts.length - 1 && (
                  <AdcashBanner300x100 slotKey={`watch-comments-${post.id}-${index}`} />
                )}
              </Fragment>
            ))}
          </div>
        </div>
        <CommentModal post={selectedPost} onClose={handleCloseComments} />
      </>
    )
  }

  return (
    <div className="max-w-2xl mx-auto px-4 sm:px-6 lg:px-8">
      <div className="space-y-4 pb-20 sm:pb-24">
        {posts.length === 0 && !loading ? (
          <div className="text-center py-12">
            <p className="text-muted-foreground">No videos yet</p>
            <p className="text-sm text-muted-foreground mt-2">Videos from creators you follow will appear here</p>
          </div>
        ) : (
          posts.map((post, index) => (
            <Fragment key={post.id}>
              <PostCard
                post={post}
                feedType="watch"
                onVideoClick={handleVideoClick}
                onCommentClick={() => handleCommentClick(post)}
              />
              {index < posts.length - 1 && (
                <AdcashBanner300x100 slotKey={`watch-${post.id}-${index}`} />
              )}
            </Fragment>
          ))
        )}
        {loading && posts.length === 0 && (
          <div className="flex items-center justify-center py-12">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
          </div>
        )}
      </div>
    </div>
  )
}
