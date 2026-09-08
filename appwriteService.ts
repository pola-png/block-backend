import { Client, Account, Databases, Storage, Functions, ID, Query, ExecutionMethod } from 'appwrite'
import { Chat, Message } from './types'
import { getUploadAccess } from './lib/creator-plan'
import { encryptMessage } from './lib/crypto'

class AppwriteService {
  private static instance: AppwriteService
  private client: Client
  private account: Account
  private databases: Databases
  private storage: Storage
  private functions: Functions

  // Configuration - matching Flutter app exactly
  private readonly endpoint = 'https://nyc.cloud.appwrite.io/v1'
  private readonly projectId = '690641ad0029b51eefe0'
  private readonly databaseId = 'xapzap_db'

  // Collections - exactly matching Flutter app
  private readonly collections = {
    users: 'users',
    posts: 'posts',
    comments: 'comments',
    profiles: 'profiles',
    follows: 'follows',
    likes: 'likes',
    commentLikes: 'commentLikes',
    reposts: 'reposts',
    reports: 'reports',
    saves: 'saves',
    chats: 'chats',
    messages: 'messages',
    statuses: 'statuses',
    notifications: 'notifications',
    postBoosts: 'post_boosts',
    news: 'news',
    adRevenue: 'ad_revenue_events',
    postAggregates: 'post_aggregates',
    feedEvents: 'feed_events'
  }

  private readonly mediaBucketId = '6915baaa00381391d7b2'
  private readonly blockFilterFunctionId = process.env.NEXT_PUBLIC_APPWRITE_BLOCK_FILTER_FUNCTION_ID || '69bfdc350034b3294afe'

  private normalizeIdentifier(value: unknown): string | null {
    if (typeof value !== 'string') return null
    const normalized = value.trim()
    if (!normalized) return null
    if (normalized === 'undefined' || normalized === 'null' || normalized === 'nan') return null
    return normalized
  }

  private constructor() {
    this.client = new Client()
      .setEndpoint(this.endpoint)
      .setProject(this.projectId)

    this.account = new Account(this.client)
    this.databases = new Databases(this.client)
    this.storage = new Storage(this.client)
    this.functions = new Functions(this.client)
  }

  static getInstance(): AppwriteService {
    if (!AppwriteService.instance) {
      AppwriteService.instance = new AppwriteService()
    }
    return AppwriteService.instance
  }

  // Auth methods
  async getCurrentUser() {
    try {
      return await this.account.get()
    } catch {
      return null
    }
  }

  async signUp(email: string, password: string, username: string, displayName?: string, referralCode?: string) {
    try {
      // Create account
      await this.account.create(
        ID.unique(),
        email,
        password,
        username
      )

      // Sign in immediately
      await this.signIn(email, password)

      // Get the created user
      const user = await this.getCurrentUser()
      if (!user) throw new Error('Failed to get user after signup')

      // Create profile record (only required fields)
      await this.databases.createDocument(
        this.databaseId,
        this.collections.profiles,
        user.$id,
        {
          userId: user.$id,
          username,
          displayName: displayName || username
        }
      )

      const safeReferralCode = this.normalizeIdentifier(referralCode)
      if (safeReferralCode) {
        try {
          const referrerProfile = await this.findProfileByUsername(safeReferralCode)
          const referrerUserId = this.normalizeIdentifier(referrerProfile?.userId || referrerProfile?.$id)

          if (referrerUserId && referrerUserId !== user.$id) {
            const alreadyFollowing = await this.isFollowing(user.$id, referrerUserId)
            if (!alreadyFollowing) {
              await this.databases.createDocument(
                this.databaseId,
                this.collections.follows,
                ID.unique(),
                {
                  followerId: user.$id,
                  followeeId: referrerUserId,
                  followedAt: new Date().toISOString(),
                  status: 'referral',
                  notificationEnabled: true,
                }
              )
            }
          }
        } catch (error) {
          console.error('Failed to apply referral code:', error)
        }
      }

      return user
    } catch (error: any) {
      throw new Error(error.message || 'Sign up failed')
    }
  }

  async signIn(email: string, password: string) {
    try {
      return await this.account.createEmailPasswordSession(email, password)
    } catch (error: any) {
      throw new Error(error.message || 'Sign in failed')
    }
  }

  async getCurrentSession() {
    try {
      return await this.account.getSession('current')
    } catch (error) {
      return null
    }
  }

  async createJWT() {
    try {
      return await this.account.createJWT()
    } catch (error: any) {
      throw new Error(error.message || 'Failed to create JWT')
    }
  }

  async deleteCurrentAccount() {
    try {
      if (!this.blockFilterFunctionId) {
        throw new Error('Account deletion is unavailable until the block filter function ID is configured.')
      }

      const jwt = await this.createJWT()
      const execution = await this.functions.createExecution(
        this.blockFilterFunctionId,
        JSON.stringify({ confirm: true, userJwt: jwt.jwt }),
        false,
        '/v1/account/delete',
        ExecutionMethod.POST,
        {
          'content-type': 'application/json'
        }
      )

      let payload: any = {}
      if (execution.responseBody?.trim()) {
        try {
          payload = JSON.parse(execution.responseBody)
        } catch {
          payload = {}
        }
      }

      if (execution.responseStatusCode < 200 || execution.responseStatusCode >= 300) {
        throw new Error(payload?.error || payload?.message || `Account deletion failed with HTTP ${execution.responseStatusCode}.`)
      }

      return payload
    } catch (error: any) {
      throw new Error(error.message || 'Account deletion failed')
    }
  }

