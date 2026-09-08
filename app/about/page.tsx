import type { Metadata } from 'next'
import Link from 'next/link'

export const metadata: Metadata = {
  title: 'About XapZap',
  description:
    'Learn about XapZap, our mission, and how we help creators and communities share videos, reels, news, and stories.',
  alternates: {
    canonical: '/about',
  },
  openGraph: {
    title: 'About XapZap',
    description:
      'Learn about XapZap and how we support creators with social video, reels, and community tools.',
    url: '/about',
    type: 'website',
  },
}

export default function AboutPage() {
  return (
    <main className="mx-auto max-w-4xl px-4 py-10 sm:px-6">
      <h1 className="text-3xl font-extrabold text-foreground sm:text-4xl">About XapZap</h1>
      <p className="mt-4 text-base leading-7 text-muted-foreground">
        XapZap is a social platform built for creators and audiences to discover, share, and
        discuss videos, reels, and news in one place.
      </p>

      <section className="mt-8 rounded-xl border border-border bg-card p-5 sm:p-6">
        <h2 className="text-2xl font-bold text-foreground">What You Can Do</h2>
        <ul className="mt-4 list-disc space-y-2 pl-5 text-muted-foreground">
          <li>Watch and share short and long-form video content.</li>
          <li>Engage with creators through likes, reposts, comments, and follows.</li>
          <li>Discover entertainment and trending stories across categories.</li>
        </ul>
      </section>

      <div className="mt-8 flex flex-wrap gap-3">
        <Link
          href="/watch"
          className="rounded-full bg-primary px-5 py-2 text-sm font-semibold text-primary-foreground hover:bg-primary/90"
        >
          Watch Videos
        </Link>
        <Link
          href="/reels"
          className="rounded-full border border-border px-5 py-2 text-sm font-semibold text-foreground hover:bg-accent"
        >
          Explore Reels
        </Link>
        <Link
          href="/news"
          className="rounded-full border border-border px-5 py-2 text-sm font-semibold text-foreground hover:bg-accent"
        >
          Read News
        </Link>
      </div>
    </main>
  )
}

