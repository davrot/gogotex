import { test, expect } from '@playwright/test'

// Test does an end-to-end browser flow against Keycloak + frontend + backend.
// Expectations:
// - Keycloak is reachable at PLAYWRIGHT_KEYCLOAK (or http://keycloak-keycloak:8080)
// - Frontend is reachable at PLAYWRIGHT_BASE_URL (default http://localhost:3000 or http://frontend when run inside docker network)
// - Redirect URI used will be PLAYWRIGHT_REDIRECT_URI or `${baseURL}/auth/callback`
// - TEST_USER and TEST_PASS must be provided via env

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

  // Intercept the POST to /auth/login so we can verify backend response body
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

  // Start at the Keycloak auth endpoint (simulate clicking the Sign-in link)
  await page.goto(authUrl)
  // Fill Keycloak login form
  await page.fill('input[name="username"]', TEST_USER)
  await page.fill('input[name="password"]', TEST_PASS)
  // Submit login form (Keycloak uses button#kc-login or button[type=submit])
  await Promise.all([
    page.waitForNavigation({ url: new RegExp(redirectUri.replace(/[-/\\^$*+?.()|[\]{}]/g, '\\$&')) }),
    page.click('button[type=submit], input[type=submit], button#kc-login'),
  ])

  // After redirect the frontend should POST the code to /auth/login — wait for that response
  await page.waitForTimeout(500) // brief pause to let callback handler run
  expect(loginResponseBody).not.toBeNull()
  expect(loginResponseBody.accessToken).toBeTruthy()
  expect(loginResponseBody.user).toBeTruthy()
})