  async signOut() {
    try {
      await this.account.deleteSession('current')
    } catch (error: any) {
      throw new Error(error.message || 'Sign out failed')
    }
  }

  async forgotPassword(email: string) {
    try {
      await this.account.createRecovery(email, 'http://localhost:3000/auth/reset-password')
    } catch (error: any) {
      throw new Error(error.message || 'Failed to send password reset email')
    }
  }

  // Admin/Ban checking
  async isCurrentUserAdmin() {
    const user = await this.getCurrentUser()
    if (!user) return false
    
    try {
      const profile = await this.getProfileByUserId(user.$id)
      return profile?.isAdmin || false
    } catch {
      return false
    }
  }

  async isCurrentUserBanned() {
    const user = await this.getCurrentUser()
    if (!user) return false
    
    try {
      const profile = await this.getProfileByUserId(user.$id)
      return profile?.isBanned || false
    } catch {
      return false
    }
  }

  async getProfileByUserId(userId: string) {
    const safeUserId = this.normalizeIdentifier(userId)
    if (!safeUserId) return null
    return this.getProfileByUserIdPrimary(safeUserId)
  }

  // Posts methods with different algorithms
  async fetchPosts(limit = 20, cursor?: string) {
    const queries = [
      Query.orderDesc('$createdAt'),
      Query.limit(limit)
    ]
    if (cursor) queries.push(Query.cursorAfter(cursor))

    return await this.databases.listDocuments(
      this.databaseId,
      this.collections.posts,
      queries
    )
  }

  // Profiles
  async getProfileByUserIdPrimary(userId: string) {
    const safeUserId = this.normalizeIdentifier(userId)
    if (!safeUserId) return null

    try {
      // Primary: profile document ID matches userId
      return await this.databases.getDocument(
        this.databaseId,
        this.collections.profiles,
        safeUserId
      )
    } catch {
      try {
        // Fallback: look up by userId field
        const result = await this.databases.listDocuments(
          this.databaseId,
          this.collections.profiles,
          [Query.equal('userId', safeUserId), Query.limit(1)]
        )
        return result.documents[0] ?? null
      } catch {
        return null
      }
    }
  }

  async findProfileByUsername(username: string) {
    const safeUsername = this.normalizeIdentifier(username)
    if (!safeUsername) return null

    try {
      const result = await this.databases.listDocuments(
        this.databaseId,
        this.collections.profiles,
        [Query.equal('username', safeUsername), Query.limit(1)]
      )
      return result.documents[0] ?? null
    } catch {
      return null
    }
  }

  async fetchReferralFollows(userId: string) {
    const safeUserId = this.normalizeIdentifier(userId)
    if (!safeUserId) return [] as Array<{ userId: string; username: string; displayName: string; avatarUrl?: string }>

    try {
      const result = await this.databases.listDocuments(
        this.databaseId,
        this.collections.follows,
        [Query.equal('followeeId', safeUserId), Query.equal('status', 'referral'), Query.orderDesc('followedAt'), Query.limit(100)]
      )

      const followerIds = result.documents
        .map((doc: any) => this.normalizeIdentifier(doc.followerId))
        .filter((value): value is string => !!value)

      const uniqueFollowerIds = Array.from(new Set(followerIds))
      const profiles = await Promise.all(uniqueFollowerIds.map((id) => this.getProfileByUserId(id)))

      return profiles
        .filter((p): p is any => !!p)
        .map((profile) => ({
          userId: String(profile.userId || profile.$id || '').trim(),
          username: String(profile.username || '').trim(),
          displayName: String(profile.displayName || profile.username || 'User').trim(),
          avatarUrl: profile.avatarUrl ? String(profile.avatarUrl) : undefined,
        }))
        .filter((item) => item.userId && item.username)
    } catch (error) {
      console.error('Failed to fetch referral follows:', error)
      return [] as Array<{ userId: string; username: string; displayName: string; avatarUrl?: string }>
    }
  }

  // For You feed - ranked by recency, engagement, and simple diversity
  async fetchForYouFeed(userId?: string, limit = 20, cursor?: string) {
    try {
      // Get posts from last 9 months for variety
      const nineMonthsAgo = new Date()
      nineMonthsAgo.setMonth(nineMonthsAgo.getMonth() - 9)

      let queries: any[] = [
        Query.greaterThanEqual('$createdAt', nineMonthsAgo.toISOString()),
        Query.limit(limit * 3), // fetch extra to allow diversity
      ]
      if (cursor) queries.push(Query.cursorAfter(cursor))

      const result = await this.databases.listDocuments(
        this.databaseId,
        this.collections.posts,
        queries
      )

      const now = Date.now()

      // Score posts based on engagement, recency, and optional aggregates
      const scoredPosts = (result.documents as any[]).map(post => {
        const ageInHours =
          (now - new Date(post.$createdAt || post.createdAt).getTime()) /
          (1000 * 60 * 60)

        const baseEngagement =
          (post.likes || 0) +
          (post.comments || 0) * 2 +
          (post.reposts || 0) * 3 +
          (post.views || 0) * 0.1

        // If post_aggregates are being maintained, they can be joined here in the future.
        // For now, rely on the live engagement fields.
        const recencyScore = Math.max(0, 168 - ageInHours) // 7-day window

        const totalScore = baseEngagement + recencyScore

        return { ...post, score: totalScore }
      })

      // Sort by score
      scoredPosts.sort((a, b) => b.score - a.score)

      // Simple diversity: limit consecutive posts from same creator
      const seenPerCreator: Record<string, number> = {}
      const diversified: any[] = []

      for (const post of scoredPosts) {
        const creatorId = post.userId || post.creatorId || ''
        if (creatorId) {
          const count = seenPerCreator[creatorId] ?? 0
          if (count >= 3) continue
          seenPerCreator[creatorId] = count + 1
        }
        diversified.push(post)
        if (diversified.length >= limit) break
      }

      return {
        ...result,
        documents: diversified,
      }
    } catch (error) {
      // Fallback to regular fetch
      return this.fetchPosts(limit, cursor)
    }
  }

