import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Premium Creator',
  description:
    'Learn about XapZap Premium Creator tools, benefits, and upcoming monetization features.',
  alternates: {
    canonical: '/premium',
  },
  openGraph: {
    title: 'Premium Creator | XapZap',
    description: 'Premium creator tools and monetization roadmap on XapZap.',
    url: '/premium',
    type: 'website',
  },
}

export default function PremiumLayout({ children }: { children: React.ReactNode }) {
  return children
}

