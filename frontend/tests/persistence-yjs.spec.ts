import { test, expect } from '@playwright/test'

// Integration: verify compile produces persisted artifacts (downloadable PDF / synctex map)
// and that yjs-server caches the compile metadata (GET /api/compile/:docId/latest).
// This test is safe-skippable when yjs-server or backend aren't available in the environment.

test('persistence → MinIO + Mongo → yjs replication (integration)', async ({ request }) => {
  // quick check: is yjs-server reachable? if not, skip (useful for local dev)
  let yjsAvailable = true
  try {
    const r = await request.get('http://yjs-server:1234/')
    yjsAvailable = r.ok()
  } catch (e) {
    yjsAvailable = false
  }
  test.skip(!yjsAvailable, 'yjs-server not available in this environment')

  // create a real document via backend API
  const create = await request.post('/api/documents', { data: { name: 'persistence-e2e.tex', content: '\\documentclass{article}\\begin{document}Hello E2E\\end{document}' } })
  expect(create.ok()).toBeTruthy()
  const doc = await create.json()
  const docId = doc.id || doc._id
  expect(docId).toBeTruthy()

  // trigger compile
  const compileStart = await request.post(`/api/documents/${docId}/compile`)
  expect(compileStart.ok()).toBeTruthy()

  // poll compile logs/status until ready
  let jobId: string | null = null
  for (let i = 0; i < 60; i++) {
    const logs = await request.get(`/api/documents/${docId}/compile/logs`)
    expect(logs.ok()).toBeTruthy()
    const body = await logs.json()
    if (body.status === 'ready') { jobId = body.jobId || body.jobID; break }
    await new Promise((r) => setTimeout(r, 500))
  }
  expect(jobId).toBeTruthy()

  // download compiled PDF (served through backend -> MinIO) and assert PDF header
  const pdf = await request.get(`/api/documents/${docId}/compile/${jobId}/download`)
  expect(pdf.ok()).toBeTruthy()
  const buf = await pdf.body()
  const header = Buffer.from(buf).slice(0, 4).toString()
  expect(header).toBe('%PDF')

  // fetch best-effort SyncTeX JSON map (persisted in Mongo)
  const mapRes = await request.get(`/api/documents/${docId}/compile/${jobId}/synctex/map`)
  expect(mapRes.ok()).toBeTruthy()
  const mapJson = await mapRes.json()
  expect(mapJson).toHaveProperty('pages')

  // finally assert yjs-server cached the compile metadata (replicated via Redis pub/sub)
  const yjsRes = await request.get(`http://yjs-server:1234/api/compile/${docId}/latest`)
  expect(yjsRes.ok()).toBeTruthy()
  const yjsJson = await yjsRes.json()
  const yjsJobId = yjsJson.jobId || yjsJson.jobID
  expect(yjsJobId).toBe(jobId)
})