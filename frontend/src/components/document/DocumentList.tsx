import React, { useEffect, useState } from 'react'
import { editorService } from '../../services/editorService'

export type DocInfo = { id: string; name: string }

const DocumentList: React.FC<{ onOpen: (id: string) => void }> = ({ onOpen }) => {
  const [docs, setDocs] = useState<DocInfo[]>([])
  const [loading, setLoading] = useState(false)

  const load = async () => {
    setLoading(true)
    try {
      const res = await editorService.listDocuments()
      setDocs(res || [])
    } catch (e) {
      setDocs([])
    } finally { setLoading(false) }
  }

  useEffect(() => { void load() }, [])

  return (
    <div style={{marginBottom:12}}>
      <div style={{display:'flex',alignItems:'center',justifyContent:'space-between', marginBottom:6}}>
        <strong>Documents</strong>
        <button className="btn btn-ghost" onClick={() => void load()}>{loading ? '...' : 'Refresh'}</button>
      </div>
      {docs.length === 0 ? (
        <div style={{color:'#666'}}>No documents</div>
      ) : (
        <ul style={{paddingLeft:12}}>
          {docs.map(d => (
            <li key={d.id} style={{marginBottom:6}}>
              <button className="link-like" onClick={() => onOpen(d.id)}>{d.name}</button>
              <small style={{marginLeft:8,color:'#666'}}>({d.id})</small>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

export default DocumentList
