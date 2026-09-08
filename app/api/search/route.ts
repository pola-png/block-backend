import { NextRequest, NextResponse } from 'next/server'
import appwriteService from '../../../appwriteService'

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const query = searchParams.get('q') || ''
    const type = searchParams.get('type') || 'users' // users, hashtags, posts
    const limit = parseInt(searchParams.get('limit') || '10')

    if (!query.trim()) {
      return NextResponse.json({ results: [] })
    }

    let results: any[] = []

    switch (type) {
      case 'users':
        results = await appwriteService.searchUsers(query, limit)
        break
      case 'hashtags':
        results = await appwriteService.searchHashtags(query, limit)
        break
      case 'posts':
        // For posts, we can search through content using the existing fetchPosts method
        // This is a basic implementation - you might want to add full-text search
        try {
          const postsResult = await appwriteService.fetchPosts(limit * 2) // Get more to filter
          results = postsResult.documents
            .filter((post: any) =>
              post.content && post.content.toLowerCase().includes(query.toLowerCase())
            )
            .slice(0, limit)
        } catch (error) {
          console.error('Posts search error:', error)
          results = []
        }
        break
      default:
        results = await appwriteService.searchUsers(query, limit)
    }

    return NextResponse.json({ results })
  } catch (error) {
    console.error('Search API error:', error)
    return NextResponse.json(
      { error: 'Search failed' },
      { status: 500 }
    )
  }
}
