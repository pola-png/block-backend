import { NextRequest, NextResponse } from 'next/server'
import { createHmac, timingSafeEqual } from 'crypto'
import { isPaidPlan } from '../../../../../lib/billing'

const APPWRITE_ENDPOINT = 'https://nyc.cloud.appwrite.io/v1'
const APPWRITE_PROJECT = '690641ad0029b51eefe0'
const APPWRITE_DATABASE = 'xapzap_db'
const APPWRITE_PROFILES = 'profiles'

export const runtime = 'nodejs'

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

function verifyPaystackSignature(rawBody: string, signature: string, secretKey: string): boolean {
  const computedHash = createHmac('sha512', secretKey).update(rawBody).digest('hex')

  const incomingBuffer = Buffer.from(signature, 'utf8')
  const computedBuffer = Buffer.from(computedHash, 'utf8')
  if (incomingBuffer.length !== computedBuffer.length) return false

  return timingSafeEqual(incomingBuffer, computedBuffer)
}

function getAppwriteHeaders() {
  const apiKey = process.env.APPWRITE_API_KEY
  if (!apiKey) {
    throw new Error('APPWRITE_API_KEY is not configured on the server.')
  }
  return {
    'Content-Type': 'application/json',
    'X-Appwrite-Project': APPWRITE_PROJECT,
    'X-Appwrite-Key': apiKey,
  }
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

    const signature = String(request.headers.get('x-paystack-signature') || '')
    if (!signature) {
      return NextResponse.json({ error: 'Missing Paystack signature.' }, { status: 401 })
    }

    const rawBody = await request.text()
    if (!verifyPaystackSignature(rawBody, signature, paystackSecretKey)) {
      return NextResponse.json({ error: 'Invalid Paystack signature.' }, { status: 401 })
    }

    const payload = JSON.parse(rawBody || '{}')
    const eventType = String(payload?.event || '').toLowerCase()
    if (eventType !== 'charge.success') {
      return NextResponse.json({ received: true, ignored: true })
    }

    const tx = payload?.data || {}
    const metadata = parseMetadata(tx.metadata)
    const paymentStatus = String(tx.status || '').toLowerCase()
    const paidAmountSubunit = Number(tx.amount || 0)
    const paidCurrency = String(tx.currency || '').toUpperCase()
    const expectedCurrency = String(metadata.expectedCurrency || '').toUpperCase()
    const expectedAmountSubunit = Number(metadata.expectedAmountSubunit || 0)
    const plan = String(metadata.plan || '').toLowerCase()
    const userId = String(metadata.userId || '').trim()
    const reference = String(tx.reference || '').trim()

    if (paymentStatus !== 'success') {
      return NextResponse.json({ received: true, ignored: true, reason: 'status_not_success' })
    }

    if (!isPaidPlan(plan) || !userId || !reference) {
      return NextResponse.json({ received: true, ignored: true, reason: 'invalid_metadata' })
    }

    if (
      !expectedCurrency ||
      paidCurrency !== expectedCurrency ||
      !expectedAmountSubunit ||
      paidAmountSubunit < expectedAmountSubunit
    ) {
      return NextResponse.json({ received: true, ignored: true, reason: 'amount_or_currency_mismatch' })
    }

    const appwriteHeaders = getAppwriteHeaders()
    const listUrl = new URL(
      `${APPWRITE_ENDPOINT}/databases/${APPWRITE_DATABASE}/collections/${APPWRITE_PROFILES}/documents`
    )
    listUrl.searchParams.append('queries[]', `equal("userId",["${userId}"])`)
    listUrl.searchParams.append('queries[]', 'limit(1)')

    const listResponse = await fetch(listUrl.toString(), {
      method: 'GET',
      headers: appwriteHeaders,
      cache: 'no-store',
    })
    const profilesResult = await listResponse.json().catch(() => ({ documents: [] }))
    if (!listResponse.ok) {
      throw new Error(profilesResult?.message || 'Failed to query profile during webhook sync.')
    }

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

    if (profilesResult.documents.length > 0) {
      const existingProfile = profilesResult.documents[0] as any

      if (
        String(existingProfile.upgradePaymentReference || '') === reference &&
        String(existingProfile.upgradePaymentStatus || '').toLowerCase() === 'paid'
      ) {
        return NextResponse.json({ received: true, processed: true, duplicate: true })
      }

      const updateResponse = await fetch(
        `${APPWRITE_ENDPOINT}/databases/${APPWRITE_DATABASE}/collections/${APPWRITE_PROFILES}/documents/${existingProfile.$id}`,
        {
          method: 'PATCH',
          headers: appwriteHeaders,
          body: JSON.stringify({
            data: {
              userId: existingProfile.userId || userId,
              username: existingProfile.username || `user_${userId.slice(0, 10)}`,
              displayName: existingProfile.displayName || 'User',
              ...profileUpdateData,
            },
          }),
        }
      )
      if (!updateResponse.ok) {
        const updatePayload = await updateResponse.json().catch(() => null)
        throw new Error(updatePayload?.message || 'Failed to update profile from webhook.')
      }
    } else {
      const createResponse = await fetch(
        `${APPWRITE_ENDPOINT}/databases/${APPWRITE_DATABASE}/collections/${APPWRITE_PROFILES}/documents`,
        {
          method: 'POST',
          headers: appwriteHeaders,
          body: JSON.stringify({
            documentId: 'unique()',
            data: {
              userId,
              username: `user_${userId.slice(0, 10)}`,
              displayName: 'User',
              ...profileUpdateData,
            },
          }),
        }
      )
      if (!createResponse.ok) {
        const createPayload = await createResponse.json().catch(() => null)
        throw new Error(createPayload?.message || 'Failed to create profile from webhook.')
      }
    }

    return NextResponse.json({
      received: true,
      processed: true,
      reference,
      plan,
    })
  } catch (error: any) {
    return NextResponse.json(
      { error: error?.message || 'Failed to process Paystack webhook.' },
      { status: 500 }
    )
  }
}
