'use client'

import { Search, X, User, Hash, TrendingUp } from 'lucide-react'
import { Fragment, useState, useEffect } from 'react'
import appwriteService from './appwriteService'
import { PostCard } from './PostCard'
import { formatCount } from './utils'
import { AdcashBanner300x100 } from './components/AdcashBanner300x100'

interface SearchScreenProps {
  onClose: () => void
}

interface SearchResult {
  type: 'post' | 'user' | 'hashtag'
  data: any
}

export function SearchScreen({ onClose }: SearchScreenProps) {
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
            const postsResult = await appwriteService.fetchPosts(20)
            const filteredPosts = postsResult.documents.filter((post: any) =>
              post.content?.toLowerCase().includes(query.toLowerCase()) ||
              post.title?.toLowerCase().includes(query.toLowerCase())
            ).slice(0, 10)

            filteredPosts.forEach((post: any) => {
              searchResults.push({
                type: 'post',
                data: {
                  ...post,
                  id: post.$id,
                  timestamp: new Date(post.$createdAt || post.createdAt)
                }
              })
            })
          } catch (error) {
            console.error('Posts search error:', error)
          }
        }

        // Search users - simplified for now
        if (activeTab === 'all' || activeTab === 'users') {
          // For now, skip user search to avoid private property access
          // This can be implemented later with a proper public search method
        }

        // Mock hashtags for now (can be enhanced with real hashtag tracking)
        if (activeTab === 'all' || activeTab === 'hashtags') {
          const mockHashtags = [
            { tag: '#TechNews', count: 1250 },
            { tag: '#WebDevelopment', count: 890 },
            { tag: '#AI', count: 2100 },
            { tag: '#React', count: 1450 },
            { tag: '#NextJS', count: 780 }
          ].filter(hashtag =>
            hashtag.tag.toLowerCase().includes(query.toLowerCase())
          )

          mockHashtags.forEach(hashtag => {
            searchResults.push({
              type: 'hashtag',
              data: hashtag
            })
          })
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
          <div key={`post-${result.data.id}`} className="border-b border-border last:border-b-0">
            <PostCard
              post={result.data}
              feedType="home"
            />
          </div>
        )

      case 'user':
        return (
          <div key={`user-${result.data.$id}`} className="p-4 border-b border-border last:border-b-0 hover:bg-accent cursor-pointer">
            <div className="flex items-center gap-3">
              {result.data.avatarUrl ? (
                <img
                  src={result.data.avatarUrl}
                  alt={result.data.displayName}
                  className="w-12 h-12 rounded-full object-cover"
                />
              ) : (
                <div className="w-12 h-12 rounded-full bg-muted flex items-center justify-center">
                  <User size={20} className="text-muted-foreground" />
                </div>
              )}
              <div className="flex-1 min-w-0">
                <p className="font-semibold truncate">{result.data.displayName || result.data.username}</p>
                <p className="text-sm text-muted-foreground truncate">@{result.data.username}</p>
                {result.data.bio && (
                  <p className="text-sm text-muted-foreground mt-1 line-clamp-2">{result.data.bio}</p>
                )}
              </div>
            </div>
          </div>
        )

      case 'hashtag':
        return (
          <div key={`hashtag-${result.data.tag}`} className="p-4 border-b border-border last:border-b-0 hover:bg-accent cursor-pointer">
            <div className="flex items-center gap-3">
              <div className="w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center">
                <Hash size={20} className="text-primary" />
              </div>
              <div className="flex-1">
                <p className="font-semibold">{result.data.tag}</p>
                <p className="text-sm text-muted-foreground">{formatCount(result.data.count)} posts</p>
              </div>
              <TrendingUp size={16} className="text-muted-foreground" />
            </div>
          </div>
        )

      default:
        return null
    }
  }

  return (
    <div className="fixed inset-0 z-50 bg-background animate-in slide-in-from-top duration-300">
      <div className="h-full flex flex-col">
        {/* Header */}
        <div className="bg-background border-b border-border p-4">
          <div className="flex items-center space-x-3">
            <button
              onClick={onClose}
              className="p-2 hover:bg-accent rounded-full transition-colors"
              aria-label="Close search"
            >
              <X size={20} />
            </button>
            <div className="flex-1 relative">
              <Search size={20} className="absolute left-3 top-1/2 transform -translate-y-1/2 text-muted-foreground" />
              <input
                type="text"
                placeholder="Search XapZap"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                className="w-full pl-10 pr-4 py-2 bg-muted rounded-full border-0 focus:outline-none focus:ring-2 focus:ring-primary"
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
                      ? 'bg-primary text-primary-foreground'
                      : 'bg-muted text-muted-foreground hover:bg-accent'
                  }`}
                  aria-label={`Search ${tab.label.toLowerCase()}`}
                  title={`Search ${tab.label.toLowerCase()}`}
                >
                  {tab.label}
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Results */}
        <div className="flex-1 overflow-y-auto">
          {loading ? (
            <div className="flex items-center justify-center py-12">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
            </div>
          ) : query.trim() ? (
            results.length > 0 ? (
              <div className="divide-y divide-border">
                {results.map((result, index) => {
                  const node = renderResult(result)
                  if (result.type !== 'post') return node

                  const hasAnotherPostAhead = results
                    .slice(index + 1)
                    .some((item) => item.type === 'post')

                  const resultKey =
                    result.type === 'post'
                      ? `overlay-result-post-${result.data.id || index}`
                      : `overlay-result-${result.type}-${index}`

                  return (
                    <Fragment key={resultKey}>
                      {node}
                      {hasAnotherPostAhead && (
                        <AdcashBanner300x100 slotKey={`overlay-search-post-${result.data.id || index}-${index}`} />
                      )}
                    </Fragment>
                  )
                })}
              </div>
            ) : (
              <div className="text-center py-12">
                <Search size={48} className="mx-auto mb-4 text-muted-foreground" />
                <p className="text-muted-foreground">No results found for "{query}"</p>
                <p className="text-sm text-muted-foreground mt-2">Try searching for posts, users, or hashtags</p>
              </div>
            )
          ) : (
            <div className="p-4">
              <h2 className="font-semibold mb-4">Trending</h2>
              <div className="space-y-2">
                {[
                  { tag: '#TechNews', category: 'Technology', posts: '1.2K posts' },
                  { tag: '#WebDevelopment', category: 'Technology', posts: '890 posts' },
                  { tag: '#AI', category: 'Technology', posts: '2.1K posts' },
                  { tag: '#React', category: 'Technology', posts: '1.4K posts' },
                  { tag: '#NextJS', category: 'Technology', posts: '780 posts' }
                ].map((trend) => (
                  <div
                    key={trend.tag}
                    className="p-3 hover:bg-accent rounded-lg cursor-pointer transition-colors"
                    onClick={() => setQuery(trend.tag)}
                  >
                    <div className="flex items-center gap-2 mb-1">
                      <TrendingUp size={16} className="text-primary" />
                      <p className="font-medium">{trend.tag}</p>
                    </div>
                    <p className="text-sm text-muted-foreground">{trend.category} • {trend.posts}</p>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

export function NotificationsScreen() {
  return (
    <div className="max-w-2xl mx-auto px-4 sm:px-6 lg:px-8">
      <div className="py-6">
        <h1 className="text-2xl font-bold mb-6">Notifications</h1>
        <div className="text-center py-12">
          <p className="text-muted-foreground">No notifications yet</p>
          <p className="text-sm text-muted-foreground mt-2">We'll notify you when something happens!</p>
        </div>
      </div>
    </div>
  )
}

// Export detail screens
export { CommentScreen } from './CommentScreen'
export { PostDetailScreen } from './PostDetailScreen'
export { VideoDetailScreen, ReelsDetailScreen } from './VideoDetailScreen'
export { ImageDetailScreen } from './ImageDetailScreen'