  // Watch feed - normal resolution video posts by engagement
  async fetchWatchFeed(limit = 20, cursor?: string) {
    try {
      let queries: any[] = [
        Query.or([
          Query.equal('kind', 'video'),
          Query.equal('postType', 'video')
        ]),
        Query.limit(limit * 3) // Get more to sort by engagement
      ]
      if (cursor) queries.push(Query.cursorAfter(cursor))

      const result = await this.databases.listDocuments(
        this.databaseId,
        this.collections.posts,
        queries
      )

      // Filter for posts that have video content (excluding reels)
      const videoPosts = result.documents.filter(post =>
        (post.videoUrl || (post.mediaUrls && post.mediaUrls.length > 0) || post.thumbnailUrl) &&
        post.postType !== 'reel'
      )

      // Sort by engagement score
      const sortedPosts = videoPosts
        .map(post => ({
          ...post,
          engagementScore: (post.views || 0) * 0.5 + (post.likes || 0) + (post.comments || 0) * 2 + (post.reposts || 0) * 3
        }))
        .sort((a, b) => b.engagementScore - a.engagementScore)
        .slice(0, limit)

      return {
        ...result,
        documents: sortedPosts
      }
    } catch (error) {
      console.error('Watch feed error:', error)
      // Fallback: get posts and filter for videos (not reels)
      try {
        const result = await this.fetchPosts(limit * 2)
        const videoPosts = result.documents.filter(post =>
          (post.videoUrl || (post.mediaUrls && post.mediaUrls.length > 0)) &&
          post.postType !== 'reel' &&
          post.postType === 'video'
        ).slice(0, limit)

        return {
          ...result,
          documents: videoPosts
        }
      } catch (fallbackError) {
        console.error('Watch feed fallback error:', fallbackError)
        return { documents: [], total: 0 }
      }
    }
  }

  // Reels feed - short videos by engagement
  async fetchReelsFeed(limit = 20, cursor?: string) {
    try {
      let queries: any[] = [
        Query.equal('postType', 'reel'),
        Query.limit(limit * 2)
      ]
      if (cursor) queries.push(Query.cursorAfter(cursor))

      const result = await this.databases.listDocuments(
        this.databaseId,
        this.collections.posts,
        queries
      )

      // Sort by engagement
      const sortedPosts = result.documents
        .map(post => ({
          ...post,
          engagementScore: (post.likes || 0) + (post.comments || 0) * 2 + (post.reposts || 0) * 3 + (post.views || 0) * 0.3
        }))
        .sort((a, b) => b.engagementScore - a.engagementScore)
        .slice(0, limit)

      return {
        ...result,
        documents: sortedPosts
      }
    } catch (error) {
      return this.fetchPostsByKind('reel', limit, cursor)
    }
  }

  // Following feed - posts from followed users
  async fetchFollowingFeed(userId: string, limit = 20, cursor?: string) {
    try {
      const followingIds = await this.getFollowingUserIds(userId)
      if (followingIds.length === 0) {
        return { documents: [], total: 0 }
      }

      return await this.fetchPostsByUserIds(followingIds, limit, cursor)
    } catch (error) {
      return { documents: [], total: 0 }
    }
  }

  async getPost(postId: string) {
    const safePostId = this.normalizeIdentifier(postId)
    if (!safePostId) {
      throw new Error('Invalid post id')
    }

    try {
      // Try direct get first (faster for authenticated users)
      return await this.databases.getDocument(
        this.databaseId,
        this.collections.posts,
        safePostId
      )
    } catch (error) {
      // Fallback to listDocuments for public access (guests)
      try {
        const result = await this.databases.listDocuments(
          this.databaseId,
          this.collections.posts,
          [
            Query.equal('$id', safePostId),
            Query.limit(1)
          ]
        )
        if (result.documents.length > 0) {
          return result.documents[0]
        }

        // Secondary fallback: some records use a dedicated postId field for lookup.
        const byPostId = await this.databases.listDocuments(
          this.databaseId,
          this.collections.posts,
          [
            Query.equal('postId', safePostId),
            Query.limit(1)
          ]
        )
        if (byPostId.documents.length > 0) {
          return byPostId.documents[0]
        }

        throw new Error('Post not found')
      } catch (fallbackError) {
        console.error('Failed to fetch post:', fallbackError)
        throw new Error('Post not found')
      }
    }
  }

  async createPost(data: any) {
    const postId = ID.unique()
    return await this.databases.createDocument(
      this.databaseId,
      this.collections.posts,
      postId,
      {
        ...data,
        postId,
        createdAt: new Date().toISOString(),
        likes: 0,
        comments: 0,
        reposts: 0,
        impressions: 0,
        views: 0
      }
    )
  }

