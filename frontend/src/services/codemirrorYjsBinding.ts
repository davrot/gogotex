import { ViewPlugin, ViewUpdate, EditorView } from '@codemirror/view'
import * as Y from 'yjs'

// Minimal, loop-safe CodeMirror <-> Y.Text binding implemented as a ViewPlugin.
// - Applies local editor transactions to Y.Text (incremental diff).
// - Applies remote Y.Text updates to the editor using the minimal replace.
// This intentionally keeps the implementation small and dependency-free so we
// don't need `y-codemirror.next` peer-resolution.

export function yjsBinding(ytext: Y.Text) {
  return ViewPlugin.fromClass(class {
    view: EditorView
    ytext: Y.Text
    applyingRemote: boolean
    observer: (event: Y.YTextEvent) => void

    constructor(view: EditorView) {
      this.view = view
      this.ytext = ytext
      this.applyingRemote = false

      this.observer = (_event) => {
        try {
          // apply remote snapshot into editor
          const newText = this.ytext.toString()
          const oldText = this.view.state.doc.toString()
          if (newText === oldText) return

          this.applyingRemote = true

          // compute minimal replace (prefix / suffix)
          let start = 0
          const minLen = Math.min(oldText.length, newText.length)
          while (start < minLen && oldText[start] === newText[start]) start++

          let endOld = oldText.length - 1
          let endNew = newText.length - 1
          while (endOld >= start && endNew >= start && oldText[endOld] === newText[endNew]) {
            endOld--
            endNew--
          }

          const insert = newText.slice(start, endNew + 1)
          const from = start
          const to = endOld + 1

          this.view.dispatch({ changes: { from, to, insert } })
        } catch (err) {
          console.warn('[yjsBinding] failed to apply remote update', err)
        } finally {
          this.applyingRemote = false
        }
      }

      this.ytext.observe(this.observer)
    }

    update(update: ViewUpdate) {
      // local editor change -> propagate to Y.Text
      if (!update.docChanged) return
      if (this.applyingRemote) return // change originated from remote, ignore

      try {
        const editorText = this.view.state.doc.toString()
        const yText = this.ytext.toString()
        if (editorText === yText) return

        // compute minimal diff (prefix/suffix)
        let start = 0
        const minLen = Math.min(editorText.length, yText.length)
        while (start < minLen && editorText[start] === yText[start]) start++

        let endEditor = editorText.length - 1
        let endY = yText.length - 1
        while (endEditor >= start && endY >= start && editorText[endEditor] === yText[endY]) {
          endEditor--
          endY--
        }

        const insert = editorText.slice(start, endEditor + 1)
        const deleteLen = Math.max(0, endY - start + 1)

        // apply to Y.Text (these operations will be observed by other peers)
        if (deleteLen > 0) {
          this.ytext.delete(start, deleteLen)
        }
        if (insert.length > 0) {
          this.ytext.insert(start, insert)
        }
      } catch (err) {
        console.warn('[yjsBinding] failed to propagate local change to Y.Text', err)
      }
    }

    destroy() {
      try { this.ytext.unobserve(this.observer) } catch (e) { /* ignore */ }
    }
  })
}
