import { NextRequest, NextResponse } from 'next/server'
import { Client, Account, Databases, Query, ID } from 'appwrite'

const client = new Client()
  .setEndpoint('https://nyc.cloud.appwrite.io/v1')
  .setProject('690641ad0029b51eefe0')

const account = new Account(client)
const databases = new Databases(client)

const databaseId = 'xapzap_db'
const collections = {
  likes: 'likes',
  posts: 'posts'
}

// Helper function to get authenticated services
async function getAuthenticatedServices(request: NextRequest) {
  // Get session token
  const authHeader = request.headers.get('authorization')
  const sessionToken = authHeader?.replace('Bearer ', '')

  if (!sessionToken) {
    return null
  }

  // Create authenticated client
  const authClient = new Client()
    .setEndpoint('https://nyc.cloud.appwrite.io/v1')
    .setProject('690641ad0029b51eefe0')
    .setJWT(sessionToken)

  const authAccount = new Account(authClient)
  const authDatabases = new Databases(authClient)

  // Verify user
  const user = await authAccount.get()

  return {
    user,
    databases: authDatabases
  }
}

export async function POST(request: NextRequest) {
  try {
    // Get authenticated services
    const auth = await getAuthenticatedServices(request)
    if (!auth) {
      return NextResponse.json(
        { error: 'Authentication required' },
        { status: 401 }
      )
    }

    const { user, databases } = auth
    const { postId } = await request.json()

    if (!postId) {
      return NextResponse.json(
        { error: 'Post ID is required' },
        { status: 400 }
      )
    }

    // Check if already liked
    const existingLikes = await databases.listDocuments(
      databaseId,
      collections.likes,
      [
        Query.equal('userId', user.$id),
        Query.equal('postId', postId),
        Query.limit(1)
      ]
    )

    if (existingLikes.documents.length > 0) {
      // Unlike: Remove the like
      await databases.deleteDocument(
        databaseId,
        collections.likes,
        existingLikes.documents[0].$id
      )

      // Decrement post likes count
      const post = await databases.getDocument(databaseId, collections.posts, postId)
      const currentLikes = post.likes || 0
      await databases.updateDocument(
        databaseId,
        collections.posts,
        postId,
        { likes: Math.max(0, currentLikes - 1) }
      )

      return NextResponse.json({
        success: true,
        action: 'unliked',
        likes: Math.max(0, currentLikes - 1)
      })
    } else {
      // Like: Create new like
      await databases.createDocument(
        databaseId,
        collections.likes,
        ID.unique(),
        {
          postId,
          userId: user.$id,
          createdAt: new Date().toISOString()
        }
      )

      // Increment post likes count
      const post = await databases.getDocument(databaseId, collections.posts, postId)
      const currentLikes = post.likes || 0
      await databases.updateDocument(
        databaseId,
        collections.posts,
        postId,
        { likes: currentLikes + 1 }
      )

      return NextResponse.json({
        success: true,
        action: 'liked',
        likes: currentLikes + 1
      })
    }

  } catch (error: any) {
    console.error('Like post error:', error)

    return NextResponse.json(
      { error: error.message || 'Failed to toggle like' },
      { status: 500 }
    )
  }
}