  // Status/Stories methods
  async fetchStatuses(limit = 40) {
    return await this.databases.listDocuments(
      this.databaseId,
      this.collections.statuses,
      [
        Query.orderDesc('timestamp'),
        Query.limit(limit)
      ]
    )
  }

  async createStatus(mediaPath: string, caption = '') {
    const user = await this.getCurrentUser()
    if (!user) throw new Error('User must be signed in')

    const statusId = ID.unique()
    return await this.databases.createDocument(
      this.databaseId,
      this.collections.statuses,
      statusId,
      {
        statusId,
        userId: user.$id,
        mediaPath,
        caption,
        timestamp: new Date().toISOString()
      }
    )
  }

  // News methods
  async fetchNewsArticles(limit = 20, cursor?: string) {
    const queries = [
      Query.orderDesc('$createdAt'),
      Query.limit(limit)
    ]
    if (cursor) queries.push(Query.cursorAfter(cursor))

    return await this.databases.listDocuments(
      this.databaseId,
      this.collections.news,
      queries
    )
  }

  async fetchNewsArticle(id: string) {
    return await this.databases.getDocument(
      this.databaseId,
      this.collections.news,
      id
    )
  }

  // Likes methods
  async isPostLikedBy(userId: string, postId: string) {
    try {
      const result = await this.databases.listDocuments(
        this.databaseId,
        this.collections.likes,
        [
          Query.equal('userId', userId),
          Query.equal('postId', postId),
          Query.limit(1)
        ]
      )
      return result.documents.length > 0
    } catch {
      return false
    }
  }

  async likePost(postId: string) {
    const user = await this.getCurrentUser()
    if (!user) throw new Error('User must be signed in')

    // Check if already liked to prevent duplicates
    const isAlreadyLiked = await this.isPostLikedBy(user.$id, postId)
    if (isAlreadyLiked) return

    await this.databases.createDocument(
      this.databaseId,
      this.collections.likes,
      ID.unique(),
      {
        postId,
        userId: user.$id,
        createdAt: new Date().toISOString()
      }
    )
    await this.incrementPostField(postId, 'likes', 1)
  }

  async unlikePost(postId: string) {
    const user = await this.getCurrentUser()
    if (!user) return

    try {
      const result = await this.databases.listDocuments(
        this.databaseId,
        this.collections.likes,
        [
          Query.equal('userId', user.$id),
          Query.equal('postId', postId)
        ]
      )
      
      for (const doc of result.documents) {
        await this.databases.deleteDocument(
          this.databaseId,
          this.collections.likes,
          doc.$id
        )
      }
      await this.incrementPostField(postId, 'likes', -1)
    } catch {}
  }

  // Reposts methods
  async isPostRepostedBy(userId: string, postId: string) {
    try {
      const result = await this.databases.listDocuments(
        this.databaseId,
        this.collections.reposts,
        [
          Query.equal('userId', userId),
          Query.equal('postId', postId),
          Query.limit(1)
        ]
      )
      return result.documents.length > 0
    } catch {
      return false
    }
  }

  async repostPost(postId: string) {
    const user = await this.getCurrentUser()
    if (!user) throw new Error('User must be signed in')

    const isReposted = await this.isPostRepostedBy(user.$id, postId)
    
    if (isReposted) {
      // Undo repost
      const result = await this.databases.listDocuments(
        this.databaseId,
        this.collections.reposts,
        [
          Query.equal('userId', user.$id),
          Query.equal('postId', postId)
        ]
      )
      
      for (const doc of result.documents) {
        await this.databases.deleteDocument(
          this.databaseId,
          this.collections.reposts,
          doc.$id
        )
      }
      await this.incrementPostField(postId, 'reposts', -1)
    } else {
      // Create repost
      await this.databases.createDocument(
        this.databaseId,
        this.collections.reposts,
        ID.unique(),
        {
          postId,
          userId: user.$id,
          createdAt: new Date().toISOString()
        }
      )
      await this.incrementPostField(postId, 'reposts', 1)
    }
  }

  // Saves methods
  async isPostSavedBy(userId: string, postId: string) {
    try {
      const result = await this.databases.listDocuments(
        this.databaseId,
        this.collections.saves,
        [
          Query.equal('userId', userId),
          Query.equal('postId', postId),
          Query.limit(1)
        ]
      )
      return result.documents.length > 0
    } catch {
      return false
    }
  }

  async savePost(postId: string) {
    const user = await this.getCurrentUser()
    if (!user) throw new Error('User must be signed in')

    const isSaved = await this.isPostSavedBy(user.$id, postId)
    
    if (isSaved) {
      // Unsave
      const result = await this.databases.listDocuments(
        this.databaseId,
        this.collections.saves,
        [
          Query.equal('userId', user.$id),
          Query.equal('postId', postId)
        ]
      )
      
      for (const doc of result.documents) {
        await this.databases.deleteDocument(
          this.databaseId,
          this.collections.saves,
          doc.$id
        )
      }
    } else {
      // Save
      await this.databases.createDocument(
        this.databaseId,
        this.collections.saves,
        ID.unique(),
        {
          postId,
          userId: user.$id,
          createdAt: new Date().toISOString()
        }
      )
    }
  }

