import { create } from 'zustand'
import { persist } from 'zustand/middleware'

type AuthStore = {
  currentUserId: string | null
  currentUserAvatar: string | null
  isLoading: boolean
  setCurrentUserId: (userId: string | null) => void
  setCurrentUserAvatar: (avatar: string | null) => void
  setLoading: (loading: boolean) => void
  clearAuth: () => void
}

export const useAuthStore = create<AuthStore>()(
  persist(
    (set) => ({
      currentUserId: null,
      currentUserAvatar: null,
      isLoading: true,
      setCurrentUserId: (userId) => set({ currentUserId: userId, isLoading: false }),
      setCurrentUserAvatar: (avatar) => set({ currentUserAvatar: avatar }),
      setLoading: (loading) => set({ isLoading: loading }),
      clearAuth: () => set({ currentUserId: null, currentUserAvatar: null, isLoading: false })
    }),
    {
      name: 'auth-storage'
    }
  )
)
