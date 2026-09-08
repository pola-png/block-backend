import { NextRequest, NextResponse } from 'next/server'
import { Account, Client, Databases, ID, Query } from 'appwrite'
import { isPaidPlan } from '../../../../../lib/billing'

const APPWRITE_ENDPOINT = 'https://nyc.cloud.appwrite.io/v1'
const APPWRITE_PROJECT = '690641ad0029b51eefe0'
const APPWRITE_DATABASE = 'xapzap_db'
const APPWRITE_PROFILES = 'profiles'

async function getAuthenticatedServices(request: NextRequest) {
  const authHeader = request.headers.get('authorization')
  const sessionToken = authHeader?.replace('Bearer ', '')
  if (!sessionToken) return null

  const authClient = new Client()
    .setEndpoint(APPWRITE_ENDPOINT)
    .setProject(APPWRITE_PROJECT)
    .setJWT(sessionToken)

  const account = new Account(authClient)
  const databases = new Databases(authClient)
  const user = await account.get()

  return { user, databases }
}

function parseMetadata(value: any): Record<string, any> {
  if (!value) return {}
  if (typeof value === 'object') return value
  if (typeof value === 'string') {
    try {
      const parsed = JSON.parse(value)
      return typeof parsed === 'object' && parsed ? parsed : {}
    } catch {
      return {}
    }
  }
  return {}
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

    const auth = await getAuthenticatedServices(request)
    if (!auth) {
      return NextResponse.json({ error: 'Authentication required' }, { status: 401 })
    }

    const body = await request.json().catch(() => ({}))
    const reference = String(body?.reference || body?.trxref || '').trim()
    if (!reference) {
      return NextResponse.json({ error: 'Payment reference is required.' }, { status: 400 })
    }

    const verifyResponse = await fetch(
      `https://api.paystack.co/transaction/verify/${encodeURIComponent(reference)}`,
      {
        method: 'GET',
        headers: {
          Authorization: `Bearer ${paystackSecretKey}`,
          'Content-Type': 'application/json',
        },
      }
    )

    const payload = await verifyResponse.json().catch(() => null)
    if (!verifyResponse.ok || !payload?.status || !payload?.data) {
      return NextResponse.json(
        { error: payload?.message || 'Unable to verify payment with Paystack.' },
        { status: 400 }
      )
    }

    const tx = payload.data
    const metadata = parseMetadata(tx.metadata)

    const paymentStatus = String(tx.status || '').toLowerCase()
    const paidAmountSubunit = Number(tx.amount || 0)
    const paidCurrency = String(tx.currency || '').toUpperCase()
    const expectedCurrency = String(metadata.expectedCurrency || '').toUpperCase()
    const expectedAmountSubunit = Number(metadata.expectedAmountSubunit || 0)
    const plan = String(metadata.plan || '').toLowerCase()
    const metadataUserId = String(metadata.userId || '')

    if (paymentStatus !== 'success') {
      return NextResponse.json({ error: 'Payment is not successful yet.' }, { status: 400 })
    }

    if (!isPaidPlan(plan)) {
      return NextResponse.json({ error: 'Invalid plan in payment metadata.' }, { status: 400 })
    }

    if (!metadataUserId || metadataUserId !== auth.user.$id) {
      return NextResponse.json(
        { error: 'This payment does not belong to the authenticated user.' },
        { status: 403 }
      )
    }

    if (
      !expectedCurrency ||
      paidCurrency !== expectedCurrency ||
      !expectedAmountSubunit ||
      paidAmountSubunit < expectedAmountSubunit
    ) {
      return NextResponse.json(
        { error: 'Payment validation failed (amount/currency mismatch).' },
        { status: 400 }
      )
    }

    const profileResult = await auth.databases.listDocuments(
      APPWRITE_DATABASE,
      APPWRITE_PROFILES,
      [Query.equal('userId', auth.user.$id), Query.limit(1)]
    )

    const profileUpdateData = {
      upgradeRequestedTier: plan,
      upgradeBillingCycle: 'monthly',
      upgradePaymentStatus: 'paid',
      upgradeApprovalStatus: 'pending',
      upgradeRequestedAt: new Date().toISOString(),
      upgradePaidAt: new Date().toISOString(),
      upgradePaymentReference: reference,
      upgradePaymentCurrency: paidCurrency,
      upgradePaymentAmountSubunit: paidAmountSubunit,
      upgradePaymentGateway: 'paystack',
    }

    if (profileResult.documents.length > 0) {
      const existingProfile = profileResult.documents[0] as any
      await auth.databases.updateDocument(
        APPWRITE_DATABASE,
        APPWRITE_PROFILES,
        existingProfile.$id,
        {
          userId: existingProfile.userId || auth.user.$id,
          username: existingProfile.username || auth.user.name || 'user',
          displayName: existingProfile.displayName || auth.user.name || 'User',
          ...profileUpdateData,
        }
      )
    } else {
      await auth.databases.createDocument(
        APPWRITE_DATABASE,
        APPWRITE_PROFILES,
        ID.unique(),
        {
          userId: auth.user.$id,
          username: auth.user.name || 'user',
          displayName: auth.user.name || 'User',
          ...profileUpdateData,
        }
      )
    }

    return NextResponse.json({
      verified: true,
      plan,
      billingCycle: 'monthly',
      requiresAdminApproval: true,
      reference,
      amountSubunit: paidAmountSubunit,
      currency: paidCurrency,
    })
  } catch (error: any) {
    return NextResponse.json(
      { error: error?.message || 'Failed to verify payment.' },
      { status: 500 }
    )
  }
}

