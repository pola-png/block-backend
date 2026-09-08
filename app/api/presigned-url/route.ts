import { NextRequest, NextResponse } from 'next/server'
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3'
import { getSignedUrl } from '@aws-sdk/s3-request-presigner'

export async function POST(request: NextRequest) {
  try {
    const { fileName, fileType } = await request.json()

    const s3Client = new S3Client({
      region: process.env.WASABI_REGION || 'us-east-1',
      endpoint: process.env.WASABI_ENDPOINT || 'https://s3.wasabisys.com',
      credentials: {
        accessKeyId: process.env.WASABI_ACCESS_KEY!,
        secretAccessKey: process.env.WASABI_SECRET_KEY!
      }
    })

    const key = `media/${Date.now()}_${fileName}`

    const command = new PutObjectCommand({
      Bucket: process.env.WASABI_BUCKET || 'xapzap-media',
      Key: key,
      ContentType: fileType
    })

    const presignedUrl = await getSignedUrl(s3Client, command, { expiresIn: 3600 })

    return NextResponse.json({
      presignedUrl,
      key,
      url: `/${key}`
    })
  } catch (error: any) {
    console.error('Presigned URL error:', error)
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