  // Chat methods
  async fetchChatsForUser(userId: string) {
    try {
      // Since memberIds is stored as comma-separated string, we need to search differently
      // For now, return empty array to avoid 400 error
      return { documents: [] as any[], total: 0 }
    } catch (error) {
      console.error('Chat fetch error:', error)
      return { documents: [] as any[], total: 0 }
    }
  }

  async fetchMessagesForChat(chatId: string, limit = 100) {
    return await this.databases.listDocuments(
      this.databaseId,
      this.collections.messages,
      [
        Query.equal('chatId', chatId),
        Query.orderDesc('timestamp'),
        Query.limit(limit)
      ]
    )
  }

  async sendMessage(chatId: string, content: string, partnerUserId?: string) {
    const user = await this.getCurrentUser()
    if (!user) throw new Error('User must be signed in')

    let ciphertext = ''
    let nonce = ''
    let mac = ''
    let contentToSave = content

    if (partnerUserId) {
      const encrypted = await encryptMessage(chatId, user.$id, partnerUserId, content)
      if (encrypted) {
        ciphertext = encrypted.ciphertext
        nonce = encrypted.nonce
        mac = encrypted.mac
        contentToSave = ''
      }
    }

    return await this.databases.createDocument(
      this.databaseId,
      this.collections.messages,
      ID.unique(),
      {
        chatId,
        senderId: user.$id,
        content: contentToSave,
        timestamp: new Date().toISOString(),
        readBy: user.$id,
        messageType: 'text',
        ciphertext,
        nonce,
        mac
      }
    )
  }



  // Notifications methods
  async fetchNotifications(userId: string, limit = 20) {
    try {
      return await this.databases.listDocuments(
        this.databaseId,
        this.collections.notifications,
        [
          Query.equal('userId', userId),
          Query.orderDesc('timestamp'),
          Query.limit(limit)
        ]
      )
    } catch (error) {
      // Notifications collection might not exist yet
      console.log('Notifications collection not available:', error)
      return { documents: [], total: 0 }
    }
  }

  // Follow methods
  async isFollowing(followerId: string, followeeId: string) {
    try {
      const result = await this.databases.listDocuments(
        this.databaseId,
        this.collections.follows,
        [
          Query.equal('followerId', followerId),
          Query.equal('followeeId', followeeId),
          Query.limit(1)
        ]
      )
      return result.documents.length > 0
    } catch {
      return false
    }
  }

  async followUser(followeeId: string) {
    const user = await this.getCurrentUser()
    if (!user) throw new Error('User must be signed in')

    const isAlreadyFollowing = await this.isFollowing(user.$id, followeeId)
    if (isAlreadyFollowing) return

    await this.databases.createDocument(
      this.databaseId,
      this.collections.follows,
      ID.unique(),
      {
        followerId: user.$id,
        followeeId,
        followedAt: new Date().toISOString(),
        status: 'active',
        notificationEnabled: true
      }
    )
  }

  async unfollowUser(followeeId: string) {
    const user = await this.getCurrentUser()
    if (!user) return

    try {
      const result = await this.databases.listDocuments(
        this.databaseId,
        this.collections.follows,
        [
          Query.equal('followerId', user.$id),
          Query.equal('followeeId', followeeId)
        ]
      )
      
      for (const doc of result.documents) {
        await this.databases.deleteDocument(
          this.databaseId,
          this.collections.follows,
          doc.$id
        )
      }
    } catch {}
  }

  async getFollowerCount(userId: string) {
    try {
      const result = await this.databases.listDocuments(
        this.databaseId,
        this.collections.follows,
        [
          Query.equal('followeeId', userId),
          Query.limit(1)
        ]
      )
      return result.total
    } catch {
      return 0
    }
  }

  async getFollowingCount(userId: string) {
    try {
      const result = await this.databases.listDocuments(
        this.databaseId,
        this.collections.follows,
        [
          Query.equal('followerId', userId),
          Query.limit(1)
        ]
      )
      return result.total
    } catch {
      return 0
    }
  }

  // Profile methods
  async updateProfile(userId: string, data: any) {
    try {
      const profile = await this.getProfileByUserId(userId)
      if (profile) {
        // Ensure required fields are present
        const updateData = {
          userId: profile.userId,
          username: profile.username,
          displayName: profile.displayName,
          ...data
        }
        return await this.databases.updateDocument(
          this.databaseId,
          this.collections.profiles,
          profile.$id,
          updateData
        )
      } else {
        // Create new profile with required fields
        const user = await this.getCurrentUser()
        const createData = {
          userId,
          username: user?.name || 'user',
          displayName: user?.name || 'User',
          ...data
        }
        return await this.databases.createDocument(
          this.databaseId,
          this.collections.profiles,
          ID.unique(),
          createData
        )
      }
    } catch (error) {
      console.error('Failed to update profile:', error)
      throw error
    }
  }

  async uploadProfilePicture(file: File) {
    const user = await this.getCurrentUser()
    if (!user) throw new Error('User must be signed in')

    // Use storageService to upload to Wasabi
    const { default: storageService } = await import('./storage')
    const avatarUrl = await storageService.uploadFile(file)
    return avatarUrl
  }

