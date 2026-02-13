import React from 'react'
import { Link } from 'react-router-dom'

export const Header: React.FC = () => {
  return (
    <header className="bg-white dark:bg-vscode-sidebar border-b border-gray-200 dark:border-vscode-border px-4 py-3 flex items-center justify-between">
      <div className="flex items-center gap-3">
        <img src="/logo.svg" alt="gogotex" className="h-6 w-6" />
        <div className="text-vscode-primary font-semibold">gogotex</div>
        <nav className="hidden sm:flex gap-3 text-sm text-gray-600 dark:text-vscode-textMuted ml-4">
          <Link to="/dashboard" className="hover:underline">Dashboard</Link>
          <Link to="/editor" className="hover:underline">Editor</Link>
        </nav>
      </div>
      <div className="flex items-center gap-3">
        <Link to="/login" className="text-sm text-gray-700 dark:text-vscode-text">Sign in</Link>
      </div>
    </header>
  )
}

export default Header
