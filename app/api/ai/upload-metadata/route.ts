import { NextRequest, NextResponse } from 'next/server'
import { Account, Client, Databases, Query } from 'appwrite'
import { resolveCreatorPlan } from '../../../../lib/creator-plan'

type AiUploadRequest = {
  postType?: string
  title?: string
  description?: string
  content?: string
  seoTitle?: string
  seoDescription?: string
  seoKeywords?: string
  seoCategory?: string
  aiBrief?: string
  aiAudience?: string
  aiFocusKeywords?: string
}

type AiUploadResponse = {
  title: string
  description: string
  seoTitle: string
  seoDescription: string
  seoKeywords: string
  seoCategory: string
}

const APPWRITE_ENDPOINT = 'https://nyc.cloud.appwrite.io/v1'
const APPWRITE_PROJECT_ID = '690641ad0029b51eefe0'
const APPWRITE_DATABASE_ID = 'xapzap_db'
const APPWRITE_PROFILES_COLLECTION = 'profiles'

function stripCodeFence(input: string) {
  const trimmed = input.trim()
  if (!trimmed.startsWith('```')) return trimmed
  return trimmed
    .replace(/^```[a-zA-Z]*\n?/, '')
    .replace(/```$/, '')
    .trim()
}

function normalizeKeywords(value: string) {
  return value
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean)
    .slice(0, 12)
    .join(', ')
}

function sanitizeAiResponse(raw: Partial<AiUploadResponse>): AiUploadResponse {
  return {
    title: String(raw.title || '').trim().slice(0, 120),
    description: String(raw.description || '').trim().slice(0, 1200),
    seoTitle: String(raw.seoTitle || '').trim().slice(0, 70),
    seoDescription: String(raw.seoDescription || '').trim().slice(0, 170),
    seoKeywords: normalizeKeywords(String(raw.seoKeywords || '')),
    seoCategory: String(raw.seoCategory || '').trim().slice(0, 60),
  }
}

function buildPrompt(payload: AiUploadRequest) {
  const context = [
    `Post type: ${payload.postType || 'video'}`,
    `Current title: ${payload.title || ''}`,
    `Current description: ${payload.description || ''}`,
    `Current caption/content: ${payload.content || ''}`,
    `Current SEO title: ${payload.seoTitle || ''}`,
    `Current SEO description: ${payload.seoDescription || ''}`,
    `Current SEO keywords: ${payload.seoKeywords || ''}`,
    `Current SEO category: ${payload.seoCategory || ''}`,
    `AI brief (main guidance): ${payload.aiBrief || ''}`,
    `Target audience: ${payload.aiAudience || ''}`,
    `Focus keywords: ${payload.aiFocusKeywords || ''}`,
  ].join('\n')

  return [
    'You are an expert social video copywriter and SEO strategist.',
    'Generate high-quality metadata for a short-form social video upload.',
    'Requirements:',
    '- Keep language natural, non-spammy, and click-worthy.',
    '- Follow the AI brief and audience details strictly when they are provided.',
    '- Use focus keywords naturally when relevant.',
    '- Title should be clear and engaging.',
    '- Description should be rich, helpful, and include context without keyword stuffing.',
    '- SEO title should be concise and ranking-friendly.',
    '- SEO description should be around 140-160 chars where possible.',
    '- SEO keywords should be comma-separated and relevant.',
    '- SEO category should be short and broad.',
    '- Return ONLY valid JSON with keys: title, description, seoTitle, seoDescription, seoKeywords, seoCategory.',
    '',
    'Input:',
    context,
  ].join('\n')
}

export async function POST(request: NextRequest) {
  const apiKey = process.env.GEMINI_API_KEY || ''
  const model = process.env.GEMINI_MODEL || 'gemini-2.5-flash'

  if (!apiKey) {
    return NextResponse.json({ error: 'Missing GEMINI_API_KEY' }, { status: 500 })
  }

  const authHeader = request.headers.get('authorization')
  const sessionToken = authHeader?.replace('Bearer ', '').trim()
  if (!sessionToken) {
    return NextResponse.json({ error: 'Authentication required.' }, { status: 401 })
  }

  const authClient = new Client()
    .setEndpoint(APPWRITE_ENDPOINT)
    .setProject(APPWRITE_PROJECT_ID)
    .setJWT(sessionToken)

  const authAccount = new Account(authClient)
  const authDatabases = new Databases(authClient)

  let user: any = null
  let profile: any = null
  let isAdmin = false
  let plan: string = 'free'

  try {
    user = await authAccount.get()
    const profileResult = await authDatabases.listDocuments(
      APPWRITE_DATABASE_ID,
      APPWRITE_PROFILES_COLLECTION,
      [Query.equal('userId', user.$id), Query.limit(1)]
    )
    profile = profileResult.documents[0] || null
    isAdmin = Boolean(profile?.isAdmin)
    plan = resolveCreatorPlan(profile, isAdmin)
  } catch {
    return NextResponse.json({ error: 'Invalid authentication.' }, { status: 401 })
  }

  if (!isAdmin && plan !== 'business') {
    return NextResponse.json(
      { error: 'AI and SEO tools are available only for Admin and Business plans.' },
      { status: 403 }
    )
  }

  let body: AiUploadRequest
  try {
    body = (await request.json()) as AiUploadRequest
  } catch {
    return NextResponse.json({ error: 'Invalid JSON payload.' }, { status: 400 })
  }

  const postType = String(body.postType || '').trim().toLowerCase()
  if (postType !== 'video' && postType !== 'reel') {
    return NextResponse.json({ error: 'AI metadata supports only video and reel.' }, { status: 400 })
  }

  const prompt = buildPrompt(body)
  const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`

  try {
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        generationConfig: {
          temperature: 0.7,
          responseMimeType: 'application/json',
        },
        contents: [
          {
            role: 'user',
            parts: [{ text: prompt }],
          },
        ],
      }),
      cache: 'no-store',
    })

    if (!response.ok) {
      const errorText = await response.text()
      return NextResponse.json(
        { error: `Gemini request failed: ${response.status}`, details: errorText.slice(0, 500) },
        { status: 502 }
      )
    }

    const geminiPayload = await response.json()
    const rawText =
      geminiPayload?.candidates?.[0]?.content?.parts?.[0]?.text ||
      geminiPayload?.candidates?.[0]?.output ||
      ''

    if (!rawText) {
      return NextResponse.json({ error: 'Gemini returned empty content.' }, { status: 502 })
    }

    let parsed: Partial<AiUploadResponse> = {}
    try {
      parsed = JSON.parse(stripCodeFence(rawText))
    } catch {
      return NextResponse.json({ error: 'Gemini returned non-JSON content.' }, { status: 502 })
    }

    const sanitized = sanitizeAiResponse(parsed)
    return NextResponse.json(sanitized, { status: 200 })
  } catch (error: any) {
    return NextResponse.json(
      {
        error: 'Gemini metadata generation failed.',
        details: error?.message || 'Unknown error',
      },
      { status: 502 }
    )
  }
}
