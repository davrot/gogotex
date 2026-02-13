import React, { useRef, useState } from 'react'
import Editor, { EditorHandle } from '../../components/editor/Editor'

export const EditorPage: React.FC = () => {
  const saved = typeof window !== 'undefined' ? localStorage.getItem('gogotex.editor.content') || '' : ''
  const [value, setValue] = useState(saved)
  const editorRef = useRef<EditorHandle | null>(null)

  const insertBold = () => editorRef.current?.replaceSelection('\\textbf{bold}')
  const insertSection = () => editorRef.current?.insertText('\\section{New section}\n')
  const insertMath = () => editorRef.current?.replaceSelection('\\[  e^{i\\pi} + 1 = 0  \\]')
  const insertTemplate = () => editorRef.current?.insertText('% LaTeX template\n\\documentclass{article}\n\\begin{document}\nHello World\\end{document}\n')

  return (
    <div style={{maxWidth:960,margin:'2rem auto'}}>
      <h2>Editor (Phase‑03)</h2>
      <div style={{marginBottom:12}}>
        <button className="btn btn-primary" onClick={() => alert('Compile (stub)')}>Compile</button>
        <button className="btn btn-secondary" style={{marginLeft:8}} onClick={() => { navigator.clipboard?.writeText(value) }}>Copy</button>
      </div>

      <div style={{marginBottom:12}}>
        <button className="btn" onClick={insertBold}>Bold</button>
        <button className="btn" style={{marginLeft:8}} onClick={insertSection}>Section</button>
        <button className="btn" style={{marginLeft:8}} onClick={insertMath}>Math</button>
        <button className="btn" style={{marginLeft:8}} onClick={insertTemplate}>Insert template</button>
      </div>

      <div className="card">
        <Editor ref={editorRef} initialValue={value} onChange={setValue} language="latex" />
      </div>
    </div>
  )
}

export default EditorPage
