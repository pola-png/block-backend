import { NextRequest, NextResponse } from 'next/server'

export async function GET(request: NextRequest) {
  try {
    // Get all cookies
    const cookies = request.cookies
    const allCookies = cookies.getAll()

    console.log('All cookies received:', allCookies.map(c => ({ name: c.name, value: c.value.substring(0, 20) + '...' })))

    // Look for Appwrite session cookies
    const sessionCookies = allCookies.filter(cookie =>
      cookie.name.startsWith('a_session_')
    )

    console.log('Session cookies found:', sessionCookies.map(c => c.name))

    if (sessionCookies.length > 0) {
      // Return the first session cookie value
      const sessionCookie = sessionCookies[0]
      return NextResponse.json({
        token: sessionCookie.value,
        cookieName: sessionCookie.name
      })
    }

    return NextResponse.json({ error: 'No session cookie found' }, { status: 404 })
  } catch (error) {
    console.error('Session endpoint error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}