import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'For You Feed',
  description:
    'Explore your personalized For You feed on XapZap with trending videos, reels, news, and posts.',
  alternates: {
    canonical: '/for-you',
  },
  openGraph: {
    title: 'For You Feed | XapZap',
    description: 'Personalized For You feed with trending content on XapZap.',
    url: '/for-you',
    type: 'website',
  },
}

export default function ForYouLayout({ children }: { children: React.ReactNode }) {
  return children
}

