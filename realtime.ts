'use client'

import { useEffect, useState, useCallback } from 'react'
import { Chat, Message } from './types'
import appwriteService from './appwriteService'
import { decryptMessage } from './lib/crypto'

interface RealtimeUpdate {
  type: 'like' | 'comment' | 'repost' | 'share' | 'impression'
  postId: string
  count: number
  userId?: string
}

interface ChatUpdate {
  type: 'message' | 'typing' | 'online_status'
  chatId?: string
  message?: Message
  userId?: string
  isTyping?: boolean
  isOnline?: boolean
}

interface StatusUpdate {
  type: 'status_created' | 'status_viewed'
  statusId: string
  userId: string
  username: string
  userAvatar: string
  mediaUrl?: string
  mediaType?: 'image' | 'video'
  timestamp: Date
}

interface NotificationUpdate {
  type: 'notification_created'
  notificationId: string
  actorId: string
  actorUsername: string
  actorAvatar: string
  title: string
  body: string
  timestamp: Date
}

class RealtimeService {
  private static instance: RealtimeService
  private subscribers: Map<string, Set<(update: RealtimeUpdate) => void>> = new Map()
  private chatSubscribers: Map<string, Set<(update: ChatUpdate) => void>> = new Map()
  private statusSubscribers: Set<(update: StatusUpdate) => void> = new Set()
  private notificationSubscribers: Set<(update: NotificationUpdate) => void> = new Set()
  private subscriptions: any[] = []

  static getInstance(): RealtimeService {
    if (!RealtimeService.instance) {
      RealtimeService.instance = new RealtimeService()
    }
    return RealtimeService.instance
  }

  connect() {
    // Subscribe to real-time updates from Appwrite
    this.subscribeToAppwriteUpdates()
  }

  private subscribeToAppwriteUpdates() {
    // Subscribe to posts for like/comment/repost updates
    const postsSubscription = appwriteService.subscribeToCollection('posts', (response) => {
      if (response.events.includes('databases.*.collections.*.documents.*.update')) {
        const postId = response.payload.$id
        this.notifySubscribers(postId, {
          type: 'impression',
          postId,
          count: 1
        })
      }
    })
    this.subscriptions.push(postsSubscription)

    // Subscribe to messages for chat updates
    const messagesSubscription = appwriteService.subscribeToCollection('messages', (response) => {
      if (response.events.includes('databases.*.collections.*.documents.*.create')) {
        const messageData = response.payload
        const message: Message = {
          id: messageData.$id,
          chatId: messageData.chatId,
          senderId: messageData.senderId,
          content: messageData.content,
          timestamp: new Date(messageData.timestamp),
          readBy: messageData.readBy || '',
          messageType: messageData.messageType || 'text',
          ciphertext: messageData.ciphertext,
          nonce: messageData.nonce,
          mac: messageData.mac
        }
        
        this.notifyChatSubscribers(messageData.chatId, {
          type: 'message',
          chatId: messageData.chatId,
          message
        })
      }
    })
    this.subscriptions.push(messagesSubscription)

    // Subscribe to statuses
    const statusesSubscription = appwriteService.subscribeToCollection('statuses', (response) => {
      if (response.events.includes('databases.*.collections.*.documents.*.create')) {
        const statusData = response.payload
        this.notifyStatusSubscribers({
          type: 'status_created',
          statusId: statusData.$id,
          userId: statusData.userId,
          username: statusData.username || 'User',
          userAvatar: statusData.userAvatar || '',
          mediaUrl: statusData.mediaPath,
          timestamp: new Date(statusData.timestamp)
        })
      }
    })
    this.subscriptions.push(statusesSubscription)

    // Subscribe to notifications
    const notificationsSubscription = appwriteService.subscribeToCollection('notifications', (response) => {
      if (response.events.includes('databases.*.collections.*.documents.*.create')) {
        const notificationData = response.payload
        this.notifyNotificationSubscribers({
          type: 'notification_created',
          notificationId: notificationData.$id,
          actorId: notificationData.actorId || '',
          actorUsername: notificationData.actorName || 'User',
          actorAvatar: notificationData.actorAvatar || '',
          title: notificationData.title,
          body: notificationData.body || '',
          timestamp: new Date(notificationData.timestamp)
        })
      }
    })
    this.subscriptions.push(notificationsSubscription)
  }

