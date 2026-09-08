'use client'

import { Fragment, useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { Search, X, User, Hash, TrendingUp, ArrowLeft } from 'lucide-react'
import appwriteService from '../../appwriteService'
import { PostCard } from '../../PostCard'
import { formatCount } from '../../utils'
import { AdcashBanner300x100 } from '../../components/AdcashBanner300x100'

interface SearchResult {
  type: 'post' | 'user' | 'hashtag'
  data: any
}

export default function SearchPage() {
  const router = useRouter()
  const [query, setQuery] = useState('')
  const [results, setResults] = useState<SearchResult[]>([])
  const [loading, setLoading] = useState(false)
  const [activeTab, setActiveTab] = useState<'all' | 'posts' | 'users' | 'hashtags'>('all')

  // Real-time search
  useEffect(() => {
    const search = async () => {
      if (!query.trim()) {
        setResults([])
        return
      }

      setLoading(true)
      try {
        const searchResults: SearchResult[] = []

        // Search posts
        if (activeTab === 'all' || activeTab === 'posts') {
          try {
            // Use a broader search approach since Appwrite search has limitations
            const postsResult = await appwriteService.fetchPosts(50)
            const filteredPosts = postsResult.documents.filter((post: any) =>
              post.content?.toLowerCase().includes(query.toLowerCase()) ||
              post.title?.toLowerCase().includes(query.toLowerCase()) ||
              post.username?.toLowerCase().includes(query.toLowerCase())
            ).slice(0, 20)

            filteredPosts.forEach((post: any) => {
              searchResults.push({
                type: 'post',
                data: {
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
                }
              })
            })
          } catch (error) {
            console.error('Posts search error:', error)
          }
        }

        // Search users
        if (activeTab === 'all' || activeTab === 'users') {
          try {
            // Search for users by username or display name
            const usersResult = await appwriteService.searchUsers(query, 10)
            usersResult.forEach((user: any) => {
              searchResults.push({
                type: 'user',
                data: user
              })
            })
          } catch (error) {
            console.error('Users search error:', error)
          }
        }

        // Search hashtags - use real hashtag data from posts
        if (activeTab === 'all' || activeTab === 'hashtags') {
          try {
            const hashtagResults = await appwriteService.searchHashtags(query, 10)
            hashtagResults.forEach((hashtag: any) => {
              searchResults.push({
                type: 'hashtag',
                data: hashtag
              })
            })
          } catch (error) {
            console.error('Hashtags search error:', error)
          }
        }

        setResults(searchResults)
      } catch (error) {
        console.error('Search error:', error)
        setResults([])
      } finally {
        setLoading(false)
      }
    }

    const debounceTimer = setTimeout(search, 300) // Debounce search
    return () => clearTimeout(debounceTimer)
  }, [query, activeTab])

  const renderResult = (result: SearchResult) => {
    switch (result.type) {
      case 'post':
        return (
          <div key={`post-${result.data.id}`} className="border-b border-gray-800 last:border-b-0">
            <PostCard
              post={result.data}
              currentUserId=""
              feedType="home"
            />
          </div>
        )

      case 'user':
        return (
          <div
            key={`user-${result.data.$id}`}
            className="p-4 border-b border-gray-800 last:border-b-0 hover:bg-gray-900 cursor-pointer transition-colors"
            onClick={() => router.push(`/profile/${result.data.$id}`)}
          >
            <div className="flex items-center gap-3">
              {result.data.avatarUrl ? (
                <img
                  src={result.data.avatarUrl}
                  alt={result.data.displayName || result.data.username}
                  className="w-12 h-12 rounded-full object-cover"
                />
              ) : (
                <div className="w-12 h-12 rounded-full bg-gray-800 flex items-center justify-center">
                  <User size={20} className="text-gray-400" />
                </div>
              )}
              <div className="flex-1 min-w-0">
                <p className="font-semibold text-white truncate">
                  {result.data.displayName || result.data.username}
                </p>
                <p className="text-sm text-gray-400 truncate">@{result.data.username}</p>
                {result.data.bio && (
                  <p className="text-sm text-gray-400 mt-1 line-clamp-2">{result.data.bio}</p>
                )}
              </div>
            </div>
          </div>
        )

      case 'hashtag':
        return (
          <div
            key={`hashtag-${result.data.tag}`}
            className="p-4 border-b border-gray-800 last:border-b-0 hover:bg-gray-900 cursor-pointer transition-colors"
            onClick={() => router.push(`/hashtag/${result.data.tag.substring(1)}`)}
          >
            <div className="flex items-center gap-3">
              <div className="w-12 h-12 rounded-full bg-blue-600/10 flex items-center justify-center">
                <Hash size={20} className="text-blue-400" />
              </div>
              <div className="flex-1">
                <p className="font-semibold text-white">{result.data.tag}</p>
                <p className="text-sm text-gray-400">{formatCount(result.data.count || 0)} posts</p>
              </div>
              <TrendingUp size={16} className="text-gray-400" />
            </div>
          </div>
        )

      default:
        return null
    }
  }

  return (
    <div className="min-h-screen bg-black">
      {/* Header */}
      <div className="sticky top-0 z-50 bg-black border-b border-gray-800 p-4">
        <div className="flex items-center space-x-3">
          <button
            onClick={() => router.back()}
            className="p-2 hover:bg-gray-800 rounded-full transition-colors"
            aria-label="Go back"
          >
            <ArrowLeft size={20} />
          </button>
          <div className="flex-1 relative">
            <Search size={20} className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400" />
            <input
              type="text"
              placeholder="Search XapZap"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              className="w-full pl-10 pr-4 py-3 bg-gray-900 border border-gray-700 rounded-full text-white placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              autoFocus
            />
          </div>
        </div>

        {/* Search Tabs */}
        {query.trim() && (
          <div className="flex gap-2 mt-3">
            {[
              { id: 'all', label: 'All' },
              { id: 'posts', label: 'Posts' },
              { id: 'users', label: 'Users' },
              { id: 'hashtags', label: 'Hashtags' }
            ].map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id as any)}
                className={`px-3 py-1 text-sm rounded-full transition-colors ${
                  activeTab === tab.id
                    ? 'bg-blue-600 text-white'
                    : 'bg-gray-800 text-gray-400 hover:bg-gray-700'
                }`}
                aria-label={`Search ${tab.label.toLowerCase()}`}
              >
                {tab.label}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Results */}
      <div className="flex-1">
        {loading ? (
          <div className="flex items-center justify-center py-12">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500"></div>
          </div>
        ) : query.trim() ? (
          results.length > 0 ? (
            <div className="divide-y divide-gray-800">
              {results.map((result, index) => {
                const node = renderResult(result)
                if (result.type !== 'post') return node

                const hasAnotherPostAhead = results
                  .slice(index + 1)
                  .some((item) => item.type === 'post')

                const resultKey =
                  result.type === 'post'
                    ? `result-post-${result.data.id || index}`
                    : `result-${result.type}-${index}`

                return (
                  <Fragment key={resultKey}>
                    {node}
                    {hasAnotherPostAhead && (
                      <AdcashBanner300x100 slotKey={`search-post-${result.data.id || index}-${index}`} />
                    )}
                  </Fragment>
                )
              })}
            </div>
          ) : (
            <div className="text-center py-12">
              <Search size={48} className="mx-auto mb-4 text-gray-600" />
              <p className="text-gray-400">No results found for "{query}"</p>
              <p className="text-sm text-gray-500 mt-2">Try searching for posts, users, or hashtags</p>
            </div>
          )
        ) : (
          <div className="p-4">
            <h2 className="font-semibold text-white mb-4">Trending</h2>
            <div className="space-y-2">
              {/* This will be populated with real trending data */}
              <div className="text-center py-8">
                <TrendingUp size={48} className="mx-auto mb-4 text-gray-600" />
                <p className="text-gray-400">Trending topics will appear here</p>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
