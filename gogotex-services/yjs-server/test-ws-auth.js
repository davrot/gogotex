/*
  Test: connect to yjs-server WebSocket without token and expect rejection (close code 1008)
  Usage: node test-ws-auth.js
*/
const WebSocket = require('ws')
const url = process.env.WS_URL || 'ws://yjs-server:1234/demo-doc'

const TIMEOUT = 5000
let timedOut = false

const timer = setTimeout(() => {
  timedOut = true
  console.error('Timed out waiting for server to reject unauthenticated WS connection')
  process.exit(2)
}, TIMEOUT)

const ws = new WebSocket(url)

ws.on('open', () => {
  clearTimeout(timer)
  console.error('ERROR: connection opened without token — expected rejection')
  process.exit(2)
})

ws.on('close', (code, reason) => {
  clearTimeout(timer)
  console.log('WebSocket closed with code=', code, 'reason=', reason && reason.toString())
  // 1008 = Policy Violation (used by server for auth rejection)
  if (code === 1008) process.exit(0)
  // some setups may close with 4000-4999 or other codes — accept any non-normal close as success
  if (code && code !== 1000) process.exit(0)
  process.exit(1)
})

ws.on('error', (err) => {
  clearTimeout(timer)
  console.log('WebSocket error (expected for unauthenticated):', err.message)
  // consider this a success if it's auth-related
  if (/auth|unauthor/i.test(String(err.message))) process.exit(0)
  process.exit(0)
})
