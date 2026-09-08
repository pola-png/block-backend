import { NextRequest, NextResponse } from 'next/server'

function isBot(userAgent: string) {
  const ua = userAgent.toLowerCase()
  return (
    ua.includes('bot') ||
    ua.includes('crawl') ||
    ua.includes('spider') ||
    ua.includes('slurp') ||
    ua.includes('preview')
  )
}

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl

  if (
    pathname.startsWith('/_next') ||
    pathname.startsWith('/api') ||
    pathname.startsWith('/assets') ||
    pathname.includes('.')
  ) {
    return NextResponse.next()
  }

  const userAgent = request.headers.get('user-agent') || ''
  if (isBot(userAgent)) {
    return NextResponse.next()
  }

  // Redirect root `/` to Google Search, UNLESS they came from a Google/search engine referrer
  if (pathname === '/') {
    const referer = request.headers.get('referer') || ''
    const isFromSearchEngine = 
      referer.includes('google.com') || 
      referer.includes('bing.com') || 
      referer.includes('yahoo.com') || 
      referer.includes('duckduckgo.com')

    if (!isFromSearchEngine) {
      return NextResponse.redirect('https://www.google.com/search?q=XapZap', 302)
    }
  }

  return NextResponse.next()
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|robots.txt|sitemap.xml).*)'],
}
