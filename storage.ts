import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3'

class StorageService {
  private static instance: StorageService
  private s3Client: S3Client

  // Wasabi configuration
  private readonly wasabiConfig = {
    region: process.env.WASABI_REGION || 'us-east-1',
    endpoint: process.env.WASABI_ENDPOINT || 'https://s3.wasabisys.com',
    credentials: {
      accessKeyId: process.env.WASABI_ACCESS_KEY || '',
      secretAccessKey: process.env.WASABI_SECRET_KEY || ''
    }
  }

  private readonly bucketName = process.env.WASABI_BUCKET || 'xapzap-media'

  private constructor() {
    this.s3Client = new S3Client(this.wasabiConfig)
  }

  static getInstance(): StorageService {
    if (!StorageService.instance) {
      StorageService.instance = new StorageService()
    }
    return StorageService.instance
  }

  async uploadFile(file: File, path?: string): Promise<string> {
    try {
      const fileName = path || `${Date.now()}_${file.name}`
      const buffer = await file.arrayBuffer()
      const uint8Array = new Uint8Array(buffer)

      const uploadParams = {
        Bucket: this.bucketName,
        Key: `media/${fileName}`,
        Body: uint8Array,
        ContentType: file.type
      }

      const command = new PutObjectCommand(uploadParams)
      await this.s3Client.send(command)

      // TODO: Trigger Appwrite Function for video optimization
      // if (file.type.startsWith('video/')) {
      //   await this.triggerAppwriteOptimization(fileName)
      // }

      return `/media/${fileName}`
    } catch (error) {
      console.error('Upload error:', error)
      throw error
    }
  }

  getFileUrl(fileName: string): string {
    return `/media/${fileName}`
  }

  extractFileName(url: string): string {
    return url.replace('/media/', '')
  }
}

export const storageService = StorageService.getInstance()
export default storageService