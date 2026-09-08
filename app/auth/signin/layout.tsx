import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Sign In',
  description: 'Sign in to your XapZap account to watch, post, comment, and connect with creators.',
  alternates: {
    canonical: '/auth/signin',
  },
  openGraph: {
    title: 'Sign In | XapZap',
    description: 'Sign in to your XapZap account.',
    url: '/auth/signin',
    type: 'website',
  },
}

export default function SignInLayout({ children }: { children: React.ReactNode }) {
  return children
}

