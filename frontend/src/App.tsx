import React from 'react'
import { Link } from 'react-router-dom'

export default function App() {
  return (
    <div style={{maxWidth:1000,margin:'2rem auto',fontFamily:'Inter,Arial'}}>
      <h1>gogotex — frontend (dev)</h1>
      <p>
        This is a minimal scaffold for Phase‑03 focusing on authentication (login
        + callback). Use the <code>/auth/callback</code> route for the OAuth
        callback.
      </p>
      <p>
        <a href={`${import.meta.env.VITE_KEYCLOAK_URL}/realms/${import.meta.env.VITE_KEYCLOAK_REALM}/protocol/openid-connect/auth?client_id=${import.meta.env.VITE_KEYCLOAK_CLIENT_ID}&response_type=code&redirect_uri=${encodeURIComponent(import.meta.env.VITE_REDIRECT_URI || 'http://localhost:3000/auth/callback')}`}>
          Sign in with Keycloak
        </a>
      </p>
      <p>
        <Link to="/auth/callback">Open callback page (dev)</Link>
        <Link style={{marginLeft:12}} to="/editor">Open editor (dev)</Link>
      </p>
    </div>
  )
}
