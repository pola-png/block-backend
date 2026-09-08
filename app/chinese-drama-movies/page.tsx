import type { Metadata } from 'next'
import Link from 'next/link'
import { ChineseDramaMoviesFeed } from './ChineseDramaMoviesFeed'

const baseUrl = process.env.NEXT_PUBLIC_SITE_URL || 'https://xapzap.com'
const pageUrl = `${baseUrl}/chinese-drama-movies`

export const metadata: Metadata = {
  title: 'Chinese Drama Movies: Best C-Drama Films to Watch',
  description:
    'Discover trending Chinese drama movies, romance stories, historical titles, and modern C-drama films. Stream and explore Chinese drama content on XapZap.',
  keywords: [
    'chinese drama movies',
    'c drama movies',
    'best chinese drama movies',
    'chinese romance movies',
    'historical chinese drama films',
    'watch chinese drama online',
  ],
  alternates: {
    canonical: '/chinese-drama-movies',
  },
  openGraph: {
    title: 'Chinese Drama Movies: Best C-Drama Films to Watch',
    description:
      'Explore Chinese drama movies by genre, mood, and popularity. Find romance, youth, and historical C-drama films on XapZap.',
    url: pageUrl,
    type: 'website',
    siteName: 'XapZap',
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Chinese Drama Movies: Best C-Drama Films to Watch',
    description:
      'Find top Chinese drama movie recommendations and trending C-drama content on XapZap.',
  },
}

export default function ChineseDramaMoviesPage() {
  const structuredData = {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'WebPage',
        name: 'Chinese Drama Movies: Best C-Drama Films to Watch',
        description:
          'Discover trending Chinese drama movies, romance stories, historical titles, and modern C-drama films.',
        url: pageUrl,
      },
      {
        '@type': 'BreadcrumbList',
        itemListElement: [
          {
            '@type': 'ListItem',
            position: 1,
            name: 'Home',
            item: baseUrl,
          },
          {
            '@type': 'ListItem',
            position: 2,
            name: 'Chinese Drama Movies',
            item: pageUrl,
          },
        ],
      },
      {
        '@type': 'ItemList',
        name: 'Popular Chinese Drama Movie Categories',
        itemListElement: [
          { '@type': 'ListItem', position: 1, name: 'Romance Chinese Drama Movies' },
          { '@type': 'ListItem', position: 2, name: 'Historical Chinese Drama Movies' },
          { '@type': 'ListItem', position: 3, name: 'Modern Urban Chinese Drama Movies' },
          { '@type': 'ListItem', position: 4, name: 'Youth and School Chinese Drama Movies' },
        ],
      },
      {
        '@type': 'FAQPage',
        mainEntity: [
          {
            '@type': 'Question',
            name: 'Where can I watch Chinese drama movies online?',
            acceptedAnswer: {
              '@type': 'Answer',
              text: 'You can discover and watch trending Chinese drama movie content on XapZap across Watch and Reels sections.',
            },
          },
          {
            '@type': 'Question',
            name: 'What are the most popular Chinese drama movie genres?',
            acceptedAnswer: {
              '@type': 'Answer',
              text: 'Popular genres include romance, historical drama, modern urban stories, and youth-focused drama films.',
            },
          },
        ],
      },
    ],
  }

  return (
    <main className="mx-auto max-w-5xl px-4 py-8 sm:px-6 sm:py-10">
      <h1 className="text-3xl font-extrabold tracking-tight text-foreground sm:text-4xl">
        Chinese Drama Movies
      </h1>
      <p className="mt-4 text-base leading-7 text-muted-foreground sm:text-lg">
        Explore the best Chinese drama movies in one place. Discover romance C-drama films,
        historical stories, modern city drama movies, and emotional character-driven titles
        trending with viewers.
      </p>

      <section className="mt-8 rounded-xl border border-border bg-card p-5 sm:p-6">
        <h2 className="text-2xl font-bold text-foreground">Popular C-Drama Movie Categories</h2>
        <ul className="mt-4 list-disc space-y-2 pl-5 text-base text-muted-foreground">
          <li>Romance Chinese drama movies</li>
          <li>Historical Chinese palace and wuxia drama films</li>
          <li>Modern urban relationship drama movies</li>
          <li>Youth and coming-of-age Chinese drama stories</li>
        </ul>
      </section>

      <section className="mt-8 rounded-xl border border-border bg-card p-5 sm:p-6">
        <h2 className="text-2xl font-bold text-foreground">Watch and Discover on XapZap</h2>
        <p className="mt-3 text-base leading-7 text-muted-foreground">
          Browse short clips, trailers, and full-length drama content. Follow creators,
          comment on scenes, and keep up with trending Chinese drama movie discussions.
        </p>
        <div className="mt-5 flex flex-wrap gap-3">
          <Link
            href="/watch"
            className="rounded-full bg-primary px-5 py-2 text-sm font-semibold text-primary-foreground hover:bg-primary/90"
          >
            Browse Watch
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
            Entertainment News
          </Link>
        </div>
      </section>

      <section className="mt-8">
        <h2 className="text-2xl font-bold text-foreground">Chinese Drama Movie Posts</h2>
        <p className="mt-2 text-base text-muted-foreground">
          This feed shows all post cards matching keywords like Chinese, drama, and movies.
        </p>
        <ChineseDramaMoviesFeed />
      </section>

      <section className="mt-8 rounded-xl border border-border bg-card p-5 sm:p-6">
        <h2 className="text-2xl font-bold text-foreground">FAQ</h2>
        <div className="mt-4 space-y-4">
          <div>
            <h3 className="text-lg font-semibold text-foreground">
              Where can I find trending Chinese drama movies?
            </h3>
            <p className="mt-1 text-base text-muted-foreground">
              Trending Chinese drama content is available across the Watch and Reels feeds.
            </p>
          </div>
          <div>
            <h3 className="text-lg font-semibold text-foreground">
              Do you include romance and historical Chinese drama films?
            </h3>
            <p className="mt-1 text-base text-muted-foreground">
              Yes. You can discover romance, historical, and modern story-based Chinese drama
              movie content on this page and in related feeds.
            </p>
          </div>
        </div>
      </section>

      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData) }}
      />
    </main>
  )
}
