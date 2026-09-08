# Content Moderation Setup

## Install dependencies:
```bash
npm install nsfwjs @tensorflow/tfjs
```

## Usage in ReelsScreen.tsx:

```typescript
import { useVideoModeration } from './useVideoModeration'

// Inside component:
const videoRef = useRef<HTMLVideoElement>(null)
const { isChecked } = useVideoModeration(post.id, videoRef)
```

## How it works:
1. On first video watch, extracts 3 frames (10%, 50%, 80% of duration)
2. Analyzes each frame with NSFW.js model
3. If inappropriate content detected (>60% confidence), flags post
4. Flagged posts are hidden from feeds automatically
5. System marks violation reason in database

## Thresholds:
- Porn: 60% confidence
- Hentai: 60% confidence  
- Sexy: 80% confidence

## API Endpoint:
POST /api/moderation/flag
Body: { postId, reason, flaggedAt }
