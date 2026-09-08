# XapZap Web

Modern web version of the XapZap social media platform built with Next.js, React, TypeScript, and Tailwind CSS.

## Features

- 🏠 **Home Feed** - For You, Following, Watch, Reels, News, Live
- 📱 **Stories** - 24-hour temporary media sharing
- 💬 **Chat** - Real-time messaging
- 🔔 **Notifications** - Live updates
- 👤 **Profiles** - User profiles with follow system
- 📸 **Media Upload** - Images and videos via Wasabi + Fastly CDN
- 🎨 **Responsive Design** - Works on all devices

## Tech Stack

- **Framework**: Next.js 14
- **Language**: TypeScript
- **Styling**: Tailwind CSS
- **Backend**: Appwrite
- **Storage**: Wasabi S3-compatible storage
- **CDN**: Fastly (permanent URLs)
- **Real-time**: Appwrite Realtime

## Deployment

This app is configured for deployment on Appwrite Web Hosting.

### Environment Variables

Set these in your Appwrite project:

```
NEXT_PUBLIC_APPWRITE_ENDPOINT=https://nyc.cloud.appwrite.io/v1
NEXT_PUBLIC_APPWRITE_PROJECT_ID=690641ad0029b51eefe0

# Wasabi Storage Configuration
WASABI_ACCESS_KEY=your-actual-access-key
WASABI_SECRET_KEY=your-actual-secret-key
WASABI_REGION=us-east-1
WASABI_ENDPOINT=https://s3.wasabisys.com
WASABI_BUCKET=xapzap-media

# Fastly CDN Configuration
FASTLY_CDN_URL=https://cdn.xapzap.com
```

### Build Commands

- **Build Command**: `npm run build`
- **Output Directory**: `out`

## Development

```bash
npm install
npm run dev
```

## License

Part of the XapZap social media platform.