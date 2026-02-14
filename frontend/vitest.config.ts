import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    environment: 'jsdom',
    include: ['src/**/*.test.{js,ts,jsx,tsx}', 'src/**/*.spec.{js,ts,jsx,tsx}'],
    setupFiles: 'test/setupTests.ts',
  },
})
