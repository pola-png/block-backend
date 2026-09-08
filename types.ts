export interface Post {
  id: string
  postId: string
  userId: string
  username: string
  userAvatar: string
  displayName: string
  isVerified?: boolean
  avatarUrl: string
  content: string
  caption?: string
  // SEO fields (for video/reel/news; image/text can leave empty)
  slug?: string
  seoTitle?: string
  seoDescription?: string
  seoKeywords?: string
  seoCategory?: string
  language?: string
  aiSeoGenerated?: boolean
  isSeoIndexable?: boolean
  postType: 'text' | 'image' | 'video' | 'reel' | 'news' | 'stories'
  title?: string
  thumbnailUrl?: string
  mediaUrls: string[]
  timestamp: Date
  createdAt: string
  likes: number
  comments: number
  reposts: number
  shares: number
  impressions: number
  views: number
  isLiked: boolean
  isReposted: boolean
  isSaved: boolean
  sourcePostId?: string
  sourceUserId?: string
  sourceUsername?: string
  textBgColor?: number
  isBoosted: boolean
  activeBoostId?: string
}

export interface Story {
  id: string
  statusId: string
  userId: string
  username: string
  userAvatar: string
  mediaPath: string
  mediaUrls: string[]
  caption: string
  timestamp: Date
  isViewed: boolean
  mediaCount: number
}

export interface Chat {
  id: string
  chatId: string
  memberIds: string
  partnerId: string
  partnerName: string
  partnerAvatar: string
  lastMessage: string
  timestamp: Date
  unreadCount: number
  isOnline: boolean
  createdAt: string
  partnerIsVerified?: boolean
  partnerIsAdmin?: boolean
}

export interface User {
  $id: string
  name: string
  email: string
}

export interface Profile {
  $id: string
  userId: string
  username: string
  displayName: string
  bio?: string
  avatarUrl?: string
  coverUrl?: string
  category?: string
  followersCount: number
  followingCount: number
  postsCount: number
  isAdmin: boolean
  isBanned: boolean
  joinedAt: Date
}

export interface Message {
  id: string
  chatId: string
  senderId: string
  content: string
  timestamp: Date
  readBy: string
  messageType: 'text' | 'image' | 'video' | 'voice'
  imageUrl?: string
  videoUrl?: string
  voiceUrl?: string
  ciphertext?: string
  nonce?: string
  mac?: string
}

export interface NewsArticle {
  id: string
  newsId: string
  title: string
  subtitle?: string
  content: string
  summary?: string
  category?: string
  tags: string[]
  topic?: string
  thumbnailUrl?: string
  imageUrls: string[]
  language: string
  sourceType: string
  aiGenerated: boolean
  createdAt: Date
}

export interface AppNotification {
  id: string
  userId: string
  title: string
  body: string
  timestamp: Date
  actorName?: string
  actorAvatar?: string
  type?: string
}

export interface Comment {
  id: string
  postId: string
  userId: string
  username: string
  userAvatar: string
  content: string
  voiceUrl?: string
  type: 'text' | 'voice'
  likes: number
  replies: number
  createdAt: string
  parentCommentId?: string
}

export type UploadType = 'standard' | 'video' | 'reel' | 'news'
