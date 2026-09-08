'use client'

import { useEffect } from 'react'
import { useRouter } from 'next/navigation'
import appwriteService from '../../appwriteService'

export default function ProfilePage() {
  const router = useRouter()

  useEffect(() => {
    const redirectToProfile = async () => {
      try {
        const user = await appwriteService.getCurrentUser()
        if (user) {
          router.replace(`/profile/${user.$id}`)
        } else {
          router.replace('/auth/signin')
        }
      } catch (error) {
        router.replace('/auth/signin')
      }
    }

    redirectToProfile()
  }, [router])

  return (
    <div className="min-h-screen bg-[rgb(var(--bg-primary))] flex items-center justify-center">
      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-[rgb(var(--text-primary))]"></div>
    </div>
  )
}
