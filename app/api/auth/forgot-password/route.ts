import { NextRequest, NextResponse } from 'next/server'
import { Client, Account } from 'appwrite'

const client = new Client()
  .setEndpoint('https://nyc.cloud.appwrite.io/v1')
  .setProject('690641ad0029b51eefe0')

const account = new Account(client)

export async function POST(request: NextRequest) {
  try {
    const { email } = await request.json()

    if (!email) {
      return NextResponse.json(
        { error: 'Email is required' },
        { status: 400 }
      )
    }

    // Send password reset email
    await account.createRecovery(email, `${process.env.NEXT_PUBLIC_APP_URL || 'http://localhost:3000'}/auth/reset-password`)

    return NextResponse.json({
      success: true,
      message: 'Password reset link sent to your email'
    })

  } catch (error: any) {
    console.error('Forgot password error:', error)

    return NextResponse.json(
      { error: error.message || 'Failed to send password reset email' },
      { status: 400 }
    )
  }
}