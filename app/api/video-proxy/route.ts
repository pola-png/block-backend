import { NextRequest, NextResponse } from 'next/server'
import { S3Client, GetObjectCommand } from '@aws-sdk/client-s3'
import { Readable } from 'stream'

const wasabiConfig = {
  region: process.env.WASABI_REGION || 'us-east-1',
  endpoint: process.env.WASABI_ENDPOINT || 'https://s3.wasabisys.com',
  credentials: {
    accessKeyId: process.env.WASABI_ACCESS_KEY || '',
    secretAccessKey: process.env.WASABI_SECRET_KEY || '',
  },
}

const bucketName = process.env.WASABI_BUCKET || 'xapzap-media'
const s3Client = new S3Client(wasabiConfig)

export const runtime = 'nodejs'

function toWebReadableStream(body: any): ReadableStream {
  if (!body) throw new Error('Missing response body')
  if (typeof body.transformToWebStream === 'function') {
    return body.transformToWebStream()
  }
  if (body instanceof Readable) {
    return Readable.toWeb(body) as unknown as ReadableStream
  }
  return body as ReadableStream
}

function isVideoKey(key: string): boolean {
  const ext = key.split('.').pop()?.toLowerCase()
  return ext === 'mp4' || ext === 'webm' || ext === 'mov'
}

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const path = searchParams.get('path')
    if (!path) {
      return NextResponse.json({ error: 'Path parameter required' }, { status: 400 })
    }

    const key = path.startsWith('/') ? path.substring(1) : path
    if (!isVideoKey(key)) {
      return NextResponse.json(
        { error: 'Only video files are supported on /api/video-proxy' },
        { status: 415 }
      )
    }

    const range = request.headers.get('range')
    const command = new GetObjectCommand({
      Bucket: bucketName,
      Key: key,
      ...(range ? { Range: range } : {}),
    })

    const response = await s3Client.send(command)
    if (!response.Body) {
      return NextResponse.json({ error: 'File not found' }, { status: 404 })
    }

    const stream = toWebReadableStream(response.Body)
    const status = range && response.ContentRange ? 206 : 200
    const headers = new Headers()
    headers.set('Content-Type', response.ContentType || 'video/mp4')
    headers.set('Cache-Control', 'public, max-age=31536000, immutable')
    headers.set('Accept-Ranges', response.AcceptRanges || 'bytes')
    if (response.ContentRange) {
      headers.set('Content-Range', response.ContentRange)
    }
    if (typeof response.ContentLength === 'number' && Number.isFinite(response.ContentLength)) {
      headers.set('Content-Length', String(response.ContentLength))
    }

    return new NextResponse(stream, {
      status,
      headers,
    })
  } catch (error) {
    console.error('Video proxy error:', error)
    const maybeCode = (error as any)?.Code || (error as any)?.name
    if (maybeCode === 'InvalidRange') {
      return NextResponse.json(
        { error: 'Invalid range' },
        { status: 416 }
      )
    }
    return NextResponse.json(
      { error: 'Failed to fetch file' },
      { status: 500 }
    )
  }
}
