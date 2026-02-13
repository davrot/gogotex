import React from 'react'
import { Link } from 'react-router-dom'

export const Sidebar: React.FC = () => {
  return (
    <aside className="hidden md:block w-56 bg-gray-50 dark:bg-vscode-sidebar border-r border-gray-200 dark:border-vscode-border p-4">
      <div className="mb-6 text-sm text-vscode-textMuted">Workspace</div>
      <ul className="space-y-2 text-sm">
        <li><Link to="/dashboard" className="block py-2 px-3 rounded hover:bg-gray-100 dark:hover:bg-vscode-panel">Home</Link></li>
        <li><Link to="/editor" className="block py-2 px-3 rounded hover:bg-gray-100 dark:hover:bg-vscode-panel">Editor</Link></li>
        <li><a className="block py-2 px-3 rounded text-gray-500 cursor-not-allowed">Projects (coming)</a></li>
      </ul>
    </aside>
  )
}

export default Sidebar
