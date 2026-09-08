'use client'

import { useState, useEffect, useRef } from 'react'
import { ArrowLeft, Send, Image, Video, Smile, MoreVertical, Phone, VideoIcon, Search } from 'lucide-react'
import { Chat, Message } from './types'
import appwriteService from './appwriteService'
import { useRealtimeChat } from './realtime'
import { useAuthStore } from './authStore'
import { VerifiedBadge } from './components/VerifiedBadge'
import { hasVerifiedBadge, isPremiumBadge } from './lib/verification'

function formatTime(date: Date): string {
  const now = new Date()
  const diff = now.getTime() - date.getTime()
  
  if (diff < 60 * 1000) return 'now'
  if (diff < 60 * 60 * 1000) return `${Math.floor(diff / (60 * 1000))}m`
  if (diff < 24 * 60 * 60 * 1000) return `${Math.floor(diff / (60 * 60 * 1000))}h`
  return `${Math.floor(diff / (24 * 60 * 60 * 1000))}d`
}

export interface ChatListProps {
  chats: Chat[]
  onChatSelect: (chat: Chat) => void
  loading?: boolean
}

export function ChatList({ chats, onChatSelect, loading }: ChatListProps) {
  const [searchQuery, setSearchQuery] = useState('')
  const [shouldLoadAvatars, setShouldLoadAvatars] = useState<Set<string>>(new Set())
  const avatarRefs = useRef<Map<string, HTMLDivElement>>(new Map())
  
  const filteredChats = chats.filter(chat =>
    chat.partnerName.toLowerCase().includes(searchQuery.toLowerCase())
  )

  useEffect(() => {
    const observers = new Map<string, IntersectionObserver>()
    
    filteredChats.forEach(chat => {
      const element = avatarRefs.current.get(chat.id)
      if (!element || shouldLoadAvatars.has(chat.id)) return
      
      const observer = new IntersectionObserver(
        ([entry]) => {
          if (entry.isIntersecting) {
            setShouldLoadAvatars(prev => new Set(prev).add(chat.id))
            observer.disconnect()
          }
        },
        { rootMargin: '100px' }
      )
      observer.observe(element)
      observers.set(chat.id, observer)
    })
    
    return () => observers.forEach(obs => obs.disconnect())
  }, [filteredChats])

  return (
    <div className="h-full flex flex-col">
      <div className="p-4 border-b border-border">
        <h1 className="text-2xl font-bold mb-4">Messages</h1>
        <div className="relative">
          <Search size={20} className="absolute left-3 top-1/2 transform -translate-y-1/2 text-muted-foreground" />
          <input
            type="text"
            placeholder="Search conversations"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-10 pr-4 py-2 bg-muted rounded-full border-0 focus:outline-none focus:ring-2 focus:ring-xapzap-blue"
          />
        </div>
      </div>
      
      <div className="flex-1 overflow-y-auto">
        {loading ? (
          <div className="p-4 space-y-4">
            {[1, 2, 3, 4, 5].map((i) => (
              <div key={i} className="flex items-center space-x-3 animate-pulse">
                <div className="w-12 h-12 rounded-full bg-muted"></div>
                <div className="flex-1">
                  <div className="h-4 bg-muted rounded w-1/3 mb-2"></div>
                  <div className="h-3 bg-muted rounded w-2/3"></div>
                </div>
              </div>
            ))}
          </div>
        ) : filteredChats.length === 0 ? (
          <div className="text-center py-12">
            <p className="text-muted-foreground">No conversations found</p>
          </div>
        ) : (
          <div className="divide-y divide-border">
            {filteredChats.map((chat) => (
              <div
                key={chat.id}
                onClick={() => onChatSelect(chat)}
                className="p-4 hover:bg-accent cursor-pointer transition-colors"
                ref={el => { if (el) avatarRefs.current.set(chat.id, el) }}
              >
                <div className="flex items-center space-x-3">
                  <div className="relative">
                    {shouldLoadAvatars.has(chat.id) ? (
                    <img
                      src={chat.partnerAvatar.startsWith('/media/') ? `/api/image-proxy?path=${chat.partnerAvatar.substring(1)}` : chat.partnerAvatar}
                      alt={chat.partnerName}
                      className="w-12 h-12 rounded-full object-cover"
                    />
                    ) : (
                      <div className="w-12 h-12 rounded-full bg-muted" />
                    )}
                    {chat.isOnline && (
                      <div className="absolute -bottom-1 -right-1 w-4 h-4 bg-green-500 rounded-full border-2 border-background"></div>
                    )}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center justify-between">
                      <h3 className="font-semibold truncate flex items-center gap-1">
                        {chat.partnerName}
                        {chat.partnerIsVerified && (
                          <VerifiedBadge className="h-3.5 w-3.5 shrink-0" isPremium={chat.partnerIsAdmin} />
                        )}
                      </h3>
                      <span className="text-sm text-muted-foreground">
                        {formatTime(chat.timestamp)}
                      </span>
                    </div>
                    <div className="flex items-center justify-between">
                      <p className="text-sm text-muted-foreground truncate">
                        {chat.lastMessage}
                      </p>
                      {chat.unreadCount > 0 && (
                        <span className="bg-xapzap-blue text-white text-xs rounded-full px-2 py-1 min-w-[20px] text-center">
                          {chat.unreadCount}
                        </span>
                      )}
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}

export interface ChatViewProps {
  chat: Chat
  onBack: () => void
}

export function ChatView({ chat, onBack }: ChatViewProps) {
  const [newMessage, setNewMessage] = useState('')
  const authStore = useAuthStore()
  const { messages, sendMessage } = useRealtimeChat(chat.id, chat.partnerId)

  const scrollToBottom = () => {
    const messagesEnd = document.getElementById('messages-end')
    messagesEnd?.scrollIntoView({ behavior: 'smooth' })
  }

  useEffect(() => {
    scrollToBottom()
  }, [messages])

  const handleSend = async () => {
    if (newMessage.trim()) {
      await sendMessage(newMessage.trim())
      setNewMessage('')
    }
  }

  const handleKeyPress = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSend()
    }
  }

  return (
    <div className="h-full flex flex-col">
      {/* Chat Header */}
      <div className="p-4 border-b border-border flex items-center justify-between">
        <div className="flex items-center space-x-3">
          <button
            onClick={onBack}
            className="p-2 hover:bg-accent rounded-full lg:hidden"
            aria-label="Back"
          >
            <ArrowLeft size={20} />
          </button>
          <div className="relative">
            <img
              src={chat.partnerAvatar.startsWith('/media/') ? `/api/image-proxy?path=${chat.partnerAvatar.substring(1)}` : chat.partnerAvatar}
              alt={chat.partnerName}
              className="w-10 h-10 rounded-full object-cover"
            />
            {chat.isOnline && (
              <div className="absolute -bottom-1 -right-1 w-3 h-3 bg-green-500 rounded-full border-2 border-background"></div>
            )}
          </div>
          <div>
            <h2 className="font-semibold flex items-center gap-1">
              {chat.partnerName}
              {chat.partnerIsVerified && (
                <VerifiedBadge className="h-4 w-4 shrink-0" isPremium={chat.partnerIsAdmin} />
              )}
            </h2>
            <p className="text-sm text-muted-foreground">
              {chat.isOnline ? 'Online' : 'Offline'}
            </p>
          </div>
        </div>
        <div className="flex items-center space-x-2">
          <button className="p-2 hover:bg-accent rounded-full" aria-label="Call">
            <Phone size={20} />
          </button>
          <button className="p-2 hover:bg-accent rounded-full" aria-label="Video call">
            <VideoIcon size={20} />
          </button>
          <button className="p-2 hover:bg-accent rounded-full" aria-label="More">
            <MoreVertical size={20} />
          </button>
        </div>
      </div>

      {/* Messages */}
      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {messages.length === 0 ? (
          <div className="text-center py-12">
            <p className="text-muted-foreground">No messages yet</p>
            <p className="text-sm text-muted-foreground mt-2">Start the conversation!</p>
          </div>
        ) : (
          messages.map((message) => (
            <div
              key={message.id}
              className={`flex ${message.senderId === 'me' ? 'justify-end' : 'justify-start'}`}
            >
              <div
                className={`max-w-xs lg:max-w-md px-4 py-2 rounded-2xl ${
                  message.senderId === 'me'
                    ? 'bg-xapzap-blue text-white'
                    : 'bg-muted'
                }`}
              >
                <p className="text-sm">{message.content}</p>
                <p className={`text-xs mt-1 ${
                  message.senderId === 'me' ? 'text-blue-100' : 'text-muted-foreground'
                }`}>
                  {formatTime(message.timestamp)}
                </p>
              </div>
            </div>
          ))
        )}
        <div id="messages-end" />
      </div>

      {/* Message Input */}
      <div className="p-4 border-t border-border">
        <div className="flex items-end space-x-2">
          <div className="flex space-x-2">
            <button className="p-2 hover:bg-accent rounded-full" aria-label="Send image">
              <Image size={20} className="text-muted-foreground" />
            </button>
            <button className="p-2 hover:bg-accent rounded-full" aria-label="Send video">
              <Video size={20} className="text-muted-foreground" />
            </button>
          </div>
          <div className="flex-1 relative">
            <textarea
              value={newMessage}
              onChange={(e) => setNewMessage(e.target.value)}
              onKeyPress={handleKeyPress}
              placeholder="Type a message..."
              className="w-full px-4 py-2 pr-12 bg-muted rounded-2xl border-0 focus:outline-none focus:ring-2 focus:ring-xapzap-blue resize-none"
              rows={1}
            />
            <button className="absolute right-2 top-1/2 transform -translate-y-1/2 p-1 hover:bg-accent rounded-full" aria-label="Emoji">
              <Smile size={16} className="text-muted-foreground" />
            </button>
          </div>
          <button
            onClick={handleSend}
            disabled={!newMessage.trim()}
            className="p-2 bg-xapzap-blue text-white rounded-full hover:bg-blue-600 disabled:opacity-50 disabled:cursor-not-allowed"
            aria-label="Send message"
          >
            <Send size={20} />
          </button>
        </div>
      </div>
    </div>
  )
}

export function ChatScreen() {
  const [selectedChat, setSelectedChat] = useState<Chat | null>(null)
  const [chats, setChats] = useState<Chat[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    loadChats()
  }, [])

  const loadChats = async () => {
    setLoading(true)
    try {
      const user = await appwriteService.getCurrentUser()
      if (!user) {
        setLoading(false)
        return
      }
      const result = await appwriteService.fetchChatsForUser(user.$id)
      const mappedChats = await Promise.all(result.documents.map(async (doc: any) => {
        const memberIds = doc.memberIds.split(',').map((id: string) => id.trim())
        const partnerId = memberIds.find((id: string) => id !== user.$id) || 'unknown'
        const partnerProfile = await appwriteService.getProfileByUserId(partnerId)
        const partnerIsVerified = hasVerifiedBadge(partnerProfile)
        const partnerIsAdmin = isPremiumBadge(partnerProfile)
        return {
          id: doc.$id,
          chatId: doc.chatId,
          memberIds: doc.memberIds,
          partnerId,
          partnerName: partnerProfile?.displayName || partnerId.slice(0,8),
          partnerAvatar: partnerProfile?.avatarUrl || '',
          lastMessage: doc.lastMessage || 'No messages',
          timestamp: new Date(doc.lastMessageAt || doc.timestamp || doc.createdAt || doc.$createdAt),
          unreadCount: doc.unreadCount || 0,
          isOnline: false,
          partnerIsVerified,
          partnerIsAdmin,
        } as Chat
      }))
      setChats(mappedChats)
    } catch (error) {
      console.error('Failed to load chats:', error)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    const unsubscribe = appwriteService.subscribeToCollection('messages', () => {
      loadChats()
    })
    return unsubscribe
  }, [])

  return (
    <div className="h-[calc(100vh-4rem)] lg:h-[calc(100vh-5rem)]">
      <div className="h-full lg:grid lg:grid-cols-5">
        {/* Chat List - Hidden on mobile when chat is selected */}
        <div className={`lg:col-span-2 lg:border-r lg:border-border ${
          selectedChat ? 'hidden lg:block' : 'block'
        }`}>
          <ChatList chats={chats} onChatSelect={setSelectedChat} loading={loading} />
        </div>

        {/* Chat View - Hidden on mobile when no chat is selected */}
        <div className={`lg:col-span-3 ${
          selectedChat ? 'block' : 'hidden lg:block'
        }`}>
          {selectedChat ? (
            <ChatView
              chat={selectedChat}
              onBack={() => setSelectedChat(null)}
            />
          ) : (
            <div className="h-full flex items-center justify-center">
              <div className="text-center">
                <div className="w-24 h-24 bg-muted rounded-full flex items-center justify-center mx-auto mb-4">
                  <Send size={32} className="text-muted-foreground" />
                </div>
                <h3 className="text-lg font-semibold mb-2">No conversations yet</h3>
                <p className="text-muted-foreground">Start a conversation with someone to see it here</p>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}