import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Sign Up',
  description: 'Create your XapZap account to share videos, reels, posts, and connect with others.',
  alternates: {
    canonical: '/auth/signup',
  },
  openGraph: {
    title: 'Sign Up | XapZap',
    description: 'Create a new XapZap account.',
    url: '/auth/signup',
    type: 'website',
  },
}

export default function SignUpLayout({ children }: { children: React.ReactNode }) {
  return children
}

