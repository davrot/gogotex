import { test } from '@playwright/test'

const BASE = process.env.PLAYWRIGHT_BASE_URL || 'http://frontend'

test('debug /dashboard content', async ({ page }) => {
  await page.goto(`${BASE}/dashboard`, { waitUntil: 'networkidle' })
  console.log('URL', page.url())
  console.log('content snippet', (await page.content()).slice(0,1200))
})
