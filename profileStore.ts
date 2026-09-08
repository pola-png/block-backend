import { create } from 'zustand'
import { Post } from './types'

type ProfileData = {
  displayName?: string
  username?: string
  isVerified?: boolean
  bio?: string
  category?: string
  avatarUrl?: string
  coverUrl?: string
  website?: string
  joinedAt?: string
}

type ProfileCache = {
  userId: string
  profile: ProfileData
  posts: Post[]
  stats: {
    posts: number
    followers: number
    following: number
  }
  activeTab: 'posts' | 'videos' | 'news' | 'all'
  timestamp: number
}

type ProfileStore = {
  cache: Map<string, ProfileCache>
  setProfile: (userId: string, data: Omit<ProfileCache, 'timestamp'>) => void
  getProfile: (userId: string) => ProfileCache | null
  updateActiveTab: (userId: string, tab: 'posts' | 'videos' | 'news' | 'all') => void
  clearProfile: (userId: string) => void
}

export const useProfileStore = create<ProfileStore>((set, get) => ({
  cache: new Map(),
  
  setProfile: (userId, data) => {
    const cache = new Map(get().cache)
    cache.set(userId, { ...data, timestamp: Date.now() })
    set({ cache })
  },
  
  getProfile: (userId) => {
    const cached = get().cache.get(userId)
    if (!cached) return null
    
    // Cache valid for 5 minutes
    if (Date.now() - cached.timestamp > 5 * 60 * 1000) {
      return null
    }
    
    return cached
  },
  
  updateActiveTab: (userId, tab) => {
    const cache = new Map(get().cache)
    const existing = cache.get(userId)
    if (existing) {
      cache.set(userId, { ...existing, activeTab: tab, timestamp: Date.now() })
      set({ cache })
    }
  },
  
  clearProfile: (userId) => {
    const cache = new Map(get().cache)
    cache.delete(userId)
    set({ cache })
  }
}))
