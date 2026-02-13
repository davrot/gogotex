export interface LoginResponse {
  accessToken: string
  refreshToken: string
  user: any
}

export const authService = {
  // Exchange authorization code with the backend auth service
  async handleCallback(code: string, _state: string): Promise<LoginResponse> {
    const resp = await fetch((import.meta.env.VITE_AUTH_URL || 'http://localhost:8081') + '/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ code, redirect_uri: import.meta.env.VITE_REDIRECT_URI || 'http://localhost:3000/auth/callback' }),
    })
    if (!resp.ok) {
      const body = await resp.text()
      throw new Error(`Auth service error: ${resp.status} ${body}`)
    }
    return resp.json()
  },
}
