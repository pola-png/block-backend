'use client'

import { Fragment, useEffect, useMemo, useState } from 'react'
import appwriteService from '../../appwriteService'
import { PostCard } from '../../PostCard'
import { Post } from '../../types'
import { AdcashBanner300x100 } from '../../components/AdcashBanner300x100'

const KEYWORDS = [
  'chinese',
  'china',
  'c-drama',
  'cdrama',
  'drama',
  'movie',
  'movies',
  'romance',
  'historical',
  'wuxia',
  '中国',
  '中文',
  '华语',
  '古装',
]

const toSearchableText = (post: Post) =>
  `${post.title || ''} ${post.content || ''} ${post.caption || ''} ${post.seoKeywords || ''}`.toLowerCase()

const scorePost = (post: Post) => {
  const text = toSearchableText(post)
  return KEYWORDS.reduce((score, keyword) => (text.includes(keyword) ? score + 1 : score), 0)
}

const normalizePost = (doc: any): Post => ({
  ...doc,
  id: doc.$id,
  postId: doc.$id,
  userId: doc.userId || '',
  username: doc.username || '',
  userAvatar: doc.userAvatar || doc.avatarUrl || '',
  displayName: doc.displayName || 'User',
  avatarUrl: doc.avatarUrl || doc.userAvatar || '',
  content: doc.content || '',
  caption: doc.caption || '',
  postType: doc.postType || 'text',
  title: doc.title || '',
  thumbnailUrl: doc.thumbnailUrl || '',
  mediaUrls: Array.isArray(doc.mediaUrls) ? doc.mediaUrls : [],
  timestamp: new Date(doc.$createdAt || doc.createdAt || Date.now()),
  createdAt: doc.$createdAt || doc.createdAt || new Date().toISOString(),
  likes: Number(doc.likes || 0),
  comments: Number(doc.comments || 0),
  reposts: Number(doc.reposts || 0),
  shares: Number(doc.shares || 0),
  impressions: Number(doc.impressions || 0),
  views: Number(doc.views || 0),
  isLiked: false,
  isReposted: false,
  isSaved: false,
  isBoosted: Boolean(doc.isBoosted),
})

export function ChineseDramaMoviesFeed() {
  const [posts, setPosts] = useState<Post[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const loadPosts = async () => {
      try {
        const result = await appwriteService.fetchPosts(200)
        const normalized = result.documents.map(normalizePost)
        setPosts(normalized)
      } catch (error) {
        console.error('Failed to load Chinese drama movie posts:', error)
        setPosts([])
      } finally {
        setLoading(false)
      }
    }

    void loadPosts()
  }, [])

  const filteredPosts = useMemo(() => {
    return posts
      .map((post) => ({ post, score: scorePost(post) }))
      .filter(({ score }) => score > 0)
      .sort((a, b) => {
        if (b.score !== a.score) return b.score - a.score
        return b.post.timestamp.getTime() - a.post.timestamp.getTime()
      })
      .map(({ post }) => post)
  }, [posts])

  if (loading) {
    return (
      <div className="mt-6 flex items-center justify-center py-8">
        <div className="h-8 w-8 animate-spin rounded-full border-b-2 border-primary" />
      </div>
    )
  }

  if (filteredPosts.length === 0) {
    return (
      <div className="mt-6 rounded-xl border border-border bg-card p-6 text-center">
        <p className="text-base font-semibold text-foreground">No Chinese drama movie posts yet.</p>
        <p className="mt-2 text-sm text-muted-foreground">
          When creators upload matching content, post cards will appear here.
        </p>
      </div>
    )
  }

  return (
    <div className="mt-6 overflow-hidden rounded-xl border border-border bg-card">
      {filteredPosts.map((post, index) => (
        <Fragment key={post.id}>
          <div className="border-b border-border last:border-b-0">
            <PostCard
              post={post}
              feedType={post.postType === 'reel' ? 'reels' : post.postType === 'news' ? 'news' : 'home'}
            />
          </div>
          {index < filteredPosts.length - 1 && (
            <AdcashBanner300x100
              slotKey={`chinese-drama-${post.id}-${index}`}
              className="border-b border-border"
            />
          )}
        </Fragment>
      ))}
    </div>
  )
}
