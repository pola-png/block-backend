// Wasabi Media Proxy Utilities
// Based on the property listing app's approach

/**
 * Normalize Wasabi image URLs to proxy URLs
 * Input: ["property-images/abc.jpg"] or "[\"property-images/abc.jpg\"]" (JSON string)
 * Output: ["/api/image-proxy?path=property-images%2Fabc.jpg"]
 */
export function normalizeWasabiImageArray(images: string[] | string | null | undefined): string[] {
  if (!images) return []

  let imageArray: string[]

  // Handle JSON string format
  if (typeof images === 'string') {
    try {
      imageArray = JSON.parse(images)
    } catch {
      // If not JSON, treat as single URL
      imageArray = [images]
    }
  } else {
    imageArray = images
  }

  // Filter out empty/null values and convert to proxy URLs
  return imageArray
    .filter(img => img && typeof img === 'string' && img.trim().length > 0)
    .map(img => toWasabiProxyPath(img))
    .filter(url => url !== null)
}

/**
 * Convert Wasabi URL/key to proxy path
 * Detects if URL is Wasabi (ends with .wasabisys.com)
 * Extracts the object key from full URL
 * Returns: /api/image-proxy?path={encoded-key}
 */
export function toWasabiProxyPath(urlOrKey: string): string | null {
  if (!urlOrKey || typeof urlOrKey !== 'string') return null

  let objectKey = urlOrKey.trim()

  // Support appwrite:// protocol (new Appwrite Storage system)
  if (objectKey.startsWith('appwrite://')) {
    try {
      const url = new URL(objectKey)
      const bucketId = url.host
      const pathParts = url.pathname.split('/').filter(p => p)
      const fileId = pathParts[0] || ''
      const fileName = pathParts.slice(1).join('/')
      
      if (bucketId && fileId) {
        return `https://nyc.cloud.appwrite.io/v1/storage/buckets/${bucketId}/files/${fileId}/view?project=690641ad0029b51eefe0&mode=public${fileName ? `&filename=${encodeURIComponent(fileName)}` : ''}`
      }
    } catch (e) {
      console.error('Failed to parse appwrite ref:', e)
    }
  }

  // If already a full Appwrite storage view URL, return as-is
  if (objectKey.includes('/storage/buckets/') && objectKey.includes('/files/')) {
    return objectKey
  }

  // If it's already a full HTTP/HTTPS URL (and not Wasabi or Appwrite), return it as-is
  if ((objectKey.startsWith('http://') || objectKey.startsWith('https://')) && 
      !objectKey.includes('wasabisys.com') && 
      !objectKey.includes('/storage/buckets/')) {
    return objectKey
  }

  // If it's a full Wasabi URL, extract the key
  if (objectKey.includes('wasabisys.com')) {
    try {
      const url = new URL(objectKey)
      // Extract path after bucket name
      const pathParts = url.pathname.split('/').filter(p => p)
      if (pathParts.length >= 2) {
        // Remove bucket name and join remaining parts
        objectKey = pathParts.slice(1).join('/')
      } else {
        return null
      }
    } catch {
      return null
    }
  }

  // If it's already a proxy URL, return as-is
  if (objectKey.startsWith('/api/image-proxy')) {
    return objectKey
  }

  // If it's a full CDN URL from our system, extract the media path
  if (objectKey.includes('/media/')) {
    const mediaPath = objectKey.split('/media/')[1]
    if (mediaPath) {
      objectKey = mediaPath
    }
  }

  // Remove any leading slashes and encode
  objectKey = objectKey.replace(/^\/+/, '')
  const encodedKey = encodeURIComponent(objectKey)

  return `/api/image-proxy?path=${encodedKey}`
}

/**
 * Convert Wasabi video URL/key to video proxy path
 */
export function toWasabiVideoProxyPath(urlOrKey: string): string | null {
  if (!urlOrKey || typeof urlOrKey !== 'string') return null

  let objectKey = urlOrKey.trim()

  // Support appwrite:// protocol
  if (objectKey.startsWith('appwrite://')) {
    try {
      const url = new URL(objectKey)
      const bucketId = url.host
      const pathParts = url.pathname.split('/').filter(p => p)
      const fileId = pathParts[0] || ''
      const fileName = pathParts.slice(1).join('/')
      
      if (bucketId && fileId) {
        return `https://nyc.cloud.appwrite.io/v1/storage/buckets/${bucketId}/files/${fileId}/view?project=690641ad0029b51eefe0&mode=public${fileName ? `&filename=${encodeURIComponent(fileName)}` : ''}`
      }
    } catch (e) {
      console.error('Failed to parse appwrite ref:', e)
    }
  }

  // If already a full Appwrite storage view URL, return as-is
  if (objectKey.includes('/storage/buckets/') && objectKey.includes('/files/')) {
    return objectKey
  }

  // If it's already a full HTTP/HTTPS URL (and not Wasabi or Appwrite), return it as-is
  if ((objectKey.startsWith('http://') || objectKey.startsWith('https://')) && 
      !objectKey.includes('wasabisys.com') && 
      !objectKey.includes('/storage/buckets/')) {
    return objectKey
  }

  // If it's a full Wasabi URL, extract the key
  if (objectKey.includes('wasabisys.com')) {
    try {
      const url = new URL(objectKey)
      const pathParts = url.pathname.split('/').filter(p => p)
      if (pathParts.length >= 2) {
        objectKey = pathParts.slice(1).join('/')
      } else {
        return null
      }
    } catch {
      return null
    }
  }

  // If it's already a proxy URL, return as-is
  if (objectKey.startsWith('/api/video-proxy')) {
    return objectKey
  }

  // If it's a full CDN URL from our system, extract the media path
  if (objectKey.includes('/media/')) {
    const mediaPath = objectKey.split('/media/')[1]
    if (mediaPath) {
      objectKey = mediaPath
    }
  }

  // Remove any leading slashes and encode
  objectKey = objectKey.replace(/^\/+/, '')
  const encodedKey = encodeURIComponent(objectKey)

  return `/api/video-proxy?path=${encodedKey}`
}

/**
 * Convert single image URL to proxy URL
 */
export function normalizeWasabiImage(image: string | null | undefined): string | null {
  if (!image) return null
  return toWasabiProxyPath(image)
}

/**
 * Convert single video URL to proxy URL
 */
export function normalizeWasabiVideo(video: string | null | undefined): string | null {
  if (!video) return null
  return toWasabiVideoProxyPath(video)
}

/**
 * Check if a URL is already a proxy URL
 */
export function isProxyUrl(url: string): boolean {
  return url?.startsWith('/api/image-proxy') || false
}

/**
 * Get the original key from a proxy URL
 */
export function getKeyFromProxyUrl(proxyUrl: string): string | null {
  if (!isProxyUrl(proxyUrl)) return null

  try {
    const url = new URL(proxyUrl, 'http://localhost')
    const path = url.searchParams.get('path')
    return path ? decodeURIComponent(path) : null
  } catch {
    return null
  }
}