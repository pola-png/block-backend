'use client'

import { useState, useEffect, useRef } from 'react'
import { useRouter } from 'next/navigation'
import { ArrowLeft, Camera } from 'lucide-react'
import appwriteService from '../../../appwriteService'
import { useProfileStore } from '../../../profileStore'
import { useAuthStore } from '../../../authStore'

export default function EditProfilePage() {
  const router = useRouter()
  const profileStore = useProfileStore()
  const authStore = useAuthStore()
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [displayName, setDisplayName] = useState('')
  const [username, setUsername] = useState('')
  const [bio, setBio] = useState('')
  const [location, setLocation] = useState('')
  const [website, setWebsite] = useState('')
  const [category, setCategory] = useState('')
  const [avatarUrl, setAvatarUrl] = useState('')
  const [coverUrl, setCoverUrl] = useState('')
  const [avatarFile, setAvatarFile] = useState<File | null>(null)
  const [coverFile, setCoverFile] = useState<File | null>(null)
  const avatarInputRef = useRef<HTMLInputElement>(null)
  const coverInputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    loadProfile()
  }, [])

  const loadProfile = async () => {
    try {
      const user = await appwriteService.getCurrentUser()
      if (!user) {
        router.push('/auth/signin')
        return
      }

      const profile = await appwriteService.getProfileByUserId(user.$id)
      if (profile) {
        setDisplayName(profile.displayName || '')
        setUsername(profile.username || '')
        setBio(profile.bio || '')
        setLocation(profile.location || '')
        setWebsite(profile.website || '')
        setCategory(profile.category || '')
        setAvatarUrl(profile.avatarUrl || '')
        setCoverUrl(profile.coverUrl || '')
      }
    } catch (error) {
      console.error('Failed to load profile:', error)
    } finally {
      setLoading(false)
    }
  }

  const handleAvatarChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (file) {
      if (!file.type.startsWith('image/')) {
        alert('Please select a valid image file')
        return
      }
      if (file.size > 5 * 1024 * 1024) {
        alert('Image must be less than 5MB')
        return
      }
      setAvatarFile(file)
      setAvatarUrl(URL.createObjectURL(file))
    }
  }

  const handleCoverChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (file) {
      if (!file.type.startsWith('image/')) {
        alert('Please select a valid image file')
        return
      }
      if (file.size > 10 * 1024 * 1024) {
        alert('Image must be less than 10MB')
        return
      }
      setCoverFile(file)
      setCoverUrl(URL.createObjectURL(file))
    }
  }

  const uploadToWasabi = async (file: File): Promise<string> => {
    try {
      // Sanitize filename - remove spaces and special characters
      const sanitizedName = file.name.replace(/\s+/g, '_').replace(/[()]/g, '')
      const timestamp = Date.now()
      const cleanFileName = `${timestamp}_${sanitizedName}`
      
      console.log('Uploading file:', cleanFileName, file.type, file.size)
      
      const presignedRes = await fetch('/api/presigned-url', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          fileName: cleanFileName,
          fileType: file.type
        })
      })
      
      if (!presignedRes.ok) {
        const error = await presignedRes.text()
        console.error('Presigned URL error:', error)
        throw new Error('Failed to get presigned URL')
      }
      
      const { presignedUrl, url } = await presignedRes.json()
      console.log('Got presigned URL, uploading...')
      
      const uploadRes = await fetch(presignedUrl, {
        method: 'PUT',
        body: file,
        headers: { 'Content-Type': file.type }
      })
      
      console.log('Upload response:', uploadRes.status, uploadRes.statusText)
      
      if (!uploadRes.ok) {
        const errorText = await uploadRes.text()
        console.error('Upload error:', errorText)
        throw new Error(`Upload failed: ${uploadRes.status}`)
      }
      
      console.log('Upload successful, URL:', url)
      return url
    } catch (error) {
      console.error('Upload to Wasabi failed:', error)
      throw error
    }
  }

  const handleSave = async () => {
    if (!displayName.trim() || !username.trim()) {
      alert('Display Name and Username are required')
      return
    }
    
    setSaving(true)
    try {
      const user = await appwriteService.getCurrentUser()
      if (!user) return

      const updateData: any = {
        userId: user.$id,
        displayName: displayName.trim(),
        username: username.trim()
      }

      if (bio.trim()) updateData.bio = bio.trim()
      if (location.trim()) updateData.location = location.trim()
      if (website.trim()) updateData.website = website.trim()
      if (category) updateData.category = category

      if (avatarFile) {
        updateData.avatarUrl = await uploadToWasabi(avatarFile)
      } else if (avatarUrl && !avatarUrl.startsWith('blob:')) {
        updateData.avatarUrl = avatarUrl
      }

      if (coverFile) {
        updateData.coverUrl = await uploadToWasabi(coverFile)
      } else if (coverUrl && !coverUrl.startsWith('blob:')) {
        updateData.coverUrl = coverUrl
      }

      await appwriteService.updateProfile(user.$id, updateData)

      authStore.setCurrentUserId(user.$id)
      profileStore.clearProfile(user.$id)
      router.push('/profile')
    } catch (error) {
      console.error('Failed to save profile:', error)
      alert('Failed to save profile. Please try again.')
    } finally {
      setSaving(false)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-xapzap-blue"></div>
      </div>
    )
  }

  return (
    <div className="max-w-2xl mx-auto min-h-screen">
      <div className="sticky top-0 bg-background border-b border-border p-4 flex items-center justify-between z-10">
        <div className="flex items-center gap-4">
          <button
            onClick={() => router.back()}
            className="p-2 hover:bg-accent rounded-full transition-colors"
          >
            <ArrowLeft size={20} />
          </button>
          <h1 className="text-xl font-bold">Edit Profile</h1>
        </div>
        <button
          onClick={handleSave}
          disabled={saving}
          className="px-6 py-2 bg-xapzap-blue text-white rounded-full font-medium hover:bg-blue-600 transition-colors disabled:opacity-50"
        >
          {saving ? 'Saving...' : 'Save'}
        </button>
      </div>

      <div className="p-4 space-y-6">
        {/* Cover Image */}
        <div className="relative">
          <div 
            onClick={() => coverInputRef.current?.click()}
            className="relative h-48 bg-gray-200 dark:bg-gray-700 rounded-lg overflow-hidden cursor-pointer group"
          >
            {coverUrl ? (
              <img src={coverUrl} alt="Cover" className="w-full h-full object-cover" />
            ) : (
              <div className="w-full h-full flex items-center justify-center">
                <Camera size={32} className="text-gray-400" />
              </div>
            )}
            <div className="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
              <Camera size={24} className="text-white" />
            </div>
          </div>
          <input
            ref={coverInputRef}
            type="file"
            accept="image/*"
            onChange={handleCoverChange}
            className="hidden"
          />
        </div>

        {/* Avatar */}
        <div className="relative -mt-20 ml-4">
          <div 
            onClick={() => avatarInputRef.current?.click()}
            className="relative w-32 h-32 rounded-full border-4 border-background bg-gray-200 dark:bg-gray-700 overflow-hidden cursor-pointer group"
          >
            {avatarUrl ? (
              <img src={avatarUrl} alt="Avatar" className="w-full h-full object-cover" />
            ) : (
              <div className="w-full h-full flex items-center justify-center">
                <Camera size={24} className="text-gray-400" />
              </div>
            )}
            <div className="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
              <Camera size={20} className="text-white" />
            </div>
          </div>
          <input
            ref={avatarInputRef}
            type="file"
            accept="image/*"
            onChange={handleAvatarChange}
            className="hidden"
          />
        </div>
        <div>
          <label className="block text-sm font-medium mb-2">Display Name *</label>
          <input
            type="text"
            value={displayName}
            onChange={(e) => setDisplayName(e.target.value)}
            className="w-full px-4 py-3 bg-background border border-border rounded-lg focus:outline-none focus:ring-2 focus:ring-xapzap-blue"
            placeholder="Your display name"
            required
          />
        </div>

        <div>
          <label className="block text-sm font-medium mb-2">Username *</label>
          <input
            type="text"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            className="w-full px-4 py-3 bg-background border border-border rounded-lg focus:outline-none focus:ring-2 focus:ring-xapzap-blue"
            placeholder="@username"
            required
          />
        </div>

        <div>
          <label className="block text-sm font-medium mb-2">Bio</label>
          <textarea
            value={bio}
            onChange={(e) => setBio(e.target.value)}
            rows={4}
            className="w-full px-4 py-3 bg-background border border-border rounded-lg focus:outline-none focus:ring-2 focus:ring-xapzap-blue resize-none"
            placeholder="Tell us about yourself"
          />
        </div>

        <div>
          <label className="block text-sm font-medium mb-2">Location</label>
          <input
            type="text"
            value={location}
            onChange={(e) => setLocation(e.target.value)}
            className="w-full px-4 py-3 bg-background border border-border rounded-lg focus:outline-none focus:ring-2 focus:ring-xapzap-blue"
            placeholder="City, Country"
          />
        </div>

        <div>
          <label className="block text-sm font-medium mb-2">Website</label>
          <input
            type="url"
            value={website}
            onChange={(e) => setWebsite(e.target.value)}
            className="w-full px-4 py-3 bg-background border border-border rounded-lg focus:outline-none focus:ring-2 focus:ring-xapzap-blue"
            placeholder="https://example.com"
          />
        </div>

        <div>
          <label className="block text-sm font-medium mb-2">Category</label>
          <select
            value={category}
            onChange={(e) => setCategory(e.target.value)}
            className="w-full px-4 py-3 bg-background border border-border rounded-lg focus:outline-none focus:ring-2 focus:ring-xapzap-blue"
          >
            <option value="">Select a category</option>
            <option value="Creator">Creator</option>
            <option value="Business">Business</option>
            <option value="Artist">Artist</option>
            <option value="Musician">Musician</option>
            <option value="Influencer">Influencer</option>
            <option value="Developer">Developer</option>
            <option value="Other">Other</option>
          </select>
        </div>
      </div>
    </div>
  )
}
