import './globals.css'
import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import { AuthWrapper } from '../AuthWrapper'
import { MainLayoutWrapper } from '../MainLayoutWrapper'
import { generateWebsiteStructuredData, generateOrganizationStructuredData } from '../lib/structured-data'

const inter = Inter({ subsets: ['latin'] })
const googleVerificationToken = process.env.NEXT_PUBLIC_GOOGLE_SITE_VERIFICATION

export const metadata: Metadata = {
  title: {
    default: 'XapZap - Social Media Platform',
    template: '%s | XapZap'
  },
  description: 'Connect, share videos, news, reels and discover content with XapZap - the ultimate social media platform for posts, stories, chats and more.',
  keywords: 'social media, videos, news, reels, posts, stories, chat, xapzap, social network, share content',
  authors: [{ name: 'XapZap Team' }],
  creator: 'XapZap',
  publisher: 'XapZap',
  icons: {
    icon: '/favicon.png',
  },
  openGraph: {
    title: 'XapZap - Social Media Platform',
    description: 'Connect, share and discover with XapZap',
    url: 'https://xapzap.com',
    siteName: 'XapZap',
    images: [
      {
        url: '/og-image.jpg',
        width: 1200,
        height: 630,
        alt: 'XapZap',
      },
    ],
    locale: 'en_US',
    type: 'website',
  },
  twitter: {
    card: 'summary_large_image',
    title: 'XapZap - Social Media Platform',
    description: 'Connect, share and discover with XapZap',
    images: ['/twitter-image.jpg'],
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      'max-video-preview': -1,
      'max-image-preview': 'large',
      'max-snippet': -1,
    },
  },
  verification: googleVerificationToken
    ? {
        google: googleVerificationToken,
      }
    : undefined,
  metadataBase: new URL(process.env.NEXT_PUBLIC_SITE_URL || 'https://xapzap.com'),
}

// Allow Next.js to statically optimize the shell where possible.
// Individual pages that need always-fresh data can opt into dynamic behavior.

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const websiteData = generateWebsiteStructuredData()
  const orgData = generateOrganizationStructuredData()

  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <meta name="clckd" content="9e74e972a063854e6f79469ab24a989d" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <script
          async
          src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=ca-pub-3088816615654692"
          crossOrigin="anonymous"
        />
        <script
          dangerouslySetInnerHTML={{
            __html: `
              (function() {
                function updateTheme() {
                  if (localStorage.theme === 'dark' || (!localStorage.theme && window.matchMedia('(prefers-color-scheme: dark)').matches)) {
                    document.documentElement.classList.add('dark')
                  } else {
                    document.documentElement.classList.remove('dark')
                  }
                }
                updateTheme()
                window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', updateTheme)
              })()
            `,
          }}
        />
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(websiteData) }}
        />
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(orgData) }}
        />
      </head>
      <body className={inter.className}>
        <AuthWrapper>
          <MainLayoutWrapper>{children}</MainLayoutWrapper>
        </AuthWrapper>
      </body>
    </html>
  )
}
