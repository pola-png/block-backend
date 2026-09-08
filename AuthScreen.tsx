'use client'

import { useState } from 'react'
import { Eye, EyeOff, Mail, Lock, User, AtSign } from 'lucide-react'
import appwriteService from './appwriteService'
import { cn } from './utils'

type AuthMode = 'signin' | 'signup' | 'forgotPassword'

interface AuthScreenProps {
  onAuthSuccess: () => void
}

export function AuthScreen({ onAuthSuccess }: AuthScreenProps) {
  const [mode, setMode] = useState<AuthMode>('signin')
  const [isLoading, setIsLoading] = useState(false)
  const [showPassword, setShowPassword] = useState(false)
  const [showConfirmPassword, setShowConfirmPassword] = useState(false)
  const [error, setError] = useState('')

  const [formData, setFormData] = useState({
    email: '',
    password: '',
    confirmPassword: '',
    username: '',
    displayName: ''
  })

  const handleInputChange = (field: string, value: string) => {
    setFormData(prev => ({ ...prev, [field]: value }))
    if (error) setError('')
  }

  const validateForm = () => {
    if (!formData.email || !/^[^@]+@[^@]+\.[^@]+/.test(formData.email)) {
      setError('Please enter a valid email')
      return false
    }

    if (mode !== 'forgotPassword' && formData.password.length < 8) {
      setError('Password must be at least 8 characters')
      return false
    }

    if (mode === 'signup') {
      if (!formData.displayName || formData.displayName.trim().length < 2) {
        setError('Display name must be at least 2 characters')
        return false
      }

      if (!formData.username || formData.username.length < 3) {
        setError('Username must be at least 3 characters')
        return false
      }

      if (!/^[a-zA-Z0-9_]+$/.test(formData.username.replace(/^@/, ''))) {
        setError('Username can only contain letters, numbers, and underscores')
        return false
      }

      if (formData.password !== formData.confirmPassword) {
        setError('Passwords do not match')
        return false
      }
    }

    return true
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!validateForm()) return

    setIsLoading(true)
    setError('')

    try {
      if (mode === 'signin') {
        console.log('Attempting sign in...')
        const result = await appwriteService.signIn(formData.email, formData.password)
        console.log('Sign in result:', result)

        // Verify session was created
        const user = await appwriteService.getCurrentUser()
        console.log('User after sign in:', user)

        onAuthSuccess()
      } else if (mode === 'forgotPassword') {
        await appwriteService.forgotPassword(formData.email)
        setError('Password reset link sent to your email!')
      } else {
        const username = formData.username.startsWith('@')
          ? formData.username.substring(1)
          : formData.username
        console.log('Attempting sign up...')
        const result = await appwriteService.signUp(formData.email, formData.password, username, formData.displayName)
        console.log('Sign up result:', result)

        // Verify session was created
        const user = await appwriteService.getCurrentUser()
        console.log('User after sign up:', user)

        onAuthSuccess()
      }
    } catch (err: any) {
      console.error('Authentication error:', err)
      setError(err.message || 'Authentication failed')
    } finally {
      setIsLoading(false)
    }
  }

  return (
    <div className="min-h-screen bg-background flex items-center justify-center p-4">
      <div className="w-full max-w-md">
        <div className="bg-card rounded-2xl shadow-lg border border-border p-8">
          {/* Header */}
          <div className="text-center mb-8">
            <h1 className="text-3xl font-bold text-foreground mb-2">
              {mode === 'signin' ? 'Welcome Back!' : mode === 'forgotPassword' ? 'Reset Password' : 'Create Account'}
            </h1>
            <p className="text-muted-foreground">
              {mode === 'signin'
                ? 'Enter your credentials to access your account'
                : mode === 'forgotPassword'
                ? 'Enter your email to receive a reset link'
                : 'Enter your details to create your account'}
            </p>
          </div>

          {/* Form */}
          <form onSubmit={handleSubmit} className="space-y-6">
            {mode === 'signup' && (
              <>
                <div>
                  <label className="block text-sm font-medium text-foreground mb-2">
                    Display Name
                  </label>
                  <div className="relative">
                    <User className="absolute left-3 top-1/2 transform -translate-y-1/2 text-muted-foreground" size={16} />
                    <input
                      type="text"
                      value={formData.displayName}
                      onChange={(e) => handleInputChange('displayName', e.target.value)}
                      placeholder="Your full name"
                      className="w-full pl-10 pr-4 py-3 border border-border rounded-lg bg-background text-foreground placeholder-muted-foreground focus:outline-none focus:ring-2 focus:ring-xapzap-blue focus:border-transparent"
                      disabled={isLoading}
                    />
                  </div>
                </div>

                <div>
                  <label className="block text-sm font-medium text-foreground mb-2">
                    Username
                  </label>
                  <div className="relative">
                    <AtSign className="absolute left-3 top-1/2 transform -translate-y-1/2 text-muted-foreground" size={16} />
                    <input
                      type="text"
                      value={formData.username}
                      onChange={(e) => handleInputChange('username', e.target.value)}
                      placeholder="yourusername"
                      className="w-full pl-10 pr-4 py-3 border border-border rounded-lg bg-background text-foreground placeholder-muted-foreground focus:outline-none focus:ring-2 focus:ring-xapzap-blue focus:border-transparent"
                      disabled={isLoading}
                    />
                  </div>
                </div>
              </>
            )}

            <div>
              <label className="block text-sm font-medium text-foreground mb-2">
                Email
              </label>
              <div className="relative">
                <Mail className="absolute left-3 top-1/2 transform -translate-y-1/2 text-muted-foreground" size={16} />
                <input
                  type="email"
                  value={formData.email}
                  onChange={(e) => handleInputChange('email', e.target.value)}
                  placeholder="name@example.com"
                  className="w-full pl-10 pr-4 py-3 border border-border rounded-lg bg-background text-foreground placeholder-muted-foreground focus:outline-none focus:ring-2 focus:ring-xapzap-blue focus:border-transparent"
                  disabled={isLoading}
                />
              </div>
            </div>

            {mode !== 'forgotPassword' && (
              <div>
                <label className="block text-sm font-medium text-foreground mb-2">
                  Password
                </label>
                <div className="relative">
                  <Lock className="absolute left-3 top-1/2 transform -translate-y-1/2 text-muted-foreground" size={16} />
                  <input
                    type={showPassword ? 'text' : 'password'}
                    value={formData.password}
                    onChange={(e) => handleInputChange('password', e.target.value)}
                    placeholder="Enter your password"
                    className="w-full pl-10 pr-12 py-3 border border-border rounded-lg bg-background text-foreground placeholder-muted-foreground focus:outline-none focus:ring-2 focus:ring-xapzap-blue focus:border-transparent"
                    disabled={isLoading}
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-3 top-1/2 transform -translate-y-1/2 text-muted-foreground hover:text-foreground"
                    disabled={isLoading}
                  >
                    {showPassword ? <EyeOff size={16} /> : <Eye size={16} />}
                  </button>
                </div>
              </div>
            )}

            {mode === 'signup' && (
              <div>
                <label className="block text-sm font-medium text-foreground mb-2">
                  Confirm Password
                </label>
                <div className="relative">
                  <Lock className="absolute left-3 top-1/2 transform -translate-y-1/2 text-muted-foreground" size={16} />
                  <input
                    type={showConfirmPassword ? 'text' : 'password'}
                    value={formData.confirmPassword}
                    onChange={(e) => handleInputChange('confirmPassword', e.target.value)}
                    placeholder="Confirm your password"
                    className="w-full pl-10 pr-12 py-3 border border-border rounded-lg bg-background text-foreground placeholder-muted-foreground focus:outline-none focus:ring-2 focus:ring-xapzap-blue focus:border-transparent"
                    disabled={isLoading}
                  />
                  <button
                    type="button"
                    onClick={() => setShowConfirmPassword(!showConfirmPassword)}
                    className="absolute right-3 top-1/2 transform -translate-y-1/2 text-muted-foreground hover:text-foreground"
                    disabled={isLoading}
                  >
                    {showConfirmPassword ? <EyeOff size={16} /> : <Eye size={16} />}
                  </button>
                </div>
              </div>
            )}

            {error && (
              <div className="p-3 bg-red-50 border border-red-200 rounded-lg">
                <p className="text-red-600 text-sm">{error}</p>
              </div>
            )}

            <button
              type="submit"
              disabled={isLoading}
              className={cn(
                "w-full py-3 px-4 rounded-lg font-medium transition-colors",
                "bg-xapzap-blue text-white hover:bg-blue-600",
                "disabled:opacity-50 disabled:cursor-not-allowed"
              )}
            >
              {isLoading ? (
                <div className="flex items-center justify-center">
                  <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin mr-2" />
                  {mode === 'signin' ? 'Signing In...' : mode === 'forgotPassword' ? 'Sending Reset Link...' : 'Creating Account...'}
                </div>
              ) : (
                mode === 'signin' ? 'Sign In' : mode === 'forgotPassword' ? 'Send Reset Link' : 'Create Account'
              )}
            </button>
          </form>

          {/* Footer */}
          <div className="mt-6 text-center space-y-2">
            {mode === 'signin' && (
              <button
                onClick={() => {
                  setMode('forgotPassword')
                  setError('')
                  setFormData({ email: '', password: '', confirmPassword: '', username: '', displayName: '' })
                }}
                className="text-sm text-muted-foreground hover:text-xapzap-blue hover:underline"
                disabled={isLoading}
              >
                Forgot your password?
              </button>
            )}

            {mode === 'forgotPassword' && (
              <button
                onClick={() => {
                  setMode('signin')
                  setError('')
                  setFormData({ email: '', password: '', confirmPassword: '', username: '', displayName: '' })
                }}
                className="text-sm text-muted-foreground hover:text-xapzap-blue hover:underline"
                disabled={isLoading}
              >
                Back to Sign In
              </button>
            )}

            {mode !== 'forgotPassword' && (
              <p className="text-muted-foreground">
                {mode === 'signin' ? "Don't have an account? " : "Already have an account? "}
                <button
                  onClick={() => {
                    setMode(mode === 'signin' ? 'signup' : 'signin')
                    setError('')
                    setFormData({ email: '', password: '', confirmPassword: '', username: '', displayName: '' })
                  }}
                  className="text-xapzap-blue hover:underline font-medium"
                  disabled={isLoading}
                >
                  {mode === 'signin' ? 'Sign Up' : 'Sign In'}
                </button>
              </p>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}