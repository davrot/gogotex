import { test, expect } from '@playwright/test'

const BASE = process.env.PLAYWRIGHT_BASE_URL || 'http://frontend'
const KC = process.env.PLAYWRIGHT_KEYCLOAK || 'http://keycloak-keycloak:8080/sso'
const REDIRECT = process.env.PLAYWRIGHT_REDIRECT_URI || `${BASE}/auth/callback`
const USER = process.env.TEST_USER || 'testuser'
const PASS = process.env.TEST_PASS || 'Test123!'

test('protected /dashboard redirects unauthenticated users to /login', async ({ page }) => {
  // navigate to dashboard (should redirect to login when unauthenticated)
  await page.goto(`${BASE}/dashboard`)
  // expect immediate redirect to login page
  await page.waitForURL('**/login', { timeout: 5000 })
  // login affordance present
  await page.waitForSelector('text=Sign in with Keycloak')
})