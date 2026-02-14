import React, { useState } from 'react'
import Editor from '../../components/editor/Editor'

export const EditorPage: React.FC = () => {
  const saved = typeof window !== 'undefined' ? localStorage.getItem('gogotex.editor.content') || '' : ''
  const [value, setValue] = useState(saved)
  return (
    <div style={{maxWidth:960,margin:'2rem auto'}}>
      <h2>Editor (Phase‑03)</h2>
      <div style={{marginBottom:12}}>
        <button className="btn btn-primary" onClick={() => alert('Compile (stub)')}>Compile</button>
        <button className="btn btn-secondary" style={{marginLeft:8}} onClick={() => { navigator.clipboard?.writeText(value) }}>Copy</button>
      </div>
      <div className="card">
        <Editor initialValue={value} onChange={setValue} />
      </div>
    </div>
  )
}

export default EditorPage
