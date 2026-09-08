'use client'

import { useCallback, useEffect, useState } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import appwriteService from '../../appwriteService'
import { CreatorPlan, resolveCreatorPlan } from '../../lib/creator-plan'

type PaidPlan = Exclude<CreatorPlan, 'free'>

type PricingPayload = {
  currency: string
  country: string
  countryCurrency: string
  usedFallbackCurrency: boolean
  monthly: {
    basic: number
    business: number
  }
  formatted: {
    basic: string
    business: string
  }
}

const EMPTY_PRICING: PricingPayload = {
  currency: 'USD',
  country: 'US',
  countryCurrency: 'USD',
  usedFallbackCurrency: false,
  monthly: { basic: 2.5, business: 5 },
  formatted: { basic: '$2.50', business: '$5.00' },
}

export default function PremiumPage() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const [currentPlan, setCurrentPlan] = useState<CreatorPlan>('free')
  const [loading, setLoading] = useState(true)
  const [updatingPlan, setUpdatingPlan] = useState<PaidPlan | null>(null)
  const [requestStatus, setRequestStatus] = useState<'none' | 'pending' | 'approved' | 'rejected'>('none')
  const [requestedTier, setRequestedTier] = useState<CreatorPlan>('free')
  const [pricing, setPricing] = useState<PricingPayload>(EMPTY_PRICING)
  const [pricingLoading, setPricingLoading] = useState(true)
  const [verifyingPayment, setVerifyingPayment] = useState(false)

  const loadPlan = useCallback(async () => {
    setLoading(true)
    try {
      const user = await appwriteService.getCurrentUser()
      if (!user) {
        setCurrentPlan('free')
        setRequestStatus('none')
        setRequestedTier('free')
        return
      }

      const [isAdmin, profile] = await Promise.all([
        appwriteService.isCurrentUserAdmin().catch(() => false),
        appwriteService.getProfileByUserId(user.$id),
      ])

      setCurrentPlan(resolveCreatorPlan(profile, isAdmin))

      const approval = String((profile as any)?.upgradeApprovalStatus || '').toLowerCase()
      if (approval === 'pending' || approval === 'approved' || approval === 'rejected') {
        setRequestStatus(approval)
      } else {
        setRequestStatus('none')
      }

      const requested = String((profile as any)?.upgradeRequestedTier || '').toLowerCase()
      if (requested === 'basic' || requested === 'business') {
        setRequestedTier(requested as CreatorPlan)
      } else {
        setRequestedTier('free')
      }
    } catch {
      setCurrentPlan('free')
      setRequestStatus('none')
      setRequestedTier('free')
    } finally {
      setLoading(false)
    }
  }, [])

  const loadPricing = useCallback(async () => {
    setPricingLoading(true)
    try {
      const response = await fetch('/api/payments/paystack/pricing', {
        method: 'GET',
        cache: 'no-store',
      })
      const payload = await response.json().catch(() => null)
      if (!response.ok || !payload) {
        throw new Error(payload?.error || 'Failed to load pricing')
      }
      setPricing(payload)
    } catch {
      setPricing(EMPTY_PRICING)
    } finally {
      setPricingLoading(false)
    }
  }, [])

  useEffect(() => {
    void loadPlan()
    void loadPricing()
  }, [loadPlan, loadPricing])

  useEffect(() => {
    const reference = searchParams.get('reference') || searchParams.get('trxref')
    if (!reference) return

    let isMounted = true
    const verifyPayment = async () => {
      try {
        setVerifyingPayment(true)
        const user = await appwriteService.getCurrentUser()
        if (!user) {
          router.replace('/auth/signin')
          return
        }

        const jwt = await appwriteService.createJWT()
        const response = await fetch('/api/payments/paystack/verify', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${jwt.jwt}`,
          },
          body: JSON.stringify({ reference }),
        })
        const payload = await response.json().catch(() => null)
        if (!response.ok) {
          throw new Error(payload?.error || 'Payment verification failed.')
        }

        if (isMounted) {
          alert('Payment verified successfully. Your upgrade is being processed.')
          await loadPlan()
          router.replace('/premium')
        }
      } catch (error: any) {
        if (isMounted) {
          alert(error?.message || 'Unable to verify payment at the moment.')
          router.replace('/premium')
        }
      } finally {
        if (isMounted) {
          setVerifyingPayment(false)
        }
      }
    }

    void verifyPayment()
    return () => {
      isMounted = false
    }
  }, [loadPlan, router, searchParams])

  const startCheckout = async (plan: PaidPlan) => {
    try {
      const user = await appwriteService.getCurrentUser()
      if (!user) {
        router.push('/auth/signin')
        return
      }

      if (requestStatus === 'pending') {
        alert('Your previous upgrade request is still processing.')
        return
      }

      setUpdatingPlan(plan)
      const jwt = await appwriteService.createJWT()
      const response = await fetch('/api/payments/paystack/initialize', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${jwt.jwt}`,
        },
        body: JSON.stringify({ plan }),
      })
      const payload = await response.json().catch(() => null)
      if (!response.ok || !payload?.authorizationUrl) {
        throw new Error(payload?.error || 'Unable to start payment.')
      }

      window.location.assign(payload.authorizationUrl)
    } catch (error: any) {
      alert(error?.message || 'Failed to start payment. Please try again.')
    } finally {
      setUpdatingPlan(null)
    }
  }

  return (
    <div className="min-h-screen bg-[rgb(var(--bg-primary))] px-4 py-8">
      <div className="mx-auto max-w-5xl">
        <h1 className="text-3xl font-bold text-[rgb(var(--text-primary))] sm:text-4xl">
          Creator Plans
        </h1>
        <p className="mt-3 text-sm text-[rgb(var(--text-secondary))] sm:text-base">
          Monthly plans. Basic is $2.5/month, Business is $5/month.
        </p>

        <div className="mt-6 rounded-xl border border-border/60 bg-card p-4 text-sm text-[rgb(var(--text-secondary))]">
          Current plan:{' '}
          <span className="font-semibold text-[rgb(var(--text-primary))]">
            {loading ? 'Loading...' : currentPlan === 'business' ? 'Business' : currentPlan === 'basic' ? 'Basic' : 'Free'}
          </span>
          {verifyingPayment && (
            <div className="mt-2 text-blue-600 dark:text-blue-400">
              Verifying payment...
            </div>
          )}
          {requestStatus === 'pending' && requestedTier !== 'free' && (
            <div className="mt-2 text-amber-600 dark:text-amber-400">
              Upgrade request pending: {requestedTier === 'business' ? 'Business' : 'Basic'} (processing)
            </div>
          )}
        </div>

        <div className="mt-6 grid grid-cols-1 gap-4 md:grid-cols-2">
          <div className="rounded-2xl border border-border/70 bg-card p-6">
            <h2 className="text-2xl font-bold text-[rgb(var(--text-primary))]">Basic</h2>
            <p className="mt-2 text-lg font-semibold text-[rgb(var(--text-primary))]">
              {pricingLoading ? 'Loading price...' : `${pricing.formatted.basic} / month`}
            </p>
            <p className="mt-2 text-sm text-[rgb(var(--text-secondary))]">
              For creators who want monetization-ready content posting.
            </p>
            <ul className="mt-4 list-disc space-y-2 pl-5 text-sm text-[rgb(var(--text-secondary))]">
              <li>Post photo and text content</li>
              <li>Post video content</li>
              <li>Post reels</li>
            </ul>
            <button
              onClick={() => startCheckout('basic')}
              disabled={loading || pricingLoading || verifyingPayment || updatingPlan !== null || currentPlan === 'basic' || requestStatus === 'pending'}
              className="mt-6 rounded-full bg-primary px-5 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-50"
            >
              {currentPlan === 'basic'
                ? 'Active Plan'
                : requestStatus === 'pending' && requestedTier === 'basic'
                  ? 'Processing Upgrade...'
                  : updatingPlan === 'basic'
                    ? 'Redirecting...'
                    : 'Pay & Activate Basic'}
            </button>
          </div>

          <div className="rounded-2xl border border-border/70 bg-card p-6">
            <h2 className="text-2xl font-bold text-[rgb(var(--text-primary))]">Business</h2>
            <p className="mt-2 text-lg font-semibold text-[rgb(var(--text-primary))]">
              {pricingLoading ? 'Loading price...' : `${pricing.formatted.business} / month`}
            </p>
            <p className="mt-2 text-sm text-[rgb(var(--text-secondary))]">
              For creators and brands who need all upload features.
            </p>
            <ul className="mt-4 list-disc space-y-2 pl-5 text-sm text-[rgb(var(--text-secondary))]">
              <li>Everything in Basic</li>
              <li>Post news/articles (4th upload type)</li>
              <li>Full creator upload access</li>
            </ul>
            <button
              onClick={() => startCheckout('business')}
              disabled={loading || pricingLoading || verifyingPayment || updatingPlan !== null || currentPlan === 'business' || requestStatus === 'pending'}
              className="mt-6 rounded-full bg-primary px-5 py-2 text-sm font-semibold text-primary-foreground disabled:opacity-50"
            >
              {currentPlan === 'business'
                ? 'Active Plan'
                : requestStatus === 'pending' && requestedTier === 'business'
                  ? 'Processing Upgrade...'
                  : updatingPlan === 'business'
                    ? 'Redirecting...'
                    : 'Pay & Activate Business'}
            </button>
          </div>
        </div>

        <p className="mt-6 text-xs text-[rgb(var(--text-secondary))]">
          Payments are securely processed. Your plan will activate once verification is complete.
        </p>
      </div>
    </div>
  )
}

