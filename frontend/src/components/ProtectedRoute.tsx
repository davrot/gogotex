import React from 'react'
import { Navigate } from 'react-router-dom'
import { useAuthStore } from '../stores/authStore'

interface Props { children: JSX.Element }

export const ProtectedRoute: React.FC<Props> = ({ children }) => {
  const accessToken = useAuthStore((s) => s.accessToken)
  const refreshToken = useAuthStore((s) => s.refreshToken)

  // If we have an access token, consider the route allowed. If not but refreshToken
  // exists we can attempt a refresh (synchronously via store) before redirecting.
  if (accessToken) return children

  // Fallback for E2E/tests: if the persisted localStorage contains a valid access
  // token (rehydration can be async), allow optimistic access to avoid immediate
  // redirect during app startup.
  try {
    const raw = typeof window !== 'undefined' ? window.localStorage.getItem('gogotex-auth') : null
    if (!accessToken && raw) {
      const parsed = JSON.parse(raw)
      if (parsed && parsed.accessToken) return children
    }
  } catch (e) {
    /* ignore parse errors */
  }

  if (!accessToken && refreshToken) {
    // trigger a background refresh (non-blocking) and allow optimistic render to /login
    useAuthStore.getState().refreshTokens().catch(() => {})
    return <Navigate to="/login" replace />
  }
  return <Navigate to="/login" replace />
}

export default ProtectedRoute
