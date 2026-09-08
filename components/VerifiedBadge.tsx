import { BadgeCheck } from 'lucide-react'

interface VerifiedBadgeProps {
  className?: string
  isPremium?: boolean
}

export function VerifiedBadge({ className = '', isPremium = false }: VerifiedBadgeProps) {
  const gradientId = isPremium ? 'gold-gradient' : 'cyan-green-gradient'

  return (
    <span className="inline-flex shrink-0" title={isPremium ? "Premium Verified" : "Verified"}>
      <svg width="0" height="0" className="absolute" aria-hidden="true">
        <defs>
          <linearGradient id="gold-gradient" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor="#FFD700" />
            <stop offset="50%" stopColor="#FFA500" />
            <stop offset="100%" stopColor="#FF8C00" />
          </linearGradient>
          <linearGradient id="cyan-green-gradient" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor="#00C9FF" />
            <stop offset="100%" stopColor="#92FE9D" />
          </linearGradient>
        </defs>
      </svg>
      <BadgeCheck
        className={`inline-block ${className}`}
        style={{
          fill: `url(#${gradientId})`,
          stroke: 'var(--verified-badge-stroke, #fff)',
          strokeWidth: 2,
        }}
        aria-label={isPremium ? "Premium Verified" : "Verified"}
      />
    </span>
  )
}
