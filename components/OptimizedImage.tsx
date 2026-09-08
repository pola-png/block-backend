'use client'

import { useState } from 'react'
import { normalizeWasabiImage } from '../lib/wasabi'

interface OptimizedImageProps {
  src: string
  alt: string
  width?: number
  height?: number
  fill?: boolean
  sizes?: string
  className?: string
  priority?: boolean
  onError?: () => void
  onLoad?: () => void
}

export function OptimizedImage({
  src,
  alt,
  width,
  height,
  fill = false,
  className,
  priority = false,
  onError,
  onLoad
}: OptimizedImageProps) {
  const [isLoading, setIsLoading] = useState(true)
  const proxySrc = normalizeWasabiImage(src) || src

  const handleError = () => {
    setIsLoading(false)
    onError?.()
  }

  const handleLoad = () => {
    setIsLoading(false)
    onLoad?.()
  }

  if (fill) {
    return (
      <>
        {isLoading && <div className="absolute inset-0 bg-gray-200 dark:bg-gray-800 animate-pulse" />}
        <img
          src={proxySrc}
          alt={alt}
          className={`${className} transition-opacity duration-300 ${isLoading ? 'opacity-0' : 'opacity-100'} absolute inset-0 w-full h-full`}
          onError={handleError}
          onLoad={handleLoad}
          loading={priority ? 'eager' : 'lazy'}
          decoding="async"
          referrerPolicy="no-referrer"
        />
      </>
    )
  }

  return (
    <img
      src={proxySrc}
      alt={alt}
      width={width}
      height={height}
      className={`${className} transition-opacity duration-300 ${isLoading ? 'opacity-0' : 'opacity-100'}`}
      onError={handleError}
      onLoad={handleLoad}
      loading={priority ? 'eager' : 'lazy'}
      decoding="async"
      referrerPolicy="no-referrer"
    />
  )
}
