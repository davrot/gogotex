import { test, expect } from '@playwright/test'

const BASE = process.env.PLAYWRIGHT_BASE_URL || 'http://frontend'
const KC = process.env.PLAYWRIGHT_KEYCLOAK || 'http://keycloak-keycloak:8080/sso'
const REDIRECT = process.env.PLAYWRIGHT_REDIRECT_URI || `${BASE}/auth/callback`
const USER = process.env.TEST_USER || 'testuser'
const PASS = process.env.TEST_PASS || 'Test123!'

test('login -> dashboard (protected route) flows', async ({ page }) => {
  // navigate to dashboard (should redirect to login when unauthenticated)
  await page.goto(`${BASE}/dashboard`)
  // if not authenticated, we expect to see login link
  await page.waitForSelector('a[href="/login"]')

  // perform Keycloak login flow
  const authUrl = `${KC}/realms/gogotex/protocol/openid-connect/auth?client_id=gogotex-backend&response_type=code&redirect_uri=${encodeURIComponent(REDIRECT)}`
  await page.goto(authUrl)
  await page.fill('input[name="username"]', USER)
  await page.fill('input[name="password"]', PASS)
  await Promise.all([
    page.waitForNavigation({ url: new RegExp(REDIRECT.replace(/[-/\\^$*+?.()|[\]{}]/g, '\\$&')) }),
    page.click('button[type=submit], input[type=submit], button#kc-login')
  ])

  // after callback the frontend should redirect back to dashboard and show user info
  await page.goto(`${BASE}/dashboard`)
  await page.waitForSelector('text=Welcome,')
  const txt = await page.textContent('h3')
  expect(txt).toContain('Welcome')
})