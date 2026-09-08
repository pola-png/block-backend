'use client'

import { ReactNode, useState, useEffect } from 'react'
import { useRouter, usePathname } from 'next/navigation'
import { Home, MessageCircle, PlusSquare, Bell, User, Search, Video, Film, Radio, Newspaper, Users, Image as ImageIcon, X, Briefcase } from 'lucide-react'
import { cn } from './utils'
import appwriteService from './appwriteService'

type UploadKind = 'video' | 'reel' | 'image' | 'news'

interface MainLayoutWrapperProps {
  children: ReactNode
}

export function MainLayoutWrapper({ children }: MainLayoutWrapperProps) {
  const router = useRouter()
  const pathname = usePathname()
  const isLegalPage =
    pathname === '/privacy' ||
    pathname === '/terms' ||
    pathname === '/account-deletion' ||
    pathname === '/safety-standards'
  const [unreadChats, setUnreadChats] = useState(0)
  const [unreadNotifications, setUnreadNotifications] = useState(0)
  const [user, setUser] = useState<any>(null)
  const [userAvatar, setUserAvatar] = useState('')
  const hideBottomNav = pathname.startsWith('/upload')
  const [isCreateSheetOpen, setIsCreateSheetOpen] = useState(false)
  const [showMobileBanner, setShowMobileBanner] = useState(false)

  useEffect(() => {
    if (typeof window !== 'undefined') {
      const closed = localStorage.getItem('xapzap-app-banner-closed')
      if (!closed) {
        setShowMobileBanner(true)
      }
    }
  }, [])

  const handleDismissBanner = () => {
    localStorage.setItem('xapzap-app-banner-closed', 'true')
    setShowMobileBanner(false)
  }

  useEffect(() => {
    if (isLegalPage) return
    loadUserData()
    // Prefetch the most likely next routes eagerly
    router.prefetch('/watch')
    router.prefetch('/reels')
    router.prefetch('/upload')

    // Defer lower-priority prefetches to avoid blocking first paint
    const timeout = setTimeout(() => {
      router.prefetch('/profile')
      router.prefetch('/notifications')
    }, 3000)

    return () => clearTimeout(timeout)
  }, [isLegalPage])

  useEffect(() => {
    if (isLegalPage) return
    if (pathname.startsWith('/upload')) {
      setIsCreateSheetOpen(false)
    }
  }, [isLegalPage, pathname])

  if (isLegalPage) {
    return <div className="min-h-screen bg-[rgb(var(--bg-primary))]">{children}</div>
  }

  const loadUserData = async () => {
    const currentUser = await appwriteService.getCurrentUser().catch(() => null)
    if (!currentUser) return
    
    setUser(currentUser)
    
    // Non-blocking background loads
    appwriteService.getProfileByUserId(currentUser.$id).then(profile => setUserAvatar(profile?.avatarUrl || '')).catch(() => {})
    appwriteService.getUnreadChatCount(currentUser.$id).then(setUnreadChats).catch(() => {})
    appwriteService.getUnreadNotificationCount(currentUser.$id).then(setUnreadNotifications).catch(() => {})
  }

  const handleCreateClick = () => {
    setIsCreateSheetOpen(true)
    router.prefetch('/upload')
  }

  const handleNavClick = (path: string) => {
    router.push(path)
  }

  const handleUploadKindSelect = (kind: UploadKind) => {
    setIsCreateSheetOpen(false)
    router.push(`/upload?type=${kind}`)
  }

  const sidebarItems = [
    { icon: Home, label: 'For You', path: '/' },
    { icon: Video, label: 'Watch', path: '/watch' },
    { icon: Film, label: 'Reels', path: '/reels' },
    { icon: Radio, label: 'Live', path: '/live' },
    { icon: Newspaper, label: 'News', path: '/news' },
    { icon: Briefcase, label: 'Jobs', path: '/jobs' },
    { icon: Users, label: 'Following', path: '/following' },
  ]

  const isHomeTab = ['/', '/watch', '/reels', '/live', '/news', '/following', '/jobs'].includes(pathname)

  return (
    <div className="min-h-screen bg-[rgb(var(--bg-primary))]">
      {isCreateSheetOpen && (
        <div
          className="fixed inset-0 z-[60] flex items-end justify-center bg-black/40 p-4 backdrop-blur-sm"
          onClick={() => {
            setIsCreateSheetOpen(false)
          }}
        >
          <div
            className="w-full max-w-sm rounded-2xl border border-[rgb(var(--border-color))] bg-[rgb(var(--bg-primary))] p-5 shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="mb-4 flex items-center justify-between">
              <div>
                <p className="text-base font-semibold text-[rgb(var(--text-primary))]">Create Post</p>
                <p className="mt-1 text-sm text-[rgb(var(--text-secondary))]">Choose what to upload</p>
              </div>
              <button
                className="rounded-full p-2 text-[rgb(var(--text-primary))] hover:bg-[rgb(var(--bg-secondary))]"
                onClick={() => setIsCreateSheetOpen(false)}
                aria-label="Close create sheet"
              >
                <X size={18} />
              </button>
            </div>

            <div className="grid grid-cols-2 gap-2">
              {[
                { kind: 'video' as const, label: 'Video', icon: Video },
                { kind: 'reel' as const, label: 'Reel', icon: Film },
                { kind: 'image' as const, label: 'Text/Image', icon: ImageIcon },
                { kind: 'news' as const, label: 'News', icon: Newspaper },
              ].map((item) => {
                const Icon = item.icon
                return (
                  <button
                    key={item.kind}
                    onClick={() => handleUploadKindSelect(item.kind)}
                    className="flex flex-col items-center justify-center rounded-xl p-4 text-center transition hover:bg-[rgb(var(--bg-secondary))]"
                  >
                    <Icon size={28} className="mb-2 text-[rgb(var(--text-primary))]" />
                    <span className="text-sm font-semibold text-[rgb(var(--text-primary))]">{item.label}</span>
                  </button>
                )
              })}
            </div>
          </div>
        </div>
      )}

      {/* Desktop Layout */}
      <div className="hidden lg:flex flex-col min-h-screen">
        {/* Header */}
        <header className="fixed top-0 left-0 right-0 z-50 bg-[rgb(var(--bg-primary))] border-b border-[rgb(var(--border-color))] px-6 py-3 flex items-center justify-between">
          <h1 className="text-xl font-bold text-[rgb(var(--text-primary))]">XapZap</h1>
          
          <div className="flex items-center gap-8">
            <button onClick={() => router.push('/')} className={cn("p-2 rounded-lg", pathname === '/' ? "text-[#1DA1F2]" : "text-[rgb(var(--text-primary))] hover:text-[#1DA1F2]")} aria-label="Home">
              <Home size={24} />
            </button>
            <button onClick={() => handleNavClick('/chat')} className={cn("p-2 rounded-lg relative", pathname === '/chat' ? "text-[#1DA1F2]" : "text-[rgb(var(--text-primary))] hover:text-[#1DA1F2]")} aria-label="Chat">
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
            <button onClick={() => handleNavClick('/notifications')} className={cn("p-2 rounded-lg relative", pathname === '/notifications' ? "text-[#1DA1F2]" : "text-[rgb(var(--text-primary))] hover:text-[#1DA1F2]")} aria-label="Notifications">
              <Bell size={24} />
              {unreadNotifications > 0 && (
                <span className="absolute -top-1 -right-1 bg-red-500 text-white text-sm rounded-full px-1.5 min-w-[18px] h-[18px] flex items-center justify-center">
                  {unreadNotifications}
                </span>
              )}
            </button>
            <button onClick={() => handleNavClick('/profile')} className={cn("p-2 rounded-lg", pathname.startsWith('/profile') ? "text-[#1DA1F2]" : "text-[rgb(var(--text-primary))] hover:text-[#1DA1F2]")} aria-label="Profile">
              <User size={24} />
            </button>
          </div>

          <div className="flex items-center gap-4">
            <button onClick={() => router.push('/search')} className="p-2 rounded-lg text-[rgb(var(--text-primary))] hover:text-[#1DA1F2]" aria-label="Search">
              <Search size={24} />
            </button>
            {userAvatar ? (
              <img src={userAvatar} alt="Profile" className="w-9 h-9 rounded-full object-cover cursor-pointer" onClick={() => handleNavClick('/profile')} />
            ) : (
              <div className="w-9 h-9 bg-[rgb(var(--bg-secondary))] rounded-full flex items-center justify-center cursor-pointer" onClick={() => handleNavClick('/profile')}>
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
                const isActive = pathname === item.path

                return (
                  <button
                    key={item.path}
                    onClick={() => router.push(item.path)}
                    className={cn(
                      "tab-text w-full flex items-center gap-3 px-6 py-3",
                      isActive ? "text-[#1DA1F2] bg-[#1DA1F2]/10" : "text-[rgb(var(--text-primary))] hover:bg-[rgb(var(--bg-secondary))]"
                    )}
                  >
                    <Icon size={20} />
                    <span className="tab-text text-base font-black tracking-[0.06em]">{item.label}</span>
                  </button>
                )
              })}
            </nav>
          </aside>

          {/* Main Content */}
          <main className="ml-[200px] flex-1">
            {children}
          </main>
        </div>
      </div>

      {/* Mobile Layout */}
      <div className="lg:hidden">
        {showMobileBanner && (
          <div className="bg-gradient-to-r from-slate-900 via-blue-950 to-slate-900 border-b border-[#1DA1F2]/20 px-4 py-2 flex items-center justify-between gap-2.5 text-xs text-slate-100 z-[70] relative">
            <div className="flex items-center gap-2 truncate">
              <span className="flex-shrink-0 w-2 h-2 rounded-full bg-[#1DA1F2] animate-ping" />
              <p className="truncate font-medium text-slate-200">
                Get the XapZap app on Google Play to start doing Micro Jobs & earning!
              </p>
            </div>
            <div className="flex items-center gap-2 shrink-0">
              <a
                href="https://play.google.com/store/apps/details?id=com.xapzap.app"
                target="_blank"
                rel="noopener noreferrer"
                className="bg-[#1DA1F2] hover:bg-[#1A8CD8] text-white px-2.5 py-1 rounded-md font-bold text-[10px] uppercase tracking-wider transition whitespace-nowrap"
              >
                Install
              </a>
              <button
                onClick={handleDismissBanner}
                className="text-slate-400 hover:text-slate-200 p-1"
                aria-label="Dismiss banner"
              >
                <X size={14} />
              </button>
            </div>
          </div>
        )}
        {isHomeTab && pathname !== '/reels' && (
          <header className="sticky top-0 z-50 bg-[rgb(var(--bg-primary))] border-b border-[rgb(var(--border-color))]">
            <div className="flex items-center justify-between px-4 py-3">
              <h1 className="text-xl font-bold text-[rgb(var(--text-primary))]">XapZap</h1>
              <button onClick={() => router.push('/search')} className="p-2 text-[rgb(var(--text-primary))]" aria-label="Search">
                <Search size={20} />
              </button>
            </div>
          </header>
        )}
        {isHomeTab && pathname !== '/reels' && (
          <div className="sticky top-14 z-40 bg-[rgb(var(--bg-primary))] border-b border-[rgb(var(--border-color))]">
            <div className="flex overflow-x-auto scrollbar-hide -mb-px">
              <div className="flex gap-4 px-4 min-w-max sm:gap-6">
                {sidebarItems.map((item) => (
                  <button
                    key={item.path}
                    onClick={() => router.push(item.path)}
                    className={cn(
                      "navigation-tab tab-text px-3 py-4 text-sm font-black tracking-[0.08em] whitespace-nowrap border-b-2 flex-shrink-0",
                      pathname === item.path
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
                { icon: Home, path: '/', label: 'Home' },
                { icon: MessageCircle, path: '/chat', label: 'Chat', badge: unreadChats },
                { icon: PlusSquare, path: '/upload', label: 'Create', onClick: handleCreateClick },
                { icon: Bell, path: '/notifications', label: 'Notifications', badge: unreadNotifications },
                { icon: User, path: '/profile', label: 'Profile' }
              ].map((item) => {
                const Icon = item.icon
                return (
                  <button
                    key={item.path}
                    onClick={item.onClick || (() => handleNavClick(item.path))}
                    className={cn(
                      "p-3 min-w-[48px] min-h-[48px] flex items-center justify-center rounded-lg relative",
                      pathname === item.path ? "text-[#1DA1F2]" : "text-[rgb(var(--text-primary))] hover:bg-[rgb(var(--bg-secondary))]"
                    )}
                    aria-label={item.label}
                  >
                    <Icon size={24} />
                    {item.badge && item.badge > 0 && (
                      <span className="absolute top-1 right-1 bg-red-500 text-white text-sm rounded-full px-1.5 min-w-[18px] h-[18px] flex items-center justify-center">
                        {item.badge}
                      </span>
                    )}
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
