'use client'

import { useEffect } from 'react'
import { ArrowLeft, Clock, Calendar, Share2, Bookmark, CheckCircle2, User } from 'lucide-react'
import { OptimizedImage } from './components/OptimizedImage'
import { formatTimeAgo } from './utils'

interface NewsDetailScreenProps {
  article: any
  onClose: () => void
}

export function NewsDetailScreen({ article, onClose }: NewsDetailScreenProps) {
  const title = article.title || ''
  const content = article.content || ''
  const summary = article.summary || article.seoDescription || ''
  const category = article.category || 'General'
  const author = 'XapZap News'
  const publishedDate = article.createdAt || article.publishedAt
  const imageUrls = article.imageUrls || []
  const thumbnail = article.thumbnailUrl || article.thumbnailUr || (imageUrls.length > 0 ? imageUrls[0] : null)

  useEffect(() => {
    const hasTwitterLink = 
      (article.videoUrl && (article.videoUrl.includes('twitter.com') || article.videoUrl.includes('x.com'))) ||
      content.includes('twitter.com') ||
      content.includes('x.com')

    if (hasTwitterLink) {
      const script = document.createElement('script')
      script.setAttribute('src', 'https://platform.twitter.com/widgets.js')
      script.setAttribute('async', 'true')
      script.setAttribute('charset', 'utf-8')
      document.head.appendChild(script)
      return () => {
        try {
          document.head.removeChild(script)
        } catch (_) {}
      }
    }
  }, [article.videoUrl, content])

  useEffect(() => {
    const hasInstagramLink = 
      (article.videoUrl && article.videoUrl.includes('instagram.com')) ||
      content.includes('instagram.com')

    if (hasInstagramLink) {
      const script = document.createElement('script')
      script.setAttribute('src', 'https://www.instagram.com/embed.js')
      script.setAttribute('async', 'true')
      document.head.appendChild(script)
      
      script.onload = () => {
        if (typeof window !== 'undefined' && (window as any).instgrm?.Embeds?.process) {
          (window as any).instgrm.Embeds.process()
        }
      }

      return () => {
        try {
          document.head.removeChild(script)
        } catch (_) {}
      }
    }
  }, [article.videoUrl, content])

  useEffect(() => {
    if (typeof window !== 'undefined' && (window as any).instgrm?.Embeds?.process) {
      (window as any).instgrm.Embeds.process()
    }
  }, [content])

  // Helper to turn raw URLs and markdown links into React elements
  function parseTextWithLinks(text: string): React.ReactNode[] {
    const parts = text.split(/(\[[^\]]+\]\([^)]+\)|https?:\/\/[^\s\)]+)/g)
    
    return parts.map((part, index) => {
      // Check if it's a markdown link [label](url)
      const markdownMatch = part.match(/^\[([^\]]+)\]\(([^)]+)\)$/)
      if (markdownMatch) {
        const [_, label, url] = markdownMatch
        return (
          <a
            key={index}
            href={url}
            target="_blank"
            rel="noopener noreferrer"
            className="text-primary hover:underline font-semibold"
          >
            {label}
          </a>
        )
      }
      
      // Check if it's a plain URL
      const urlMatch = part.match(/^(https?:\/\/[^\s\)]+)$/)
      if (urlMatch) {
        const url = urlMatch[1]
        let cleanedUrl = url
        let trailing = ""
        const trailingPunctuationMatch = url.match(/([.,;!?]+)$/)
        if (trailingPunctuationMatch) {
          cleanedUrl = url.substring(0, url.length - trailingPunctuationMatch[0].length)
          trailing = trailingPunctuationMatch[0]
        }
        return (
          <span key={index}>
            <a
              href={cleanedUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="text-primary hover:underline font-semibold break-all"
            >
              {cleanedUrl}
            </a>
            {trailing}
          </span>
        )
      }
      
      return part
    })
  }

  // Parse markdown headings, point outline, and paragraphs for a standard structure
  const lines = content.split('\n')
  const processedBody: React.ReactNode[] = []

  let inlineImageIndex = 0
  let skipRemainingLines = false

  // Standard renderer helper
  lines.forEach((line: string, index: number) => {
    const trimmed = line.trim()
    if (!trimmed || skipRemainingLines) return

    // Detect "Sort replies:" or "Replying to @" which indicates the start of replies
    if (trimmed.includes('Sort replies:') || trimmed.includes('Replying to @')) {
      skipRemainingLines = true
      return
    }

    // Check if the paragraph contains scraped metadata and an X/Twitter post link
    // e.g. "[Scraped facts from original source https://xcancel.com/...]"
    const scrapedSourceMatch = trimmed.match(/\[Scraped facts from original source\s+(https?:\/\/[^\]\s]+)\]/i) ||
                               trimmed.match(/original source\s+(https?:\/\/[^\s\]\)]+)/i)

    if (scrapedSourceMatch) {
      let sourceUrl = scrapedSourceMatch[1]
      // Convert alternative scraper frontends to official x.com
      if (sourceUrl.includes('xcancel.com') || sourceUrl.includes('nitter')) {
        sourceUrl = sourceUrl.replace(/(?:xcancel\.com|nitter\.[a-z]{2,3})/g, 'x.com')
      }

      // Check if there is any preceding text before the scraper bracket
      const preMatchText = trimmed.split(/\[Scraped facts/i)[0].trim()
      if (preMatchText && preMatchText.length > 5) {
        processedBody.push(
          <p key={`scraped-pre-${index}`} className="my-4 text-muted-foreground leading-relaxed text-[17px]">
            {parseTextWithLinks(preMatchText)}
          </p>
        )
      }

      // Render the source post as a beautiful interactive embed
      processedBody.push(
        <div key={`scraped-embed-${index}`} className="bg-accent/30 rounded-2xl p-6 border border-border/80 my-6 space-y-3">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold uppercase tracking-widest text-primary flex items-center gap-1.5">
              <span className="w-2 h-2 rounded-full bg-primary animate-pulse" />
              Source Social Post
            </span>
            <a
              href={sourceUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="text-xs text-muted-foreground hover:text-primary transition-colors underline"
            >
              View on X
            </a>
          </div>
          <div className="flex justify-center w-full min-h-[150px] bg-background/50 rounded-xl p-4 border border-border/40 overflow-x-auto">
            <blockquote className="twitter-tweet" data-theme="dark" data-align="center">
              <a href={sourceUrl}>Loading source post...</a>
            </blockquote>
          </div>
        </div>
      )

      // Skip the rest of the scraped copy and replies
      skipRemainingLines = true
      return
    }

    if (trimmed.startsWith('# ')) {
      // H1 (Title) - skip as we display it in header
      return
    } else if (trimmed.startsWith('## ')) {
      const headingText = trimmed.replace('## ', '')
      processedBody.push(
        <h2 key={index} className="text-2xl font-bold text-foreground mt-8 mb-4 border-b border-border pb-2 tracking-tight">
          {headingText}
        </h2>
      )
    } else if (trimmed.startsWith('### ')) {
      const headingText = trimmed.replace('### ', '')
      processedBody.push(
        <h3 key={index} className="text-xl font-semibold text-foreground mt-6 mb-3 tracking-tight">
          {headingText}
        </h3>
      )
    } else if (trimmed.startsWith('* ') || trimmed.startsWith('- ')) {
      // Bullet list items
      const bulletText = trimmed.substring(2)
      processedBody.push(
        <div key={index} className="flex items-start space-x-3 my-2 text-muted-foreground leading-relaxed pl-2">
          <span className="text-primary mt-1.5">•</span>
          <span>{parseTextWithLinks(bulletText)}</span>
        </div>
      )
    } else if (trimmed.startsWith('1. ') || trimmed.startsWith('2. ') || trimmed.startsWith('3. ') || trimmed.startsWith('4. ') || trimmed.startsWith('5. ')) {
      // Numbered list items
      const numText = trimmed.substring(3)
      processedBody.push(
        <div key={index} className="flex items-start space-x-3 my-2 text-muted-foreground leading-relaxed pl-2">
          <span className="text-primary font-bold">{trimmed.substring(0, 2)}</span>
          <span>{parseTextWithLinks(numText)}</span>
        </div>
      )
    } else if (trimmed.startsWith('> ')) {
      // Blockquotes
      const quoteText = trimmed.replace('> ', '')
      processedBody.push(
        <blockquote key={index} className="border-l-4 border-primary pl-4 py-1 my-4 italic text-muted-foreground bg-accent/30 rounded-r-md">
          {parseTextWithLinks(quoteText)}
        </blockquote>
      )
    } else if (trimmed.length > 0) {
      // Check if image tag is embedded
      if (trimmed.startsWith('![') && trimmed.includes('](')) {
        // Embed image tag parsed
        const start = trimmed.indexOf('(') + 1
        const end = trimmed.indexOf(')')
        const imgUrl = trimmed.substring(start, end)
        processedBody.push(
          <div key={index} className="my-6 rounded-xl overflow-hidden shadow-lg border border-border">
            <OptimizedImage
              src={imgUrl}
              alt="Visual asset"
              className="w-full h-auto object-cover max-h-[400px]"
            />
          </div>
        )
      } else {
        // Check if the entire paragraph is a raw media URL
        const isRawUrl = /^(https?:\/\/[^\s]+)$/.test(trimmed)
        if (isRawUrl) {
          // Check for YouTube
          const ytMatch = trimmed.match(/(?:youtube\.com\/watch\?v=|youtu\.be\/)([a-zA-Z0-9_-]+)/)
          if (ytMatch) {
            const videoId = ytMatch[1]
            processedBody.push(
              <div key={index} className="my-6 rounded-xl overflow-hidden shadow-lg border border-border aspect-video">
                <iframe
                  width="100%"
                  height="100%"
                  src={`https://www.youtube.com/embed/${videoId}`}
                  title="YouTube video player"
                  frameBorder="0"
                  allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
                  allowFullScreen
                  className="w-full h-full"
                />
              </div>
            )
            return
          }

          // Check for Twitter/X status URL
          const twitterMatch = trimmed.match(/(?:twitter\.com|x\.com)\/[a-zA-Z0-9_]+\/status\/([0-9]+)/)
          if (twitterMatch) {
            processedBody.push(
              <div key={index} className="bg-accent/30 rounded-2xl p-6 border border-border/80 my-6 space-y-3">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-bold uppercase tracking-widest text-primary flex items-center gap-1.5">
                    <span className="w-2 h-2 rounded-full bg-primary animate-pulse" />
                    Embedded Post
                  </span>
                  <a
                    href={trimmed}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-xs text-muted-foreground hover:text-primary transition-colors underline"
                  >
                    View on X
                  </a>
                </div>
                <div className="flex justify-center w-full min-h-[150px] bg-background/50 rounded-xl p-4 border border-border/40 overflow-x-auto">
                  <blockquote className="twitter-tweet" data-theme="dark" data-align="center">
                    <a href={trimmed}>Loading post...</a>
                  </blockquote>
                </div>
              </div>
            )
            return
          }

          // Check for Instagram post or reel URL
          const instagramMatch = trimmed.match(/(?:instagram\.com)\/(?:p|reel|tv)\/([a-zA-Z0-9_-]+)/)
          if (instagramMatch) {
            processedBody.push(
              <div key={index} className="bg-accent/30 rounded-2xl p-6 border border-border/80 my-6 space-y-3">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-bold uppercase tracking-widest text-primary flex items-center gap-1.5">
                    <span className="w-2 h-2 rounded-full bg-primary animate-pulse" />
                    Instagram Feed
                  </span>
                  <a
                    href={trimmed}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-xs text-muted-foreground hover:text-primary transition-colors underline"
                  >
                    View on Instagram
                  </a>
                </div>
                <div className="flex justify-center w-full min-h-[300px] bg-background/50 rounded-xl p-4 border border-border/40 overflow-x-auto">
                  <blockquote className="instagram-media w-full max-w-[400px]" data-instgrm-permalink={trimmed} data-instgrm-version="14">
                    <a href={trimmed}>Loading Instagram post...</a>
                  </blockquote>
                </div>
              </div>
            )
            return
          }

          // Check for Facebook post or video URL
          const isFacebook = /facebook\.com\//.test(trimmed)
          if (isFacebook) {
            const isVideo = /facebook\.com\/watch|fb\.watch|plugins\/video\.php/.test(trimmed)
            const pluginUrl = isVideo 
              ? `https://www.facebook.com/plugins/video.php?href=${encodeURIComponent(trimmed)}&show_text=true&width=500`
              : `https://www.facebook.com/plugins/post.php?href=${encodeURIComponent(trimmed)}&show_text=true&width=500`

            processedBody.push(
              <div key={index} className="bg-accent/30 rounded-2xl p-6 border border-border/80 my-6 space-y-3">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-bold uppercase tracking-widest text-primary flex items-center gap-1.5">
                    <span className="w-2 h-2 rounded-full bg-primary animate-pulse" />
                    Facebook Update
                  </span>
                  <a
                    href={trimmed}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-xs text-muted-foreground hover:text-primary transition-colors underline"
                  >
                    View on Facebook
                  </a>
                </div>
                <div className="flex justify-center w-full bg-background/50 rounded-xl p-4 border border-border/40 overflow-hidden">
                  <iframe
                    src={pluginUrl}
                    width="500"
                    height={isVideo ? "280" : "450"}
                    style={{ border: 'none', overflow: 'hidden' }}
                    scrolling="no"
                    frameBorder="0"
                    allowFullScreen={true}
                    allow="autoplay; clipboard-write; encrypted-media; picture-in-picture; web-share"
                    className="w-full max-w-[500px] rounded-lg"
                  />
                </div>
              </div>
            )
            return
          }

          // Check for image extensions
          const isImageUrl = /\.(jpg|jpeg|png|webp|gif|svg)(?:\?.*)?$/i.test(trimmed)
          if (isImageUrl) {
            processedBody.push(
              <div key={index} className="my-6 rounded-xl overflow-hidden shadow-lg border border-border">
                <OptimizedImage
                  src={trimmed}
                  alt="Embedded visual asset"
                  className="w-full h-auto object-cover max-h-[400px]"
                />
              </div>
            )
            return
          }
        }

        // Plain paragraph
        processedBody.push(
          <p key={index} className="my-4 text-muted-foreground leading-relaxed text-[17px]">
            {parseTextWithLinks(trimmed)}
          </p>
        )
      }
    }
  })

  // Ensure at least 2 images are embedded inside content
  // If the markdown parsing didn't find embedded images but we have imageUrls, append them
  if (imageUrls.length > 1 && processedBody.filter((x: any) => x && x.key && x.key.toString().includes('embed-img')).length === 0) {
    const additionalImages: React.ReactNode[] = []
    imageUrls.forEach((img: string, idx: number) => {
      // Skip the thumbnail
      if (img !== thumbnail) {
        additionalImages.push(
          <div key={`embed-img-${idx}`} className="my-8 rounded-xl overflow-hidden shadow-lg border border-border">
            <OptimizedImage
              src={img}
              alt={`Article detail visual ${idx}`}
              className="w-full h-[320px] object-cover"
            />
          </div>
        )
      }
    })
    // Insert them at 1/3 and 2/3 points of the content
    if (additionalImages.length > 0) {
      const splitIndex = Math.floor(processedBody.length / 2)
      processedBody.splice(splitIndex, 0, additionalImages[0])
      if (additionalImages.length > 1 && processedBody.length > splitIndex + 3) {
        processedBody.splice(splitIndex + 3, 0, additionalImages[1])
      } else if (additionalImages.length > 1) {
        processedBody.push(additionalImages[1])
      }
    }
  }

  const handleShare = async () => {
    try {
      await navigator.share({
        title,
        text: summary,
        url: window.location.href,
      })
    } catch (_) {
      // Fallback copy link
      navigator.clipboard.writeText(window.location.href)
      alert('Link copied to clipboard!')
    }
  }

  return (
    <div className="fixed inset-0 bg-background z-50 flex flex-col animate-in fade-in slide-in-from-right duration-300">
      {/* Premium Glassmorphic Top Nav Bar */}
      <div className="sticky top-0 bg-background/80 backdrop-blur-md z-10 flex items-center justify-between px-6 py-4 border-b border-border">
        <button
          onClick={onClose}
          className="flex items-center space-x-2 px-3 py-2 bg-accent hover:bg-accent/80 text-foreground text-sm font-medium rounded-full transition-all border border-border shadow-sm hover:scale-105"
        >
          <ArrowLeft size={18} />
          <span>Back to Hub</span>
        </button>
        <div className="flex items-center space-x-2">
          <span className="w-2.5 h-2.5 rounded-full bg-primary animate-pulse" />
          <span className="text-xs font-bold uppercase tracking-widest text-muted-foreground">{category}</span>
        </div>
        <div className="flex items-center space-x-3">
          <button
            onClick={handleShare}
            className="p-2.5 bg-accent hover:bg-accent/80 text-foreground rounded-full transition-all border border-border shadow-sm hover:scale-105"
            title="Share article"
          >
            <Share2 size={16} />
          </button>
        </div>
      </div>

      {/* Main Content Layout */}
      <div className="flex-1 overflow-y-auto safe-area-inset-bottom bg-background">
        <div className="max-w-6xl mx-auto px-6 py-8 md:py-12">
          {/* Grid Layout: Main content (left 2/3) & Sidebar (right 1/3) on desktop */}
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
            
            {/* Left Content Column */}
            <div className="lg:col-span-2 space-y-6">
              {/* Article Header Metadata */}
              <div className="space-y-4">
                <span className="inline-flex items-center px-3 py-1 rounded-full text-xs font-semibold bg-primary/10 text-primary border border-primary/20">
                  {category}
                </span>
                <h1 className="text-3xl md:text-5xl font-black text-foreground tracking-tight leading-tight">
                  {title}
                </h1>
                {article.subtitle && (
                  <p className="text-xl text-muted-foreground font-medium leading-normal">
                    {article.subtitle}
                  </p>
                )}
              </div>

              {/* Cover Image */}
              {thumbnail && (
                <div className="space-y-2">
                  <div className="relative aspect-[16/9] w-full rounded-2xl overflow-hidden shadow-xl border border-border group">
                    <OptimizedImage
                      src={thumbnail}
                      alt={title}
                      className="w-full h-full object-cover group-hover:scale-102 transition-transform duration-700"
                    />
                    <div className="absolute inset-0 bg-gradient-to-t from-black/20 to-transparent" />
                  </div>
                  {(article.mediaCredits || article.mediaSource) && (
                    <div className="text-right text-xs text-muted-foreground/85 italic pr-2">
                      Image Source: {article.mediaCredits || 'Original Publisher'} ({article.mediaSource || 'Official Source'})
                    </div>
                  )}
                </div>
              )}

              {/* Social Embed Section */}
              {article.videoUrl && (article.videoUrl.includes('twitter.com') || article.videoUrl.includes('x.com')) && (
                <div className="bg-accent/30 rounded-2xl p-6 border border-border/80 my-4 space-y-3">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-bold uppercase tracking-widest text-primary flex items-center gap-1.5">
                      <span className="w-2 h-2 rounded-full bg-primary animate-pulse" />
                      Live Social Update
                    </span>
                    <a
                      href={article.videoUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-xs text-muted-foreground hover:text-primary transition-colors underline"
                    >
                      View on X
                    </a>
                  </div>
                  <div className="flex justify-center w-full min-h-[150px] bg-background/50 rounded-xl p-4 border border-border/40 overflow-x-auto">
                    <blockquote className="twitter-tweet" data-theme="dark" data-align="center">
                      <a href={article.videoUrl}>Loading original post...</a>
                    </blockquote>
                  </div>
                </div>
              )}

              {/* Dynamic Rendered Body */}
              <div className="prose prose-lg dark:prose-invert max-w-none pt-4">
                {processedBody}
              </div>
            </div>

            {/* Right Sidebar Column */}
            <div className="lg:col-span-1 space-y-6 lg:border-l lg:border-border lg:pl-8">
              
              {/* Publisher Detail Widget */}
              <div className="bg-accent/40 rounded-2xl p-6 border border-border/60">
                <h3 className="text-xs font-bold uppercase tracking-widest text-muted-foreground mb-4">Publisher Desk</h3>
                <div className="flex items-center space-x-3 mb-4">
                  <div className="w-12 h-12 rounded-full bg-primary/10 border border-primary/20 flex items-center justify-center text-primary font-black">
                    XZ
                  </div>
                  <div>
                    <div className="flex items-center space-x-1.5">
                      <span className="font-bold text-foreground">{author}</span>
                      <CheckCircle2 size={14} className="text-primary fill-primary/10" />
                    </div>
                    <span className="text-xs text-muted-foreground">Verified Publisher</span>
                  </div>
                </div>
                <p className="text-sm text-muted-foreground leading-relaxed">
                  XapZap News provides rapid, detailed reporting on emerging global trends, curated concurrently across 32 countries.
                </p>
              </div>

              {/* Meta Stats & Actions Widget */}
              <div className="bg-accent/40 rounded-2xl p-6 border border-border/60 space-y-4">
                <h3 className="text-xs font-bold uppercase tracking-widest text-muted-foreground">Article Info</h3>
                
                <div className="space-y-3 text-sm text-muted-foreground pt-2">
                  <div className="flex items-center space-x-2.5">
                    <Clock size={16} className="text-primary" />
                    <span>8 min read</span>
                  </div>
                  <div className="flex items-center space-x-2.5">
                    <Calendar size={16} className="text-primary" />
                    <span>{formatTimeAgo(publishedDate)}</span>
                  </div>
                </div>

                <div className="pt-4 border-t border-border/60">
                  <button
                    onClick={handleShare}
                    className="w-full flex items-center justify-center space-x-2 py-3 px-4 bg-primary hover:bg-primary/95 text-primary-foreground font-semibold rounded-xl shadow-md transition-all hover:scale-[1.02] active:scale-[0.98]"
                  >
                    <Share2 size={16} />
                    <span>Share This Story</span>
                  </button>
                </div>
              </div>

              {/* Tags Widget */}
              {article.tags && article.tags.length > 0 && (
                <div className="bg-accent/40 rounded-2xl p-6 border border-border/60">
                  <h3 className="text-xs font-bold uppercase tracking-widest text-muted-foreground mb-4">Topic Tags</h3>
                  <div className="flex flex-wrap gap-2">
                    {article.tags.map((tag: string, idx: number) => (
                      <span
                        key={idx}
                        className="px-3 py-1 bg-accent border border-border/80 hover:border-primary/40 text-foreground text-xs font-medium rounded-full cursor-pointer transition-colors"
                      >
                        #{tag}
                      </span>
                    ))}
                  </div>
                </div>
              )}
            </div>

          </div>
        </div>
      </div>
    </div>
  )
}
