import * as Y from 'yjs'
import { WebsocketProvider } from 'y-websocket'

class WebSocketService {
  connect(documentId: string, ydoc?: Y.Doc, opts?: { token?: string }) {
    const doc = ydoc || new Y.Doc()
    const protocol = window.location.protocol === 'https:' ? 'wss' : 'ws'
    const host = window.location.hostname || 'localhost'
    const port = 4444
    const wsUrl = `${protocol}://${host}:${port}`
    const provider = new WebsocketProvider(wsUrl, documentId, doc, { params: { token: opts?.token } })
    return { provider, doc }
  }

  disconnect(provider: WebsocketProvider) {
    try { provider.disconnect() } catch (e) { /* ignore */ }
  }
}

export const websocketService = new WebSocketService()
