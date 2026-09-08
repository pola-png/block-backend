export type CreatorPlan = 'free' | 'basic' | 'business'

export interface UploadAccess {
  plan: CreatorPlan
  isVerifiedCreator: boolean
  canUploadImage: boolean
  canUploadVideo: boolean
  canUploadReel: boolean
  canUploadNews: boolean
  canUseAi: boolean
  canUploadLongVideo: boolean
}

export function isVerifiedCreatorProfile(profile: any): boolean {
  const p: any = profile || {}
  return !!p.isVerifiedCreator || !!p.isVerified || p.verificationStatus === 'creator'
}

export function resolveCreatorPlan(profile: any, isAdmin = false): CreatorPlan {
  if (isAdmin) return 'business'

  const p: any = profile || {}
  const approvalStatus = String(p.upgradeApprovalStatus || '')
    .trim()
    .toLowerCase()
  const requestedTier = String(
    p.upgradeRequestedTier || p.requestedTier || p.pendingTier || ''
  )
    .trim()
    .toLowerCase()

  // Admin-approved upgrade should immediately unlock the requested plan.
  if (approvalStatus === 'approved') {
    if (requestedTier === 'business' || requestedTier === 'enterprise') {
      return 'business'
    }
    if (requestedTier === 'basic' || requestedTier === 'premium' || requestedTier === 'pro') {
      return 'basic'
    }
  }

  const rawValues = [
    p.subscriptionTier,
    p.subscription,
    p.planTier,
    p.plan,
    p.creatorPlan,
  ]
    .map((value) => String(value || '').trim().toLowerCase())
    .filter(Boolean)

  if (rawValues.some((value) => value === 'business' || value === 'enterprise')) {
    return 'business'
  }

  // Backward compatibility with old premium/pro naming.
  if (
    rawValues.some(
      (value) =>
        value === 'basic' ||
        value === 'premium' ||
        value === 'pro' ||
        value === 'creator'
    ) ||
    !!p.isPremiumCreator ||
    !!p.isPremium
  ) {
    return 'basic'
  }

  return 'free'
}

export function getUploadAccess(profile: any, isAdmin = false): UploadAccess {
  const plan = resolveCreatorPlan(profile, isAdmin)
  const isVerifiedCreator = isVerifiedCreatorProfile(profile)

  const canUploadVideo = true
  const canUploadReel = canUploadVideo
  const canUploadNews = isAdmin || plan === 'business'
  const canUseAi = isAdmin || plan === 'business'
  const canUploadLongVideo = isAdmin || isVerifiedCreator || plan === 'basic' || plan === 'business'

  return {
    plan,
    isVerifiedCreator,
    canUploadImage: true,
    canUploadVideo,
    canUploadReel,
    canUploadNews,
    canUseAi,
    canUploadLongVideo,
  }
}

export function canUploadPostType(postType: string, profile: any, isAdmin = false): boolean {
  const access = getUploadAccess(profile, isAdmin)
  if (postType === 'news') return access.canUploadNews
  if (postType === 'video') return access.canUploadVideo
  if (postType === 'reel') return access.canUploadReel
  if (postType === 'image' || postType === 'text') return access.canUploadImage
  return false
}
