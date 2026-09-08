'use client'

import { Fragment, useState, useEffect } from 'react'
import appwriteService from './appwriteService'
import { feedCache } from './lib/cache'
import { useFeedStore } from './feedStore'
import { hasVerifiedBadge } from './lib/verification'
import { AdcashBanner300x100 } from './components/AdcashBanner300x100'
import { NewsDetailScreen } from './NewsDetailScreen'
import { Clock, Calendar, CheckCircle2, TrendingUp, Filter, Sparkles } from 'lucide-react'
import { OptimizedImage } from './components/OptimizedImage'
import { formatTimeAgo } from './utils'
import { Post } from './types'
import { generateSlug, extractIdFromSlug } from './lib/slug'

function cleanPreviewText(text?: string): string {
  if (!text) return ''
  // Remove markdown links [Label](url) with just Label
  let cleaned = text.replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
  // Remove raw URLs
  cleaned = cleaned.replace(/https?:\/\/[^\s]+/g, '')
  // Normalize spacing
  return cleaned.replace(/\s+/g, ' ').trim()
}

export function NewsScreen() {
  const feedStore = useFeedStore()
  const [posts, setPosts] = useState<any[]>([])
  const [loading, setLoading] = useState(false)
  const [selectedCategory, setSelectedCategory] = useState('All')
  const [activeArticle, setActiveArticle] = useState<any | null>(null)

  // Listen to popstate to handle back button smoothly when detail is open
  useEffect(() => {
    const handlePopState = () => {
      const path = window.location.pathname
      if (path === '/news' || path === '/') {
        setActiveArticle(null)
      } else {
        // Find article matching id in path
        const matches = path.match(/\/news\/([a-zA-Z0-9_-]+)/)
        if (matches && matches[1]) {
          const matchedId = matches[1]
          const found = posts.find(p => p.id === matchedId)
          if (found) {
            setActiveArticle(found)
          }
        }
      }
    }
    window.addEventListener('popstate', handlePopState)
    return () => window.removeEventListener('popstate', handlePopState)
  }, [posts])

  useEffect(() => {
    const cached = feedStore.getFeed('news')
    if (cached && cached.posts.length > 0) {
      setPosts(cached.posts)
      
      // Check if URL has a specific news ID to open it initially
      const path = window.location.pathname
      const matches = path.match(/\/news\/([a-zA-Z0-9_-]+)/)
      if (matches && matches[1]) {
        const found = cached.posts.find(p => p.id === matches[1])
        if (found) setActiveArticle(found)
      }
      return
    }

    loadNews()

    const unsubscribe = appwriteService.subscribeToCollection('posts', (payload) => {
      if (payload.events.includes('databases.*.collections.posts.documents.*.create')) {
        const newPost = payload.payload
        if (newPost.postType === 'news') {
          setPosts(prev => {
            const updated = [{
              ...newPost,
              id: newPost.$id,
              timestamp: new Date(newPost.$createdAt || newPost.createdAt),
            }, ...prev]
            feedStore.setFeed('news', updated)
            return updated
          })
        }
      }
    })

    return unsubscribe
  }, [])

  const loadNews = async () => {
    const isInitialLoad = posts.length === 0
    if (isInitialLoad) setLoading(true)
    try {
      const result = await appwriteService.fetchNewsArticles()
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
            displayName: profile?.displayName || 'XapZap News Desk',
            avatarUrl: profile?.avatarUrl || '',
            isVerified: hasVerifiedBadge(profile) || true,
            isLiked: interactions[0],
            isSaved: interactions[1],
            isReposted: interactions[2]
          }
        })
      )
      
      setPosts(enrichedPosts as Post[])
      feedStore.setFeed('news', enrichedPosts as Post[])

      // Check if URL has a specific news ID to open it initially
      const path = window.location.pathname
      const matches = path.match(/\/news\/([a-zA-Z0-9_-]+)/)
      if (matches && matches[1]) {
        const docId = extractIdFromSlug(matches[1])
        const found = enrichedPosts.find(p => p.id === docId)
        if (found) setActiveArticle(found as Post)
      }
    } catch (error) {
      console.error('Failed to load news:', error)
    } finally {
      if (isInitialLoad) setLoading(false)
    }
  }

  const handleOpenArticle = (article: Post) => {
    setActiveArticle(article)
    const slug = generateSlug(article.title || 'news', article.id)
    window.history.pushState(null, '', `/news/${slug}`)
  }

  const handleCloseArticle = () => {
    setActiveArticle(null)
    window.history.pushState(null, '', '/news')
  }

  // Filter posts based on category
  const filteredPosts = posts.filter(post => {
    if (selectedCategory === 'All') return true
    return (post.category || '').toLowerCase() === selectedCategory.toLowerCase()
  })

  // Hero stories
  const featuredStory = filteredPosts.length > 0 ? filteredPosts[0] : null
  const trendingStories = filteredPosts.slice(1, 4)
  const remainingStories = filteredPosts.slice(4)

  const categories = ['All', 'Technology', 'Science', 'Business', 'General', 'Sports', 'Health']

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
      {/* Dynamic Article Reader Overlay */}
      {activeArticle && (
        <NewsDetailScreen
          article={activeArticle}
          onClose={handleCloseArticle}
        />
      )}

      {/* Header section with brand accent */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 mb-8 border-b border-border pb-6">
        <div>
          <div className="flex items-center space-x-2 text-primary mb-1">
            <Sparkles size={18} className="animate-pulse" />
            <span className="text-xs font-bold uppercase tracking-widest">Global Live Bulletin</span>
          </div>
          <h1 className="text-3xl font-black text-foreground tracking-tight sm:text-4xl">
            XapZap <span className="text-primary">Newsroom</span>
          </h1>
          <p className="text-muted-foreground text-sm mt-1">
            Real-time, high-integrity analytical reporting compiled autonomously.
          </p>
        </div>

        {/* Glassmorphic Category Pills */}
        <div className="flex items-center space-x-2 overflow-x-auto scrollbar-hide py-1 -mx-4 px-4 md:mx-0 md:px-0">
          {categories.map(cat => (
            <button
              key={cat}
              onClick={() => setSelectedCategory(cat)}
              className={`px-4 py-2 rounded-full text-xs font-bold transition-all border whitespace-nowrap ${
                selectedCategory === cat
                  ? 'bg-primary text-primary-foreground border-primary shadow-lg shadow-primary/20 scale-105'
                  : 'bg-accent/40 hover:bg-accent/80 text-muted-foreground border-border'
              }`}
            >
              {cat}
            </button>
          ))}
        </div>
      </div>

      {loading && posts.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-20 space-y-4">
          <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-primary"></div>
          <span className="text-sm text-muted-foreground font-medium">Synchronizing live reports...</span>
        </div>
      ) : filteredPosts.length === 0 ? (
        <div className="text-center py-16 bg-accent/20 rounded-2xl border border-border/60">
          <p className="text-muted-foreground font-semibold">No articles found in {selectedCategory}</p>
          <p className="text-xs text-muted-foreground mt-1">Select another category or refresh the newsroom.</p>
        </div>
      ) : (
        <div className="space-y-12 pb-24">
          
          {/* Hero Section Grid (Top stories layout) */}
          {selectedCategory === 'All' && featuredStory && (
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
              {/* Massive Primary Featured Card */}
              <div 
                onClick={() => handleOpenArticle(featuredStory)}
                className="lg:col-span-2 relative aspect-[16/10] sm:aspect-[16/9] lg:aspect-auto lg:h-[480px] rounded-3xl overflow-hidden group cursor-pointer shadow-xl border border-border/80 hover:border-primary/50 transition-all duration-300 hover:shadow-primary/5"
              >
                {featuredStory.thumbnailUrl || featuredStory.thumbnailUr ? (
                  <OptimizedImage
                    src={featuredStory.thumbnailUrl || featuredStory.thumbnailUr!}
                    alt={featuredStory.title || ''}
                    className="w-full h-full object-cover group-hover:scale-103 transition-transform duration-700 ease-out"
                  />
                ) : (
                  <div className="w-full h-full bg-gradient-to-br from-primary/10 to-accent flex items-center justify-center">
                    <Sparkles size={48} className="text-primary/30" />
                  </div>
                )}
                
                {/* Visual Gradient Layer */}
                <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-black/30 to-black/10" />

                {/* Content Overlay */}
                <div className="absolute inset-0 flex flex-col justify-end p-6 sm:p-8">
                  <div className="flex items-center space-x-2 mb-3">
                    <span className="px-2.5 py-1 rounded-md text-[10px] font-black uppercase tracking-wider bg-primary text-primary-foreground">
                      {featuredStory.category || 'Breaking'}
                    </span>
                    <span className="text-white/60 text-xs flex items-center gap-1 font-medium">
                      <Clock size={12} />
                      {formatTimeAgo(featuredStory.timestamp)}
                    </span>
                  </div>
                  <h2 className="text-2xl sm:text-4xl font-black text-white leading-tight tracking-tight mb-3 group-hover:text-primary-foreground/90 transition-colors">
                    {featuredStory.title}
                  </h2>
                  <p className="text-white/80 text-sm sm:text-base line-clamp-2 max-w-2xl font-light">
                    {cleanPreviewText(featuredStory.summary || featuredStory.content)}
                  </p>
                </div>
              </div>

              {/* Trending Sidebar Column */}
              <div className="flex flex-col justify-between space-y-6">
                <div className="flex items-center space-x-2 text-foreground font-black uppercase tracking-wider text-sm border-b border-border pb-3">
                  <TrendingUp size={16} className="text-primary" />
                  <span>Trending Highlights</span>
                </div>

                <div className="flex-1 space-y-4">
                  {trendingStories.map((story) => (
                    <div
                      key={story.id}
                      onClick={() => handleOpenArticle(story)}
                      className="flex gap-4 p-3 rounded-2xl hover:bg-accent/40 cursor-pointer transition-all border border-transparent hover:border-border group"
                    >
                      <div className="w-24 h-20 rounded-xl overflow-hidden bg-accent/40 flex-shrink-0 border border-border/60">
                        {(story.thumbnailUrl || story.thumbnailUr) ? (
                          <OptimizedImage
                            src={story.thumbnailUrl || story.thumbnailUr!}
                            alt={story.title || ''}
                            className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                          />
                        ) : (
                          <div className="w-full h-full flex items-center justify-center text-primary/30">
                            <Sparkles size={20} />
                          </div>
                        )}
                      </div>
                      <div className="flex-1 min-w-0 flex flex-col justify-center">
                        <span className="text-[10px] font-black uppercase tracking-wider text-primary mb-1">
                          {story.category || 'General'}
                        </span>
                        <h3 className="text-sm font-bold text-foreground leading-snug line-clamp-2 group-hover:text-primary transition-colors">
                          {story.title}
                        </h3>
                        <span className="text-[11px] text-muted-foreground mt-1.5 font-medium">
                          {formatTimeAgo(story.timestamp)}
                        </span>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )}

          {/* Rest of Newsroom Masonry Grid */}
          <div>
            {selectedCategory === 'All' && (
              <h3 className="text-lg font-black uppercase tracking-wider text-foreground border-b border-border pb-3 mb-6">
                All Bulletins
              </h3>
            )}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {(selectedCategory === 'All' ? remainingStories : filteredPosts).map((post, index) => (
                <div
                  key={post.id}
                  onClick={() => handleOpenArticle(post)}
                  className="bg-card hover:bg-accent/20 border border-border hover:border-primary/30 rounded-2xl overflow-hidden group cursor-pointer transition-all duration-300 shadow-md hover:shadow-lg flex flex-col h-full"
                >
                  <div className="relative aspect-[16/10] w-full overflow-hidden bg-accent/50 border-b border-border/80">
                    {(post.thumbnailUrl || post.thumbnailUr) ? (
                      <OptimizedImage
                        src={post.thumbnailUrl || post.thumbnailUr!}
                        alt={post.title || ''}
                        className="w-full h-full object-cover group-hover:scale-104 transition-transform duration-500"
                      />
                    ) : (
                      <div className="w-full h-full flex items-center justify-center text-primary/30">
                        <Sparkles size={32} />
                      </div>
                    )}
                    <span className="absolute top-3 left-3 px-2 py-0.5 rounded text-[9px] font-black uppercase bg-background/90 text-foreground shadow-sm">
                      {post.category || 'News'}
                    </span>
                  </div>

                  <div className="p-5 flex-1 flex flex-col justify-between">
                    <div className="space-y-2">
                      <h4 className="text-[15px] font-extrabold text-foreground leading-snug tracking-tight line-clamp-2 group-hover:text-primary transition-colors">
                        {post.title}
                      </h4>
                      <p className="text-xs text-muted-foreground line-clamp-3 leading-relaxed font-light">
                        {cleanPreviewText(post.summary || post.content)}
                      </p>
                    </div>

                    <div className="flex items-center justify-between pt-4 mt-4 border-t border-border/60 text-[11px] text-muted-foreground font-semibold">
                      <span>{formatTimeAgo(post.timestamp)}</span>
                      <span className="text-primary hover:underline">Read Analysis →</span>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>

        </div>
      )}
    </div>
  )
}
