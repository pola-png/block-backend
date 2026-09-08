'use client'

import { useState, useRef } from 'react'
import { X, Image, Video, FileText, Upload } from 'lucide-react'
import { UploadType } from './types'
import appwriteService from './appwriteService'
import storageService from './storage'
import { cn } from './utils'
import { useProfileStore } from './profileStore'

interface CreatePostModalProps {
  isOpen: boolean
  onClose: () => void
}

export function CreatePostModal({ isOpen, onClose }: CreatePostModalProps) {
  const [step, setStep] = useState<'select' | 'create'>('select')
  const [uploadType, setUploadType] = useState<UploadType>('standard')
  const [content, setContent] = useState('')
  const [title, setTitle] = useState('')
  const [selectedFile, setSelectedFile] = useState<File | null>(null)
  const [uploading, setUploading] = useState(false)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const profileStore = useProfileStore()

  const uploadTypes = [
    { type: 'standard' as UploadType, icon: Image, label: 'Image / Text', desc: 'Share photos and thoughts' },
    { type: 'video' as UploadType, icon: Video, label: 'Video', desc: 'Upload video content' },
    { type: 'reel' as UploadType, icon: Video, label: 'Reel', desc: 'Short vertical videos' },
    { type: 'news' as UploadType, icon: FileText, label: 'News / Blog', desc: 'Write articles and news' }
  ]

  const handleTypeSelect = (type: UploadType) => {
    setUploadType(type)
    setStep('create')
  }

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (file) {
      setSelectedFile(file)
    }
  }

  const handleSubmit = async () => {
    if (!content.trim() && !selectedFile) return

    setUploading(true)
    try {
      let mediaUrl = ''
      
      if (selectedFile) {
        mediaUrl = await storageService.uploadFile(selectedFile)
      }

      const user = await appwriteService.getCurrentUser()
      if (!user) throw new Error('Must be signed in')

      const postData = {
        content: content.trim(),
        kind: uploadType,
        title: title.trim() || undefined,
        imageUrl: uploadType === 'standard' && mediaUrl ? mediaUrl : undefined,
        videoUrl: (uploadType === 'video' || uploadType === 'reel') && mediaUrl ? mediaUrl : undefined,
        thumbnailUrl: uploadType === 'video' ? mediaUrl : undefined,
        userId: user.$id,
        username: user.name || 'User'
      }

      await appwriteService.createPost(postData)
      
      profileStore.clearProfile(user.$id)
      
      setContent('')
      setTitle('')
      setSelectedFile(null)
      setStep('select')
      onClose()
    } catch (error) {
      console.error('Failed to create post:', error)
      alert('Failed to create post. Please try again.')
    } finally {
      setUploading(false)
    }
  }

  if (!isOpen) return null

  return (
    <div className="fixed inset-0 bg-black/50 flex items-end sm:items-center justify-center z-50 p-0 sm:p-4">
      <div className="bg-background rounded-t-3xl sm:rounded-2xl w-full sm:max-w-lg max-h-[70vh] sm:max-h-[90vh] overflow-hidden animate-in slide-in-from-bottom sm:slide-in-from-bottom-0 duration-300">
        <div className="flex items-center justify-between p-4 border-b border-border">
          <h2 className="text-lg font-semibold">
            {step === 'select' ? 'Create' : `Create ${uploadTypes.find(t => t.type === uploadType)?.label}`}
          </h2>
          <button onClick={onClose} className="p-2 hover:bg-accent rounded-full transition-colors">
            <X size={20} />
          </button>
        </div>

        <div className="p-4">
          {step === 'select' ? (
            <div className="space-y-3">
              {uploadTypes.map(({ type, icon: Icon, label, desc }) => (
                <button
                  key={type}
                  onClick={() => handleTypeSelect(type)}
                  className="w-full flex items-center space-x-3 p-3 hover:bg-accent rounded-lg transition-colors text-left"
                >
                  <Icon size={20} className="text-muted-foreground" />
                  <div>
                    <div className="font-medium">{label}</div>
                    <div className="text-sm text-muted-foreground">{desc}</div>
                  </div>
                </button>
              ))}
            </div>
          ) : (
            <div className="space-y-4">
              {uploadType === 'news' && (
                <input
                  type="text"
                  placeholder="Article title..."
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  className="w-full p-3 bg-muted rounded-lg border-0 focus:outline-none focus:ring-2 focus:ring-xapzap-blue"
                />
              )}
              
              <textarea
                placeholder={uploadType === 'news' ? 'Write your article...' : "What's happening?"}
                value={content}
                onChange={(e) => setContent(e.target.value)}
                className="w-full p-3 bg-muted rounded-lg border-0 resize-none focus:outline-none focus:ring-2 focus:ring-xapzap-blue"
                rows={uploadType === 'news' ? 8 : 4}
              />

              {(uploadType === 'standard' || uploadType === 'video' || uploadType === 'reel') && (
                <div>
                  <input
                    ref={fileInputRef}
                    type="file"
                    accept={uploadType === 'standard' ? 'image/*' : 'video/*'}
                    onChange={handleFileSelect}
                    className="hidden"
                  />
                  <button
                    onClick={() => fileInputRef.current?.click()}
                    className="flex items-center space-x-2 px-4 py-2 bg-muted rounded-lg hover:bg-accent transition-colors"
                  >
                    <Upload size={16} />
                    <span>{selectedFile ? selectedFile.name : `Add ${uploadType === 'standard' ? 'Image' : 'Video'}`}</span>
                  </button>
                </div>
              )}

              <div className="flex space-x-3">
                <button
                  onClick={() => setStep('select')}
                  className="flex-1 px-4 py-2 bg-muted rounded-lg hover:bg-accent transition-colors"
                >
                  Back
                </button>
                <button
                  onClick={handleSubmit}
                  disabled={uploading || (!content.trim() && !selectedFile)}
                  className={cn(
                    "flex-1 px-4 py-2 rounded-lg font-medium transition-colors",
                    content.trim() || selectedFile
                      ? "bg-xapzap-blue text-white hover:bg-xapzap-darkBlue"
                      : "bg-muted text-muted-foreground cursor-not-allowed"
                  )}
                >
                  {uploading ? 'Posting...' : 'Post'}
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}