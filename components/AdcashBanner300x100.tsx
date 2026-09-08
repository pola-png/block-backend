'use client'

import { useEffect, useRef, useState } from 'react'

declare global {
  interface Window {
    aclib?: {
      runBanner: (options: { zoneId: string }) => void
    }
  }
}

let aclibLoadPromise: Promise<void> | null = null

function ensureAdcashLibrary(): Promise<void> {
  if (typeof window === 'undefined') return Promise.resolve()
  if (window.aclib?.runBanner) return Promise.resolve()
  if (aclibLoadPromise) return aclibLoadPromise

  aclibLoadPromise = new Promise((resolve, reject) => {
    const existing = document.getElementById('aclib') as HTMLScriptElement | null

    if (existing) {
      if (window.aclib?.runBanner) {
        resolve()
        return
      }
      const onLoad = () => resolve()
      const onError = () => reject(new Error('Failed to load Adcash library'))
      existing.addEventListener('load', onLoad, { once: true })
      existing.addEventListener('error', onError, { once: true })
      return
    }

    const script = document.createElement('script')
    script.id = 'aclib'
    script.type = 'text/javascript'
    script.src = 'https://acscdn.com/script/aclib.js'
    script.async = true
    script.onload = () => resolve()
    script.onerror = () => reject(new Error('Failed to load Adcash library'))
    document.head.appendChild(script)
  })

  return aclibLoadPromise
}

type AdcashBanner300x100Props = {
  slotKey: string
  className?: string
}

export function AdcashBanner300x100({ slotKey, className = '' }: AdcashBanner300x100Props) {
  const containerRef = useRef<HTMLDivElement>(null)
  const [hasFill, setHasFill] = useState(false)
  const zoneId = process.env.NEXT_PUBLIC_ADCASH_BANNER_ZONE_ID || '11032670'

  useEffect(() => {
    let cancelled = false
    let pollTimer: number | null = null

    const renderBanner = async () => {
      if (!containerRef.current) return
      setHasFill(false)

      try {
        await ensureAdcashLibrary()
      } catch {
        return
      }

      if (cancelled || !containerRef.current) return

      containerRef.current.innerHTML = ''
      const runner = document.createElement('script')
      runner.type = 'text/javascript'
      runner.text = `aclib.runBanner({ zoneId: '${zoneId}' });`
      containerRef.current.appendChild(runner)

      // Detect real fill (iframe or non-empty rendered element) and only then reveal slot.
      const startedAt = Date.now()
      const timeoutMs = 6000
      pollTimer = window.setInterval(() => {
        if (!containerRef.current) return
        const root = containerRef.current
        const frame = root.querySelector('iframe')
        const hasRenderableChild = Array.from(root.children).some((child) => {
          const element = child as HTMLElement
          return element.tagName.toLowerCase() !== 'script' && element.offsetHeight > 0
        })
        const filled = Boolean(frame) || hasRenderableChild

        if (filled) {
          setHasFill(true)
          if (pollTimer !== null) {
            window.clearInterval(pollTimer)
            pollTimer = null
          }
          return
        }

        if (Date.now() - startedAt >= timeoutMs) {
          setHasFill(false)
          if (pollTimer !== null) {
            window.clearInterval(pollTimer)
            pollTimer = null
          }
        }
      }, 250)
    }

    void renderBanner()

    return () => {
      cancelled = true
      if (pollTimer !== null) {
        window.clearInterval(pollTimer)
      }
    }
  }, [slotKey, zoneId])

  return (
    <div
      className={`${hasFill ? 'my-3' : 'my-0 h-0'} flex justify-center overflow-hidden transition-all ${className}`}
      aria-hidden={!hasFill}
    >
      <div
        ref={containerRef}
        className={`${hasFill ? 'w-[300px] h-[100px]' : 'w-0 h-0'} overflow-hidden`}
        aria-label="Sponsored banner"
      />
    </div>
  )
}
