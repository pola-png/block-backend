'use client'

import { Fragment, useState, useEffect } from 'react'
import { useParams, useRouter } from 'next/navigation'
import { ArrowLeft, Hash } from 'lucide-react'
import { PostCard } from '../../../PostCard'
import { Post } from '../../../types'
import appwriteService from '../../../appwriteService'
import { AdcashBanner300x100 } from '../../../components/AdcashBanner300x100'

export default function HashtagPage() {
  const params = useParams()
  const router = useRouter()
  const tag = params.tag as string

  const [posts, setPosts] = useState<Post[]>([])
  const [loading, setLoading] = useState(true)
  const [currentUserId, setCurrentUserId] = useState<string>('')

  useEffect(() => {
    loadHashtagPosts()
  }, [tag])

  const loadHashtagPosts = async () => {
    try {
      setLoading(true)

      // Get current user
      const currentUser = await appwriteService.getCurrentUser()
      setCurrentUserId(currentUser?.$id || '')

      // Search for posts containing this hashtag
      const postsResult = await appwriteService.fetchPosts(100)
      const hashtagPosts = postsResult.documents.filter((post: any) =>
        post.content?.toLowerCase().includes(`#${tag.toLowerCase()}`)
      )

      const formattedPosts = hashtagPosts.map((post: any) => ({
        ...post,
        id: post.$id,
        postId: post.$id,
        userId: post.userId,
        username: post.username,
        userAvatar: post.userAvatar,
        content: post.content,
        timestamp: new Date(post.$createdAt || post.createdAt),
        createdAt: post.$createdAt || post.createdAt,
        likes: post.likes || 0,
        comments: post.comments || 0,
        reposts: post.reposts || 0,
        impressions: post.impressions || 0,
        views: post.views || 0,
        isLiked: false,
        isReposted: false,
        isSaved: false,
        isBoosted: false
      })) as Post[]

      setPosts(formattedPosts)
    } catch (error) {
      console.error('Failed to load hashtag posts:', error)
    } finally {
      setLoading(false)
    }
  }

  if (loading) {
    return (
      <div className="min-h-screen bg-[rgb(var(--bg-primary))] flex items-center justify-center">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-white"></div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-[rgb(var(--bg-primary))] text-[rgb(var(--text-primary))]">
      {/* Header */}
      <div className="sticky top-0 z-50 bg-[rgb(var(--bg-primary))]/95 backdrop-blur-md border-b border-[rgb(var(--border-color))] p-4">
        <div className="max-w-2xl mx-auto flex items-center space-x-3">
          <button
            onClick={() => router.back()}
            className="p-2 hover:bg-[rgb(var(--bg-secondary))] rounded-full transition-colors text-[rgb(var(--text-primary))]"
            aria-label="Go back"
          >
            <ArrowLeft size={20} />
          </button>
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 rounded-full bg-blue-600/10 flex items-center justify-center">
              <Hash size={20} className="text-blue-400" />
            </div>
            <div>
              <h1 className="text-xl font-bold text-[rgb(var(--text-primary))]">#{tag}</h1>
              <p className="text-sm text-[rgb(var(--text-secondary))]">{posts.length} posts</p>
            </div>
          </div>
        </div>
      </div>

      {/* Posts */}
      <div className="max-w-2xl mx-auto px-4 pb-20 pt-4">
        {posts.length === 0 ? (
          <div className="text-center py-12">
            <Hash size={48} className="mx-auto mb-4 text-[rgb(var(--text-secondary))]" />
            <p className="text-[rgb(var(--text-secondary))]">No posts found for #{tag}</p>
            <p className="text-sm text-[rgb(var(--text-secondary))]/80 mt-2">Be the first to use this hashtag!</p>
          </div>
        ) : (
          <div className="divide-y divide-[rgb(var(--border-color))]">
            {posts.map((post, index) => (
              <Fragment key={post.id}>
                <PostCard
                  post={post}
                  currentUserId={currentUserId}
                  feedType="home"
                />
                {index < posts.length - 1 && (
                  <div className="py-4">
                    <AdcashBanner300x100 slotKey={`hashtag-${tag}-${post.id}-${index}`} />
                  </div>
                )}
              </Fragment>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
