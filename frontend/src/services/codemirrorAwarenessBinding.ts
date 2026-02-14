import { ViewPlugin, ViewUpdate, EditorView } from '@codemirror/view'

// Simple awareness -> DOM overlay binding for CodeMirror 6
// - listens to provider.awareness and renders remote carets/selections as DOM overlays
// - updates local selection into awareness (so other clients can render this user's caret)

export function awarenessBinding(awareness: any) {
  return ViewPlugin.fromClass(class {
    view: EditorView
    awareness: any
    overlay: HTMLDivElement
    onAwarenessChange: () => void
    onScroll: () => void

    constructor(view: EditorView) {
      this.view = view
      this.awareness = awareness

      // overlay container (absolute inside editor root)
      this.overlay = document.createElement('div')
      this.overlay.className = 'cm-remote-overlays'
      this.overlay.style.position = 'absolute'
      this.overlay.style.top = '0'
      this.overlay.style.left = '0'
      this.overlay.style.width = '100%'
      this.overlay.style.height = '100%'
      this.overlay.style.pointerEvents = 'none'
      this.overlay.style.zIndex = '10'
      // insert as first child so it sits above content
      try { this.view.dom.appendChild(this.overlay) } catch (e) { /* ignore */ }

      this.onAwarenessChange = () => this.renderFromAwareness()
      this.onScroll = () => this.repositionOverlays()

      try {
        this.awareness.on('change', this.onAwarenessChange)
      } catch (e) { /* ignore - provider might not expose awareness events */ }

      // reposition on scroll/resize
      try { this.view.scrollDOM.addEventListener('scroll', this.onScroll) } catch (e) { /* ignore */ }
      window.addEventListener('resize', this.onScroll)

      // seed local selection into awareness immediately
      this.setLocalSelection()

      // initial render
      this.renderFromAwareness()
    }

    update(update: ViewUpdate) {
      // push local selection changes into awareness so peers can render our caret
      if (update.selectionSet) this.setLocalSelection()
      // reposition overlays when doc layout changes
      if (update.docChanged || update.viewportChanged || update.selectionSet) this.repositionOverlays()
    }

    setLocalSelection() {
      try {
        const sel = this.view.state.selection.main
        const anchor = sel.anchor
        const head = sel.head
        // store minimal selection info
        this.awareness.setLocalStateField('selection', { anchor, head })
      } catch (e) { /* ignore */ }
    }

    renderFromAwareness() {
      try {
        // clear existing overlays
        while (this.overlay.firstChild) this.overlay.removeChild(this.overlay.firstChild)

        const states: Map<number, any> = this.awareness.getStates()
        const localClient = (this.awareness && this.awareness.clientID) || null

        states.forEach((st: any, clientId: number) => {
          try {
            if (!st || clientId === localClient) return // skip local
            const user = st.user || { name: 'Anon', color: '#888' }
            const sel = st.selection
            if (!sel) return

            const anchor = Math.max(0, Math.min(sel.anchor ?? 0, this.view.state.doc.length))
            const head = Math.max(0, Math.min(sel.head ?? anchor, this.view.state.doc.length))

            if (anchor === head) {
              const caret = document.createElement('span')
              caret.className = 'cm-remote-caret'
              caret.setAttribute('data-user', String(user.name || user.email || clientId))
              caret.style.position = 'absolute'
              caret.style.width = '2px'
              caret.style.background = user.color || '#ff4d4f'
              caret.style.height = (this.view.defaultLineHeight || 16) + 'px'
              caret.style.transform = 'translateY(-1px)'
              this.overlay.appendChild(caret)
            } else {
              const rangeEl = document.createElement('div')
              rangeEl.className = 'cm-remote-selection'
              rangeEl.setAttribute('data-user', String(user.name || user.email || clientId))
              rangeEl.style.position = 'absolute'
              rangeEl.style.background = (user.color || '#ff4d4f')
              rangeEl.style.opacity = '0.25'
              rangeEl.style.borderRadius = '3px'
              this.overlay.appendChild(rangeEl)
            }
          } catch (e) { /* ignore per-state errors */ }
        })

        // position created overlay children
        this.repositionOverlays()
      } catch (err) {
        // don't throw in plugin
        // console.warn('[awarenessBinding] render failed', err)
      }
    }

    repositionOverlays() {
      try {
        const baseRect = this.view.dom.getBoundingClientRect()
        const children = Array.from(this.overlay.children)
        const states: Map<number, any> = this.awareness.getStates()

        // Build an ordered list of states so we can map overlays to states in the same order
        const remoteStates: any[] = []
        states.forEach((st: any, clientId: number) => {
          if (!st) return
          if (clientId === (this.awareness && this.awareness.clientID)) return
          remoteStates.push({ clientId, state: st })
        })

        for (let i = 0; i < children.length; i++) {
          const el = children[i] as HTMLElement
          const rs = remoteStates[i]
          if (!rs) { el.style.display = 'none'; continue }
          const sel = rs.state.selection
          if (!sel) { el.style.display = 'none'; continue }

          const anchor = Math.max(0, Math.min(sel.anchor ?? 0, this.view.state.doc.length))
          const head = Math.max(0, Math.min(sel.head ?? anchor, this.view.state.doc.length))

          // coordsAtPos may return null in non-browser testing environments — guard
          const fromCoords = this.view.coordsAtPos(Math.min(anchor, this.view.state.doc.length))
          const toCoords = this.view.coordsAtPos(Math.min(head, this.view.state.doc.length))

          if (!fromCoords || !toCoords) {
            el.style.display = 'none'
            continue
          }

          const left = fromCoords.left - baseRect.left + this.view.scrollDOM.scrollLeft
          const top = fromCoords.top - baseRect.top + this.view.scrollDOM.scrollTop

          if (el.classList.contains('cm-remote-caret')) {
            (el as HTMLElement).style.left = `${left}px`
            (el as HTMLElement).style.top = `${top}px`
            el.style.display = ''
          } else {
            const width = Math.max(2, toCoords.right - fromCoords.left)
            (el as HTMLElement).style.left = `${left}px`
            (el as HTMLElement).style.top = `${top}px`
            (el as HTMLElement).style.width = `${width}px`
            (el as HTMLElement).style.height = `${fromCoords.bottom - fromCoords.top}px`
            el.style.display = ''
          }
        }
      } catch (e) {
        // ignore runtime positioning errors (eg. in jsdom)
      }
    }

    destroy() {
      try { this.awareness.off('change', this.onAwarenessChange) } catch (e) { /* ignore */ }
      try { this.view.scrollDOM.removeEventListener('scroll', this.onScroll) } catch (e) { /* ignore */ }
      try { window.removeEventListener('resize', this.onScroll) } catch (e) { /* ignore */ }
      try { if (this.overlay && this.overlay.parentNode) this.overlay.parentNode.removeChild(this.overlay) } catch (e) { /* ignore */ }
    }
  })
}