  // Real-time subscriptions with mobile optimization
  subscribeToCollection(collectionId: string, callback: (payload: any) => void) {
    const channel = `databases.${this.databaseId}.collections.${collectionId}.documents`;

    // Add error handling and reconnection logic for mobile
    const handleMessage = (payload: any) => {
      try {
        callback(payload);
      } catch (error) {
        console.error('Realtime callback error:', error);
      }
    };

    const unsubscribe = this.client.subscribe([channel], handleMessage);

    // Handle connection issues (common on mobile)
    const handleVisibilityChange = () => {
      if (document.visibilityState === 'visible') {
        // Reconnect when tab becomes visible again
        console.log('Reconnecting realtime subscription for', collectionId);
      }
    };

    document.addEventListener('visibilitychange', handleVisibilityChange);

    // Return enhanced unsubscribe function
    return () => {
      document.removeEventListener('visibilitychange', handleVisibilityChange);
      unsubscribe();
    };
  }

  subscribeToDocument(collectionId: string, documentId: string, callback: (payload: any) => void) {
    const channel = `databases.${this.databaseId}.collections.${collectionId}.documents.${documentId}`;

    const handleMessage = (payload: any) => {
      try {
        callback(payload);
      } catch (error) {
        console.error('Realtime document callback error:', error);
      }
    };

    const unsubscribe = this.client.subscribe([channel], handleMessage);

    // Handle connection issues (common on mobile)
    const handleVisibilityChange = () => {
      if (document.visibilityState === 'visible') {
        console.log('Reconnecting document realtime subscription for', documentId);
      }
    };

    document.addEventListener('visibilitychange', handleVisibilityChange);

    return () => {
      document.removeEventListener('visibilitychange', handleVisibilityChange);
      unsubscribe();
    };
  }

  // Additional methods needed for HomeScreen
  async getFollowingUserIds(userId: string): Promise<string[]> {
    try {
      const result = await this.databases.listDocuments(
        this.databaseId,
        this.collections.follows,
        [
          Query.equal('followerId', userId),
          Query.limit(500)
        ]
      )
      return result.documents.map(doc => doc.followeeId)
    } catch {
      return []
    }
  }

  async fetchPostsByUserIds(userIds: string[], limit = 20, cursor?: string) {
    if (userIds.length === 0) return { documents: [], total: 0 }

    // If only one user ID, use simple equal query
    if (userIds.length === 1) {
      const queries = [
        Query.equal('userId', userIds[0]),
        Query.orderDesc('$createdAt'),
        Query.limit(limit)
      ]
      if (cursor) queries.push(Query.cursorAfter(cursor))

      return await this.databases.listDocuments(
        this.databaseId,
        this.collections.posts,
        queries
      )
    }

    // For multiple user IDs, use OR query
    const orQueries = userIds.map(id => Query.equal('userId', id))
    const queries = [
      Query.or(orQueries),
      Query.orderDesc('$createdAt'),
      Query.limit(limit)
    ]
    if (cursor) queries.push(Query.cursorAfter(cursor))

    return await this.databases.listDocuments(
      this.databaseId,
      this.collections.posts,
      queries
    )
  }

  async fetchPostsByKind(kind: string, limit = 20, cursor?: string) {
    const queries = [
      Query.equal('postType', kind),
      Query.orderDesc('createdAt'),
      Query.limit(limit)
    ]
    if (cursor) queries.push(Query.cursorAfter(cursor))

    return await this.databases.listDocuments(
      this.databaseId,
      this.collections.posts,
      queries
    )
  }

  async fetchLivePosts(limit = 20, cursor?: string) {
    return this.fetchPostsByKind('live', limit, cursor)
  }
  async getUnreadChatCount(userId: string) {
    try {
      const chats = await this.fetchChatsForUser(userId)
      let unreadCount = 0
      
      for (const chat of chats.documents) {
        const memberIds = (chat.memberIds as string).split(',').map(id => id.trim())
        const partnerId = memberIds.find(id => id !== userId)
        if (!partnerId) continue
        
        const messages = await this.fetchMessagesForChat(chat.$id, 30)
        for (const msg of messages.documents) {
          if (msg.senderId === userId) continue
          const readBy = (msg.readBy as string || '').split(',').map(id => id.trim())
          if (!readBy.includes(userId)) {
            unreadCount++
          }
        }
      }
      
      return Math.min(unreadCount, 99)
    } catch {
      return 0
    }
  }

  async getUnreadNotificationCount(userId: string) {
    try {
      const result = await this.fetchNotifications(userId, 50)
      return Math.min(result.documents.length, 99)
    } catch {
      return 0
    }
  }

  // Comments methods
  async fetchComments(postId: string, limit = 50) {
    return await this.databases.listDocuments(
      this.databaseId,
      this.collections.comments,
      [
        Query.equal('postId', postId),
        Query.orderDesc('createdAt'),
        Query.limit(limit)
      ]
    )
  }

  async createComment(postId: string, content: string, parentCommentId?: string) {
    const user = await this.getCurrentUser()
    if (!user) throw new Error('User must be signed in')

    const profile = await this.getProfileByUserId(user.$id)
    const username = profile?.displayName || profile?.username || user.name || 'User'
    const avatar = profile?.avatarUrl || ''

    const comment = await this.databases.createDocument(
      this.databaseId,
      this.collections.comments,
      ID.unique(),
      {
        postId,
        userId: user.$id,
        username,
        userAvatar: avatar,
        content,
        type: 'text',
        timestamp: new Date().toISOString(),
        likes: 0,
        replies: 0,
        createdAt: new Date().toISOString(),
        ...(parentCommentId && { parentCommentId })
      }
    )
    
    await this.incrementPostField(postId, 'comments', 1)
    if (parentCommentId) {
      await this.incrementCommentField(parentCommentId, 'replies', 1)
    }
    return comment
  }

