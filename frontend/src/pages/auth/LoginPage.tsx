import React from 'react'

export const LoginPage: React.FC = () => {
  const keycloakUrl = import.meta.env.VITE_KEYCLOAK_URL || 'http://keycloak-keycloak:8080/sso'
  const realm = import.meta.env.VITE_KEYCLOAK_REALM || 'gogotex'
  const clientId = import.meta.env.VITE_KEYCLOAK_CLIENT_ID || 'gogotex-backend'
  const redirect = import.meta.env.VITE_REDIRECT_URI || 'http://localhost:3000/auth/callback'
  const href = `${keycloakUrl}/realms/${realm}/protocol/openid-connect/auth?client_id=${clientId}&response_type=code&redirect_uri=${encodeURIComponent(redirect)}`

  return (
    <div style={{maxWidth:720,margin:'3rem auto'}}>
      <h2 className="text-2xl mb-4">Sign in</h2>
      <p className="mb-6 text-sm text-gray-600">Sign in with Keycloak to access gogotex features.</p>
      <a href={href} className="btn btn-primary">Sign in with Keycloak</a>
      <div className="mt-6 text-sm text-gray-500">Developer: you can also open <code>/auth/callback</code> to test the callback flow.</div>
    </div>
  )
}

export default LoginPage
