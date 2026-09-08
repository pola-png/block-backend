import { CreatorPlan } from './creator-plan'

type PaidPlan = Exclude<CreatorPlan, 'free'>

export const MONTHLY_PLAN_PRICE_USD: Record<PaidPlan, number> = {
  basic: 2.5,
  business: 5,
}

export const PAYSTACK_SUPPORTED_CURRENCIES = new Set([
  'NGN',
  'USD',
  'GHS',
  'ZAR',
  'KES',
  'XOF',
])

const COUNTRY_TO_CURRENCY: Record<string, string> = {
  NG: 'NGN',
  GH: 'GHS',
  ZA: 'ZAR',
  KE: 'KES',
  CI: 'XOF',
  US: 'USD',
  GB: 'USD',
  CA: 'USD',
  AU: 'USD',
  FR: 'USD',
  DE: 'USD',
  ES: 'USD',
  IT: 'USD',
  IN: 'USD',
  AE: 'USD',
  SA: 'USD',
}

const FALLBACK_COUNTRY = 'US'
const FALLBACK_CURRENCY = 'USD'

type CachedRates = {
  updatedAt: number
  rates: Record<string, number>
}

let cachedUsdRates: CachedRates | null = null

export function detectCountryFromHeaders(headers: Headers): string {
  const candidates = [
    headers.get('x-vercel-ip-country'),
    headers.get('cf-ipcountry'),
    headers.get('x-country-code'),
    headers.get('x-appengine-country'),
  ]

  for (const value of candidates) {
    const normalized = String(value || '').trim().toUpperCase()
    if (normalized.length === 2) {
      return normalized
    }
  }

  return FALLBACK_COUNTRY
}

export function resolveCheckoutCurrency(countryCode: string) {
  const country = String(countryCode || FALLBACK_COUNTRY).toUpperCase()
  const countryCurrency = COUNTRY_TO_CURRENCY[country] || FALLBACK_CURRENCY
  const checkoutCurrency = PAYSTACK_SUPPORTED_CURRENCIES.has(countryCurrency)
    ? countryCurrency
    : FALLBACK_CURRENCY

  return {
    country,
    countryCurrency,
    checkoutCurrency,
    usedFallbackCurrency: checkoutCurrency !== countryCurrency,
  }
}

export async function fetchUsdRates(): Promise<Record<string, number>> {
  const now = Date.now()
  const ttlMs = 15 * 60 * 1000

  if (cachedUsdRates && now - cachedUsdRates.updatedAt < ttlMs) {
    return cachedUsdRates.rates
  }

  try {
    const response = await fetch('https://open.er-api.com/v6/latest/USD', {
      method: 'GET',
      cache: 'no-store',
    })

    if (!response.ok) {
      throw new Error(`Rate request failed with ${response.status}`)
    }

    const payload = await response.json()
    const rates = payload?.rates
    if (!rates || typeof rates !== 'object') {
      throw new Error('Invalid rate payload')
    }

    cachedUsdRates = {
      updatedAt: now,
      rates,
    }
    return rates
  } catch {
    const fallbackRates = {
      USD: 1,
      NGN: 1800,
      GHS: 15,
      ZAR: 18,
      KES: 130,
      XOF: 600,
    }
    cachedUsdRates = {
      updatedAt: now,
      rates: fallbackRates,
    }
    return fallbackRates
  }
}

export function convertUsdToCurrency(usdAmount: number, currency: string, rates: Record<string, number>) {
  const rate = Number(rates[currency] || 1)
  const raw = usdAmount * (Number.isFinite(rate) && rate > 0 ? rate : 1)
  return Math.round(raw * 100) / 100
}

export function toCurrencySubunit(amount: number): number {
  return Math.round(amount * 100)
}

export function formatCurrency(amount: number, currency: string, locale = 'en-US') {
  try {
    return new Intl.NumberFormat(locale, {
      style: 'currency',
      currency,
      maximumFractionDigits: 2,
    }).format(amount)
  } catch {
    return `${currency} ${amount.toFixed(2)}`
  }
}

export function isPaidPlan(plan: string): plan is PaidPlan {
  return plan === 'basic' || plan === 'business'
}

