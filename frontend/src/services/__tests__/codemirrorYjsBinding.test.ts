import { describe, it, expect } from 'vitest'
import { EditorState } from '@codemirror/state'
import { EditorView } from '@codemirror/view'
import * as Y from 'yjs'
import { yjsBinding } from '../codemirrorYjsBinding'

describe('codemirrorYjsBinding', () => {
  it('propagates local editor changes to Y.Text', () => {
    const ydoc = new Y.Doc()
    const ytext = ydoc.getText('codemirror')

    const state = EditorState.create({ doc: 'local', extensions: [yjsBinding(ytext)] })
    const mount = document.createElement('div')
    const view = new EditorView({ state, parent: mount })

    // local edit -> should update ytext
    view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: 'hello from editor' } })
    expect(ytext.toString()).toBe('hello from editor')

    view.destroy()
  })

  it('applies remote Y.Text changes into the editor', () => {
    const ydoc = new Y.Doc()
    const ytext = ydoc.getText('codemirror')

    const state = EditorState.create({ doc: '', extensions: [yjsBinding(ytext)] })
    const mount = document.createElement('div')
    const view = new EditorView({ state, parent: mount })

    // remote change
    ytext.insert(0, 'remote update')
    // binding uses synchronous observer -> editor should reflect change
    expect(view.state.doc.toString()).toBe('remote update')

    view.destroy()
  })
})
