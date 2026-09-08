# Deployment Instructions

## Setup

1. Create new GitHub repository: `xapzap-functions`
2. Copy the `functions` folder to the new repository
3. Push to GitHub

## Connect to Appwrite

1. Go to Appwrite Console > Functions
2. Create new function: `upload-media`
3. Connect to GitHub repository
4. Set branch: `main`
5. Set root directory: `upload-media`
6. Set entrypoint: `src/main.js`
7. Set runtime: `node-18.0`
8. Add environment variables
9. Deploy

## Environment Variables

```
WASABI_ACCESS_KEY=your_access_key
WASABI_SECRET_KEY=your_secret_key
WASABI_REGION=us-east-1
WASABI_ENDPOINT=https://s3.wasabisys.com
WASABI_BUCKET=xapzap-media
```

## Auto-Deploy

Every push to `main` branch will automatically deploy to Appwrite.
