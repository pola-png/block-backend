'use client'

import { useState } from 'react'
import { Bell, Plus } from 'lucide-react'
import { useRealtimeStatus, useRealtimeNotifications } from './realtime'

const formatTime = (date: Date) => {
  const now = new Date()
  const diff = now.getTime() - date.getTime()
  
  if (diff < 60 * 1000) return 'Just now'
  if (diff < 60 * 60 * 1000) return `${Math.floor(diff / (60 * 1000))}m ago`
  if (diff < 24 * 60 * 60 * 1000) return `${Math.floor(diff / (60 * 60 * 1000))}h ago`
  return `${Math.floor(diff / (24 * 60 * 60 * 1000))}d ago`
}

function StatusTab() {
  const statuses = useRealtimeStatus()
  const unviewedStatuses = statuses.filter(s => s.type === 'status_created')
  const viewedStatuses = statuses.filter(s => s.type === 'status_viewed')

  const showStoryOptions = () => {
    console.log('Show story creation options')
  }

  return (
    <div className="space-y-4">
      {/* My Status */}
      <div 
        onClick={showStoryOptions}
        className="flex items-center space-x-3 p-4 hover:bg-accent cursor-pointer transition-colors"
      >
        <div className="relative">
          <div className="w-12 h-12 rounded-full bg-muted flex items-center justify-center">
            <span className="font-medium">U</span>
          </div>
          <div className="absolute -bottom-1 -right-1 w-5 h-5 bg-green-500 rounded-full border-2 border-background flex items-center justify-center">
            <Plus size={12} className="text-white" />
          </div>
        </div>
        <div>
          <p className="font-semibold">My status</p>
          <p className="text-sm text-muted-foreground">Tap to add status update</p>
        </div>
      </div>

      {/* Recent Updates */}
      {unviewedStatuses.length > 0 && (
        <div>
          <p className="text-sm font-medium text-muted-foreground px-4 mb-2">Recent updates</p>
          {unviewedStatuses.map((status) => (
            <div key={status.statusId} className="flex items-center space-x-3 p-4 hover:bg-accent cursor-pointer transition-colors">
              <div className="relative">
                <div className="w-12 h-12 p-0.5 rounded-full border-2 border-xapzap-blue">
                  <img
                    src={status.userAvatar}
                    alt={status.username}
                    className="w-full h-full rounded-full object-cover"
                  />
                </div>
              </div>
              <div>
                <p className="font-medium">{status.username}</p>
                <p className="text-sm text-muted-foreground">{formatTime(status.timestamp)}</p>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Viewed Updates */}
      {viewedStatuses.length > 0 && (
        <div>
          <p className="text-sm font-medium text-muted-foreground px-4 mb-2">Viewed updates</p>
          {viewedStatuses.map((status) => (
            <div key={status.statusId} className="flex items-center space-x-3 p-4 hover:bg-accent cursor-pointer transition-colors opacity-60">
              <div className="relative">
                <div className="w-12 h-12 p-0.5 rounded-full border-2 border-muted-foreground">
                  <img
                    src={status.userAvatar}
                    alt={status.username}
                    className="w-full h-full rounded-full object-cover"
                  />
                </div>
              </div>
              <div>
                <p className="font-medium">{status.username}</p>
                <p className="text-sm text-muted-foreground">{formatTime(status.timestamp)}</p>
              </div>
            </div>
          ))}
        </div>
      )}

      {statuses.length === 0 && (
        <div className="text-center py-12">
          <p className="text-muted-foreground">No new stories from people you follow yet.</p>
        </div>
      )}
    </div>
  )
}

function NotificationsTab() {
  const notifications = useRealtimeNotifications()

  return (
    <div className="divide-y divide-border">
      {notifications.length === 0 ? (
        <div className="text-center py-12">
          <Bell size={48} className="mx-auto mb-4 text-muted-foreground" />
          <p className="text-muted-foreground">No notifications yet</p>
        </div>
      ) : (
        notifications.map((notification) => (
          <div key={notification.notificationId} className="p-4 hover:bg-accent transition-colors cursor-pointer">
            <div className="flex items-start space-x-3">
              <img
                src={notification.actorAvatar}
                alt={notification.actorUsername}
                className="w-12 h-12 rounded-full object-cover"
              />
              <div className="flex-1">
                <p className="font-medium">{notification.title}</p>
                {notification.body && (
                  <p className="text-sm text-muted-foreground mt-1">{notification.body}</p>
                )}
                <p className="text-sm text-muted-foreground mt-1">{formatTime(notification.timestamp)}</p>
              </div>
            </div>
          </div>
        ))
      )}
    </div>
  )
}

export function UpdatesScreen() {
  const [activeTab, setActiveTab] = useState<'status' | 'notifications'>('status')

  return (
    <div className="max-w-2xl mx-auto">
      {/* Header */}
      <div className="sticky top-0 bg-background border-b border-border z-10">
        <div className="p-4">
          <h1 className="text-2xl font-bold mb-4">Updates</h1>
          
          {/* Tabs */}
          <div className="flex space-x-1 bg-muted rounded-lg p-1">
            <button
              onClick={() => setActiveTab('status')}
              className={`flex-1 px-4 py-2 rounded-md text-sm font-medium transition-colors ${
                activeTab === 'status'
                  ? 'bg-background text-foreground shadow-sm'
                  : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              Status
            </button>
            <button
              onClick={() => setActiveTab('notifications')}
              className={`flex-1 px-4 py-2 rounded-md text-sm font-medium transition-colors ${
                activeTab === 'notifications'
                  ? 'bg-background text-foreground shadow-sm'
                  : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              Notifications
            </button>
          </div>
        </div>
      </div>

      {/* Tab Content */}
      <div className="pb-4">
        {activeTab === 'status' ? <StatusTab /> : <NotificationsTab />}
      </div>
    </div>
  )
}