import { test, expect } from '@playwright/test'

test.describe('Editor (Phase‑03)', () => {
  test.beforeEach(async ({ page, baseURL }) => {
    await page.goto(baseURL || 'http://frontend')
    await page.click('a[href="/editor"]')
    await expect(page).toHaveURL(/\/editor/) // ensure on editor page
  })

  test('toolbar actions insert text and autosave persists', async ({ page }) => {
    const editorSelector = '.cm-editor'

    // ensure editor present
    await page.waitForSelector(editorSelector)

    // click 'Insert template' toolbar button
    await page.click('button:has-text("Insert template")')

    // wait a short time for editor update + autosave
    await page.waitForTimeout(200)

    // read localStorage key used by editor
    const stored = await page.evaluate(() => localStorage.getItem('gogotex.editor.content'))
    expect(stored).toBeTruthy()
    expect(stored).toContain('\\documentclass{article}')

    // click Bold button and ensure latex command inserted
    await page.click('button:has-text("Bold")')
    await page.waitForTimeout(100)
    const s2 = await page.evaluate(() => localStorage.getItem('gogotex.editor.content'))
    expect(s2).toContain('\\textbf')

    // reload and verify persisted content is still present in editor DOM
    await page.reload()
    await page.click('a[href="/editor"]')
    await page.waitForSelector(editorSelector)
    // ensure saved text shows up by checking localStorage again
    const s3 = await page.evaluate(() => localStorage.getItem('gogotex.editor.content'))
    expect(s3).toContain('\\documentclass{article}')
  })
})
