'use client'

import { Fragment, useState, useEffect } from 'react'
import { PostCard } from './PostCard'
import { Post } from './types'
import appwriteService from './appwriteService'
import { useFeedStore } from './feedStore'
import { AdcashBanner300x100 } from './components/AdcashBanner300x100'

export function FollowingScreen() {
  const feedStore = useFeedStore()
  const [posts, setPosts] = useState<Post[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const cached = feedStore.getFeed('following')
    if (cached && cached.posts.length > 0) {
      setPosts(cached.posts)
      setLoading(false)
      setTimeout(() => window.scrollTo(0, cached.scrollPosition), 0)
      return
    }

    loadFollowingPosts()

    const unsubscribe = appwriteService.subscribeToCollection('posts', (payload) => {
      if (payload.events.includes('databases.*.collections.posts.documents.*.create')) {
        const newPost = payload.payload
        setPosts(prev => {
          const updated = [{
            ...newPost,
            id: newPost.$id,
            timestamp: new Date(newPost.$createdAt || newPost.createdAt),
          }, ...prev]
          feedStore.setFeed('following', updated)
          return updated
        })
      }
    })

    return unsubscribe
  }, [])

  useEffect(() => {
    const handleScroll = () => {
      feedStore.setScrollPosition('following', window.scrollY)
    }
    window.addEventListener('scroll', handleScroll)
    return () => window.removeEventListener('scroll', handleScroll)
  }, [])

  const loadFollowingPosts = async () => {
    setLoading(true)
    try {
      const user = await appwriteService.getCurrentUser()
      if (!user) {
        setPosts([])
        return
      }

      const result = await appwriteService.fetchFollowingFeed(user.$id)
      const postsData: Post[] = await Promise.all(
        result.documents.map(async (d: any) => ({
          ...d,
          id: d.$id,
          timestamp: new Date(d.$createdAt || d.createdAt),
        }))
      )

      // In the following feed, hide long description text for video posts
      // so cards focus on the title/media.
      const adjusted = postsData.map(post =>
        post.postType === 'video' ? { ...post, content: '' } : post
      )

      setPosts(adjusted)
      feedStore.setFeed('following', adjusted)
    } catch (error) {
      console.error('Failed to load following posts:', error)
      // Fallback to all posts if following feed fails
      try {
        const result = await appwriteService.fetchPosts()
        const fallbackPosts: Post[] = await Promise.all(
          result.documents.map(async (d: any) => ({
            ...d,
            id: d.$id,
            timestamp: new Date(d.$createdAt || d.createdAt),
          }))
        )

        const adjustedFallback = fallbackPosts.map(post =>
          post.postType === 'video' ? { ...post, content: '' } : post
        )

        setPosts(adjustedFallback)
      } catch (fallbackError) {
        console.error('Fallback also failed:', fallbackError)
        setPosts([])
      }
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="max-w-2xl mx-auto px-4 sm:px-6 lg:px-8">
      <div className="space-y-4 pb-20 sm:pb-24">
        {loading ? (
          <div className="flex items-center justify-center py-12">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
          </div>
        ) : posts.length === 0 ? (
          <div className="text-center py-12">
            <p className="text-muted-foreground">No posts from people you follow</p>
            <p className="text-sm text-muted-foreground mt-2">Follow creators to see their posts here</p>
          </div>
        ) : (
          posts.map((post, index) => (
            <Fragment key={post.id}>
              <PostCard
                post={post}
                feedType="following"
              />
              {index < posts.length - 1 && (
                <AdcashBanner300x100 slotKey={`following-${post.id}-${index}`} />
              )}
            </Fragment>
          ))
        )}
      </div>
    </div>
  )
}
