'use client'

type InstreamAdPayload = {
  mediaUrl: string
  clickThroughUrl: string | null
  impressionUrls: string[]
  startTrackingUrls: string[]
  completeTrackingUrls: string[]
}

type PlayInstreamAdOptions = {
  placement?: string
  videoId?: string
}

const PLAY_COUNT_KEY = 'xapzap_instream_play_count'
const LAST_AD_AT_KEY = 'xapzap_instream_last_ad_at'

let activeAdPromise: Promise<boolean> | null = null

function getNumberFromSession(key: string): number {
  if (typeof window === 'undefined') return 0
  const raw = window.sessionStorage.getItem(key)
  if (!raw) return 0
  const parsed = Number(raw)
  return Number.isFinite(parsed) ? parsed : 0
}

function setNumberToSession(key: string, value: number) {
  if (typeof window === 'undefined') return
  window.sessionStorage.setItem(key, String(value))
}

function getFrequency(): number {
  const raw = Number(process.env.NEXT_PUBLIC_ADCASH_AD_FREQUENCY || 3)
  if (!Number.isFinite(raw)) return 3
  return Math.max(1, Math.floor(raw))
}

function getCooldownSeconds(): number {
  const raw = Number(process.env.NEXT_PUBLIC_ADCASH_AD_COOLDOWN_SECONDS || 75)
  if (!Number.isFinite(raw)) return 75
  return Math.max(0, Math.floor(raw))
}

function shouldRequestAd(): boolean {
  if (typeof window === 'undefined') return false

  const nextPlayCount = getNumberFromSession(PLAY_COUNT_KEY) + 1
  setNumberToSession(PLAY_COUNT_KEY, nextPlayCount)

  const frequency = getFrequency()
  if (nextPlayCount % frequency !== 0) return false

  const cooldownMs = getCooldownSeconds() * 1000
  if (cooldownMs <= 0) return true

  const lastAdAt = getNumberFromSession(LAST_AD_AT_KEY)
  if (lastAdAt <= 0) return true
  return Date.now() - lastAdAt >= cooldownMs
}

async function ping(urls: string[]) {
  const validUrls = urls.filter((value) => typeof value === 'string' && value.length > 0)
  await Promise.allSettled(
    validUrls.map(async (url) => {
      try {
        await fetch(url, {
          method: 'GET',
          mode: 'no-cors',
          cache: 'no-store',
          keepalive: true,
        })
      } catch {
        // Ignore tracking failures.
      }
    })
  )
}

async function fetchInstreamAdPayload(options: PlayInstreamAdOptions): Promise<InstreamAdPayload | null> {
  try {
    const params = new URLSearchParams()
    if (options.videoId) params.set('videoId', options.videoId)
    if (options.placement) params.set('placement', options.placement)
    const endpoint = params.toString() ? `/api/ads/instream?${params.toString()}` : '/api/ads/instream'

    const response = await fetch(endpoint, {
      method: 'GET',
      cache: 'no-store',
    })

    if (!response.ok) return null
    const payload = (await response.json()) as InstreamAdPayload
    if (!payload?.mediaUrl) return null
    return payload
  } catch {
    return null
  }
}

