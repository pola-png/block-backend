// Simple in-memory cache for feed data
class FeedCache {
  private cache: Map<string, { data: any[], timestamp: number }> = new Map()
  private profileCache: Map<string, any> = new Map()
  private interactionCache: Map<string, { liked: boolean, saved: boolean, reposted: boolean }> = new Map()
  private readonly TTL = 5 * 60 * 1000 // 5 minutes

  set(key: string, data: any[]) {
    this.cache.set(key, { data, timestamp: Date.now() })
  }

  get(key: string): any[] | null {
    const cached = this.cache.get(key)
    if (!cached) return null
    
    // Return cached data regardless of age - only clear on manual refresh
    return cached.data
  }

  has(key: string): boolean {
    return this.cache.has(key)
  }

  clear(key?: string) {
    if (key) {
      this.cache.delete(key)
    } else {
      this.cache.clear()
    }
  }

  update(key: string, updater: (data: any[]) => any[]) {
    const cached = this.cache.get(key)
    if (cached) {
      cached.data = updater(cached.data)
      cached.timestamp = Date.now()
    }
  }

  // Profile cache
  setProfile(userId: string, profile: any) {
    this.profileCache.set(userId, profile)
  }

  getProfile(userId: string): any | null {
    return this.profileCache.get(userId) || null
  }

  // Interaction cache
  setInteraction(postId: string, userId: string, interaction: { liked: boolean, saved: boolean, reposted: boolean }) {
    this.interactionCache.set(`${postId}_${userId}`, interaction)
  }

  getInteraction(postId: string, userId: string): { liked: boolean, saved: boolean, reposted: boolean } | null {
    return this.interactionCache.get(`${postId}_${userId}`) || null
  }
}

export const feedCache = new FeedCache()
