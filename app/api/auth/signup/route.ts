import { NextRequest, NextResponse } from 'next/server'
import { Client, Account, Databases, ID } from 'appwrite'

const client = new Client()
  .setEndpoint('https://nyc.cloud.appwrite.io/v1')
  .setProject('690641ad0029b51eefe0')

const account = new Account(client)
const databases = new Databases(client)

const databaseId = 'xapzap_db'
const collections = {
  users: 'users',
  profiles: 'profiles'
}

export async function POST(request: NextRequest) {
  try {
    const { email, password, username, displayName } = await request.json()

    if (!email || !password || !username) {
      return NextResponse.json(
        { error: 'Email, password, and username are required' },
        { status: 400 }
      )
    }

    // Validate username format
    if (!/^[a-zA-Z0-9_]+$/.test(username.replace(/^@/, ''))) {
      return NextResponse.json(
        { error: 'Username can only contain letters, numbers, and underscores' },
        { status: 400 }
      )
    }

    // Create account
    await account.create(
      ID.unique(),
      email,
      password,
      username
    )

    // Sign in immediately
    const session = await account.createEmailPasswordSession(email, password)

    // Get the created user
    const user = await account.get()

    // Create user record in users collection
    await databases.createDocument(
      databaseId,
      collections.users,
      user.$id,
      {
        userId: user.$id,
        username,
        email
      }
    )

    // Create profile record
    await databases.createDocument(
      databaseId,
      collections.profiles,
      user.$id,
      {
        userId: user.$id,
        username,
        displayName: displayName || username,
        bio: '',
        avatarUrl: '',
        coverUrl: '',
        isAdmin: false,
        isBanned: false
      }
    )

    return NextResponse.json({
      success: true,
      session,
      user: {
        $id: user.$id,
        email: user.email,
        name: user.name
      }
    })

  } catch (error: any) {
    console.error('Signup error:', error)

    return NextResponse.json(
      { error: error.message || 'Sign up failed' },
      { status: 400 }
    )
  }
}