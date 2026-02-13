import React from 'react'
import Header from './Header'
import Sidebar from './Sidebar'

interface Props {
  children: React.ReactNode
}

export const Layout: React.FC<Props> = ({ children }) => {
  return (
    <div className="min-h-screen bg-white dark:bg-vscode-bg text-gray-900 dark:text-vscode-text">
      <Header />
      <div className="flex">
        <Sidebar />
        <main className="flex-1 p-6">
          {children}
        </main>
      </div>
    </div>
  )
}

export default Layout
