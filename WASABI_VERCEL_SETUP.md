# Wasabi Storage + Vercel CDN Setup Guide

This guide explains how to set up Wasabi storage with Vercel CDN for permanent, shareable URLs in your XapZap social media app.

## Architecture Overview

```
User Request → Vercel CDN → Wasabi Storage
     ↓              ↓             ↓
Permanent URL → URL Rewriting → Public Files
```

- **Files stored publicly** in Wasabi `public/` folder
- **Permanent URLs** served through Vercel CDN
- **No expiration** - URLs work forever
- **Social media friendly** - perfect for sharing

## Step 1: Set Up Wasabi Account

1. **Create Wasabi Account**: https://wasabi.com
2. **Create Bucket**:
   - Bucket name: `xapzap-media` (or your choice)
   - Region: `us-east-1` (or closest to your users)
3. **Create Access Keys**:
   - Go to Access Keys section
   - Create new access key
   - Save `Access Key` and `Secret Key`

## Step 2: Configure Wasabi Bucket Policy

Create a bucket policy to allow public read access to the `public/` folder:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::xapzap-media/public/*"
    }
  ]
}
```

## Step 3: Configure Vercel Rewrites

Since you're already hosting on Vercel, you just need to add URL rewrites in your `next.config.mjs`:

```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  async rewrites() {
    return [
      {
        source: '/media/:path*',
        destination: 'https://xapzap-media.s3.wasabisys.com/public/:path*',
      },
    ]
  },
}

export default nextConfig
```

This rewrites `/media/filename.jpg` requests to your Wasabi bucket.

## Step 4: Environment Configuration

Update your `.env` file with Wasabi credentials:

```env
# Wasabi Storage Configuration
WASABI_ACCESS_KEY=your-actual-access-key
WASABI_SECRET_KEY=your-actual-secret-key
WASABI_REGION=us-east-1
WASABI_ENDPOINT=https://s3.wasabisys.com
WASABI_BUCKET=xapzap-media

# Vercel automatically provides VERCEL_URL in production
# No additional CDN configuration needed
```

## Step 5: Deploy to Vercel

1. **Push your changes** to your Git repository
2. **Vercel will automatically deploy** with the new rewrites
3. **SSL Certificate**: Automatically handled by Vercel
4. **CDN**: Automatically enabled on all Vercel deployments

## URL Structure

**Media files are served from `/media/` path** to distinguish them from your main app routes:

- **Images/Videos**: `https://www.xapzap.com/media/filename.jpg`
- **Main App**: `https://www.xapzap.com/profile`, `https://www.xapzap.com/feed`, etc.

This prevents conflicts between your Next.js app routes and media file serving.

## How It Works

### File Upload Flow
1. User uploads file → `storageService.uploadFile()`
2. File stored in Wasabi: `s3://xapzap-media/public/filename.jpg`
3. Returns permanent URL: `https://www.xapzap.com/media/filename.jpg`

### File Access Flow
1. User requests: `https://www.xapzap.com/media/filename.jpg`
2. Vercel rewrites to: `https://xapzap-media.s3.wasabisys.com/public/filename.jpg`
3. Wasabi serves public file
4. Vercel CDN caches and delivers

## Benefits

✅ **Permanent URLs** - Never expire, perfect for social sharing
✅ **Cost Effective** - Wasabi storage + Vercel CDN (included)
✅ **Global CDN** - Vercel's worldwide edge network
✅ **Social Media Ready** - Link previews work perfectly
✅ **SEO Friendly** - Search engines can index media
✅ **Zero Config** - Works out of the box with your Vercel deployment

## Cost Estimate (Monthly)

- **Wasabi Storage**: $5.99/TB
- **Vercel CDN**: Included in your Vercel plan
- **Data Transfer**: $0.04/GB (Wasabi only)

For a growing social media app with 100GB storage + 10TB transfer: ~$400/month

## Security Features

- **Automatic HTTPS** - SSL certificates handled by Vercel
- **DDoS Protection** - Built into Vercel platform
- **Security Headers** - Automatic security headers
- **CORS** - Configurable in Next.js

## Migration from Bunny CDN

Your current setup uses Bunny CDN. To migrate:

1. Upload existing files to Wasabi `public/` folder
2. Update database URLs from `xapzapolami.b-cdn.net` to `www.xapzap.com`
3. Test file access
4. Decommission Bunny CDN

## Troubleshooting

### Files Not Loading
- Check Wasabi bucket permissions
- Verify Next.js rewrites in `next.config.mjs`
- Check Vercel deployment logs
- Ensure bucket policy allows public access

### Slow Performance
- Check Vercel function timeouts
- Consider Wasabi region closer to users
- Enable Vercel Analytics to monitor performance
- Use Vercel's Image Optimization for images

### Upload Failures
- Verify Wasabi credentials in environment variables
- Check bucket exists and permissions
- Ensure `public/` folder is writable
- Check Vercel deployment environment variables

## Support

- **Wasabi Docs**: https://docs.wasabi.com/
- **Vercel Docs**: https://vercel.com/docs
- **Next.js Rewrites**: https://nextjs.org/docs/api-reference/next.config.js/rewrites
- **AWS SDK Issues**: Check GitHub issues for @aws-sdk/client-s3