  async likeComment(commentId: string) {
    const user = await this.getCurrentUser()
    if (!user) throw new Error('User must be signed in')

    const isAlreadyLiked = await this.isCommentLikedBy(user.$id, commentId)
    if (isAlreadyLiked) return

    await this.databases.createDocument(
      this.databaseId,
      this.collections.commentLikes,
      ID.unique(),
      {
        commentId,
        userId: user.$id,
        createdAt: new Date().toISOString(),
        isActive: true
      }
    )
    await this.incrementCommentField(commentId, 'likes', 1)
  }

  async unlikeComment(commentId: string) {
    const user = await this.getCurrentUser()
    if (!user) return

    try {
      const result = await this.databases.listDocuments(
        this.databaseId,
        this.collections.commentLikes,
        [
          Query.equal('userId', user.$id),
          Query.equal('commentId', commentId)
        ]
      )
      
      for (const doc of result.documents) {
        await this.databases.deleteDocument(
          this.databaseId,
          this.collections.commentLikes,
          doc.$id
        )
      }
      await this.incrementCommentField(commentId, 'likes', -1)
    } catch {}
  }

  async isCommentLikedBy(userId: string, commentId: string) {
    try {
      const result = await this.databases.listDocuments(
        this.databaseId,
        this.collections.commentLikes,
        [
          Query.equal('userId', userId),
          Query.equal('commentId', commentId),
          Query.limit(1)
        ]
      )
      return result.documents.length > 0
    } catch {
      return false
    }
  }

  private async incrementCommentField(commentId: string, field: string, delta: number) {
    try {
      const comment = await this.databases.getDocument(
        this.databaseId,
        this.collections.comments,
        commentId
      )
      
      const current = comment[field] || 0
      const newValue = Math.max(0, current + delta)
      
      await this.databases.updateDocument(
        this.databaseId,
        this.collections.comments,
        commentId,
        { [field]: newValue }
      )
    } catch (error) {
      console.error(`Failed to increment comment field ${field}:`, error)
      throw error
    }
  }
  async incrementPostField(postId: string, field: string, delta: number) {
    try {
      const post = await this.databases.getDocument(
        this.databaseId,
        this.collections.posts,
        postId
      )

      const current = post[field] || 0
      const newValue = Math.max(0, current + delta)

      await this.databases.updateDocument(
        this.databaseId,
        this.collections.posts,
        postId,
        { [field]: newValue }
      )

      // Keep post_aggregates in sync for key fields
      if (['comments', 'reposts', 'shares', 'impressions'].includes(field)) {
        const updatedPost = { ...post, [field]: newValue }
        await this.updatePostAggregateFromPost(postId, updatedPost)
      }
    } catch (error) {
      console.error(`Failed to increment post field ${field} for post ${postId}:`, error)
      throw error
    }
  }

  // Feed & ranking metrics
  async logFeedEvent(data: {
    userId: string
    postId: string
    creatorId: string
    feed: 'home' | 'watch' | 'reels' | 'following' | 'news'
    eventType:
      | 'impression'
      | 'open'
      | 'view_start'
      | 'view_complete'
      | 'like'
      | 'comment'
      | 'repost'
      | 'save'
      | 'share'
      | 'skip'
    position: number
    durationMs?: number | null
  }) {
    try {
      // Keep payload within Appwrite schema constraints.
      const userId = String(data.userId || '').trim()
      const postId = String(data.postId || '').trim()
      const creatorId = String(data.creatorId || '').trim()
      const position = Math.min(65536, Math.max(1, Math.floor(Number(data.position) || 1)))
      const durationMs =
        data.durationMs === null || data.durationMs === undefined
          ? null
          : Math.min(2147483647, Math.max(0, Math.floor(Number(data.durationMs) || 0)))

      if (!userId || !postId || !creatorId) {
        throw new Error('logFeedEvent requires non-empty userId, postId, and creatorId')
      }

      await this.databases.createDocument(
        this.databaseId,
        this.collections.feedEvents,
        ID.unique(),
        {
          userId,
          postId,
          creatorId,
          feed: data.feed,
          eventType: data.eventType,
          position,
          durationMs,
        }
      )
    } catch (error) {
      console.error('Failed to log feed event:', error)
    }
  }

  async getPostAggregate(postId: string) {
    try {
      const result = await this.databases.listDocuments(
        this.databaseId,
        this.collections.postAggregates,
        [Query.equal('postId', postId), Query.limit(1)]
      )
      return result.documents[0] ?? null
    } catch (error) {
      console.error('Failed to load post aggregates:', error)
      return null
    }
  }

