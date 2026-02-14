// Vitest setup: add DOM matchers from Testing Library
import { expect } from 'vitest'
import * as matchers from '@testing-library/jest-dom/matchers'

// extends Vitest expect with testing-library matchers
expect.extend(matchers as any)
