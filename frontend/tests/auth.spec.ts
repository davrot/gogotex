import { test, expect } from '@playwright/test'

const KEYCLOAK = process.env.PLAYWRIGHT_KEYCLOAK || 'http://keycloak-keycloak:8080'
const CLIENT_ID = process.env.PLAYWRIGHT_KC_CLIENT || 'gogotex-backend'
const REALM = process.env.PLAYWRIGHT_KC_REALM || 'gogotex'
const TEST_USER = process.env.TEST_USER || 'testuser'
const TEST_PASS = process.env.TEST_PASS || 'Test123!'

test('auth-code E2E: browser -> Keycloak -> frontend callback -> backend exchange', async ({ page, baseURL }) => {
  const redirectUri = process.env.PLAYWRIGHT_REDIRECT_URI || `${baseURL}/auth/callback`
  const authUrl = `${KEYCLOAK}/realms/${REALM}/protocol/openid-connect/auth?client_id=${CLIENT_ID}&response_type=code&scope=openid&redirect_uri=${encodeURIComponent(
    redirectUri,
  )}`

  let loginResponseBody: any = null
  page.on('response', async (response) => {
    try {
      const req = response.request()
      if (req.method() === 'POST' && req.url().includes('/auth/login')) {
        if (response.status() === 200) {
          loginResponseBody = await response.json()
        }
      }
    } catch (err) {
      // ignore parse errors
    }
  })

  await page.goto(authUrl)
  // wait for Keycloak login form to render (fail fast if missing)
  await page.waitForSelector('input[name="username"]', { timeout: 5000 })
  await page.waitForSelector('input[name="password"]', { timeout: 5000 })
  // DEBUG: capture page URL + small snippet for CI diagnostics
  console.log('DEBUG: landed URL ->', page.url())
  const snippet = (await page.content()).slice(0,200)
  console.log('DEBUG: page content snippet ->', snippet)
  await page.fill('input[name="username"]', TEST_USER)
  await page.fill('input[name="password"]', TEST_PASS)
  await Promise.all([
    page.waitForNavigation({ url: new RegExp(redirectUri.replace(/[-/\\^$*+?.()|[\]{}]/g, '\\$&')) }),
    page.click('button[type=submit], input[type=submit], button#kc-login'),
  ])

  await page.waitForTimeout(500)
  expect(loginResponseBody).not.toBeNull()
  expect(loginResponseBody.accessToken).toBeTruthy()
  expect(loginResponseBody.user).toBeTruthy()
})
