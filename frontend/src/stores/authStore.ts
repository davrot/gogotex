import create from 'zustand'
import { persist } from 'zustand/middleware'
import { authService } from '../services/authService'

type AuthState = {
  user: any | null
  accessToken: string | null
  refreshToken: string | null
  accessTokenExpiry?: number | null // unix ms

  setAuth: (payload: Partial<AuthState> & { expiresIn?: number }) => void
  clearAuth: () => void
  refreshTokens: () => Promise<boolean>
}

// Persist auth tokens to localStorage and provide helper methods for auto-refresh
export const useAuthStore = create(persist< AuthState >((set, get) => ({
  user: null,
  accessToken: null,
  refreshToken: null,
  accessTokenExpiry: null,

  setAuth: ({ accessToken, refreshToken, user, expiresIn, ...rest }) => {
    const expiry = expiresIn ? Date.now() + expiresIn * 1000 : null
    set((s) => ({ ...s, user: user ?? s.user, accessToken: accessToken ?? s.accessToken, refreshToken: refreshToken ?? s.refreshToken, accessTokenExpiry: expiry, ...rest }))
    // schedule a refresh 60s before expiry
    if (expiry) {
      const refreshAt = Math.max(0, expiry - Date.now() - 60000)
      setTimeout(async () => {
        try { await get().refreshTokens() } catch (e) { /* ignore */ }
      }, refreshAt)
    }
  },

  clearAuth: () => set({ user: null, accessToken: null, refreshToken: null, accessTokenExpiry: null }),

  refreshTokens: async () => {
    const rt = get().refreshToken
    if (!rt) return false
    try {
      const r = await authService.refresh(rt)
      if (r && r.accessToken) {
        set({ accessToken: r.accessToken, refreshToken: r.refreshToken ?? rt, accessTokenExpiry: Date.now() + (r.expiresIn ?? 900) * 1000 })
        return true
      }
      get().clearAuth()
      return false
    } catch (err) {
      get().clearAuth()
      return false
    }
  }
}), { name: 'gogotex-auth' }))

