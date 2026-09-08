import { NextRequest, NextResponse } from 'next/server'
import { Client, Account, Databases, Query, ID } from 'appwrite'

const client = new Client()
  .setEndpoint('https://nyc.cloud.appwrite.io/v1')
  .setProject('690641ad0029b51eefe0')

const account = new Account(client)
const databases = new Databases(client)

const databaseId = 'xapzap_db'
const collections = {
  comments: 'comments',
  commentLikes: 'comment_likes',
  posts: 'posts',
  profiles: 'profiles'
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

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const postId = searchParams.get('postId')
    const limit = parseInt(searchParams.get('limit') || '50')

    if (!postId) {
      return NextResponse.json(
        { error: 'Post ID is required' },
        { status: 400 }
      )
    }

    const comments = await databases.listDocuments(
      databaseId,
      collections.comments,
      [
        Query.equal('postId', postId),
        Query.orderDesc('createdAt'),
        Query.limit(limit)
      ]
    )

    return NextResponse.json(comments)

  } catch (error: any) {
    console.error('Fetch comments error:', error)

    return NextResponse.json(
      { error: error.message || 'Failed to fetch comments' },
      { status: 500 }
    )
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
    const { postId, content } = await request.json()

    if (!postId || !content?.trim()) {
      return NextResponse.json(
        { error: 'Post ID and content are required' },
        { status: 400 }
      )
    }

    // Get user profile for display info
    const profile = await databases.listDocuments(
      databaseId,
      collections.profiles,
      [
        Query.equal('userId', user.$id),
        Query.limit(1)
      ]
    )

    const userProfile = profile.documents.length > 0 ? profile.documents[0] : null
    const username = userProfile?.displayName || userProfile?.username || user.name || 'User'
    const avatar = userProfile?.avatarUrl || ''

    // Create comment
    const comment = await databases.createDocument(
      databaseId,
      collections.comments,
      ID.unique(),
      {
        postId,
        userId: user.$id,
        username,
        userAvatar: avatar,
        content: content.trim(),
        likes: 0,
        replies: 0,
        createdAt: new Date().toISOString()
      }
    )

    // Increment post comments count
    const post = await databases.getDocument(databaseId, collections.posts, postId)
    const currentComments = post.comments || 0
    await databases.updateDocument(
      databaseId,
      collections.posts,
      postId,
      { comments: currentComments + 1 }
    )

    return NextResponse.json({
      success: true,
      comment
    })

  } catch (error: any) {
    console.error('Create comment error:', error)

    return NextResponse.json(
      { error: error.message || 'Failed to create comment' },
      { status: 500 }
    )
  }
}

// Like/Unlike comment endpoint
export async function PATCH(request: NextRequest) {
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
    const { commentId } = await request.json()

    if (!commentId) {
      return NextResponse.json(
        { error: 'Comment ID is required' },
        { status: 400 }
      )
    }

    // Check if already liked
    const existingLikes = await databases.listDocuments(
      databaseId,
      collections.commentLikes,
      [
        Query.equal('userId', user.$id),
        Query.equal('commentId', commentId),
        Query.limit(1)
      ]
    )

    if (existingLikes.documents.length > 0) {
      // Unlike: Remove the like
      await databases.deleteDocument(
        databaseId,
        collections.commentLikes,
        existingLikes.documents[0].$id
      )

      // Decrement comment likes count
      const comment = await databases.getDocument(databaseId, collections.comments, commentId)
      const currentLikes = comment.likes || 0
      await databases.updateDocument(
        databaseId,
        collections.comments,
        commentId,
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
        collections.commentLikes,
        ID.unique(),
        {
          commentId,
          userId: user.$id,
          createdAt: new Date().toISOString()
        }
      )

      // Increment comment likes count
      const comment = await databases.getDocument(databaseId, collections.comments, commentId)
      const currentLikes = comment.likes || 0
      await databases.updateDocument(
        databaseId,
        collections.comments,
        commentId,
        { likes: currentLikes + 1 }
      )

      return NextResponse.json({
        success: true,
        action: 'liked',
        likes: currentLikes + 1
      })
    }

  } catch (error: any) {
    console.error('Like comment error:', error)

    return NextResponse.json(
      { error: error.message || 'Failed to toggle comment like' },
      { status: 500 }
    )
  }
}
