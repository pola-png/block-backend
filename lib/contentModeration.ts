import * as nsfwjs from 'nsfwjs'
import * as tf from '@tensorflow/tfjs'

let model: nsfwjs.NSFWJS | null = null

export async function loadNSFWModel() {
  if (!model) {
    await tf.ready()
    model = await nsfwjs.load()
  }
  return model
}

export async function checkVideoForNudity(videoElement: HTMLVideoElement): Promise<{
  isSafe: boolean
  predictions: any[]
  flagReason?: string
}> {
  try {
    const nsfwModel = await loadNSFWModel()
    
    // Capture frame at 3 different points
    const timestamps = [0.1, 0.5, 0.8]
    const results = []
    
    for (const timestamp of timestamps) {
      videoElement.currentTime = videoElement.duration * timestamp
      await new Promise(resolve => setTimeout(resolve, 500))
      
      const predictions = await nsfwModel.classify(videoElement)
      results.push(predictions)
    }
    
    // Check if any frame has inappropriate content
    const threshold = 0.6
    for (const predictions of results) {
      const porn = predictions.find(p => p.className === 'Porn')
      const hentai = predictions.find(p => p.className === 'Hentai')
      const sexy = predictions.find(p => p.className === 'Sexy')
      
      if (porn && porn.probability > threshold) {
        return { isSafe: false, predictions, flagReason: 'Pornographic content detected' }
      }
      if (hentai && hentai.probability > threshold) {
        return { isSafe: false, predictions, flagReason: 'Explicit animated content detected' }
      }
      if (sexy && sexy.probability > 0.8) {
        return { isSafe: false, predictions, flagReason: 'Sexually suggestive content detected' }
      }
    }
    
    return { isSafe: true, predictions: results[0] }
  } catch (error) {
    console.error('Content moderation error:', error)
    return { isSafe: true, predictions: [] }
  }
}

export async function flagPost(postId: string, reason: string) {
  try {
    // Flag the post in database
    const response = await fetch('/api/moderation/flag', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ postId, reason, flaggedAt: new Date().toISOString() })
    })
    return response.ok
  } catch (error) {
    console.error('Failed to flag post:', error)
    return false
  }
}
