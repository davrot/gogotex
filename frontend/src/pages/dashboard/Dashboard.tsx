import React from 'react'
import { useAuthStore } from '../../stores/authStore'

export const Dashboard: React.FC = () => {
  const user = useAuthStore((s) => s.user)
  const setAuth = useAuthStore((s) => s.setAuth)
  const [apiUser, setApiUser] = React.useState<any | null>(null)

  React.useEffect(() => {
    let mounted = true
    ;(async () => {
      try {
        const res = await (await import('../../services/authService')).authService.apiFetch('/api/v1/me')
        if (!res.ok) return
        const data = await res.json()
        if (!mounted) return
        setApiUser(data)
        // also ensure store is up-to-date
        setAuth({ user: data })
      } catch (err) {
        // ignore
      }
    })()
    return () => { mounted = false }
  }, [setAuth])

  const displayUser = apiUser || user
  return (
    <div style={{maxWidth:960,margin:'2rem auto'}}>
      <h1 className="text-2xl font-semibold mb-4">Dashboard</h1>
      {displayUser ? (
        <div className="card">
          <h3 className="font-medium">Welcome, {displayUser.name}</h3>
          <p className="text-sm text-gray-600">Email: {displayUser.email}</p>
        </div>
      ) : (
        <div className="card">You are not signed in. Please <a href="/login" className="text-vscode-primary">sign in</a>.</div>
      )}
    </div>
  )
}

export default Dashboard
