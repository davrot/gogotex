import create from 'zustand'

type AuthState = {
  user: any | null
  accessToken: string | null
  refreshToken: string | null
  setAuth: (payload: Partial<AuthState>) => void
}

export const useAuthStore = create<AuthState>((set) => ({
  user: null,
  accessToken: null,
  refreshToken: null,
  setAuth: (payload) => set((s) => ({ ...s, ...payload })),
}))
