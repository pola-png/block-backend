import { NextRequest, NextResponse } from 'next/server'
import { Client, Account, Databases, Query } from 'appwrite'

const client = new Client()
  .setEndpoint('https://nyc.cloud.appwrite.io/v1')
  .setProject('690641ad0029b51eefe0')

const account = new Account(client)
const databases = new Databases(client)

const databaseId = 'xapzap_db'
const collections = {
  posts: 'posts',
  follows: 'follows'
}

// Helper function to get current user from session
async function getCurrentUser() {
  try {
    return await account.get()
  } catch {
    return null
  }
}

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const feedType = searchParams.get('type') || 'home'
    const limit = parseInt(searchParams.get('limit') || '20')
    const cursor = searchParams.get('cursor')

    let queries: any[] = []
    let result

    switch (feedType) {
      case 'home':
        // For You feed - personalized mix
        const sevenDaysAgo = new Date()
        sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7)

        queries = [
          Query.greaterThanEqual('$createdAt', sevenDaysAgo.toISOString()),
          Query.limit(limit * 2) // Get more to filter/score
        ]
        if (cursor) queries.push(Query.cursorAfter(cursor))

        result = await databases.listDocuments(
          databaseId,
          collections.posts,
          queries
        )

        // Score posts based on engagement and recency
        const scoredPosts = result.documents.map(post => {
          const ageInHours = (Date.now() - new Date(post.$createdAt).getTime()) / (1000 * 60 * 60)
          const engagement = (post.likes || 0) + (post.comments || 0) * 2 + (post.reposts || 0) * 3 + (post.views || 0) * 0.1
          const recencyScore = Math.max(0, 24 - ageInHours) // Higher score for newer posts
          const totalScore = engagement + recencyScore

          return { ...post, score: totalScore }
        })

        // Sort by score and return top posts
        scoredPosts.sort((a, b) => b.score - a.score)
        result = {
          ...result,
          documents: scoredPosts.slice(0, limit)
        }
        break

      case 'watch':
        // Watch feed - normal resolution video posts by engagement
        queries = [
          Query.or([
            Query.equal('kind', 'video'),
            Query.equal('postType', 'video')
          ]),
          Query.limit(limit * 3) // Get more to sort by engagement
        ]
        if (cursor) queries.push(Query.cursorAfter(cursor))

        result = await databases.listDocuments(
          databaseId,
          collections.posts,
          queries
        )

        // Filter for posts that have video content (excluding reels)
        const videoPosts = result.documents.filter(post =>
          (post.videoUrl || (post.mediaUrls && post.mediaUrls.length > 0) || post.thumbnailUrl) &&
          post.kind !== 'reel' // Exclude reels from watch feed
        )

        // Sort by engagement score
        const sortedPosts = videoPosts
          .map(post => ({
            ...post,
            engagementScore: (post.views || 0) * 0.5 + (post.likes || 0) + (post.comments || 0) * 2 + (post.reposts || 0) * 3
          }))
          .sort((a, b) => b.engagementScore - a.engagementScore)
          .slice(0, limit)

        result = {
          ...result,
          documents: sortedPosts
        }
        break

      case 'reels':
        // Reels feed - short videos by engagement
        queries = [
          Query.equal('kind', 'reel'),
          Query.limit(limit * 2)
        ]
        if (cursor) queries.push(Query.cursorAfter(cursor))

        result = await databases.listDocuments(
          databaseId,
          collections.posts,
          queries
        )

        // Sort by engagement
        const sortedReels = result.documents
          .map(post => ({
            ...post,
            engagementScore: (post.likes || 0) + (post.comments || 0) * 2 + (post.reposts || 0) * 3 + (post.views || 0) * 0.3
          }))
          .sort((a, b) => b.engagementScore - a.engagementScore)
          .slice(0, limit)

        result = {
          ...result,
          documents: sortedReels
        }
        break

      case 'following':
        // Following feed - posts from followed users
        const user = await getCurrentUser()
        if (!user) {
          return NextResponse.json(
            { error: 'Authentication required for following feed' },
            { status: 401 }
          )
        }

        // Get following user IDs
        const followingResult = await databases.listDocuments(
          databaseId,
          collections.follows,
          [
            Query.equal('followerId', user.$id),
            Query.limit(500)
          ]
        )

        const followingIds = followingResult.documents.map(doc => doc.followingId || doc.followeeId)

        if (followingIds.length === 0) {
          return NextResponse.json({
            documents: [],
            total: 0
          })
        }

        // If only one user ID, use simple equal query
        if (followingIds.length === 1) {
          queries = [
            Query.equal('userId', followingIds[0]),
            Query.orderDesc('$createdAt'),
            Query.limit(limit)
          ]
          if (cursor) queries.push(Query.cursorAfter(cursor))

          result = await databases.listDocuments(
            databaseId,
            collections.posts,
            queries
          )
        } else {
          // For multiple user IDs, use OR query
          const orQueries = followingIds.map(id => Query.equal('userId', id))
          queries = [
            Query.or(orQueries),
            Query.orderDesc('$createdAt'),
            Query.limit(limit)
          ]
          if (cursor) queries.push(Query.cursorAfter(cursor))

          result = await databases.listDocuments(
            databaseId,
            collections.posts,
            queries
          )
        }
        break

      default:
        // Regular feed
        queries = [
          Query.orderDesc('$createdAt'),
          Query.limit(limit)
        ]
        if (cursor) queries.push(Query.cursorAfter(cursor))

        result = await databases.listDocuments(
          databaseId,
          collections.posts,
          queries
        )
    }

    return NextResponse.json(result)

  } catch (error: any) {
    console.error('Feed error:', error)

    return NextResponse.json(
      { error: error.message || 'Failed to fetch feed' },
      { status: 500 }
    )
  }
}