import type { Metadata } from 'next'
import Link from 'next/link'

export const metadata: Metadata = {
  title: 'Monetization for Creators',
  description:
    'Learn how monetization works on XapZap for creators, including premium creator features, eligibility, and growth opportunities.',
  alternates: {
    canonical: '/monetization',
  },
  openGraph: {
    title: 'Monetization for Creators | XapZap',
    description:
      'Monetization information for creators on XapZap, including premium tools and roadmap updates.',
    url: '/monetization',
    type: 'website',
  },
}

export default function MonetizationPage() {
  return (
    <main className="mx-auto max-w-4xl px-4 py-10 sm:px-6">
      <h1 className="text-3xl font-extrabold text-foreground sm:text-4xl">
        Monetization on XapZap
      </h1>
      <p className="mt-4 text-base leading-7 text-muted-foreground">
        XapZap is building monetization tools for creators. This includes premium creator options,
        better upload limits, and more advanced tools to grow your audience and earnings.
      </p>

      <section className="mt-8 rounded-xl border border-border bg-card p-5 sm:p-6">
        <h2 className="text-2xl font-bold text-foreground">Current Status</h2>
        <p className="mt-3 text-muted-foreground">
          Verified creators already access longer video upload capability. Full premium
          monetization flows are in progress.
        </p>
      </section>

      <section className="mt-8 rounded-xl border border-border bg-card p-5 sm:p-6">
        <h2 className="text-2xl font-bold text-foreground">Next Steps</h2>
        <ul className="mt-4 list-disc space-y-2 pl-5 text-muted-foreground">
          <li>Creator subscriptions and premium upgrade path.</li>
          <li>Improved analytics for views, retention, and engagement.</li>
          <li>More distribution controls for high-performing content.</li>
        </ul>
      </section>

      <div className="mt-8">
        <Link
          href="/premium"
          className="rounded-full bg-primary px-5 py-2 text-sm font-semibold text-primary-foreground hover:bg-primary/90"
        >
          Go to Premium
        </Link>
      </div>
    </main>
  )
}

