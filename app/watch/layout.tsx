import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Watch Videos',
  description:
    'Watch trending videos on XapZap. Discover creators, entertainment clips, and viral content in your watch feed.',
  alternates: {
    canonical: '/watch',
  },
  openGraph: {
    title: 'Watch Videos | XapZap',
    description: 'Discover and watch trending videos on XapZap.',
    url: '/watch',
    type: 'website',
  },
}

export default function WatchLayout({ children }: { children: React.ReactNode }) {
  return children
}

