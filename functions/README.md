# XapZap Appwrite Functions

Serverless functions for XapZap social media platform.

## Functions

### upload-media
Handles media uploads to Wasabi storage for posts, reels, and stories.

## Deployment

1. Connect this repository to Appwrite
2. Set environment variables in Appwrite Console
3. Deploy automatically via GitHub integration

## Environment Variables

- `WASABI_ACCESS_KEY` - Wasabi access key
- `WASABI_SECRET_KEY` - Wasabi secret key
- `WASABI_REGION` - Wasabi region (default: us-east-1)
- `WASABI_ENDPOINT` - Wasabi endpoint (default: https://s3.wasabisys.com)
- `WASABI_BUCKET` - Wasabi bucket name (default: xapzap-media)
