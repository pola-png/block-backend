'use client'

import { useState, useEffect } from 'react'
import { DollarSign, TrendingUp, Crown, CheckCircle, Clock, CreditCard } from 'lucide-react'
import appwriteService from './appwriteService'
import { cn } from './utils'

interface Earnings {
  total: number
  month: number
  boosts: number
  eligible: boolean
}
