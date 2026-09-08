'use client'

import { ReelsScreen } from '../../ReelsScreen'

export default function ReelsPage() {
  // Nudge reels content up slightly to remove the tiny gap
  // between the horizontal tab bar and the first reel.
  return (
    <div className="-mt-2">
      <ReelsScreen />
    </div>
  )
}
