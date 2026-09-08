import { redirect } from 'next/navigation'
import appwriteService from '../../appwriteService'

type ProfileRedirectPageProps = {
  params: { username?: string | string[] } | Promise<{ username?: string | string[] }>
}

export const dynamic = 'force-dynamic'

export default async function ProfileRedirectPage({ params }: ProfileRedirectPageProps) {
  const resolvedParams = await params
  const rawUsername = Array.isArray(resolvedParams?.username)
    ? resolvedParams?.username[0]
    : resolvedParams?.username
  
  const username = rawUsername?.trim()

  if (!username || !username.startsWith('@')) {
    redirect('/')
  }

  const cleanUsername = username.substring(1)

  try {
    const profile = await appwriteService.findProfileByUsername(cleanUsername)
    if (profile) {
      const userId = profile.userId || profile.$id
      redirect(`/profile/${userId}`)
    }
  } catch (error) {
    console.error('Failed to resolve profile redirect:', error)
  }

  redirect('/')
}
