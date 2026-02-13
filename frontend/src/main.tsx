import React from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter, Routes, Route } from 'react-router-dom'
import App from './App'
import { CallbackPage } from './pages/auth/CallbackPage'

createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <BrowserRouter>
      <Routes>
        <Route path="/*" element={<App />} />
        <Route path="/auth/callback" element={<CallbackPage />} />
      </Routes>
    </BrowserRouter>
  </React.StrictMode>
)