  subscribe(postId: string, callback: (update: RealtimeUpdate) => void) {
    if (!this.subscribers.has(postId)) {
      this.subscribers.set(postId, new Set())
    }
    this.subscribers.get(postId)!.add(callback)
    this.connect()

    return () => {
      const callbacks = this.subscribers.get(postId)
      callbacks?.delete(callback)
      if (callbacks?.size === 0) {
        this.subscribers.delete(postId)
      }
    }
  }

  subscribeToChat(chatId: string, callback: (update: ChatUpdate) => void) {
    if (!this.chatSubscribers.has(chatId)) {
      this.chatSubscribers.set(chatId, new Set())
    }
    this.chatSubscribers.get(chatId)!.add(callback)
    this.connect()

    return () => {
      const callbacks = this.chatSubscribers.get(chatId)
      callbacks?.delete(callback)
      if (callbacks?.size === 0) {
        this.chatSubscribers.delete(chatId)
      }
    }
  }

  subscribeToStatus(callback: (update: StatusUpdate) => void) {
    this.statusSubscribers.add(callback)
    this.connect()

    return () => {
      this.statusSubscribers.delete(callback)
    }
  }

  subscribeToNotifications(callback: (update: NotificationUpdate) => void) {
    this.notificationSubscribers.add(callback)
    this.connect()

    return () => {
      this.notificationSubscribers.delete(callback)
    }
  }

  async sendMessage(chatId: string, content: string, partnerUserId?: string): Promise<Message> {
    const messageDoc = await appwriteService.sendMessage(chatId, content, partnerUserId)
    
    const message: Message = {
      id: messageDoc.$id,
      chatId: messageDoc.chatId,
      senderId: messageDoc.senderId,
      content: content,
      timestamp: new Date(messageDoc.timestamp),
      readBy: messageDoc.readBy || '',
      messageType: messageDoc.messageType || 'text',
      ciphertext: messageDoc.ciphertext,
      nonce: messageDoc.nonce,
      mac: messageDoc.mac
    }

    return message
  }

  private notifySubscribers(postId: string, update: RealtimeUpdate) {
    const callbacks = this.subscribers.get(postId)
    callbacks?.forEach(callback => callback(update))
  }

  private notifyChatSubscribers(chatId: string, update: ChatUpdate) {
    const callbacks = this.chatSubscribers.get(chatId)
    callbacks?.forEach(callback => callback(update))
  }

  private notifyStatusSubscribers(update: StatusUpdate) {
    this.statusSubscribers.forEach(callback => callback(update))
  }

  private notifyNotificationSubscribers(update: NotificationUpdate) {
    this.notificationSubscribers.forEach(callback => callback(update))
  }

  disconnect() {
    this.subscriptions.forEach(sub => sub.unsubscribe())
    this.subscriptions = []
    this.subscribers.clear()
    this.chatSubscribers.clear()
    this.statusSubscribers.clear()
    this.notificationSubscribers.clear()
  }
}

export const realtimeService = RealtimeService.getInstance()

export function useRealtimePost(postId: string) {
  const [updates, setUpdates] = useState<{
    likes: number
    comments: number
    reposts: number
    shares: number
    impressions: number
  }>({
    likes: 0,
    comments: 0,
    reposts: 0,
    shares: 0,
    impressions: 0
  })

  const handleUpdate = useCallback((update: RealtimeUpdate) => {
    setUpdates(prev => ({
      ...prev,
      [update.type === 'repost' ? 'reposts' : update.type + 's']: 
        prev[update.type === 'repost' ? 'reposts' : (update.type + 's') as keyof typeof prev] + update.count
    }))
  }, [])

  useEffect(() => {
    const unsubscribe = realtimeService.subscribe(postId, handleUpdate)
    return unsubscribe
  }, [postId, handleUpdate])

  return updates
}

