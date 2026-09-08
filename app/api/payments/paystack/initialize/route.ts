import { NextRequest, NextResponse } from 'next/server'
import { Account, Client } from 'appwrite'
import {
  MONTHLY_PLAN_PRICE_USD,
  convertUsdToCurrency,
  detectCountryFromHeaders,
  fetchUsdRates,
  isPaidPlan,
  resolveCheckoutCurrency,
  toCurrencySubunit,
} from '../../../../../lib/billing'

const APPWRITE_ENDPOINT = 'https://nyc.cloud.appwrite.io/v1'
const APPWRITE_PROJECT = '690641ad0029b51eefe0'

async function getAuthenticatedUser(request: NextRequest) {
  const authHeader = request.headers.get('authorization')
  const sessionToken = authHeader?.replace('Bearer ', '')
  if (!sessionToken) return null

  const authClient = new Client()
    .setEndpoint(APPWRITE_ENDPOINT)
    .setProject(APPWRITE_PROJECT)
    .setJWT(sessionToken)

  const account = new Account(authClient)
  const user = await account.get()
  return user
}

export async function POST(request: NextRequest) {
  try {
    const paystackSecretKey = process.env.PAYSTACK_SECRET_KEY
    if (!paystackSecretKey) {
      return NextResponse.json(
        { error: 'PAYSTACK_SECRET_KEY is not configured on the server.' },
        { status: 500 }
      )
    }

    const user = await getAuthenticatedUser(request)
    if (!user) {
      return NextResponse.json({ error: 'Authentication required' }, { status: 401 })
    }

    const body = await request.json().catch(() => ({}))
    const plan = String(body?.plan || '').toLowerCase()
    if (!isPaidPlan(plan)) {
      return NextResponse.json({ error: 'Invalid plan selected.' }, { status: 400 })
    }

    const country = detectCountryFromHeaders(request.headers)
    const currencyData = resolveCheckoutCurrency(country)
    const rates = await fetchUsdRates()

    const convertedAmount = convertUsdToCurrency(
      MONTHLY_PLAN_PRICE_USD[plan],
      currencyData.checkoutCurrency,
      rates
    )
    const amountSubunit = toCurrencySubunit(convertedAmount)

    const reference = `xapzap-${plan}-${Date.now()}-${Math.random()
      .toString(36)
      .slice(2, 10)}`

    const appBaseUrl =
      process.env.NEXT_PUBLIC_APP_URL ||
      process.env.APP_URL ||
      request.nextUrl.origin

    const callbackUrl = `${appBaseUrl.replace(/\/$/, '')}/premium`

    const metadata = {
      userId: user.$id,
      plan,
      billingCycle: 'monthly',
      expectedCurrency: currencyData.checkoutCurrency,
      expectedAmountSubunit: amountSubunit,
      country: currencyData.country,
      usdBasePrice: MONTHLY_PLAN_PRICE_USD[plan],
    }

    const paystackResponse = await fetch('https://api.paystack.co/transaction/initialize', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${paystackSecretKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        email: user.email,
        amount: amountSubunit,
        currency: currencyData.checkoutCurrency,
        reference,
        callback_url: callbackUrl,
        metadata,
      }),
    })

    const payload = await paystackResponse.json().catch(() => null)
    if (!paystackResponse.ok || !payload?.status || !payload?.data?.authorization_url) {
      return NextResponse.json(
        { error: payload?.message || 'Failed to initialize Paystack payment.' },
        { status: 400 }
      )
    }

    return NextResponse.json({
      authorizationUrl: payload.data.authorization_url,
      accessCode: payload.data.access_code,
      reference: payload.data.reference || reference,
      currency: currencyData.checkoutCurrency,
      amount: convertedAmount,
      amountSubunit,
      plan,
      billingCycle: 'monthly',
    })
  } catch (error: any) {
    return NextResponse.json(
      { error: error?.message || 'Failed to initialize payment.' },
      { status: 500 }
    )
  }
}
