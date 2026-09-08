import { Fragment, useEffect, useRef, useState } from "react"
import { useRouter } from "next/navigation"
import { StoryBar } from "./StoryBar"
import { PostCard } from "./PostCard"
import { CommentModal } from "./CommentModal"
import { Post, Chat } from "./types"
import appwriteService from "./appwriteService"
import { useAuthStore } from "./authStore"
import { useFeedStore } from "./feedStore"
import { hasVerifiedBadge, isPremiumBadge } from "./lib/verification"
import { AdcashBanner300x100 } from "./components/AdcashBanner300x100"
import { ChatList, ChatView } from "./ChatScreen"
import { Briefcase, ArrowRight } from "lucide-react"

export function HomeScreen() {
  const router = useRouter()
  const feedStore = useFeedStore()
  const authStore = useAuthStore()
  const [currentUserId, setCurrentUserId] = useState<string>('')
  const [posts, setPosts] = useState<Post[]>([])
  const [loading, setLoading] = useState(false)
  const [hasLoaded, setHasLoaded] = useState(false)
  const [authChecked, setAuthChecked] = useState(false)
  const [selectedPost, setSelectedPost] = useState<Post | null>(null)
  const [showComments, setShowComments] = useState(false)
  
  // Sidebar Chat States
  const [sidebarChats, setSidebarChats] = useState<Chat[]>([])
  const [selectedSidebarChat, setSelectedSidebarChat] = useState<Chat | null>(null)
  const [sidebarLoading, setSidebarLoading] = useState(true)
  const isAuthenticated = Boolean(authStore.currentUserId || currentUserId)
  const showStorySection = authChecked && isAuthenticated
  const showOnboardingPrompt = authChecked && !isAuthenticated
  const homeCommentHistoryActiveRef = useRef(false)
  const ignoreNextHomeCommentPopRef = useRef(false)

  useEffect(() => {
    let isMounted = true

    const checkAuth = async () => {
      try {
        const user = await appwriteService.getCurrentUser()
        if (!isMounted) return
        setCurrentUserId(user?.$id || '')
        authStore.setCurrentUserId(user?.$id || null)
      } catch (error) {
        if (!isMounted) return
        setCurrentUserId('')
        authStore.setCurrentUserId(null)
      } finally {
        if (isMounted) setAuthChecked(true)
      }
    }

    checkAuth()
    return () => {
      isMounted = false
    }
  }, [])

  useEffect(() => {
    if (!isAuthenticated) return

    const loadSidebarChats = async () => {
      setSidebarLoading(true)
      try {
        const user = await appwriteService.getCurrentUser()
        if (!user) {
          setSidebarLoading(false)
          return
        }
        const result = await appwriteService.fetchChatsForUser(user.$id)
        const mappedChats = await Promise.all(result.documents.map(async (doc: any) => {
          const memberIds = doc.memberIds.split(',').map((id: string) => id.trim())
          const partnerId = memberIds.find((id: string) => id !== user.$id) || 'unknown'
          const partnerProfile = await appwriteService.getProfileByUserId(partnerId)
          const partnerIsVerified = hasVerifiedBadge(partnerProfile)
          const partnerIsAdmin = isPremiumBadge(partnerProfile)
          return {
            id: doc.$id,
            chatId: doc.chatId,
            memberIds: doc.memberIds,
            partnerId,
            partnerName: partnerProfile?.displayName || partnerId.slice(0, 8),
            partnerAvatar: partnerProfile?.avatarUrl || '',
            lastMessage: doc.lastMessage || 'No messages',
            timestamp: new Date(doc.lastMessageAt || doc.timestamp || doc.createdAt || doc.$createdAt),
            unreadCount: doc.unreadCount || 0,
            isOnline: false,
            partnerIsVerified,
            partnerIsAdmin,
          } as Chat
        }))
        setSidebarChats(mappedChats)
      } catch (error) {
        console.error('Failed to load sidebar chats:', error)
      } finally {
        setSidebarLoading(false)
      }
    }

    loadSidebarChats()

    const unsubscribe = appwriteService.subscribeToCollection('messages', () => {
      loadSidebarChats()
    })
    return unsubscribe
  }, [isAuthenticated])

  useEffect(() => {
    if (!showComments || !selectedPost) return

    if (!homeCommentHistoryActiveRef.current) {
      window.history.pushState({ ...(window.history.state || {}), xapzapHomeComment: true }, '', window.location.href)
      homeCommentHistoryActiveRef.current = true
    }

    const handlePopState = () => {
      if (ignoreNextHomeCommentPopRef.current) {
        ignoreNextHomeCommentPopRef.current = false
        return
      }

      if (homeCommentHistoryActiveRef.current) {
        homeCommentHistoryActiveRef.current = false
        setShowComments(false)
        setSelectedPost(null)
      }
    }

    window.addEventListener('popstate', handlePopState)
    return () => window.removeEventListener('popstate', handlePopState)
  }, [showComments, selectedPost])

  useEffect(() => {
    const cached = feedStore.getFeed('foryou')
    if (cached && cached.posts.length > 0) {
      setPosts(cached.posts)
      setHasLoaded(true)
      setTimeout(() => window.scrollTo(0, cached.scrollPosition), 0)
      return
    }

    if (!hasLoaded) {
      loadPosts()
    }

    const unsubscribe = appwriteService.subscribeToCollection('posts', (payload) => {
      if (payload.events.includes('databases.*.collections.posts.documents.*.create')) {
        const newPost = payload.payload
        setPosts(prev => {
          const updated = [{
            ...newPost,
            id: newPost.$id,
            timestamp: new Date(newPost.$createdAt || newPost.createdAt),
          }, ...prev]
          feedStore.setFeed('foryou', updated)
          return updated
        })
      }
    })

    return unsubscribe
  }, [hasLoaded])

  useEffect(() => {
    const handleScroll = () => {
      feedStore.setScrollPosition('foryou', window.scrollY)
    }
    window.addEventListener('scroll', handleScroll)
    return () => window.removeEventListener('scroll', handleScroll)
  }, [])

  const loadPosts = async () => {
    setLoading(true)
    try {
      const user = currentUserId ? { $id: currentUserId } : await appwriteService.getCurrentUser()
      if (user) {
        setCurrentUserId(user.$id)
        const result = await appwriteService.fetchForYouFeed(user.$id)
        
        const allPosts: Post[] = await Promise.all(
          result.documents.map(async (d: any) => {
            const profile = await appwriteService.getProfileByUserId(d.userId)
            const [isLiked, isSaved, isReposted] = await Promise.all([
              appwriteService.isPostLikedBy(user.$id, d.$id),
              appwriteService.isPostSavedBy(user.$id, d.$id),
              appwriteService.isPostRepostedBy(user.$id, d.$id)
            ])

            return {
              ...d,
              id: d.$id,
              timestamp: new Date(d.$createdAt || d.createdAt),
              displayName: profile?.displayName,
              avatarUrl: profile?.avatarUrl,
              isVerified: hasVerifiedBadge(profile),
              isLiked,
              isSaved,
              isReposted
            } as Post
          })
        )

        setPosts(allPosts)
        feedStore.setFeed('foryou', allPosts)
      } else {
        const result = await appwriteService.fetchPosts()
        const allPosts: Post[] = await Promise.all(
          result.documents.map(async (d: any) => {
            const profile = await appwriteService.getProfileByUserId(d.userId)
            return {
              ...d,
              id: d.$id,
              timestamp: new Date(d.$createdAt || d.createdAt),
              displayName: profile?.displayName,
              avatarUrl: profile?.avatarUrl,
              isVerified: hasVerifiedBadge(profile)
            } as Post
          })
        )

        setPosts(allPosts)
        feedStore.setFeed('foryou', allPosts)
      }
      setHasLoaded(true)
    } catch (error) {
      console.error('Failed to load posts:', error)
    } finally {
      setLoading(false)
    }
  }

  const handleCommentClick = (post: Post) => {
    setSelectedPost(post)
    setShowComments(true)
  }

  const handleCloseComments = () => {
    setShowComments(false)
    setSelectedPost(null)

    if (homeCommentHistoryActiveRef.current) {
      homeCommentHistoryActiveRef.current = false
      ignoreNextHomeCommentPopRef.current = true
      window.history.back()
    }
  }

  return (
    <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 lg:grid lg:grid-cols-3 lg:gap-8">
      {/* Feed Column */}
      <div className="lg:col-span-2">
        {showOnboardingPrompt && (
          <div className="mt-3 mb-3 rounded-xl border border-[rgb(var(--border-color))] bg-[rgb(var(--bg-secondary))] px-4 py-3 text-sm flex items-center justify-between gap-3">
            <div className="text-[rgb(var(--text-secondary))]">
              <div className="font-semibold text-[rgb(var(--text-primary))] mb-0.5">
                Enjoying the feed?
              </div>
              <div>Sign up to post your own stories, reels, and chat with others.</div>
            </div>
            <button
              onClick={() => router.push('/auth/signup')}
              className="shrink-0 px-3 py-1.5 rounded-full bg-[#1DA1F2] text-white text-xs font-semibold hover:bg-[#1A8CD8] transition"
            >
              Sign up
            </button>
          </div>
        )}
        
        {/* Flagship Micro Jobs Promo Card */}
        <div className="mt-3 mb-4 overflow-hidden rounded-2xl border border-[#1DA1F2]/30 bg-gradient-to-r from-slate-900 via-blue-950 to-slate-900 p-5 shadow-lg relative">
          <div className="absolute top-0 right-0 w-24 h-24 bg-gradient-to-br from-cyan-400 to-[#1DA1F2] opacity-10 rounded-bl-full blur-xl pointer-events-none" />
          <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
            <div className="flex gap-3 items-start">
              <div className="p-3 rounded-xl bg-[#1DA1F2]/10 border border-[#1DA1F2]/20 text-[#1DA1F2] shrink-0 mt-0.5 sm:mt-0">
                <Briefcase className="w-6 h-6 animate-pulse" />
              </div>
              <div>
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="bg-red-500/20 text-red-400 text-[10px] font-bold px-2 py-0.5 rounded-full uppercase tracking-wider border border-red-500/30">
                    Flagship Feature
                  </span>
                  <h4 className="font-extrabold text-base text-white tracking-wide">
                    Earn with XapZap Micro Jobs!
                  </h4>
                </div>
                <p className="text-slate-300 text-xs mt-1.5 max-w-lg leading-relaxed font-semibold">
                  Complete short tasks like video annotations, app testing, and surveys directly on your mobile device to earn rewards. Start earning in minutes.
                </p>
              </div>
            </div>
            <div className="flex items-center gap-2.5 w-full sm:w-auto justify-end">
              <button
                onClick={() => router.push('/jobs')}
                className="w-full sm:w-auto px-4 py-2 rounded-xl border border-slate-600 text-slate-300 text-xs font-semibold hover:bg-slate-800 transition text-center"
              >
                Learn More
              </button>
              <button
                onClick={() => router.push('/jobs')}
                className="w-full sm:w-auto px-4 py-2 rounded-xl bg-gradient-to-r from-[#1DA1F2] to-cyan-500 text-white text-xs font-bold hover:brightness-110 transition flex items-center justify-center gap-1.5 shadow-md shadow-cyan-900/30 whitespace-nowrap"
              >
                Download App <ArrowRight className="w-3.5 h-3.5" />
              </button>
            </div>
          </div>
        </div>

        {showStorySection && <StoryBar />}
        <div className="grid grid-cols-1 md:grid-cols-2 grid-flow-row-dense gap-4 pb-20 sm:pb-24">
          {posts.map((post, index) => (
            <Fragment key={post.id}>
              <div className={post.postType === 'reel' ? 'col-span-1' : 'col-span-1 md:col-span-2'}>
                <PostCard
                  post={post}
                  currentUserId={currentUserId}
                  feedType="home"
                  onCommentClick={() => handleCommentClick(post)}
                />
              </div>
              {index < posts.length - 1 && index % 3 === 2 && (
                <div className="col-span-1 md:col-span-2">
                  <AdcashBanner300x100 slotKey={`home-${post.id}-${index}`} />
                </div>
              )}
            </Fragment>
          ))}
          {loading && (
            <div className="col-span-1 md:col-span-2 flex items-center justify-center py-12">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
            </div>
          )}
        </div>
      </div>

      {/* Right Chat Sidebar */}
      <div className="hidden lg:block border-l border-[rgb(var(--border-color))] pl-6 h-[calc(100vh-80px)] sticky top-20">
        <div className="h-full flex flex-col">
          <h3 className="font-extrabold text-xl mb-4 text-[rgb(var(--text-primary))]">Direct Messages</h3>
          <div className="flex-1 bg-[rgb(var(--bg-secondary))] rounded-2xl border border-[rgb(var(--border-color))] overflow-hidden shadow-sm flex flex-col h-[calc(100vh-160px)]">
            {selectedSidebarChat ? (
              <ChatView 
                chat={selectedSidebarChat} 
                onBack={() => setSelectedSidebarChat(null)} 
              />
            ) : (
              <ChatList 
                chats={sidebarChats} 
                onChatSelect={setSelectedSidebarChat} 
                loading={sidebarLoading} 
              />
            )}
          </div>
        </div>
      </div>

      {showComments && selectedPost && <CommentModal post={selectedPost} onClose={handleCloseComments} />}
    </div>
  )
}
