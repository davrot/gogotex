import React from 'react'
import { render, screen, waitFor } from '@testing-library/react'
import { test, expect, vi } from 'vitest'

// mock lazy-imported DocumentList used by EditorPage (keeps unit test focused)
vi.mock('../../components/document/DocumentList', () => ({
  default: (props: any) => {
    return (<div data-testid="doc-list-mock">mocked</div>)
  }
}))

import EditorPage from './EditorPage'

// Lightweight unit test for the EditorPage WebSocket handler (compile-update)
test('EditorPage handles `compile-update` websocket message and updates preview + SyncTeX', async () => {
  // set attached document in localStorage so EditorPage opens WS connection
  Object.defineProperty(window, 'localStorage', { value: window.localStorage })
  window.localStorage.setItem('gogotex.editor.docId', 'UNIT_DOC')
  window.localStorage.setItem('gogotex.editor.docName', 'unit-test.tex')

  // Fake WebSocket implementation to intercept created sockets and deliver a message
  const OriginalWebSocket = (window as any).WebSocket
  class FakeWebSocket {
    static instances: FakeWebSocket[] = []
    url: string
    readyState = 1
    onopen: ((ev?: any) => void) | null = null
    onmessage: ((ev: { data: any }) => void) | null = null
    onclose: ((ev?: any) => void) | null = null
    onerror: ((ev?: any) => void) | null = null
    constructor(url: string) {
      this.url = url
      FakeWebSocket.instances.push(this)
      // simulate open
      setTimeout(() => { this.onopen && this.onopen({}) }, 0)
    }
    send(_d: any) { /* no-op */ }
    close() { this.readyState = 3; this.onclose && this.onclose({}) }
  }
  ;(window as any).WebSocket = FakeWebSocket

  try {
    render(<EditorPage />)

    // expect the editor to show it is attached to UNIT_DOC
    await waitFor(() => expect(screen.getByText(/Attached document:/)).toBeInTheDocument())

    // grab the created fake socket and deliver a compile-update payload that includes synctexMap
    const sock = (FakeWebSocket.instances[0] as any)
    expect(sock).toBeDefined()

    const payload = {
      type: 'compile-update',
      payload: {
        docId: 'UNIT_DOC',
        jobId: 'job-unit-1',
        previewUrl: '/api/documents/UNIT_DOC/preview?job=job-unit-1',
        synctexMap: { pages: { '1': [{ y: 0.05, line: 1 }, { y: 0.9, line: 42 }] } }
      }
    }

    // deliver message
    actDeliverMessage(sock, JSON.stringify(payload))

    // iframe preview should appear with the provided previewUrl
    await waitFor(() => expect(screen.getByTitle('preview')).toHaveAttribute('src', '/api/documents/UNIT_DOC/preview?job=job-unit-1'))

    // SyncTeX indicator should be present
    await waitFor(() => expect(screen.getByText(/SyncTeX available/)).toBeInTheDocument())
  } finally {
    // restore original WebSocket implementation
    ;(window as any).WebSocket = OriginalWebSocket
    window.localStorage.removeItem('gogotex.editor.docId')
    window.localStorage.removeItem('gogotex.editor.docName')
  }
})

// helper to invoke socket onmessage in a way compatible with jsdom timing
function actDeliverMessage(sock: any, data: string) {
  if (!sock) throw new Error('socket missing')
  if (typeof sock.onmessage === 'function') {
    sock.onmessage({ data })
  } else {
    // deliver later if handler not yet attached
    setTimeout(() => sock.onmessage && sock.onmessage({ data }), 10)
  }
}
