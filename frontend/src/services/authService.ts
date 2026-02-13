export interface LoginResponse {
  accessToken: string
  refreshToken: string
  expiresIn?: number
  user: any
}

export interface RefreshResponse {
  accessToken: string
  refreshToken?: string
  expiresIn?: number
}

const AUTH_BASE = import.meta.env.VITE_AUTH_URL || 'http://localhost:8081'

export const authService = {
  // Exchange authorization code with the backend auth service
  async handleCallback(code: string, _state: string): Promise<LoginResponse> {
    const resp = await fetch(`${AUTH_BASE}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ mode: 'auth_code', code, redirect_uri: import.meta.env.VITE_REDIRECT_URI || 'http://localhost:3000/auth/callback' }),
    })
    if (!resp.ok) {
      const body = await resp.text()
      throw new Error(`Auth service error: ${resp.status} ${body}`)
    }
    return resp.json()
  },

  async refresh(refreshToken: string): Promise<RefreshResponse> {
    const resp = await fetch(`${AUTH_BASE}/auth/refresh`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refresh_token: refreshToken }),
    })
    if (!resp.ok) {
      const body = await resp.text()
      throw new Error(`Refresh failed: ${resp.status} ${body}`)
    }
    return resp.json()
  },

  // convenience fetch wrapper that attaches Authorization and auto-refreshes once on 401
  async apiFetch(input: RequestInfo, init: RequestInit = {}) {
    const { useAuthStore } = await import('../stores/authStore')
    const auth = useAuthStore.getState()
    const token = auth.accessToken
    const headers = new Headers(init.headers || {})
    if (token) headers.set('Authorization', `Bearer ${token}`)
    headers.set('Content-Type', headers.get('Content-Type') || 'application/json')

    let res = await fetch(input, { ...init, headers })
    if (res.status === 401 && auth.refreshToken) {
      // try to refresh
      const refreshed = await useAuthStore.getState().refreshTokens()
      if (refreshed) {
        const newToken = useAuthStore.getState().accessToken
        const headers2 = new Headers(init.headers || {})
        if (newToken) headers2.set('Authorization', `Bearer ${newToken}`)
        headers2.set('Content-Type', headers2.get('Content-Type') || 'application/json')
        res = await fetch(input, { ...init, headers: headers2 })
      }
    }
    return res
  }
}
