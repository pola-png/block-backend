'use client'

import { Wifi, WifiOff, Loader2 } from 'lucide-react'
import { useRealtimeConnection } from './realtime'
import { cn } from './utils'

export function RealtimeStatus() {
  const { isConnected, connectionStatus } = useRealtimeConnection()

  const getStatusConfig = () => {
    switch (connectionStatus) {
      case 'connected':
        return {
          icon: <Wifi size={16} />,
          text: 'Live',
          className: 'bg-green-100 text-green-800 border-green-200'
        }
      case 'connecting':
        return {
          icon: <Loader2 size={16} className="animate-spin" />,
          text: 'Connecting',
          className: 'bg-yellow-100 text-yellow-800 border-yellow-200'
        }
      default:
        return {
          icon: <WifiOff size={16} />,
          text: 'Offline',
          className: 'bg-red-100 text-red-800 border-red-200'
        }
    }
  }

  const config = getStatusConfig()

  return (
    <div className={cn(
      "fixed bottom-4 right-4 z-50 flex items-center space-x-2 px-3 py-2 rounded-full text-sm font-medium border transition-all duration-300",
      config.className
    )}>
      {config.icon}
      <span>{config.text}</span>
    </div>
  )
}