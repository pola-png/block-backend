import { redirect } from 'next/navigation'
import appwriteService from '../../../appwriteService'
import { generateSlug } from '../../../lib/slug'

type ShareRedirectPageProps = {
  params: { id?: string | string[] } | Promise<{ id?: string | string[] }>
}

export const dynamic = 'force-dynamic'

export default async function ShareRedirectPage({ params }: ShareRedirectPageProps) {
  const resolvedParams = await params
  const rawId = Array.isArray(resolvedParams?.id) ? resolvedParams?.id[0] : resolvedParams?.id
  const postId = rawId?.trim()

  if (!postId) {
    redirect('/')
  }

  try {
    const post = await appwriteService.getPost(postId)
    if (!post) {
      redirect('/')
    }

    const postType = post.postType || 'video'
    const title = post.title || post.content?.substring(0, 30) || 'post'
    const slug = generateSlug(title, postId)

    if (postType === 'reel') {
      redirect(`/reels/${slug}`)
    } else {
      redirect(`/watch/${slug}`)
    }
  } catch (error) {
    console.error('Failed to resolve redirect for shared post:', error)
    redirect('/')
  }
}
