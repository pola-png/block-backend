import { NextRequest, NextResponse } from 'next/server'
import { Client, Account } from 'appwrite'

const client = new Client()
  .setEndpoint('https://nyc.cloud.appwrite.io/v1')
  .setProject('690641ad0029b51eefe0')

const account = new Account(client)

export async function POST(request: NextRequest) {
  try {
    const { email, password } = await request.json()

    if (!email || !password) {
      return NextResponse.json(
        { error: 'Email and password are required' },
        { status: 400 }
      )
    }

    // Create session
    const session = await account.createEmailPasswordSession(email, password)

    return NextResponse.json({
      success: true,
      session,
      user: {
        $id: session.userId,
        email: session.providerUid
      }
    })

  } catch (error: any) {
    console.error('Signin error:', error)

    return NextResponse.json(
      { error: error.message || 'Sign in failed' },
      { status: 401 }
    )
  }
}