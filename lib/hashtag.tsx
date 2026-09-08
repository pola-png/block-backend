import Link from 'next/link'

export function parseHashtags(text: string) {
  if (!text) return null

  const parts = text.split(/(#\w+)/g)
  
  return parts.map((part, index) => {
    if (part.startsWith('#')) {
      const tag = part.substring(1)
      return (
        <Link
          key={index}
          href={`/hashtag/${tag}`}
          className="text-blue-500 hover:text-blue-400 hover:underline transition-colors"
          onClick={(e) => e.stopPropagation()}
        >
          {part}
        </Link>
      )
    }
    return <span key={index}>{part}</span>
  })
}
