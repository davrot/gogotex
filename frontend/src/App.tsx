import React from 'react'
import { Link } from 'react-router-dom'

import React from 'react'
import Layout from './components/layout/Layout'

export default function App() {
  return (
    <Layout>
      <div style={{maxWidth:1000,margin:'2rem auto',fontFamily:'Inter,Arial'}}>
        <h1>gogotex — frontend (dev)</h1>
        <p>
          This is a minimal scaffold for Phase‑03 focusing on authentication (login
          + callback). Use the <code>/auth/callback</code> route for the OAuth
          callback.
        </p>
        <p>
          <Link to="/login" className="text-vscode-primary hover:underline">Sign in with Keycloak</Link>
        </p>
        <p>
          <Link to="/auth/callback">Open callback page (dev)</Link>
          <Link style={{marginLeft:12}} to="/editor">Open editor (dev)</Link>
          <Link style={{marginLeft:12}} to="/dashboard">Open dashboard (dev)</Link>
        </p>
      </div>
    </Layout>
  )
}
