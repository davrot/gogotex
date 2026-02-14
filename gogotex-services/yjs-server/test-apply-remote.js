const Y = require('yjs')
const { applyRemoteUpdate, getInMemoryDocText } = require('./yjs-server')

;(async () => {
  const ydoc = new Y.Doc()
  const ytext = ydoc.getText('codemirror')
  ytext.insert(0, 'hello world')
  const update = Y.encodeStateAsUpdate(ydoc)

  await applyRemoteUpdate('test-doc', update)

  // small delay to allow async persistence path to settle
  setTimeout(() => {
    const txt = getInMemoryDocText('test-doc')
    console.log('in-memory text:', txt)
    process.exit(0)
  }, 200)
})().catch((err) => { console.error(err); process.exit(1) })
