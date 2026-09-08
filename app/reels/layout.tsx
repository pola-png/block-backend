import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Reels',
  description:
    'Watch short-form reels on XapZap. Discover trending creators, clips, and viral moments.',
  alternates: {
    canonical: '/reels',
  },
  openGraph: {
    title: 'Reels | XapZap',
    description: 'Explore short-form reels and trending clips on XapZap.',
    url: '/reels',
    type: 'website',
  },
}

export default function ReelsLayout({ children }: { children: React.ReactNode }) {
  return children
}

