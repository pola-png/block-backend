'use client'

import { useState, useEffect } from 'react'
import { useRouter, usePathname } from 'next/navigation'
import appwriteService from './appwriteService'
import { useAuthStore } from './authStore'

interface AuthWrapperProps {
  children: React.ReactNode
}

export function AuthWrapper({ children }: AuthWrapperProps) {
  const [user, setUser] = useState<any>(null)
  const [authChecked, setAuthChecked] = useState(false)
  const router = useRouter()
  const pathname = usePathname()
  const setCurrentUserId = useAuthStore((state) => state.setCurrentUserId)

  const isPublicRoute = (path: string) => {
    if (path === '/') return true
    if (path === '/watch' || path.startsWith('/watch/')) return true
    if (path === '/reels' || path.startsWith('/reels/')) return true
    if (path === '/news' || path.startsWith('/news/')) return true
    if (path === '/following') return true
    if (path === '/live') return true
    if (path === '/search') return true
    if (path === '/hashtag' || path.startsWith('/hashtag/')) return true
    if (path === '/auth' || path.startsWith('/auth/')) return true
    if (path === '/premium') return true
    if (path === '/monetization') return true
    if (path === '/about') return true
    if (path === '/privacy') return true
    if (path === '/terms') return true
    if (path === '/account-deletion') return true
    if (path === '/safety-standards') return true
    if (path === '/for-you') return true
    if (path === '/chinese-drama-movies') return true
    if (path === '/profile') return true
    if (/^\/profile\/[^/]+$/.test(path)) return true
    return false
  }

  const requiresAuth = !isPublicRoute(pathname)

  useEffect(() => {
    let active = true

    const checkAuthState = async () => {
      setAuthChecked(false)
      try {
        const currentUser = await appwriteService.getCurrentUser()
        if (!active) return
        setUser(currentUser)
        setCurrentUserId(currentUser?.$id || null)
      } catch (error) {
        if (!active) return
        console.error('Auth check failed:', error)
        setUser(null)
        setCurrentUserId(null)
      } finally {
        if (active) {
          setAuthChecked(true)
        }
      }
    }

    void checkAuthState()

    return () => {
      active = false
    }
  }, [pathname, setCurrentUserId])

  useEffect(() => {
    if (!authChecked) return
    if (requiresAuth && !user) {
      router.replace('/auth/signin')
    }
  }, [authChecked, requiresAuth, router, user])

  if (requiresAuth && !authChecked) return null
  if (requiresAuth && !user) return null

  return <>{children}</>
}

// RouteGuard component for protecting specific routes
interface RouteGuardProps {
  children: React.ReactNode
  requireAuth?: boolean
}

export function RouteGuard({ children, requireAuth = true }: RouteGuardProps) {
  const [user, setUser] = useState<any>(null)
  const [isLoading, setIsLoading] = useState(true)
  const router = useRouter()
  const pathname = usePathname()

  useEffect(() => {
    checkAuthState()
  }, [])

  const checkAuthState = async () => {
    try {
      const currentUser = await appwriteService.getCurrentUser()
      setUser(currentUser)
    } catch (error) {
      console.error('Auth check failed:', error)
      setUser(null)
    } finally {
      setIsLoading(false)
    }
  }

  if (isLoading) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <div className="flex flex-col items-center space-y-4">
          <div className="w-8 h-8 border-2 border-xapzap-blue border-t-transparent rounded-full animate-spin" />
          <p className="text-muted-foreground">Loading...</p>
        </div>
      </div>
    )
  }

  // If authentication is required but user is not logged in
  if (requireAuth && !user) {
    router.push('/auth/signin')
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <div className="flex flex-col items-center space-y-4">
          <div className="w-8 h-8 border-2 border-xapzap-blue border-t-transparent rounded-full animate-spin" />
          <p className="text-muted-foreground">Redirecting to sign in...</p>
        </div>
      </div>
    )
  }

  // If user is logged in but trying to access auth pages, redirect to home
  if (!requireAuth && user && (pathname.startsWith('/auth/'))) {
    router.push('/')
    return null
  }

  return <>{children}</>
}
