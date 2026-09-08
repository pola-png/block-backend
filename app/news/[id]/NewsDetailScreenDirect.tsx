'use client'

import { useRouter } from 'next/navigation'
import { NewsDetailScreen } from '../../../NewsDetailScreen'

export function NewsDetailScreenDirect({ article }: { article: any }) {
  const router = useRouter()
  
  // Maps the database row model properties directly to what NewsDetailScreen expects
  const mappedArticle = {
    ...article,
    id: article.$id,
    timestamp: new Date(article.$createdAt || article.createdAt || Date.now()),
  }

  return (
    <div className="w-full min-h-screen bg-background">
      <NewsDetailScreen
        article={mappedArticle}
        onClose={() => router.push('/news')}
      />
    </div>
  )
}