export function useRealtimeChat(chatId: string, partnerUserId?: string) {
  const [messages, setMessages] = useState<Message[]>([])

  const decryptRow = useCallback(async (msg: Message) => {
    const cipher = msg.ciphertext || '';
    const nonce = msg.nonce || '';
    const mac = msg.mac || '';
    let content = msg.content || '';

    if (cipher && nonce && mac && partnerUserId) {
      const me = await appwriteService.getCurrentUser();
      if (me) {
        const decrypted = await decryptMessage(
          chatId,
          me.$id,
          partnerUserId,
          cipher,
          nonce,
          mac
        );
        if (decrypted !== null) {
          content = decrypted;
        }
      }
    }
    return {
      ...msg,
      content
    };
  }, [chatId, partnerUserId]);

  const handleChatUpdate = useCallback(async (update: ChatUpdate) => {
    if (update.type === 'message' && update.message) {
      const decrypted = await decryptRow(update.message);
      setMessages(prev => [...prev, decrypted]);
    }
  }, [decryptRow]);

  useEffect(() => {
    if (!chatId) return

    // Load existing messages
    const loadMessages = async () => {
      try {
        const result = await appwriteService.fetchMessagesForChat(chatId)
        const messagesWithDec: Message[] = result.documents.map(doc => ({
          id: doc.$id,
          chatId: doc.chatId,
          senderId: doc.senderId,
          content: doc.content,
          timestamp: new Date(doc.timestamp),
          readBy: doc.readBy || '',
          messageType: doc.messageType || 'text',
          ciphertext: doc.ciphertext,
          nonce: doc.nonce,
          mac: doc.mac
        }));

        const decryptedMessages = await Promise.all(
          messagesWithDec.map(msg => decryptRow(msg))
        );

        setMessages(decryptedMessages.reverse())
      } catch (error) {
        console.error('Failed to load messages:', error)
      }
    }

    loadMessages()
    const unsubscribe = realtimeService.subscribeToChat(chatId, handleChatUpdate)
    return unsubscribe
  }, [chatId, handleChatUpdate, decryptRow])

  const sendMessage = useCallback(async (content: string) => {
    if (!chatId) return
    return await realtimeService.sendMessage(chatId, content, partnerUserId)
  }, [chatId, partnerUserId])

  return { messages, sendMessage }
}

export function useRealtimeStatus() {
  const [statuses, setStatuses] = useState<StatusUpdate[]>([])

  const handleStatusUpdate = useCallback((update: StatusUpdate) => {
    if (update.type === 'status_created') {
      setStatuses(prev => [update, ...prev])
    }
  }, [])

  useEffect(() => {
    // Load existing statuses
    const loadStatuses = async () => {
      try {
        const result = await appwriteService.fetchStatuses()
        const statusUpdates: StatusUpdate[] = result.documents.map(doc => ({
          type: 'status_created' as const,
          statusId: doc.$id,
          userId: doc.userId,
          username: doc.username || 'User',
          userAvatar: doc.userAvatar || '',
          mediaUrl: doc.mediaPath,
          timestamp: new Date(doc.timestamp)
        }))
        setStatuses(statusUpdates)
      } catch (error) {
        console.error('Failed to load statuses:', error)
      }
    }
    
    loadStatuses()
    const unsubscribe = realtimeService.subscribeToStatus(handleStatusUpdate)
    return unsubscribe
  }, [handleStatusUpdate])

  return statuses
}

export function useRealtimeNotifications() {
  const [notifications, setNotifications] = useState<NotificationUpdate[]>([])

  const handleNotificationUpdate = useCallback((update: NotificationUpdate) => {
    if (update.type === 'notification_created') {
      setNotifications(prev => [update, ...prev])
    }
  }, [])

  useEffect(() => {
    // Load existing notifications
    const loadNotifications = async () => {
      try {
        const user = await appwriteService.getCurrentUser()
        if (!user) return
        
        const result = await appwriteService.fetchNotifications(user.$id)
        const notificationUpdates: NotificationUpdate[] = result.documents.map(doc => ({
          type: 'notification_created' as const,
          notificationId: doc.$id,
          actorId: doc.actorId || '',
          actorUsername: doc.actorName || 'User',
          actorAvatar: doc.actorAvatar || '',
          title: doc.title,
          body: doc.body || '',
          timestamp: new Date(doc.timestamp)
        }))
        setNotifications(notificationUpdates)
      } catch (error) {
        console.error('Failed to load notifications:', error)
      }
    }
    
    loadNotifications()
    const unsubscribe = realtimeService.subscribeToNotifications(handleNotificationUpdate)
    return unsubscribe
  }, [handleNotificationUpdate])

  return notifications
}

export function useRealtimeConnection() {
  const [isConnected, setIsConnected] = useState(false)
  const [connectionStatus, setConnectionStatus] = useState<'connecting' | 'connected' | 'disconnected'>('connecting')

  useEffect(() => {
    setConnectionStatus('connecting')
    realtimeService.connect()
    
    const timer = setTimeout(() => {
      setIsConnected(true)
      setConnectionStatus('connected')
    }, 1000)

    return () => {
      clearTimeout(timer)
      setIsConnected(false)
      setConnectionStatus('disconnected')
    }
  }, [])

  return { isConnected, connectionStatus }
}