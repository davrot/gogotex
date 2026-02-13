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
  if (!accessToken && refreshToken) {
    // trigger a background refresh (non-blocking) and allow optimistic render to /login
    useAuthStore.getState().refreshTokens().catch(() => {})
    return <Navigate to="/login" replace />
  }
  return <Navigate to="/login" replace />
}

export default ProtectedRoute