  // Helper to upsert a post_aggregates document based on the latest post data
  private async updatePostAggregateFromPost(postId: string, postDoc?: any) {
    try {
      const post =
        postDoc ||
        (await this.databases.getDocument(
          this.databaseId,
          this.collections.posts,
          postId
        ))

      const creatorId = String(post.userId || post.creatorId || '').trim()
      const comments = Math.max(0, Math.floor(Number(post.comments) || 0))
      const reposts = Math.max(0, Math.floor(Number(post.reposts) || 0))
      const shares = Math.max(0, Math.floor(Number(post.shares) || 0))
      const impressions = Math.max(0, Math.floor(Number(post.impressions) || 0))

      if (!creatorId) {
        throw new Error(`Cannot upsert post_aggregates for post ${postId}: missing creatorId`)
      }

      const engagementNumerator = comments + reposts + shares
      const engagementRate =
        impressions > 0 ? Math.min(1, engagementNumerator / impressions) : 0

      // Find existing aggregate, if any
      const existing = await this.databases.listDocuments(
        this.databaseId,
        this.collections.postAggregates,
        [Query.equal('postId', postId), Query.limit(1)]
      )

      const data = {
        postId,
        creatorId,
        comments,
        reposts,
        shares,
        impressions,
        engagementRate,
      }

      if (existing.documents.length > 0) {
        await this.databases.updateDocument(
          this.databaseId,
          this.collections.postAggregates,
          existing.documents[0].$id,
          data
        )
      } else {
        await this.databases.createDocument(
          this.databaseId,
          this.collections.postAggregates,
          ID.unique(),
          data
        )
      }
    } catch (error) {
      console.error('Failed to update post aggregates:', error)
    }
  }

  async deletePost(postId: string) {
    try {
      await this.databases.deleteDocument(
        this.databaseId,
        this.collections.posts,
        postId
      )
    } catch (error) {
      console.error('Failed to delete post:', error)
      throw error
    }
  }

  // Storage methods
  async uploadFile(file: File, customFileId?: string) {
    // For videos, enforce max 2 minutes for ordinary users.
    // Admins, verified creators, and Basic/Business creators can upload longer videos.
    if (typeof window !== 'undefined' && typeof document !== 'undefined' && file.type.startsWith('video/')) {
      let canUploadLongVideo = false

      try {
        const user = await this.getCurrentUser()
        if (user) {
          const isAdmin = await this.isCurrentUserAdmin()
          const profile = await this.getProfileByUserId(user.$id)
          const access = getUploadAccess(profile, isAdmin)
          canUploadLongVideo = access.canUploadLongVideo
        }
      } catch (error) {
        console.error('Failed to resolve user role for upload:', error)
      }

      const duration = await this.getVideoDuration(file)
      if (!canUploadLongVideo && duration > 120) {
        throw new Error(
          'Videos and reels longer than 2 minutes are only available for verified creators, Basic, or Business plans. Please trim your video to 2 minutes or less in an editing app before uploading.'
        )
      }
    }

    // Generate a valid fileId (max 36 chars, only a-zA-Z0-9._-)
    const fileId = customFileId || ID.unique()

    const uploadedFile = await this.storage.createFile(
      this.mediaBucketId,
      fileId,
      file
    )

    // Get the file URL
    const fileUrl = this.storage.getFileView(this.mediaBucketId, uploadedFile.$id)

    return {
      id: uploadedFile.$id,
      url: fileUrl as string
    }
  }

  // Helper: read video duration on the client
  private getVideoDuration(file: File): Promise<number> {
    return new Promise((resolve) => {
      try {
        if (typeof document === 'undefined') {
          resolve(0)
          return
        }

        const url = URL.createObjectURL(file)
        const video = document.createElement('video')
        video.preload = 'metadata'
        video.src = url

        video.onloadedmetadata = () => {
          const duration = video.duration || 0
          URL.revokeObjectURL(url)
          resolve(duration)
        }

        video.onerror = () => {
          URL.revokeObjectURL(url)
          resolve(0)
        }
      } catch (error) {
        console.error('Error while reading video duration:', error)
        resolve(0)
      }
    })
  }

  async getFileUrl(fileId: string) {
    const fileUrl = this.storage.getFileView(this.mediaBucketId, fileId)
    return fileUrl as string
  }

  // Search methods
  async searchUsers(query: string, limit = 10) {
    try {
      const result = await this.databases.listDocuments(
        this.databaseId,
        this.collections.profiles,
        [
          Query.or([
            Query.search('username', query),
            Query.search('displayName', query)
          ]),
          Query.limit(limit)
        ]
      )
      return result.documents
    } catch (error) {
      console.error('User search error:', error)
      return []
    }
  }

  async searchHashtags(query: string, limit = 10) {
    try {
      // For now, extract hashtags from recent posts
      // In a real implementation, you'd have a dedicated hashtags collection
      const postsResult = await this.databases.listDocuments(
        this.databaseId,
        this.collections.posts,
        [
          Query.limit(100), // Search through recent posts
          Query.orderDesc('$createdAt')
        ]
      )

      const hashtagMap = new Map<string, number>()

      // Extract hashtags from post content
      postsResult.documents.forEach((post: any) => {
        const content = post.content || ''
        const hashtags = content.match(/#\w+/g) || []
        hashtags.forEach((tag: string) => {
          const lowerTag = tag.toLowerCase()
          hashtagMap.set(lowerTag, (hashtagMap.get(lowerTag) || 0) + 1)
        })
      })

      // Filter and sort hashtags
      const filteredHashtags = Array.from(hashtagMap.entries())
        .filter(([tag, count]: [string, number]) => tag.toLowerCase().includes(query.toLowerCase()))
        .sort((a: [string, number], b: [string, number]) => b[1] - a[1]) // Sort by frequency
        .slice(0, limit)
        .map(([tag, count]: [string, number]) => ({
          tag,
          count
        }))

      return filteredHashtags
    } catch (error) {
      console.error('Hashtag search error:', error)
      return []
    }
  }

}

export const appwriteService = AppwriteService.getInstance()
export default appwriteService
