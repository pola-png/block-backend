import Link from 'next/link'
import type { ReactNode } from 'react'

type LegalSection = {
  title: string
  body: string
}

interface LegalPageProps {
  title: string
  eyebrow: string
  intro: string
  sections: LegalSection[]
  currentPath: '/privacy' | '/terms' | '/account-deletion' | '/safety-standards'
  children?: ReactNode
}

export function LegalPage({
  title,
  eyebrow,
  intro,
  sections,
  currentPath,
  children,
}: LegalPageProps) {
  return (
    <div className="min-h-screen bg-[rgb(var(--bg-primary))] text-[rgb(var(--text-primary))]">
      <div className="mx-auto max-w-4xl px-4 py-10 sm:px-6 lg:px-8">
        <div className="rounded-3xl border border-[rgb(var(--border-color))] bg-[rgb(var(--bg-primary))] shadow-sm">
          <div className="border-b border-[rgb(var(--border-color))] px-6 py-8 sm:px-8">
            <p className="text-sm font-semibold uppercase tracking-[0.18em] text-[#1DA1F2]">
              {eyebrow}
            </p>
            <h1 className="mt-3 text-3xl font-black tracking-tight sm:text-4xl">
              {title}
            </h1>
            <p className="mt-4 max-w-3xl text-sm leading-7 text-[rgb(var(--text-secondary))] sm:text-base">
              {intro}
            </p>
          </div>

          <div className="px-6 py-8 sm:px-8">
            <div className="space-y-7">
              {sections.map((section) => (
                <section key={section.title}>
                  <h2 className="text-lg font-bold sm:text-xl">{section.title}</h2>
                  <p className="mt-2 text-sm leading-7 text-[rgb(var(--text-secondary))] sm:text-base">
                    {section.body}
                  </p>
                </section>
              ))}
            </div>

            {children ? <div className="mt-8">{children}</div> : null}

            <div className="mt-10 border-t border-[rgb(var(--border-color))] pt-6">
              <p className="text-sm font-semibold text-[rgb(var(--text-primary))]">
                Related legal pages
              </p>
              <div className="mt-4 flex flex-wrap gap-3">
                <LegalLink href="/privacy" currentPath={currentPath}>
                  Privacy Policy
                </LegalLink>
                <LegalLink href="/terms" currentPath={currentPath}>
                  Terms of Service
                </LegalLink>
                <LegalLink href="/account-deletion" currentPath={currentPath}>
                  Account Deletion
                </LegalLink>
                <LegalLink href="/safety-standards" currentPath={currentPath}>
                  Safety Standards
                </LegalLink>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

function LegalLink({
  href,
  currentPath,
  children,
}: {
  href: '/privacy' | '/terms' | '/account-deletion' | '/safety-standards'
  currentPath: '/privacy' | '/terms' | '/account-deletion' | '/safety-standards'
  children: ReactNode
}) {
  const active = href === currentPath
  return (
    <Link
      href={href}
      className={`rounded-full border px-4 py-2 text-sm font-semibold transition ${
        active
          ? 'border-[#1DA1F2] bg-[#1DA1F2] text-white'
          : 'border-[rgb(var(--border-color))] text-[rgb(var(--text-primary))] hover:border-[#1DA1F2] hover:text-[#1DA1F2]'
      }`}
      aria-current={active ? 'page' : undefined}
    >
      {children}
    </Link>
  )
}
