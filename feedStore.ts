import { create } from 'zustand'
import { Post } from './types'

type FeedType = 'foryou' | 'following' | 'watch' | 'reels' | 'news' | 'live'

type FeedCache = {
  posts: Post[]
  scrollPosition: number
  timestamp: number
}

type FeedStore = {
  cache: Map<FeedType, FeedCache>
  setFeed: (feedType: FeedType, posts: Post[]) => void
  getFeed: (feedType: FeedType) => FeedCache | null
  setScrollPosition: (feedType: FeedType, position: number) => void
  clearFeed: (feedType: FeedType) => void
  clearAllFeeds: () => void
}

export const useFeedStore = create<FeedStore>((set, get) => ({
  cache: new Map(),
  
  setFeed: (feedType, posts) => {
    const cache = new Map(get().cache)
    const existing = cache.get(feedType)
    cache.set(feedType, { 
      posts, 
      scrollPosition: existing?.scrollPosition || 0,
      timestamp: Date.now() 
    })
    set({ cache })
  },
  
  getFeed: (feedType) => {
    const cached = get().cache.get(feedType)
    if (!cached) return null
    
    // Cache valid for 10 minutes
    if (Date.now() - cached.timestamp > 10 * 60 * 1000) {
      return null
    }
    
    return cached
  },
  
  setScrollPosition: (feedType, position) => {
    const cache = new Map(get().cache)
    const existing = cache.get(feedType)
    if (existing) {
      cache.set(feedType, { ...existing, scrollPosition: position })
      set({ cache })
    }
  },
  
  clearFeed: (feedType) => {
    const cache = new Map(get().cache)
    cache.delete(feedType)
    set({ cache })
  },
  
  clearAllFeeds: () => {
    set({ cache: new Map() })
  }
}))
