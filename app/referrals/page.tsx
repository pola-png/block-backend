'use client'

import { useEffect, useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import { ArrowLeft, Copy, Link as LinkIcon, Users } from 'lucide-react'
import appwriteService from '../../appwriteService'

type ReferralUser = {
  userId: string
  username: string
  displayName: string
  avatarUrl?: string
}

function getBaseUrl() {
  if (typeof window === 'undefined') return ''
  return window.location.origin
}

export default function ReferralsPage() {
  const router = useRouter()
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [referralCode, setReferralCode] = useState<string>('')
  const [referrals, setReferrals] = useState<ReferralUser[]>([])
  const [copied, setCopied] = useState(false)

  const referralLink = useMemo(() => {
    if (!referralCode) return ''
    const base = getBaseUrl()
    if (!base) return ''
    return `${base}/auth/signup?ref=${encodeURIComponent(referralCode)}`
  }, [referralCode])

  useEffect(() => {
    let mounted = true

    const load = async () => {
      try {
        setIsLoading(true)
        setError(null)

        const user = await appwriteService.getCurrentUser()
        if (!user) {
          router.push('/auth/signin')
          return
        }

        const profile = await appwriteService.getProfileByUserId(user.$id)
        const code = String(profile?.username || user.name || '').trim()
        if (!code) {
          setReferralCode(user.$id)
        } else {
          setReferralCode(code)
        }

        const result = await appwriteService.fetchReferralFollows(user.$id)
        if (!mounted) return

        setReferrals(result)
      } catch (err: any) {
        if (!mounted) return
        setError(err?.message || 'Failed to load referrals')
      } finally {
        if (!mounted) return
        setIsLoading(false)
      }
    }

    void load()

    return () => {
      mounted = false
    }
  }, [router])

  const handleCopy = async () => {
    if (!referralLink) return
    try {
      await navigator.clipboard.writeText(referralLink)
      setCopied(true)
      window.setTimeout(() => setCopied(false), 1500)
    } catch {
      // ignore
    }
  }

  return (
    <div className="min-h-screen bg-background">
      <div className="max-w-2xl mx-auto">
        <div className="flex items-center gap-3 p-4 border-b border-border">
          <button onClick={() => router.back()} className="p-2 hover:bg-accent rounded-full" aria-label="Back">
            <ArrowLeft size={24} />
          </button>
          <h1 className="text-xl font-bold">Referrals</h1>
        </div>

        <div className="p-4 space-y-5">
          <div className="rounded-xl border border-border bg-card p-4">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <p className="text-sm font-semibold text-foreground">Your referral link</p>
                <p className="mt-1 text-xs text-muted-foreground">Invite friends and grow your community.</p>
                <div className="mt-3 flex items-center gap-2 rounded-lg border border-border bg-background px-3 py-2">
                  <LinkIcon size={16} className="text-muted-foreground flex-shrink-0" />
                  <span className="text-sm text-foreground truncate">{referralLink || 'Loading…'}</span>
                </div>
              </div>
              <button
                onClick={handleCopy}
                disabled={!referralLink}
                className="inline-flex items-center gap-2 rounded-lg bg-primary px-3 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-50"
              >
                <Copy size={16} />
                {copied ? 'Copied' : 'Copy'}
              </button>
            </div>
          </div>

          <div className="rounded-xl border border-border bg-card p-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <Users size={18} className="text-muted-foreground" />
                <p className="text-sm font-semibold text-foreground">People you referred</p>
              </div>
              <p className="text-sm text-muted-foreground">{referrals.length}</p>
            </div>

            {isLoading ? (
              <p className="mt-3 text-sm text-muted-foreground">Loading…</p>
            ) : error ? (
              <p className="mt-3 text-sm text-red-600">{error}</p>
            ) : referrals.length === 0 ? (
              <p className="mt-3 text-sm text-muted-foreground">No referrals yet. Share your link to get started.</p>
            ) : (
              <div className="mt-3 space-y-2">
                {referrals.map((item) => (
                  <div key={item.userId} className="flex items-center gap-3 rounded-lg border border-border bg-background p-3">
                    {item.avatarUrl ? (
                      <img src={item.avatarUrl} alt={item.displayName} className="h-9 w-9 rounded-full object-cover" />
                    ) : (
                      <div className="h-9 w-9 rounded-full bg-muted flex items-center justify-center text-sm font-semibold">
                        {(item.displayName || item.username || 'U').slice(0, 1).toUpperCase()}
                      </div>
                    )}
                    <div className="min-w-0">
                      <p className="text-sm font-semibold text-foreground truncate">{item.displayName}</p>
                      <p className="text-xs text-muted-foreground truncate">@{item.username}</p>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          <div className="rounded-xl border border-border bg-card p-4">
            <p className="text-sm font-semibold text-foreground">How it works</p>
            <ol className="mt-2 list-decimal pl-5 text-sm text-muted-foreground space-y-1">
              <li>Share your referral link.</li>
              <li>Your friend signs up using your link.</li>
              <li>They will automatically follow you.</li>
            </ol>
          </div>
        </div>
      </div>
    </div>
  )
}

