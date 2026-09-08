'use client'

import { useState, useEffect } from 'react'
import { BarChart3, Users, Eye, TrendingUp, Activity, Calendar, ArrowUpRight } from 'lucide-react'
import appwriteService from './appwriteService'
import { formatCount } from './utils'

type Period = '7d' | '30d' | '90d'

interface ChartPoint {
  label: string
  value: number
}

export function DashboardScreen() {
  const [period, setPeriod] = useState<Period>('30d')
  const [stats, setStats] = useState({
    posts: 0,
    followers: 0,
    impressions: 0,
    views: 0
  })
  const [loading, setLoading] = useState(true)
  const [hoveredPerformancePoint, setHoveredPerformancePoint] = useState<ChartPoint | null>(null)
  const [hoveredFollowerPoint, setHoveredFollowerPoint] = useState<ChartPoint | null>(null)

  useEffect(() => {
    loadStats()
  }, [])

  const loadStats = async () => {
    try {
      const user = await appwriteService.getCurrentUser()
      if (!user) return

      const [followers, postsResult] = await Promise.all([
        appwriteService.getFollowerCount(user.$id),
        appwriteService.fetchPostsByUserIds([user.$id], 100)
      ])

      const totalImpressions = postsResult.documents.reduce((sum, doc) => sum + (doc.impressions || 0), 0)
      const totalViews = postsResult.documents.reduce((sum, doc) => sum + (doc.views || 0), 0)

      setStats({
        posts: postsResult.documents.length,
        followers,
        impressions: totalImpressions,
        views: totalViews
      })
    } catch (error) {
      console.error('Failed to load dashboard stats:', error)
    } finally {
      setLoading(false)
    }
  }

  // Generate high-quality mock data for selected intervals
  const getPerformanceData = (): ChartPoint[] => {
    const counts = period === '7d' ? 7 : period === '30d' ? 15 : 30
    const points: ChartPoint[] = []
    const baseValue = Math.max(12, stats.views / Math.max(1, counts))
    
    for (let i = counts - 1; i >= 0; i--) {
      const date = new Date()
      date.setDate(date.getDate() - i * (period === '90d' ? 3 : 1))
      const label = date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
      // Add standard organic fluctuations
      const value = Math.round(baseValue * (0.6 + Math.sin(i * 0.8) * 0.35 + Math.random() * 0.25))
      points.push({ label, value })
    }
    return points
  }

  const getFollowerGrowthData = (): ChartPoint[] => {
    const counts = period === '7d' ? 7 : period === '30d' ? 15 : 30
    const points: ChartPoint[] = []
    let currentTotal = stats.followers
    
    // Work backward
    for (let i = 0; i < counts; i++) {
      const date = new Date()
      date.setDate(date.getDate() - i * (period === '90d' ? 3 : 1))
      const label = date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
      points.unshift({ label, value: Math.max(0, Math.round(currentTotal)) })
      currentTotal -= Math.round(1 + Math.random() * (period === '7d' ? 2 : 5))
    }
    return points
  }

  if (loading) {
    return (
      <div className="max-w-6xl mx-auto p-8 space-y-6">
        <div className="animate-pulse space-y-6">
          <div className="h-8 bg-muted rounded-lg w-48" />
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
            <div className="h-32 bg-muted rounded-xl" />
            <div className="h-32 bg-muted rounded-xl" />
            <div className="h-32 bg-muted rounded-xl" />
            <div className="h-32 bg-muted rounded-xl" />
          </div>
        </div>
      </div>
    )
  }

  const performancePoints = getPerformanceData()
  const followerPoints = getFollowerGrowthData()

  // Find max values for percentage scaling of charts
  const maxPerformance = Math.max(...performancePoints.map(p => p.value), 1)
  const maxFollowers = Math.max(...followerPoints.map(p => p.value), 1)
  const minFollowers = Math.min(...followerPoints.map(p => p.value), maxFollowers - 1)

  return (
    <div className="max-w-6xl mx-auto p-6 space-y-6 text-[rgb(var(--text-primary))] bg-[rgb(var(--bg-primary))]">
      <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-extrabold tracking-tight text-[rgb(var(--text-primary))]">Dashboard</h1>
          <p className="text-[rgb(var(--text-secondary))] text-sm">Insights & performance overview</p>
        </div>
        
        <div className="flex items-center gap-3">
          <div className="bg-[rgb(var(--bg-secondary))] border border-[rgb(var(--border-color))] rounded-xl p-1 flex gap-1 text-xs font-semibold">
            {(['7d', '30d', '90d'] as Period[]).map((p) => (
              <button
                key={p}
                onClick={() => setPeriod(p)}
                className={`px-3 py-1.5 rounded-lg transition-all ${
                  period === p 
                    ? 'bg-blue-500 text-white shadow-sm' 
                    : 'text-[rgb(var(--text-secondary))] hover:text-[rgb(var(--text-primary))]'
                }`}
              >
                {p === '7d' ? '7 Days' : p === '30d' ? '30 Days' : '90 Days'}
              </button>
            ))}
          </div>
          <button className="px-5 py-2.5 bg-blue-500 hover:bg-blue-600 text-white rounded-xl font-bold transition-all text-xs shadow-md flex items-center gap-1.5">
            Export Data <ArrowUpRight className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
        {/* Card 1: Posts */}
        <div className="group relative bg-[rgb(var(--bg-secondary))] p-6 rounded-2xl border border-[rgb(var(--border-color))] shadow-sm transition-all hover:-translate-y-1 hover:shadow-md">
          <div className="absolute inset-0 bg-gradient-to-br from-blue-500/5 to-transparent rounded-2xl opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none" />
          <div className="flex items-center relative z-10">
            <div className="p-3 bg-blue-500/10 rounded-xl group-hover:bg-blue-500/20 transition-colors">
              <BarChart3 className="w-6 h-6 text-blue-500" />
            </div>
            <div className="ml-4">
              <p className="text-xs font-semibold text-[rgb(var(--text-secondary))] uppercase tracking-wider">Posts</p>
              <p className="text-3xl font-extrabold text-[rgb(var(--text-primary))] mt-1">{formatCount(stats.posts)}</p>
            </div>
          </div>
        </div>

        {/* Card 2: Followers */}
        <div className="group relative bg-[rgb(var(--bg-secondary))] p-6 rounded-2xl border border-[rgb(var(--border-color))] shadow-sm transition-all hover:-translate-y-1 hover:shadow-md">
          <div className="absolute inset-0 bg-gradient-to-br from-purple-500/5 to-transparent rounded-2xl opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none" />
          <div className="flex items-center relative z-10">
            <div className="p-3 bg-purple-500/10 rounded-xl group-hover:bg-purple-500/20 transition-colors">
              <Users className="w-6 h-6 text-purple-500" />
            </div>
            <div className="ml-4">
              <p className="text-xs font-semibold text-[rgb(var(--text-secondary))] uppercase tracking-wider">Followers</p>
              <p className="text-3xl font-extrabold text-[rgb(var(--text-primary))] mt-1">{formatCount(stats.followers)}</p>
            </div>
          </div>
        </div>

        {/* Card 3: Impressions */}
        <div className="group relative bg-[rgb(var(--bg-secondary))] p-6 rounded-2xl border border-[rgb(var(--border-color))] shadow-sm transition-all hover:-translate-y-1 hover:shadow-md">
          <div className="absolute inset-0 bg-gradient-to-br from-pink-500/5 to-transparent rounded-2xl opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none" />
          <div className="flex items-center relative z-10">
            <div className="p-3 bg-pink-500/10 rounded-xl group-hover:bg-pink-500/20 transition-colors">
              <Eye className="w-6 h-6 text-pink-500" />
            </div>
            <div className="ml-4">
              <p className="text-xs font-semibold text-[rgb(var(--text-secondary))] uppercase tracking-wider">Impressions</p>
              <p className="text-3xl font-extrabold text-[rgb(var(--text-primary))] mt-1">{formatCount(stats.impressions)}</p>
            </div>
          </div>
        </div>

        {/* Card 4: Views */}
        <div className="group relative bg-[rgb(var(--bg-secondary))] p-6 rounded-2xl border border-[rgb(var(--border-color))] shadow-sm transition-all hover:-translate-y-1 hover:shadow-md">
          <div className="absolute inset-0 bg-gradient-to-br from-green-500/5 to-transparent rounded-2xl opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none" />
          <div className="flex items-center relative z-10">
            <div className="p-3 bg-green-500/10 rounded-xl group-hover:bg-green-500/20 transition-colors">
              <TrendingUp className="w-6 h-6 text-green-500" />
            </div>
            <div className="ml-4">
              <p className="text-xs font-semibold text-[rgb(var(--text-secondary))] uppercase tracking-wider">Views</p>
              <p className="text-3xl font-extrabold text-[rgb(var(--text-primary))] mt-1">{formatCount(stats.views)}</p>
            </div>
          </div>
        </div>
      </div>

      {/* Modern High-Fidelity SVG Charts */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        
        {/* Performance Chart */}
        <div className="bg-[rgb(var(--bg-secondary))] p-6 rounded-2xl border border-[rgb(var(--border-color))] shadow-sm">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-bold flex items-center gap-2 text-[rgb(var(--text-primary))]">
              <Activity className="w-5 h-5 text-blue-500" />
              Post Performance
            </h2>
            {hoveredPerformancePoint ? (
              <span className="text-xs font-extrabold text-blue-500 bg-blue-500/10 px-2 py-1 rounded-md animate-fade-in">
                {hoveredPerformancePoint.label}: {formatCount(hoveredPerformancePoint.value)} views
              </span>
            ) : (
              <span className="text-xs text-[rgb(var(--text-secondary))]">Hover nodes for insights</span>
            )}
          </div>
          
          <div className="relative w-full h-72 border border-[rgb(var(--border-color))]/30 rounded-2xl bg-[rgb(var(--bg-primary))] p-4 flex items-end">
            <div className="absolute inset-0 p-6 flex flex-col justify-between pointer-events-none">
              <div className="w-full border-b border-[rgb(var(--border-color))]/10 h-0" />
              <div className="w-full border-b border-[rgb(var(--border-color))]/10 h-0" />
              <div className="w-full border-b border-[rgb(var(--border-color))]/10 h-0" />
              <div className="w-full border-b border-[rgb(var(--border-color))]/10 h-0 animate-pulse" />
            </div>
            
            <div className="w-full h-full flex items-end justify-between relative z-10 pt-6 px-2">
              {performancePoints.map((point, index) => {
                const heightPercent = (point.value / maxPerformance) * 100
                return (
                  <div
                    key={index}
                    className="flex flex-col items-center flex-1 group/bar cursor-pointer"
                    onMouseEnter={() => setHoveredPerformancePoint(point)}
                    onMouseLeave={() => setHoveredPerformancePoint(null)}
                  >
                    <div className="w-full flex justify-center items-end h-52 relative">
                      <div
                        style={{ height: `${Math.max(8, heightPercent)}%` }}
                        className="w-4 sm:w-6 bg-gradient-to-t from-blue-600 to-blue-400 group-hover/bar:from-blue-500 group-hover/bar:to-cyan-400 rounded-t-lg transition-all duration-300 relative shadow-sm"
                      >
                        <div className="absolute -top-8 left-1/2 -translate-x-1/2 bg-gray-900 dark:bg-white text-white dark:text-gray-900 text-[10px] px-2 py-0.5 rounded shadow-lg pointer-events-none opacity-0 group-hover/bar:opacity-100 transition-opacity font-bold whitespace-nowrap z-20">
                          {point.value}
                        </div>
                      </div>
                    </div>
                    <span className="text-[10px] font-semibold text-[rgb(var(--text-secondary))] mt-2 truncate w-full text-center">
                      {index % (period === '90d' ? 4 : 2) === 0 ? point.label : ''}
                    </span>
                  </div>
                )
              })}
            </div>
          </div>
        </div>

        {/* Follower Growth Chart */}
        <div className="bg-[rgb(var(--bg-secondary))] p-6 rounded-2xl border border-[rgb(var(--border-color))] shadow-sm">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-bold flex items-center gap-2 text-[rgb(var(--text-primary))]">
              <Users className="w-5 h-5 text-purple-500" />
              Followers Analytics
            </h2>
            {hoveredFollowerPoint ? (
              <span className="text-xs font-extrabold text-purple-500 bg-purple-500/10 px-2 py-1 rounded-md animate-fade-in">
                {hoveredFollowerPoint.label}: {formatCount(hoveredFollowerPoint.value)} total
              </span>
            ) : (
              <span className="text-xs text-[rgb(var(--text-secondary))]">Hover nodes for insights</span>
            )}
          </div>
          
          <div className="relative w-full h-72 border border-[rgb(var(--border-color))]/30 rounded-2xl bg-[rgb(var(--bg-primary))] p-4 flex items-end overflow-hidden">
            {/* SVG Trendline Area Chart */}
            <svg className="absolute inset-0 w-full h-full p-6 pt-12 pb-10" viewBox="0 0 100 100" preserveAspectRatio="none">
              <defs>
                <linearGradient id="purpleGrad" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="rgb(168, 85, 247)" stopOpacity="0.25" />
                  <stop offset="100%" stopColor="rgb(168, 85, 247)" stopOpacity="0.0" />
                </linearGradient>
              </defs>
              
              {/* Gridlines */}
              <line x1="0" y1="25" x2="100" y2="25" stroke="rgba(255,255,255,0.03)" strokeWidth="0.5" />
              <line x1="0" y1="50" x2="100" y2="50" stroke="rgba(255,255,255,0.03)" strokeWidth="0.5" />
              <line x1="0" y1="75" x2="100" y2="75" stroke="rgba(255,255,255,0.03)" strokeWidth="0.5" />

              {/* Path coordinates generation */}
              {(() => {
                const points = followerPoints.map((p, idx) => {
                  const x = (idx / (followerPoints.length - 1)) * 100
                  const diffRange = maxFollowers - minFollowers || 1
                  const y = 100 - ((p.value - minFollowers) / diffRange) * 85
                  return { x, y }
                })
                
                const pathD = points.reduce((acc, p, i) => 
                  i === 0 ? `M ${p.x} ${p.y}` : `${acc} L ${p.x} ${p.y}`, ''
                )
                
                const areaD = `${pathD} L 100 100 L 0 100 Z`
                
                return (
                  <>
                    <path d={areaD} fill="url(#purpleGrad)" />
                    <path d={pathD} fill="none" stroke="rgb(168, 85, 247)" strokeWidth="1.5" strokeLinecap="round" />
                  </>
                )
              })()}
            </svg>

            {/* Interactive Hover Nodes */}
            <div className="absolute inset-0 p-6 pt-12 pb-10 flex justify-between items-stretch">
              {followerPoints.map((point, index) => {
                const diffRange = maxFollowers - minFollowers || 1
                const yPercent = ((point.value - minFollowers) / diffRange) * 85
                return (
                  <div
                    key={index}
                    className="flex-1 flex flex-col justify-end items-center relative group/node cursor-pointer"
                    onMouseEnter={() => setHoveredFollowerPoint(point)}
                    onMouseLeave={() => setHoveredFollowerPoint(null)}
                  >
                    <div 
                      className="absolute w-3 h-3 bg-purple-500 rounded-full border-2 border-white dark:border-gray-900 scale-0 group-hover/node:scale-100 transition-transform duration-150 z-20 pointer-events-none shadow-md"
                      style={{ bottom: `${yPercent}%`, transform: 'translateY(50%)' }}
                    />
                    <div className="absolute w-[1px] bg-purple-500/20 top-0 bottom-0 opacity-0 group-hover/node:opacity-100 transition-opacity pointer-events-none" />
                  </div>
                )
              })}
            </div>
            
            {/* X Axis Labels */}
            <div className="w-full flex justify-between relative z-10 px-2 text-[10px] font-semibold text-[rgb(var(--text-secondary))]">
              {followerPoints.map((point, index) => (
                <span key={index} className="truncate w-full text-center">
                  {index % (period === '90d' ? 4 : 2) === 0 ? point.label : ''}
                </span>
              ))}
            </div>
          </div>
        </div>

      </div>
    </div>
  )
}
