import type { Metadata } from 'next'
import Link from 'next/link'
import { Briefcase, Download, ShieldCheck, Zap, Sparkles, CheckCircle2, AlertTriangle, ArrowRight, HelpCircle, Smartphone } from 'lucide-react'

export const metadata: Metadata = {
  title: 'XapZap Micro Jobs - Earn Rewards for Quick Tasks',
  description:
    'Join XapZap Micro Jobs to complete simple tasks, earn rewards, and work from anywhere. Discover paid video labeling, app testing, and surveys. Exclusive to the XapZap mobile app.',
  keywords: 'micro jobs, earn money online, quick tasks, paid tasks, video annotation, app testing, surveys, gig work, side hustle, xapzap jobs, work from home',
  alternates: {
    canonical: '/jobs',
  },
  openGraph: {
    title: 'XapZap Micro Jobs - Earn Rewards for Quick Tasks',
    description:
      'Earn rewards for quick, simple tasks on your phone. Start today with XapZap Micro Jobs.',
    url: '/jobs',
    type: 'website',
    images: [
      {
        url: '/og-jobs.jpg',
        width: 1200,
        height: 630,
        alt: 'XapZap Micro Jobs',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'XapZap Micro Jobs - Earn Rewards for Quick Tasks',
    description: 'Complete quick tasks on the go and earn rewards. Exclusive to the XapZap Mobile App.',
  }
}

export default function JobsPage() {
  const structuredData = {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    "name": "XapZap Mobile App",
    "operatingSystem": "Android, iOS",
    "applicationCategory": "SocialNetworkingApplication, FinanceApplication",
    "offers": {
      "@type": "Offer",
      "price": "0.00",
      "priceCurrency": "USD"
    },
    "description": "XapZap is a social platform that enables users to complete micro jobs like video annotations, app testing, and surveys on their mobile devices to earn rewards.",
    "featureList": [
      "Micro Jobs and Paid Tasks",
      "Video Annotations and Content Tagging",
      "App Testing and Feedback Surveys",
      "Instant reward accrual and secure withdrawals"
    ]
  }

  return (
    <main className="mx-auto max-w-5xl px-4 py-8 sm:px-6 lg:px-8">
      {/* JSON-LD Structured Data */}
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData) }}
      />

      {/* Hero Section */}
      <section className="relative overflow-hidden rounded-3xl border border-blue-500/20 bg-gradient-to-br from-slate-950 via-slate-900 to-blue-950 px-6 py-12 text-center sm:px-12 sm:py-16">
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_top,_var(--tw-gradient-stops))] from-blue-900/20 via-transparent to-transparent pointer-events-none" />
        <div className="relative z-10 max-w-3xl mx-auto">
          <span className="inline-flex items-center gap-1.5 rounded-full bg-[#1DA1F2]/10 border border-[#1DA1F2]/20 px-3 py-1 text-xs font-bold text-[#1DA1F2] uppercase tracking-wider mb-4">
            <Sparkles className="w-3.5 h-3.5 animate-spin" style={{ animationDuration: '3s' }} /> Flagship Feature
          </span>
          <h1 className="text-4xl font-extrabold tracking-tight text-white sm:text-5xl lg:text-6xl">
            XapZap <span className="bg-gradient-to-r from-[#1DA1F2] to-cyan-400 bg-clip-text text-transparent">Micro Jobs</span>
          </h1>
          <p className="mx-auto mt-6 max-w-2xl text-base sm:text-lg text-slate-300 leading-relaxed">
            Turn your spare time into real rewards! Complete quick, simple tasks directly from your smartphone—anytime, anywhere.
          </p>

          {/* Alert Notice */}
          <div className="mt-8 mx-auto max-w-md rounded-xl border border-yellow-500/20 bg-yellow-500/5 p-3 text-xs text-yellow-200/90 flex items-center justify-center gap-2.5">
            <AlertTriangle className="w-4 h-4 text-yellow-400 shrink-0" />
            <span className="text-left font-semibold">
              Micro Jobs are available <strong className="text-yellow-400">exclusively on our mobile app</strong>.
            </span>
          </div>

          {/* Download CTAs */}
          <div className="mt-8 flex flex-col sm:flex-row items-center justify-center gap-4">
            <Link
              href="/jobs#download"
              className="w-full sm:w-auto inline-flex items-center justify-center gap-2 rounded-xl bg-gradient-to-r from-[#1DA1F2] to-cyan-500 px-6 py-3.5 text-sm font-bold text-white shadow-lg shadow-cyan-900/40 hover:brightness-110 transition active:scale-[0.98]"
            >
              <Download className="w-4 h-4" /> Download Android App (APK)
            </Link>
            <Link
              href="/jobs#download"
              className="w-full sm:w-auto inline-flex items-center justify-center gap-2 rounded-xl border border-slate-700 bg-slate-900/80 px-6 py-3.5 text-sm font-semibold text-slate-200 hover:bg-slate-800 transition"
            >
              <Smartphone className="w-4 h-4 text-[#1DA1F2]" /> App Store Links
            </Link>
          </div>
        </div>
      </section>

      {/* Flagship App Advantage Cards */}
      <section className="mt-16 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
        <div className="rounded-2xl border border-border bg-card p-6 shadow-sm hover:border-blue-500/20 transition-all duration-300">
          <div className="w-10 h-10 rounded-xl bg-blue-500/10 text-blue-500 flex items-center justify-center mb-4">
            <Zap className="w-5 h-5" />
          </div>
          <h3 className="text-lg font-bold text-foreground">Quick, Micro-Tasks</h3>
          <p className="mt-2 text-sm text-muted-foreground leading-relaxed">
            Most tasks take only 1 to 5 minutes to complete. Choose what fits your schedule and earn incrementally throughout your day.
          </p>
        </div>

        <div className="rounded-2xl border border-border bg-card p-6 shadow-sm hover:border-blue-500/20 transition-all duration-300">
          <div className="w-10 h-10 rounded-xl bg-green-500/10 text-green-500 flex items-center justify-center mb-4">
            <ShieldCheck className="w-5 h-5" />
          </div>
          <h3 className="text-lg font-bold text-foreground">Verified Tasks</h3>
          <p className="mt-2 text-sm text-muted-foreground leading-relaxed">
            Every task is securely registered and verified automatically. Rest assured that your contributions are recorded accurately.
          </p>
        </div>

        <div className="rounded-2xl border border-border bg-card p-6 shadow-sm hover:border-blue-500/20 transition-all duration-300 sm:col-span-2 lg:col-span-1">
          <div className="w-10 h-10 rounded-xl bg-[#1DA1F2]/10 text-[#1DA1F2] flex items-center justify-center mb-4">
            <Briefcase className="w-5 h-5" />
          </div>
          <h3 className="text-lg font-bold text-foreground">Diverse Categories</h3>
          <p className="mt-2 text-sm text-muted-foreground leading-relaxed">
            From rating and labeling media uploads to providing feedback on UI designs, you will find tasks that align with your skills.
          </p>
        </div>
      </section>

      {/* Available Jobs section */}
      <section className="mt-16 border-t border-border pt-12">
        <div className="text-center">
          <h2 className="text-2xl font-extrabold tracking-tight text-foreground sm:text-3xl">
            Popular Task Types
          </h2>
          <p className="mt-4 text-sm text-muted-foreground max-w-xl mx-auto">
            Here are some of the micro jobs you can pick up on the XapZap App to earn.
          </p>
        </div>

        <div className="mt-8 grid gap-4 sm:grid-cols-2">
          <div className="flex gap-4 p-5 rounded-2xl border border-border bg-card">
            <CheckCircle2 className="w-5 h-5 text-[#1DA1F2] shrink-0 mt-0.5" />
            <div>
              <h4 className="font-bold text-foreground">Video Classification & Annotation</h4>
              <p className="mt-1.5 text-xs text-muted-foreground leading-relaxed">
                Watch short clips and apply tagging categories, moderate tags, or describe content. Help index XapZap's growing library.
              </p>
            </div>
          </div>

          <div className="flex gap-4 p-5 rounded-2xl border border-border bg-card">
            <CheckCircle2 className="w-5 h-5 text-[#1DA1F2] shrink-0 mt-0.5" />
            <div>
              <h4 className="font-bold text-foreground">Usability Testing & Feedback</h4>
              <p className="mt-1.5 text-xs text-muted-foreground leading-relaxed">
                Explore newly deployed application components on the mobile platform and submit structured performance reports.
              </p>
            </div>
          </div>

          <div className="flex gap-4 p-5 rounded-2xl border border-border bg-card">
            <CheckCircle2 className="w-5 h-5 text-[#1DA1F2] shrink-0 mt-0.5" />
            <div>
              <h4 className="font-bold text-foreground">Opinion Polls & Surveys</h4>
              <p className="mt-1.5 text-xs text-muted-foreground leading-relaxed">
                Participate in brief consumer sentiment check-ins, questionnaires, or feature request feedback to shape creators' portfolios.
              </p>
            </div>
          </div>

          <div className="flex gap-4 p-5 rounded-2xl border border-border bg-card">
            <CheckCircle2 className="w-5 h-5 text-[#1DA1F2] shrink-0 mt-0.5" />
            <div>
              <h4 className="font-bold text-foreground">Content Moderation Tasks</h4>
              <p className="mt-1.5 text-xs text-muted-foreground leading-relaxed">
                Analyze flagged user comments, captions, or thumbnail details to keep the platform safe, inclusive, and clean.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* How to Get Started */}
      <section className="mt-16 border-t border-border pt-12">
        <h2 className="text-2xl font-extrabold text-foreground text-center sm:text-3xl mb-8">
          Getting Started is Easy
        </h2>
        <div className="relative grid gap-8 md:grid-cols-4">
          <div className="absolute top-1/2 left-0 right-0 h-0.5 bg-border -translate-y-1/2 hidden md:block z-0" />
          {[
            { step: '01', title: 'Get the App', desc: 'Download and install XapZap on Android or iOS.' },
            { step: '02', title: 'Verify Account', desc: 'Create your account or log in securely in the app.' },
            { step: '03', title: 'Select Tasks', desc: 'Browse the Jobs board and accept available micro-tasks.' },
            { step: '04', title: 'Get Paid', desc: 'Complete tasks successfully to earn platform coins.' },
          ].map((item, idx) => (
            <div key={idx} className="relative z-10 flex flex-col items-center bg-[rgb(var(--bg-primary))] px-4 text-center">
              <div className="w-12 h-12 rounded-full bg-gradient-to-br from-[#1DA1F2] to-cyan-500 flex items-center justify-center text-white font-extrabold text-sm shadow-md shadow-[#1DA1F2]/20">
                {item.step}
              </div>
              <h4 className="font-bold text-foreground mt-4 text-sm">{item.title}</h4>
              <p className="mt-1 text-xs text-muted-foreground max-w-[200px] leading-relaxed">{item.desc}</p>
            </div>
          ))}
        </div>
      </section>

      {/* Direct App Download Section */}
      <section id="download" className="mt-20 rounded-3xl border border-border bg-card p-6 sm:p-10 text-center relative overflow-hidden">
        <div className="absolute -left-12 -top-12 w-48 h-48 bg-gradient-to-tr from-[#1DA1F2]/20 to-transparent rounded-full blur-2xl pointer-events-none" />
        <h2 className="text-2xl font-extrabold text-foreground sm:text-3xl">
          Start Earning Today
        </h2>
        <p className="mt-3 text-sm text-muted-foreground max-w-lg mx-auto">
          Jobs are processed directly within the mobile application layout to ensure safe execution, location checks, and sandbox safety.
        </p>

        <div className="mt-8 flex flex-col sm:flex-row items-center justify-center gap-4">
          {/* APK Direct Link */}
          <Link
            href="/downloads/xapzap-latest.apk"
            className="w-full sm:w-auto inline-flex items-center justify-center gap-2 rounded-xl bg-slate-900 border border-slate-700 hover:bg-slate-800 text-slate-100 font-bold px-6 py-3.5 text-xs transition"
          >
            <Download className="w-4 h-4 text-[#1DA1F2]" /> Direct Download (.APK)
          </Link>
          
          {/* Google Play Store */}
          <Link
            href="https://play.google.com/store/apps/details?id=com.xapzap.app"
            target="_blank"
            rel="noopener noreferrer"
            className="w-full sm:w-auto inline-flex items-center justify-center gap-2 rounded-xl bg-slate-900 border border-slate-700 hover:bg-slate-800 text-slate-100 font-bold px-6 py-3.5 text-xs transition"
          >
            <Smartphone className="w-4 h-4 text-green-500" /> Google Play Store
          </Link>

          {/* Apple App Store */}
          <Link
            href="https://apps.apple.com/app/xapzap"
            target="_blank"
            rel="noopener noreferrer"
            className="w-full sm:w-auto inline-flex items-center justify-center gap-2 rounded-xl bg-slate-900 border border-slate-700 hover:bg-slate-800 text-slate-100 font-bold px-6 py-3.5 text-xs transition"
          >
            <Smartphone className="w-4 h-4 text-slate-400" /> Apple App Store
          </Link>
        </div>
      </section>

      {/* SEO-Optimized FAQ Section */}
      <section className="mt-20 border-t border-border pt-12 pb-12">
        <h2 className="text-2xl font-extrabold text-foreground text-center sm:text-3xl mb-8 flex items-center justify-center gap-2">
          <HelpCircle className="w-6 h-6 text-[#1DA1F2]" /> Frequently Asked Questions
        </h2>
        <div className="max-w-3xl mx-auto space-y-4">
          {[
            {
              q: 'How does the micro job verification work?',
              a: 'Every time you complete a task on the XapZap mobile app, our server registers the details. Depending on the task, it is either verified automatically or reviewed by community moderators within 24 hours.'
            },
            {
              q: 'Can I perform micro jobs using my web browser?',
              a: 'No. To prevent botting, ensure location checks, and protect against scraping, the micro jobs system requires the sandbox environment of the XapZap mobile app.'
            },
            {
              q: 'What is the minimum payout amount?',
              a: 'The payout minimum is extremely low (equivalent to $1.00 USD). You can withdraw accumulated coins into digital rewards or direct deposits in the app.'
            },
            {
              q: 'Are micro jobs available in all countries?',
              a: 'Yes, XapZap Micro Jobs are open globally! However, specific campaigns or tasks may be target-filtered based on regions, languages, or device types.'
            }
          ].map((item, idx) => (
            <details key={idx} className="group rounded-xl border border-border bg-card p-4 transition-all duration-300 [&_summary::-webkit-details-marker]:hidden">
              <summary className="flex items-center justify-between cursor-pointer focus:outline-none">
                <span className="font-bold text-sm text-foreground pr-4">
                  {item.q}
                </span>
                <span className="text-[#1DA1F2] shrink-0 font-bold text-lg select-none transition duration-300 group-open:rotate-45">
                  +
                </span>
              </summary>
              <p className="mt-3 text-xs text-muted-foreground leading-relaxed border-t border-border/40 pt-3">
                {item.a}
              </p>
            </details>
          ))}
        </div>
      </section>
    </main>
  )
}
