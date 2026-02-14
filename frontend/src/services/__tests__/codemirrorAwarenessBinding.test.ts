import { describe, it, expect } from 'vitest'
import { EditorState } from '@codemirror/state'
import { EditorView } from '@codemirror/view'
import { awarenessBinding } from '../codemirrorAwarenessBinding'

function makeFakeAwareness() {
  const states = new Map<number, any>()
  const handlers: Array<() => void> = []
  return {
    clientID: 1,
    getStates: () => states,
    on: (ev: string, h: () => void) => { if (ev === 'change') handlers.push(h) },
    off: (ev: string, h: () => void) => { /* noop for test */ },
    setLocalStateField: (_k: string, _v: any) => { /* noop */ },
    // test helper
    _setRemoteState: (id: number, state: any) => { states.set(id, state); handlers.forEach(h => h()) },
  }
}

describe('codemirrorAwarenessBinding', () => {
  it('renders a remote caret element when awareness contains a remote selection', () => {
    const awareness = makeFakeAwareness()
    const state = EditorState.create({ doc: 'hello world', extensions: [awarenessBinding(awareness as any)] })
    const mount = document.createElement('div')
    const view = new EditorView({ state, parent: mount })

    // simulate a remote client with a caret at position 5
    awareness._setRemoteState(2, { user: { name: 'remote', color: '#00f' }, selection: { anchor: 5, head: 5 } })

    // plugin creates overlay children synchronously; ensure caret exists in DOM
    const caret = mount.querySelector('.cm-remote-caret')
    expect(caret).toBeTruthy()
    if (caret) expect(caret.getAttribute('data-user')).toBe('remote')

    view.destroy()
  })
})
