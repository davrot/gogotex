import { test, expect } from '@playwright/test'

const KEYCLOAK = process.env.PLAYWRIGHT_KEYCLOAK || 'http://keycloak-keycloak:8080'
const CLIENT_ID = process.env.PLAYWRIGHT_KC_CLIENT || 'gogotex-backend'
const REALM = process.env.PLAYWRIGHT_KC_REALM || 'gogotex'
const TEST_USER = process.env.TEST_USER || 'testuser'
let TEST_PASS = process.env.TEST_PASS || 'Test123!'
try {
  const fs = require('fs')
  const pwdFile = '../../gogotex-support-services/keycloak-service/testuser_password.txt'
  if ((!process.env.TEST_PASS || process.env.TEST_PASS === 'Test123!') && fs.existsSync(pwdFile)) {
    TEST_PASS = fs.readFileSync(pwdFile, 'utf8').trim()
  }
} catch (e) { /* ignore */ }

async function performOidcLogin(page: any, baseURL: string) {
  const redirectUri = process.env.PLAYWRIGHT_REDIRECT_URI || `${baseURL}/auth/callback`
  const authUrl = `${KEYCLOAK}/realms/${REALM}/protocol/openid-connect/auth?client_id=${CLIENT_ID}&response_type=code&scope=openid&redirect_uri=${encodeURIComponent(
    redirectUri,
  )}`

  await page.goto(authUrl)
  await page.waitForSelector('input[name="username"]', { timeout: 10000 })
  await page.waitForSelector('input[name="password"]', { timeout: 10000 })
  await page.fill('input[name="username"]', TEST_USER)
  await page.fill('input[name="password"]', TEST_PASS)

  const navPromise = page.waitForNavigation({ url: new RegExp(redirectUri.replace(/[-/\\^$*+?.()|[\]{}]/g, '\\$&')), timeout: 60000 })
  await page.click('button[type=submit], input[type=submit], button#kc-login')
  await navPromise
}

test('realtime: two clients synchronize editor text via yjs-server', async ({ browser, baseURL }) => {
  test.setTimeout(120000)

  const ctxA = await browser.newContext()
  const ctxB = await browser.newContext()
  const pageA = await ctxA.newPage()
  const pageB = await ctxB.newPage()

  // Perform interactive OIDC login in both contexts so frontend has accessToken
  await performOidcLogin(pageA, baseURL!)
  await performOidcLogin(pageB, baseURL!)

  // Navigate both to the editor page
  await pageA.goto(`${baseURL}/editor`)
  await pageB.goto(`${baseURL}/editor`)

  // Enable realtime on both pages
  await pageA.click('text=Enable realtime', { timeout: 5000 })
  await pageB.click('text=Enable realtime', { timeout: 5000 })

  // Wait for provider to connect (UI text indicates connection)
  await pageA.waitForSelector('text=Realtime: connected', { timeout: 15000 })
  await pageB.waitForSelector('text=Realtime: connected', { timeout: 15000 })

  // Focus editor A and type
  await pageA.locator('.cm-editor').click()
  await pageA.keyboard.type('Hello from A')

  // Assert B sees the change
  await expect(pageB.locator('.cm-editor')).toContainText('Hello from A', { timeout: 5000 })

  // Type in B and assert A sees update
  await pageB.locator('.cm-editor').click()
  await pageB.keyboard.type(' — and B')
  await expect(pageA.locator('.cm-editor')).toContainText('Hello from A — and B', { timeout: 5000 })

  await ctxA.close()
  await ctxB.close()
})
