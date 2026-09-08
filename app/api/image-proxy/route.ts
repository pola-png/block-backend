import { NextRequest, NextResponse } from 'next/server'
import { S3Client, GetObjectCommand } from '@aws-sdk/client-s3'
import sharp from 'sharp'

// Wasabi configuration
const wasabiConfig = {
  region: process.env.WASABI_REGION || 'us-east-1',
  endpoint: process.env.WASABI_ENDPOINT || 'https://s3.wasabisys.com',
  credentials: {
    accessKeyId: process.env.WASABI_ACCESS_KEY || '',
    secretAccessKey: process.env.WASABI_SECRET_KEY || ''
  }
}

const bucketName = process.env.WASABI_BUCKET || 'xapzap-media'
const s3Client = new S3Client(wasabiConfig)

export const runtime = 'nodejs'

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const path = searchParams.get('path')
    const width = parseInt(searchParams.get('w') || '1200')
    const quality = parseInt(searchParams.get('q') || '80')

    if (!path) {
      return NextResponse.json({ error: 'Path parameter required' }, { status: 400 })
    }

    const key = path.startsWith('/') ? path.substring(1) : path
    const ext = key.split('.').pop()?.toLowerCase()
    const isVideo = ext === 'mp4' || ext === 'webm' || ext === 'mov'

    if (isVideo) {
      return NextResponse.json(
        { error: 'Use /api/video-proxy for video files' },
        { status: 415 }
      )
    }

    // Fetch from Wasabi
    const command = new GetObjectCommand({
      Bucket: bucketName,
      Key: key,
    })

    const response = await s3Client.send(command)

    if (!response.Body) {
      return NextResponse.json({ error: 'File not found' }, { status: 404 })
    }

    // Images: optimize with Sharp
    const chunks = []
    for await (const chunk of response.Body as any) {
      chunks.push(chunk)
    }
    const buffer = Buffer.concat(chunks)

    const optimized = await sharp(buffer)
      .resize(width, null, { withoutEnlargement: true })
      .webp({ quality })
      .toBuffer()

    return new NextResponse(optimized as any, {
      status: 200,
      headers: {
        'Content-Type': 'image/webp',
        'Cache-Control': 'public, max-age=31536000, immutable',
      }
    })

  } catch (error) {
    console.error('Image proxy error:', error)
    return NextResponse.json(
      { error: 'Failed to fetch file' },
      { status: 500 }
    )
  }
}
