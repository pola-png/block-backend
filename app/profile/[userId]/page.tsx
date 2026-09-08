'use client'

import { Fragment, useState, useEffect } from 'react'
import { useParams, useRouter } from 'next/navigation'
import { Calendar, MessageCircle, UserPlus, UserMinus, Share, Settings, BarChart3, DollarSign, Menu, Bookmark, LogOut, FileText, Gift, ShieldAlert, Trash2 } from 'lucide-react'
import { PostCard } from '../../../PostCard'
import { Post } from '../../../types'
import appwriteService from '../../../appwriteService'
import { useProfileStore } from '../../../profileStore'
import { useAuthStore } from '../../../authStore'
import { VerifiedBadge } from '../../../components/VerifiedBadge'
import { hasVerifiedBadge } from '../../../lib/verification'
import { normalizeWasabiImage } from '../../../lib/wasabi'
import { AdcashBanner300x100 } from '../../../components/AdcashBanner300x100'
import { getUploadProgressByUser, removeUploadProgressItem, UploadProgressItem } from '../../../lib/upload-progress'

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

type TabType = 'posts' | 'videos' | 'news' | 'all'

export default function ProfilePage() {
  const params = useParams()
  const router = useRouter()
  const userId = params.userId as string

  const [profile, setProfile] = useState<ProfileData | null>(null)
  const [posts, setPosts] = useState<Post[]>([])
  const [currentUserId, setCurrentUserId] = useState<string>('')
  const [isFollowing, setIsFollowing] = useState(false)
  const [followLoading, setFollowLoading] = useState(false)
  const [loading, setLoading] = useState(true)
  const [uploadingAvatar, setUploadingAvatar] = useState(false)
  const [uploadingBanner, setUploadingBanner] = useState(false)
  const [showAvatarMenu, setShowAvatarMenu] = useState(false)
  const [showBannerMenu, setShowBannerMenu] = useState(false)
  const [stats, setStats] = useState({
    posts: 0,
    followers: 0,
    following: 0
  })
  const [activeTab, setActiveTab] = useState<TabType>('posts')
  const [uploadProgressItems, setUploadProgressItems] = useState<UploadProgressItem[]>([])
  const profileStore = useProfileStore()
  const authStore = useAuthStore()
  const [shouldLoadCover, setShouldLoadCover] = useState(false)
  const [shouldLoadAvatar, setShouldLoadAvatar] = useState(false)

  useEffect(() => {
    setShouldLoadCover(true)
    setShouldLoadAvatar(true)
  }, [])

  const isCurrentUser = authStore.currentUserId === userId

  const handleSignOut = async () => {
    try {
      await appwriteService.signOut()
      authStore.clearAuth()
      router.push('/')
    } catch (error) {
      console.error('Sign out failed:', error)
    }
  }


  useEffect(() => {
    if (!isCurrentUser) {
      setUploadProgressItems([])
      return
    }

    const loadUploadProgress = () => {
      const items = getUploadProgressByUser(userId).filter((item) => {
        const ageMs = Date.now() - item.updatedAt
        return ageMs <= 1000 * 60 * 60 * 6
      })
      setUploadProgressItems(items)
    }

    loadUploadProgress()
    const intervalId = window.setInterval(loadUploadProgress, 800)
    const onStorage = () => loadUploadProgress()
    window.addEventListener('storage', onStorage)

    return () => {
      window.clearInterval(intervalId)
      window.removeEventListener('storage', onStorage)
    }
  }, [isCurrentUser, userId])

  useEffect(() => {
    const cached = profileStore.getProfile(userId)
    if (cached) {
      setProfile(cached.profile)
      setPosts(cached.posts)
      setStats(cached.stats)
      setActiveTab(cached.activeTab)
      setLoading(false)
    } else {
      loadProfile()
    }
  }, [userId])

  const loadProfile = async () => {
    try {
      setLoading(true)

      // Get current user
      const currentUser = await appwriteService.getCurrentUser()
      const currentUserId = currentUser?.$id || ''
      setCurrentUserId(currentUserId)
      authStore.setCurrentUserId(currentUserId)

      const profileUserId = params.userId as string

      // Get profile data
      const profileData = await appwriteService.getProfileByUserId(profileUserId)
      if (profileData) {
        const isVerified = hasVerifiedBadge(profileData)

        setProfile({
          displayName: profileData.displayName || profileData.username,
          username: profileData.username,
          isVerified,
          bio: profileData.bio,
          category: profileData.category,
          avatarUrl: profileData.avatarUrl,
          coverUrl: profileData.coverUrl,
          website: profileData.website,
          joinedAt: profileData.$createdAt
        })
      }

      // Get posts
      const postsResult = await appwriteService.fetchPostsByUserIds([profileUserId], 50)
      const postsData = await Promise.all(
        postsResult.documents.map(async (doc: any) => {
          const interactions = currentUser ? await Promise.all([
            appwriteService.isPostLikedBy(currentUser.$id, doc.$id),
            appwriteService.isPostSavedBy(currentUser.$id, doc.$id),
            appwriteService.isPostRepostedBy(currentUser.$id, doc.$id)
          ]) : [false, false, false]
          
          return {
            ...doc,
            id: doc.$id,
            postId: doc.$id,
            userId: doc.userId,
            username: doc.username,
            userAvatar: doc.userAvatar,
            content: doc.content,
            timestamp: new Date(doc.$createdAt || doc.createdAt),
            createdAt: doc.$createdAt || doc.createdAt,
            likes: doc.likes || 0,
            comments: doc.comments || 0,
            reposts: doc.reposts || 0,
            impressions: doc.impressions || 0,
            views: doc.views || 0,
            isLiked: interactions[0],
            isReposted: interactions[1],
            isSaved: interactions[2],
            isBoosted: false
          }
        })
      ) as Post[]

      setPosts(postsData)
      setStats({
        posts: postsResult.total,
        followers: await appwriteService.getFollowerCount(profileUserId),
        following: await appwriteService.getFollowingCount(profileUserId)
      })

      // Check follow status if not current user
      if (currentUser && currentUser.$id !== profileUserId) {
        const following = await appwriteService.isFollowing(currentUser.$id, profileUserId)
        setIsFollowing(following)
      }

      // Cache the profile data
      if (profileData) {
        const isVerified = hasVerifiedBadge(profileData)

        profileStore.setProfile(profileUserId, {
          userId: profileUserId,
          profile: {
            displayName: profileData.displayName || profileData.username,
            username: profileData.username,
            isVerified,
            bio: profileData.bio,
            category: profileData.category,
            avatarUrl: profileData.avatarUrl,
            coverUrl: profileData.coverUrl,
            website: profileData.website,
            joinedAt: profileData.$createdAt
          },
          posts: postsData,
          stats: {
            posts: postsResult.total,
            followers: await appwriteService.getFollowerCount(profileUserId),
            following: await appwriteService.getFollowingCount(profileUserId)
          },
          activeTab: 'posts'
        })
      }

    } catch (error) {
      console.error('Failed to load profile:', error)
    } finally {
      setLoading(false)
    }
  }

  const handleFollow = async () => {
    if (!currentUserId || followLoading) return

    const profileUserId = params.userId as string
    const wasFollowing = isFollowing
    const prevFollowers = stats.followers
    
    setFollowLoading(true)
    setIsFollowing(!wasFollowing)
    setStats(prev => ({ ...prev, followers: wasFollowing ? prev.followers - 1 : prev.followers + 1 }))
    
    try {
      if (wasFollowing) {
        await appwriteService.unfollowUser(profileUserId)
      } else {
        await appwriteService.followUser(profileUserId)
      }
    } catch (error) {
      console.error('Failed to toggle follow:', error)
      setIsFollowing(wasFollowing)
      setStats(prev => ({ ...prev, followers: prevFollowers }))
    } finally {
      setFollowLoading(false)
    }
  }

  const handleMessage = () => {
    // TODO: Implement chat functionality
    console.log('Message user:', userId)
  }

  const handleShare = () => {
    if (navigator.share) {
      navigator.share({
        title: `${profile?.displayName || 'User'}'s Profile`,
        url: window.location.href
      })
    } else {
      navigator.clipboard.writeText(window.location.href)
      // TODO: Show toast notification
    }
  }

  const handleAvatarUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file || !currentUserId) return

    setUploadingAvatar(true)
    try {
      // Sanitize filename
      const sanitizedName = file.name.replace(/\s+/g, '_').replace(/[()]/g, '')
      const cleanFileName = `${Date.now()}_${sanitizedName}`
      
      const presignedRes = await fetch('/api/presigned-url', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          fileName: cleanFileName,
          fileType: file.type
        })
      })
      
      if (!presignedRes.ok) throw new Error('Failed to get presigned URL')
      
      const { presignedUrl, url } = await presignedRes.json()
      
      const uploadRes = await fetch(presignedUrl, {
        method: 'PUT',
        body: file,
        headers: { 'Content-Type': file.type }
      })
      
      if (!uploadRes.ok) throw new Error('Upload failed')
      
      await appwriteService.updateProfile(currentUserId, { avatarUrl: url })
      setProfile(prev => prev ? { ...prev, avatarUrl: url } : null)
      setShowAvatarMenu(false)
      profileStore.clearProfile(currentUserId)
    } catch (error) {
      console.error('Failed to upload avatar:', error)
    } finally {
      setUploadingAvatar(false)
    }
  }

  const handleBannerUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file || !currentUserId) return

    setUploadingBanner(true)
    try {
      // Sanitize filename
      const sanitizedName = file.name.replace(/\s+/g, '_').replace(/[()]/g, '')
      const cleanFileName = `${Date.now()}_${sanitizedName}`
      
      const presignedRes = await fetch('/api/presigned-url', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          fileName: cleanFileName,
          fileType: file.type
        })
      })
      
      if (!presignedRes.ok) throw new Error('Failed to get presigned URL')
      
      const { presignedUrl, url } = await presignedRes.json()
      
      const uploadRes = await fetch(presignedUrl, {
        method: 'PUT',
        body: file,
        headers: { 'Content-Type': file.type }
      })
      
      if (!uploadRes.ok) throw new Error('Upload failed')
      
      await appwriteService.updateProfile(currentUserId, { coverUrl: url })
      setProfile(prev => prev ? { ...prev, coverUrl: url } : null)
      setShowBannerMenu(false)
      profileStore.clearProfile(currentUserId)
    } catch (error) {
      console.error('Failed to upload banner:', error)
    } finally {
      setUploadingBanner(false)
    }
  }

  const filteredPosts = posts.filter(post => {
    switch (activeTab) {
      case 'posts':
        return !post.postType || post.postType === 'text' || post.postType === 'image'
      case 'videos':
        return post.postType === 'video' || post.postType === 'reel'
      case 'news':
        return post.postType === 'news'
      case 'all':
      default:
        return true
    }
  })

  if (loading) {
    return (
      <div className="min-h-screen bg-[rgb(var(--bg-primary))] flex items-center justify-center">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-white"></div>
      </div>
    )
  }

  if (!profile) {
    return (
      <div className="min-h-screen bg-[rgb(var(--bg-primary))] flex items-center justify-center">
        <div className="text-white text-center">
          <p className="text-xl mb-4">Profile not found</p>
          <button
            onClick={() => router.back()}
            className="px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600"
          >
            Go Back
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-[rgb(var(--bg-primary))]">
      {/* Cover Photo */}
      <div className="relative h-48 bg-gradient-to-br from-blue-600 to-purple-700 dark:from-[#0f172a] dark:to-[#1e293b] group">
        {profile.coverUrl && shouldLoadCover && (
          <img
            src={normalizeWasabiImage(profile.coverUrl) || profile.coverUrl}
            alt="Cover"
            className="w-full h-full object-cover"
          />
        )}
        {isCurrentUser && (
          <>
            <button
              onClick={() => setShowBannerMenu(!showBannerMenu)}
              className="absolute top-4 right-4 w-10 h-10 bg-black/50 backdrop-blur-sm rounded-full flex items-center justify-center text-white hover:bg-black/70 transition-all opacity-0 group-hover:opacity-100"
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/>
                <circle cx="12" cy="13" r="4"/>
              </svg>
            </button>
            {showBannerMenu && (
              <>
                <div className="fixed inset-0 z-40" onClick={() => setShowBannerMenu(false)} />
                <div className="absolute top-16 right-4 bg-gray-900 border border-gray-800 rounded-xl shadow-2xl z-50 min-w-[160px]">
                  {profile.coverUrl && (
                    <button
                      onClick={() => {
                        window.open(profile.coverUrl, '_blank')
                        setShowBannerMenu(false)
                      }}
                      className="w-full px-4 py-3 text-left text-sm text-white hover:bg-gray-800 transition-colors rounded-t-xl"
                    >
                      View Banner
                    </button>
                  )}
                  <label className="w-full px-4 py-3 text-left text-sm text-white hover:bg-gray-800 transition-colors cursor-pointer block rounded-b-xl">
                    {uploadingBanner ? 'Uploading...' : 'Upload Banner'}
                    <input
                      type="file"
                      accept="image/*"
                      onChange={handleBannerUpload}
                      disabled={uploadingBanner}
                      className="hidden"
                    />
                  </label>
                </div>
              </>
            )}
          </>
        )}

        {/* Avatar */}
        <div className="absolute -bottom-12 left-4">
          <div className="w-24 h-24 rounded-full border-4 border-black bg-gray-800 flex items-center justify-center relative group">
            {profile.avatarUrl && shouldLoadAvatar ? (
              <img
                src={normalizeWasabiImage(profile.avatarUrl) || profile.avatarUrl}
                alt={profile.displayName}
                className="w-full h-full rounded-full object-cover"
              />
            ) : (
              <span className="text-2xl text-white font-bold">
                {(profile.displayName || 'U')[0].toUpperCase()}
              </span>
            )}
            {isCurrentUser && (
              <>
                <button
                  onClick={() => setShowAvatarMenu(!showAvatarMenu)}
                  className="absolute bottom-0 right-0 w-8 h-8 bg-blue-600 rounded-full flex items-center justify-center text-white hover:bg-blue-700 transition-all shadow-lg"
                >
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                    <path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/>
                    <circle cx="12" cy="13" r="4"/>
                  </svg>
                </button>
                {showAvatarMenu && (
                  <>
                    <div className="fixed inset-0 z-40" onClick={() => setShowAvatarMenu(false)} />
                    <div className="absolute top-full left-0 mt-2 bg-gray-900 border border-gray-800 rounded-xl shadow-2xl z-50 min-w-[160px]">
                      {profile.avatarUrl && (
                        <button
                          onClick={() => {
                            window.open(profile.avatarUrl, '_blank')
                            setShowAvatarMenu(false)
                          }}
                          className="w-full px-4 py-3 text-left text-sm text-white hover:bg-gray-800 transition-colors rounded-t-xl"
                        >
                          View Avatar
                        </button>
                      )}
                      <label className="w-full px-4 py-3 text-left text-sm text-white hover:bg-gray-800 transition-colors cursor-pointer block rounded-b-xl">
                        {uploadingAvatar ? 'Uploading...' : 'Upload Avatar'}
                        <input
                          type="file"
                          accept="image/*"
                          onChange={handleAvatarUpload}
                          disabled={uploadingAvatar}
                          className="hidden"
                        />
                      </label>
                    </div>
                  </>
                )}
              </>
            )}
          </div>
        </div>
      </div>


      {/* Main Responsive Grid Wrapper */}
      <div className="flex flex-col lg:flex-row gap-6 max-w-6xl mx-auto px-4 pb-20">

        {/* LEFT: Profile Info & Feed Column */}
        <div className="flex-1 min-w-0">

          {/* Profile info (Visible on both Mobile and Desktop) */}
          <div className="px-0 pt-16 pb-4">
            <div className="mb-1 flex items-center gap-3 flex-wrap">
              <h1 className="text-2xl font-bold text-[rgb(var(--text-primary))] inline-flex items-center gap-1">
                {profile.displayName}
                {profile.isVerified && <VerifiedBadge className="h-5 w-5 align-middle inline-flex" />}
              </h1>
              {isCurrentUser && !profile.isVerified && (
                <button
                  onClick={() => router.push('/premium')}
                  className="px-4 py-1.5 rounded-full bg-blue-500 text-white text-sm font-bold hover:bg-blue-600 transition-colors"
                >
                  Get Verified
                </button>
              )}
            </div>
            <p className="text-[rgb(var(--text-secondary))] text-sm mb-2">
              @{profile.username}{profile.category && ` · ${profile.category}`}
            </p>
            {profile.bio && <p className="text-[rgb(var(--text-primary))] text-sm mb-2">{profile.bio}</p>}
            {profile.joinedAt && (
              <div className="flex items-center text-[rgb(var(--text-secondary))] text-xs mb-3">
                <Calendar className="w-3.5 h-3.5 mr-1" />
                Joined {new Date(profile.joinedAt).toLocaleDateString('en-US', { month: 'long', year: 'numeric' })}
              </div>
            )}
            <div className="flex gap-5 mb-4">
              <div className="text-center">
                <div className="text-lg font-bold text-[rgb(var(--text-primary))]">{stats.posts}</div>
                <div className="text-xs text-[rgb(var(--text-secondary))]">Posts</div>
              </div>
              <div className="text-center">
                <div className="text-lg font-bold text-[rgb(var(--text-primary))]">{stats.followers}</div>
                <div className="text-xs text-[rgb(var(--text-secondary))]">Followers</div>
              </div>
              <div className="text-center">
                <div className="text-lg font-bold text-[rgb(var(--text-primary))]">{stats.following}</div>
                <div className="text-xs text-[rgb(var(--text-secondary))]">Following</div>
              </div>
            </div>
            <div className="flex gap-2 mb-4">
              {isCurrentUser ? (
                <>
                  <button onClick={() => router.push('/profile/edit')} className="flex-1 bg-[rgb(var(--bg-secondary))] border border-[rgb(var(--border-color))] hover:bg-neutral-100 dark:hover:bg-neutral-800 transition-all text-[rgb(var(--text-primary))] py-2.5 px-4 rounded-xl font-semibold flex items-center justify-center gap-2 text-sm shadow-sm">
                    <Settings className="w-4 h-4 text-blue-500" />Edit Profile
                  </button>
                  <button onClick={handleShare} className="bg-[rgb(var(--bg-secondary))] border border-[rgb(var(--border-color))] hover:bg-neutral-100 dark:hover:bg-neutral-800 transition-all text-[rgb(var(--text-primary))] p-2.5 rounded-xl shadow-sm" aria-label="Share"><Share className="w-5 h-5" /></button>
                  <button onClick={() => router.push('/profile/menu')} className="bg-[rgb(var(--bg-secondary))] border border-[rgb(var(--border-color))] hover:bg-neutral-100 dark:hover:bg-neutral-800 transition-all text-[rgb(var(--text-primary))] p-2.5 rounded-xl shadow-sm" aria-label="Menu"><Menu className="w-5 h-5" /></button>
                </>
              ) : (
                <>
                  <button onClick={handleFollow} disabled={followLoading} className={`flex-1 py-2.5 px-4 rounded-xl font-bold flex items-center justify-center gap-2 text-sm transition-all shadow-sm ${isFollowing ? 'bg-[rgb(var(--bg-secondary))] border border-[rgb(var(--border-color))] text-[rgb(var(--text-primary))] hover:bg-neutral-100 dark:hover:bg-neutral-800' : 'bg-blue-500 hover:bg-blue-600 text-white'}`}>
                    {followLoading ? <div className="w-4 h-4 border border-current border-t-transparent rounded-full animate-spin" /> : isFollowing ? <><UserMinus className="w-4 h-4 text-purple-500" />Following</> : <><UserPlus className="w-4 h-4" />Follow</>}
                  </button>
                  <button onClick={handleMessage} className="bg-[rgb(var(--bg-secondary))] border border-[rgb(var(--border-color))] hover:bg-neutral-100 dark:hover:bg-neutral-800 transition-all text-[rgb(var(--text-primary))] p-2.5 rounded-xl shadow-sm" aria-label="Message"><MessageCircle className="w-5 h-5 text-blue-500" /></button>
                  <button onClick={handleShare} className="bg-[rgb(var(--bg-secondary))] border border-[rgb(var(--border-color))] hover:bg-neutral-100 dark:hover:bg-neutral-800 transition-all text-[rgb(var(--text-primary))] p-2.5 rounded-xl shadow-sm" aria-label="Share"><Share className="w-5 h-5 text-green-500" /></button>
                </>
              )}
            </div>
            {isCurrentUser && (
              <div className="bg-[rgb(var(--bg-secondary))] border border-[rgb(var(--border-color))] rounded-2xl p-4 mb-4 shadow-sm">
                <h3 className="text-[rgb(var(--text-primary))] font-extrabold text-sm mb-3">Creator Tools</h3>
                <div className="grid grid-cols-2 gap-3">
                  <button onClick={() => router.push('/dashboard')} className="p-3 rounded-xl bg-[rgb(var(--bg-primary))] border border-[rgb(var(--border-color))]/50 hover:border-blue-500/30 transition-all flex items-center gap-2.5 text-left shadow-sm">
                    <BarChart3 className="w-4.5 h-4.5 text-blue-400 shrink-0" />
                    <div><div className="text-[rgb(var(--text-primary))] text-xs font-bold">Dashboard</div><div className="text-[rgb(var(--text-secondary))] text-[10px] font-medium">Insights</div></div>
                  </button>
                  <button onClick={() => router.push('/monetization')} className="p-3 rounded-xl bg-[rgb(var(--bg-primary))] border border-[rgb(var(--border-color))]/50 hover:border-green-500/30 transition-all flex items-center gap-2.5 text-left shadow-sm">
                    <DollarSign className="w-4.5 h-4.5 text-green-400 shrink-0" />
                    <div><div className="text-[rgb(var(--text-primary))] text-xs font-bold">Monetize</div><div className="text-[rgb(var(--text-secondary))] text-[10px] font-medium">Earnings</div></div>
                  </button>
                </div>
              </div>
            )}
          </div>

          {/* Tabs */}
          <div className="mt-4">
            <div className="flex border-b border-[rgb(var(--border-color))] mb-4 overflow-x-auto scrollbar-hide">
              {(['posts', 'videos', 'news', 'all'] as TabType[]).map((tab) => (
                <button
                  key={tab}
                  onClick={() => { setActiveTab(tab); profileStore.updateActiveTab(userId, tab) }}
                  className={`flex-1 min-w-[70px] py-3 text-center text-sm font-semibold transition-all relative ${
                    activeTab === tab ? 'text-blue-500 font-extrabold' : 'text-gray-400 hover:text-[rgb(var(--text-primary))]'
                  }`}
                >
                  {tab.charAt(0).toUpperCase() + tab.slice(1)}
                  {activeTab === tab && (
                    <div className="absolute bottom-0 left-4 right-4 h-0.5 bg-blue-500 rounded-full animate-fade-in" />
                  )}
                </button>
              ))}
            </div>

            {/* Upload progress */}
            <div className="space-y-3 mb-2">
              {isCurrentUser && uploadProgressItems.map((item) => (
                <div key={`upload-progress-${item.id}`} className="rounded-2xl border border-[rgb(var(--border-color))] bg-[rgb(var(--bg-secondary))] p-4">
                  <div className="mb-2 flex items-center justify-between gap-2">
                    <div className="min-w-0">
                      <p className="truncate text-sm font-semibold text-[rgb(var(--text-primary))]">{item.title || item.content || 'Uploading post...'}</p>
                      <p className="text-xs text-[rgb(var(--text-secondary))]">{item.status === 'completed' ? 'Upload completed' : item.status === 'failed' ? 'Upload failed' : 'Uploading...'}</p>
                    </div>
                    {(item.status === 'completed' || item.status === 'failed') && (
                      <button onClick={() => { removeUploadProgressItem(item.id); setUploadProgressItems((prev) => prev.filter((e) => e.id !== item.id)) }} className="rounded-full border border-[rgb(var(--border-color))] px-3 py-1 text-xs text-[rgb(var(--text-secondary))] hover:text-[rgb(var(--text-primary))]">Dismiss</button>
                    )}
                  </div>
                  <div className="h-2 w-full rounded-full bg-black/20">
                    <div className={`h-2 rounded-full transition-all duration-300 ${item.status === 'failed' ? 'bg-red-500' : item.status === 'completed' ? 'bg-green-500' : 'bg-blue-500'}`} style={{ width: `${Math.max(2, Math.min(100, item.progress))}%` }} />
                  </div>
                  <div className="mt-2 flex items-center justify-between text-xs text-[rgb(var(--text-secondary))]"><span>{item.message}</span><span>{Math.round(item.progress)}%</span></div>
                </div>
              ))}
            </div>

            {/* Posts */}
            {filteredPosts.length === 0 ? (
              <div className="text-center py-12">
                <p className="text-gray-400">No {activeTab} yet</p>
              </div>
            ) : (
              <div className="space-y-4">
                {filteredPosts.map((post, index) => (
                  <Fragment key={post.id}>
                    <PostCard post={post} currentUserId={currentUserId} feedType="home" />
                    {index < filteredPosts.length - 1 && (
                      <AdcashBanner300x100 slotKey={`profile-${userId}-${post.id}-${index}`} />
                    )}
                  </Fragment>
                ))}
              </div>
            )}

          </div>
        </div>

        {/* RIGHT: Desktop Sidebar (hidden on mobile) */}
        <aside className="hidden lg:flex flex-col w-[300px] xl:w-[340px] flex-shrink-0 pt-16 gap-5">
          {isCurrentUser ? (
            <div className="bg-[rgb(var(--bg-secondary))] border border-[rgb(var(--border-color))] rounded-2xl p-4 space-y-1">
              <h3 className="text-[rgb(var(--text-primary))] font-extrabold text-lg px-2 mb-3">Menu</h3>
              
              <button onClick={() => router.push('/profile/edit')} className="w-full flex items-center gap-3 p-3 hover:bg-[rgb(var(--bg-primary))] rounded-xl transition-all text-left text-sm font-semibold text-[rgb(var(--text-primary))]">
                <Settings className="w-4 h-4 text-blue-500" />
                <span>Edit Profile</span>
              </button>

              <button onClick={() => router.push('/profile/menu')} className="w-full flex items-center gap-3 p-3 hover:bg-[rgb(var(--bg-primary))] rounded-xl transition-all text-left text-sm font-semibold text-[rgb(var(--text-primary))]">
                <Bookmark className="w-4 h-4 text-yellow-500" />
                <span>Saved Posts</span>
              </button>

              <button onClick={() => router.push('/profile/menu')} className="w-full flex items-center gap-3 p-3 hover:bg-[rgb(var(--bg-primary))] rounded-xl transition-all text-left text-sm font-semibold text-[rgb(var(--text-primary))]">
                <FileText className="w-4 h-4 text-purple-500" />
                <span>Drafts</span>
              </button>

              <button onClick={() => router.push('/dashboard')} className="w-full flex items-center gap-3 p-3 hover:bg-[rgb(var(--bg-primary))] rounded-xl transition-all text-left text-sm font-semibold text-[rgb(var(--text-primary))]">
                <BarChart3 className="w-4 h-4 text-indigo-500" />
                <span>Analytics</span>
              </button>

              <button onClick={() => router.push('/monetization')} className="w-full flex items-center gap-3 p-3 hover:bg-[rgb(var(--bg-primary))] rounded-xl transition-all text-left text-sm font-semibold text-[rgb(var(--text-primary))]">
                <DollarSign className="w-4 h-4 text-green-500" />
                <span>Monetization</span>
              </button>

              <button onClick={() => router.push('/referrals')} className="w-full flex items-center gap-3 p-3 hover:bg-[rgb(var(--bg-primary))] rounded-xl transition-all text-left text-sm font-semibold text-[rgb(var(--text-primary))]">
                <Gift className="w-4 h-4 text-pink-500" />
                <span>Referrals</span>
              </button>

              <button onClick={() => router.push('/premium')} className="w-full flex items-center gap-3 p-3 hover:bg-[rgb(var(--bg-primary))] rounded-xl transition-all text-left text-sm font-semibold text-[rgb(var(--text-primary))]">
                <DollarSign className="w-4 h-4 text-amber-500" />
                <span>Premium</span>
              </button>

              <div className="h-px bg-[rgb(var(--border-color))] my-2" />

              <button onClick={() => router.push('/terms')} className="w-full flex items-center gap-3 p-3 hover:bg-[rgb(var(--bg-primary))] rounded-xl transition-all text-left text-sm font-semibold text-[rgb(var(--text-primary))]">
                <FileText className="w-4 h-4 text-gray-500" />
                <span>Terms of Service</span>
              </button>

              <button onClick={() => router.push('/privacy')} className="w-full flex items-center gap-3 p-3 hover:bg-[rgb(var(--bg-primary))] rounded-xl transition-all text-left text-sm font-semibold text-[rgb(var(--text-primary))]">
                <ShieldAlert className="w-4 h-4 text-red-500" />
                <span>Privacy Policy</span>
              </button>

              <button onClick={() => router.push('/account-deletion')} className="w-full flex items-center gap-3 p-3 hover:bg-[rgb(var(--bg-primary))] rounded-xl transition-all text-left text-sm font-semibold text-[rgb(var(--text-primary))]">
                <Trash2 className="w-4 h-4 text-rose-600" />
                <span>Account Deletion</span>
              </button>

              <div className="h-px bg-[rgb(var(--border-color))] my-2" />

              <button onClick={handleSignOut} className="w-full flex items-center gap-3 p-3 hover:bg-red-500/10 rounded-xl transition-all text-left text-sm font-bold text-red-500">
                <LogOut className="w-4 h-4" />
                <span>Sign Out</span>
              </button>
            </div>
          ) : (
            <div className="bg-[rgb(var(--bg-secondary))] border border-[rgb(var(--border-color))] rounded-2xl p-5 space-y-4 text-center">
              <h3 className="text-[rgb(var(--text-primary))] font-extrabold text-lg">Support Creator</h3>
              <p className="text-xs text-[rgb(var(--text-secondary))] leading-relaxed">
                Share this profile with others, or message them to connect.
              </p>
              <div className="flex flex-col gap-2">
                <button onClick={handleShare} className="w-full bg-blue-500 hover:bg-blue-600 text-white py-2.5 px-4 rounded-xl font-bold transition-all text-sm flex items-center justify-center gap-2">
                  <Share className="w-4 h-4" /> Share Profile
                </button>
                <button onClick={handleMessage} className="w-full bg-[rgb(var(--bg-primary))] border border-[rgb(var(--border-color))] text-[rgb(var(--text-primary))] hover:bg-[rgb(var(--bg-secondary))] py-2.5 px-4 rounded-xl font-semibold transition-all text-sm flex items-center justify-center gap-2">
                  <MessageCircle className="w-4 h-4" /> Message
                </button>
              </div>
            </div>
          )}
        </aside>

      </div>
    </div>
  )
}
