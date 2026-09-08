'use client'

import { ReactNode, useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { Home, MessageCircle, PlusSquare, Bell, User, Search, Video, Film, Radio, Newspaper, Users, Briefcase } from 'lucide-react'
import { cn } from './utils'
import appwriteService from './appwriteService'

interface MainLayoutProps {
  children: ReactNode
  currentTab: number
  onTabChange: (tab: number) => void
  onCreateClick: () => void
  isGuest?: boolean
  onUserStateChange?: (user: any) => void
  authRefreshTrigger?: number
  hideBottomNav?: boolean
}

export function MainLayout({ children, currentTab, onTabChange, onCreateClick, isGuest = false, onUserStateChange, authRefreshTrigger = 0, hideBottomNav = false }: MainLayoutProps) {
  const router = useRouter()
  const [unreadChats, setUnreadChats] = useState(0)
  const [unreadNotifications, setUnreadNotifications] = useState(0)
  const [user, setUser] = useState<any>(null)
  const [userAvatar, setUserAvatar] = useState('')
  const [hasLoadedUser, setHasLoadedUser] = useState(false)

  useEffect(() => {
    let cleanup: (() => void) | undefined

    const init = async () => {
      await loadUserData()
      setHasLoadedUser(true)

      if (!isGuest && user) {
        await loadBadges()
        cleanup = setupRealtimeSubscriptions()
      }
    }

    init()

    return () => {
      if (cleanup) cleanup()
    }
  }, [isGuest, authRefreshTrigger])

  const loadUserData = async () => {
    try {
      const currentUser = await appwriteService.getCurrentUser()
      setUser(currentUser)
      
      if (currentUser) {
        const profile = await appwriteService.getProfileByUserId(currentUser.$id)
        setUserAvatar(profile?.avatarUrl || '')
      }
    } catch (error) {
      console.error('Failed to load user data:', error)
    }
  }

  const loadBadges = async () => {
    if (!user) return
    
    try {
      const [chatCount, notifCount] = await Promise.all([
        appwriteService.getUnreadChatCount(user.$id),
        appwriteService.getUnreadNotificationCount(user.$id)
      ])
      
      setUnreadChats(chatCount)
      setUnreadNotifications(notifCount)
    } catch (error) {
      console.error('Failed to load badges:', error)
    }
  }

  const setupRealtimeSubscriptions = () => {
    if (!user) return

    const unsubscribeMessages = appwriteService.subscribeToCollection('messages', () => {
      loadBadges()
    })

    const unsubscribeNotifications = appwriteService.subscribeToCollection('notifications', () => {
      loadBadges()
    })

    return () => {
      unsubscribeMessages()
      unsubscribeNotifications()
    }
  }

  // Protected tabs that require authentication
  const protectedTabs = [1, 2, 3, 4, 5] // Chat, Upload, Notifications, Profile, Dashboard

  const handleTabChange = async (tab: number) => {
    // Check if tab requires authentication
    if (protectedTabs.includes(tab)) {
      const currentUser = await appwriteService.getCurrentUser()
      if (!currentUser) {
        // Redirect to auth screen
        onTabChange(6) // Auth screen index
        return
      }
    }

    // Allow tab change
    onTabChange(tab)
  }

  const handleCreateClick = async () => {
    // Check authentication before opening upload modal
    const currentUser = await appwriteService.getCurrentUser()
    if (!currentUser) {
      // Redirect to auth screen
      onTabChange(6) // Auth screen index
      return
    }

    // Proceed with upload
    onCreateClick()
  }

  const sidebarItems = [
    { icon: Home, label: 'For You', index: 0 },
    { icon: Video, label: 'Watch', index: 7 },
    { icon: Film, label: 'Reels', index: 8 },
    { icon: Radio, label: 'Live', index: 9 },
    { icon: Newspaper, label: 'News', index: 10 },
    { icon: Briefcase, label: 'Jobs', index: 12 },
    { icon: Users, label: 'Following', index: 11 },
  ]

  const isHomeTab = [0, 7, 8, 9, 10, 11, 12].includes(currentTab)

  return (
    <div className="min-h-screen bg-[rgb(var(--bg-primary))]">
      {/* Desktop Layout */}
      <div className="hidden lg:flex h-screen flex-col">
        {/* Header */}
        <header className="fixed top-0 left-0 right-0 z-50 bg-[rgb(var(--bg-primary))] border-b border-[rgb(var(--border-color))] px-6 py-3 flex items-center justify-between">
          <h1 className="text-xl font-bold text-[rgb(var(--text-primary))]">XapZap</h1>
          
          <div className="flex items-center gap-8">
            <button onClick={() => handleTabChange(0)} className={cn("p-2 rounded-lg", currentTab === 0 ? "text-[#1DA1F2]" : "text-[rgb(var(--text-primary))] hover:text-[#1DA1F2]")} aria-label="Home">
              <Home size={24} />
            </button>
            <button onClick={() => handleTabChange(1)} className={cn("p-2 rounded-lg relative", currentTab === 1 ? "text-[#1DA1F2]" : "text-[rgb(var(--text-primary))] hover:text-[#1DA1F2]")} aria-label="Chat">
              <MessageCircle size={24} />
              {unreadChats > 0 && (
                <span className="absolute -top-1 -right-1 bg-red-500 text-white text-sm rounded-full px-1.5 min-w-[18px] h-[18px] flex items-center justify-center">
                  {unreadChats}
                </span>
              )}
            </button>
            <button onClick={handleCreateClick} className="p-2 rounded-lg text-[rgb(var(--text-primary))] hover:text-[#1DA1F2]" aria-label="Create">
              <PlusSquare size={24} />
            </button>
            <button onClick={() => handleTabChange(3)} className={cn("p-2 rounded-lg relative", currentTab === 3 ? "text-[#1DA1F2]" : "text-[rgb(var(--text-primary))] hover:text-[#1DA1F2]")} aria-label="Notifications">
              <Bell size={24} />
              {unreadNotifications > 0 && (
                <span className="absolute -top-1 -right-1 bg-red-500 text-white text-sm rounded-full px-1.5 min-w-[18px] h-[18px] flex items-center justify-center">
                  {unreadNotifications}
                </span>
              )}
            </button>
            <button onClick={() => handleTabChange(4)} className={cn("p-2 rounded-lg", currentTab === 4 ? "text-[#1DA1F2]" : "text-[rgb(var(--text-primary))] hover:text-[#1DA1F2]")} aria-label="Profile">
              <User size={24} />
            </button>
          </div>

          <div className="flex items-center gap-4">
            <button onClick={() => router.push('/search')} className="p-2 rounded-lg text-[rgb(var(--text-primary))] hover:text-[#1DA1F2]" aria-label="Search">
              <Search size={24} />
            </button>
            {userAvatar ? (
              <img src={userAvatar} alt="Profile" className="w-9 h-9 rounded-full object-cover cursor-pointer" onClick={() => handleTabChange(4)} />
            ) : (
              <div className="w-9 h-9 bg-[rgb(var(--bg-secondary))] rounded-full flex items-center justify-center cursor-pointer" onClick={() => handleTabChange(4)}>
                <User size={18} className="text-[rgb(var(--text-primary))]" />
              </div>
            )}
          </div>
        </header>

        <div className="flex flex-1 pt-[60px]">
          {/* Sidebar */}
          <aside className="fixed left-0 top-[60px] bottom-0 w-[200px] bg-[rgb(var(--bg-primary))] border-r border-[rgb(var(--border-color))] overflow-y-auto">
            <nav className="py-4">
              {sidebarItems.map((item) => {
                const Icon = item.icon
                const isActive = currentTab === item.index

                return (
                  <button
                    key={item.index}
                    onClick={() => handleTabChange(item.index)}
                    className={cn(
                      "tab-text w-full flex items-center gap-3 px-6 py-3",
                      isActive ? "text-[#1DA1F2] bg-[#1DA1F2]/10" : "text-[rgb(var(--text-primary))] hover:bg-[rgb(var(--bg-secondary))]"
                    )}
                  >
                    <Icon size={20} />
                    <span className="tab-text text-[15px] font-black tracking-[0.06em]">{item.label}</span>
                  </button>
                )
              })}
            </nav>
          </aside>

          {/* Main Content */}
          <main className="ml-[200px] flex-1 overflow-y-auto">
            {children}
          </main>
        </div>
      </div>

      {/* Mobile Layout */}
      <div className="lg:hidden">
        {isHomeTab && currentTab !== 8 && (
          <header className="sticky top-0 z-50 bg-[rgb(var(--bg-primary))] border-b border-[rgb(var(--border-color))]">
            <div className="flex items-center justify-between px-4 py-3">
              <h1 className="text-xl font-bold text-[rgb(var(--text-primary))]">XapZap</h1>
              <button onClick={() => router.push('/search')} className="p-2 text-[rgb(var(--text-primary))]" aria-label="Search">
                <Search size={20} />
              </button>
            </div>
          </header>
        )}
        {isHomeTab && currentTab !== 8 && (
          <div className="sticky top-14 z-40 bg-[rgb(var(--bg-primary))] border-b border-[rgb(var(--border-color))]">
            <div className="flex overflow-x-auto scrollbar-hide -mb-px">
              <div className="flex gap-4 px-4 min-w-max sm:gap-6">
                {sidebarItems.map((item) => (
                  <button
                    key={item.index}
                    onClick={() => handleTabChange(item.index)}
                    className={cn(
                      "navigation-tab tab-text px-3 py-4 text-sm font-black tracking-[0.08em] whitespace-nowrap border-b-2 flex-shrink-0",
                      currentTab === item.index
                        ? "border-[#1DA1F2] text-[#1DA1F2]"
                        : "border-transparent text-[rgb(var(--text-secondary))] hover:border-[rgb(var(--text-primary))]/50 hover:text-[rgb(var(--text-primary))]"
                    )}
                    aria-label={item.label}
                  >
                    {item.label}
                  </button>
                ))}
              </div>
            </div>
          </div>
        )}
        <main className={hideBottomNav ? '' : 'pb-20'}>{children}</main>
        {!hideBottomNav && (
        <nav className="fixed bottom-0 left-0 right-0 bg-[rgb(var(--bg-primary))] border-t border-[rgb(var(--border-color))] safe-area-inset-bottom">
          <div className="flex items-center justify-around py-2 px-2">
            {[
              { icon: Home, index: 0, label: 'Home', onClick: () => handleTabChange(0) },
              { icon: MessageCircle, index: 1, label: 'Chat', onClick: () => handleTabChange(1) },
              { icon: PlusSquare, index: 2, label: 'Create', onClick: handleCreateClick },
              { icon: Bell, index: 3, label: 'Notifications', onClick: () => handleTabChange(3) },
              { icon: User, index: 4, label: 'Profile', onClick: () => handleTabChange(4) }
            ].map((item) => {
              const Icon = item.icon
              return (
                <button
                  key={item.index}
                  onClick={item.onClick}
                  className={cn(
                    "p-3 min-w-[48px] min-h-[48px] flex items-center justify-center rounded-lg",
                    currentTab === item.index ? "text-[#1DA1F2]" : "text-[rgb(var(--text-primary))] hover:bg-[rgb(var(--bg-secondary))]"
                  )}
                  aria-label={item.label}
                >
                  <Icon size={24} />
                </button>
              )
            })}
          </div>
        </nav>
        )}
      </div>
    </div>
  )
}
