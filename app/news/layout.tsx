import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'News',
  description:
    'Read trending news and updates on XapZap across entertainment, creators, and social topics.',
  alternates: {
    canonical: '/news',
  },
  openGraph: {
    title: 'News | XapZap',
    description: 'Read trending news and stories on XapZap.',
    url: '/news',
    type: 'website',
  },
}

export default function NewsLayout({ children }: { children: React.ReactNode }) {
  return children
}