function renderAdOverlay(payload: InstreamAdPayload): Promise<boolean> {
  return new Promise((resolve) => {
    if (typeof document === 'undefined') {
      resolve(false)
      return
    }

    const skipAfter = Math.max(0, Number(process.env.NEXT_PUBLIC_ADCASH_AD_SKIP_AFTER_SECONDS || 5))
    const overlay = document.createElement('div')
    overlay.style.position = 'fixed'
    overlay.style.inset = '0'
    overlay.style.background = '#000'
    overlay.style.zIndex = '99999'
    overlay.style.display = 'flex'
    overlay.style.alignItems = 'center'
    overlay.style.justifyContent = 'center'

    const video = document.createElement('video')
    video.src = payload.mediaUrl
    video.style.width = '100%'
    video.style.height = '100%'
    video.style.objectFit = 'contain'
    video.playsInline = true
    video.preload = 'auto'
    video.controls = false

    const badge = document.createElement('div')
    badge.textContent = 'Sponsored'
    badge.style.position = 'absolute'
    badge.style.top = '12px'
    badge.style.left = '12px'
    badge.style.padding = '6px 10px'
    badge.style.borderRadius = '999px'
    badge.style.fontSize = '12px'
    badge.style.fontWeight = '700'
    badge.style.color = '#fff'
    badge.style.background = 'rgba(0,0,0,0.6)'

    const skipButton = document.createElement('button')
    skipButton.style.position = 'absolute'
    skipButton.style.top = '12px'
    skipButton.style.right = '12px'
    skipButton.style.padding = '8px 12px'
    skipButton.style.border = 'none'
    skipButton.style.borderRadius = '999px'
    skipButton.style.fontSize = '12px'
    skipButton.style.fontWeight = '700'
    skipButton.style.color = '#fff'
    skipButton.style.background = 'rgba(0,0,0,0.6)'
    skipButton.style.cursor = 'pointer'
    skipButton.textContent = skipAfter > 0 ? `Skip in ${skipAfter}s` : 'Skip'
    skipButton.disabled = skipAfter > 0

    let cleaned = false
    let skipTimer: number | null = null
    let skipCountdown = skipAfter

    const cleanup = (shown: boolean) => {
      if (cleaned) return
      cleaned = true
      if (skipTimer !== null) {
        window.clearInterval(skipTimer)
      }
      video.pause()
      overlay.remove()
      resolve(shown)
    }

    const tryOpenClickThrough = () => {
      if (!payload.clickThroughUrl) return
      window.open(payload.clickThroughUrl, '_blank', 'noopener,noreferrer')
    }

    video.addEventListener(
      'play',
      () => {
        void ping(payload.impressionUrls)
        void ping(payload.startTrackingUrls)
      },
      { once: true }
    )

    video.addEventListener(
      'ended',
      () => {
        void ping(payload.completeTrackingUrls)
        cleanup(true)
      },
      { once: true }
    )

    video.addEventListener(
      'error',
      () => {
        cleanup(false)
      },
      { once: true }
    )

    skipButton.addEventListener('click', () => cleanup(true))
    video.addEventListener('click', tryOpenClickThrough)

    if (skipAfter > 0) {
      skipTimer = window.setInterval(() => {
        skipCountdown -= 1
        if (skipCountdown <= 0) {
          skipButton.textContent = 'Skip'
          skipButton.disabled = false
          if (skipTimer !== null) {
            window.clearInterval(skipTimer)
            skipTimer = null
          }
        } else {
          skipButton.textContent = `Skip in ${skipCountdown}s`
        }
      }, 1000)
    }

    overlay.appendChild(video)
    overlay.appendChild(badge)
    overlay.appendChild(skipButton)
    document.body.appendChild(overlay)

    const start = async () => {
      try {
        video.muted = false
        await video.play()
      } catch {
        try {
          video.muted = true
          await video.play()
        } catch {
          cleanup(false)
        }
      }
    }

    void start()
  })
}

export async function playAdcashInstreamAd(options: PlayInstreamAdOptions = {}): Promise<boolean> {
  if (typeof window === 'undefined') return false

  if (activeAdPromise) {
    return activeAdPromise
  }

  if (!shouldRequestAd()) {
    return false
  }

  activeAdPromise = (async () => {
    const payload = await fetchInstreamAdPayload(options)
    if (!payload) return false
    const shown = await renderAdOverlay(payload)
    if (shown) {
      setNumberToSession(LAST_AD_AT_KEY, Date.now())
    }
    return shown
  })()

  try {
    return await activeAdPromise
  } finally {
    activeAdPromise = null
    if (options.placement) {
      // Placeholder for future per-placement analytics.
    }
  }
}
