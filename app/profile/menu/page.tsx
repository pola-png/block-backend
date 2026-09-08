'use client'

import { ArrowLeft, Settings, Bookmark, BarChart3, DollarSign, MessageCircle, LogOut, FileText, Gift, ShieldAlert, Trash2 } from 'lucide-react'
import { useRouter } from 'next/navigation'
import appwriteService from '../../../appwriteService'
import { useAuthStore } from '../../../authStore'

export default function MenuPage() {
  const router = useRouter()
  const authStore = useAuthStore()

  const handleSignOut = async () => {
    try {
      await appwriteService.signOut()
      authStore.clearAuth()
      router.push('/')
    } catch (error) {
      console.error('Sign out failed:', error)
    }
  }

  return (
    <div className="min-h-screen bg-background">
      <div className="max-w-2xl mx-auto">
        <div className="flex items-center gap-3 p-4 border-b border-border">
          <button onClick={() => router.back()} className="p-2 hover:bg-accent rounded-full">
            <ArrowLeft size={24} />
          </button>
          <h1 className="text-xl font-bold">Menu</h1>
        </div>

        <div className="p-4 space-y-2">
          <button
            onClick={() => router.push('/profile/edit')}
            className="w-full flex items-center gap-3 p-4 hover:bg-accent rounded-lg transition-colors text-left"
          >
            <Settings size={20} />
            <span className="font-medium">Edit Profile</span>
          </button>

          <button className="w-full flex items-center gap-3 p-4 hover:bg-accent rounded-lg transition-colors text-left">
            <Bookmark size={20} />
            <span className="font-medium">Saved Posts</span>
          </button>

          <button className="w-full flex items-center gap-3 p-4 hover:bg-accent rounded-lg transition-colors text-left">
            <FileText size={20} />
            <span className="font-medium">Drafts</span>
          </button>

          <button className="w-full flex items-center gap-3 p-4 hover:bg-accent rounded-lg transition-colors text-left">
            <BarChart3 size={20} />
            <span className="font-medium">Analytics</span>
          </button>

          <button className="w-full flex items-center gap-3 p-4 hover:bg-accent rounded-lg transition-colors text-left">
            <DollarSign size={20} />
            <span className="font-medium">Monetization</span>
          </button>

          <button
            onClick={() => router.push('/referrals')}
            className="w-full flex items-center gap-3 p-4 hover:bg-accent rounded-lg transition-colors text-left"
          >
            <Gift size={20} />
            <span className="font-medium">Referrals</span>
          </button>

          <button
            onClick={() => router.push('/premium')}
            className="w-full flex items-center gap-3 p-4 hover:bg-accent rounded-lg transition-colors text-left"
          >
            <DollarSign size={20} />
            <span className="font-medium">Premium</span>
          </button>

          <div className="h-px bg-border my-2" />

          <button className="w-full flex items-center gap-3 p-4 hover:bg-accent rounded-lg transition-colors text-left">
            <Settings size={20} />
            <span className="font-medium">Settings & Privacy</span>
          </button>

          <button className="w-full flex items-center gap-3 p-4 hover:bg-accent rounded-lg transition-colors text-left">
            <MessageCircle size={20} />
            <span className="font-medium">Help & Support</span>
          </button>

          <button className="w-full flex items-center gap-3 p-4 hover:bg-accent rounded-lg transition-colors text-left">
            <span className="text-xl">i</span>
            <span className="font-medium">About XapZap</span>
          </button>

          <button
            onClick={() => router.push('/terms')}
            className="w-full flex items-center gap-3 p-4 hover:bg-accent rounded-lg transition-colors text-left"
          >
            <FileText size={20} />
            <span className="font-medium">Terms of Service</span>
          </button>

          <button
            onClick={() => router.push('/privacy')}
            className="w-full flex items-center gap-3 p-4 hover:bg-accent rounded-lg transition-colors text-left"
          >
            <ShieldAlert size={20} />
            <span className="font-medium">Privacy Policy</span>
          </button>

          <button
            onClick={() => router.push('/account-deletion')}
            className="w-full flex items-center gap-3 p-4 hover:bg-accent rounded-lg transition-colors text-left"
          >
            <Trash2 size={20} />
            <span className="font-medium">Account Deletion</span>
          </button>
        </div>

        <div className="p-4 pt-0">
          <button
            onClick={handleSignOut}
            className="w-full flex items-center gap-3 p-4 hover:bg-red-50 dark:hover:bg-red-950 rounded-lg transition-colors text-left text-red-600"
          >
            <LogOut size={20} />
            <span className="font-medium">Sign Out</span>
          </button>
        </div>
      </div>
    </div>
  )
}
