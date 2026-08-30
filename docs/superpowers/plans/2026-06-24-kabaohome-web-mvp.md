# kabaohome.fun Web MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first production-ready `kabaohome.fun` website and web family workspace that interoperates with the HarmonyOS app data.

**Architecture:** Add a separate `web/` Next.js app as the public site and Web BFF. The browser never talks to AGC Cloud DB directly; Next.js API routes validate session, sanitize inputs, enforce CSRF/session rules, and call AGC Cloud Functions. Cloud Functions remain the only data write and record-level permission enforcement layer.

**Tech Stack:** Next.js App Router, TypeScript, Tailwind CSS, Vitest, Playwright, AGC Cloud Functions, AGC Cloud DB, HttpOnly/Secure/SameSite=Strict cookies.

---

## Scope and Decomposition

The approved spec spans several subsystems. Implement them in this order so each phase produces working, testable software:

1. Web foundation and shared domain types.
2. Security/session primitives and BFF response contract.
3. Cloud Function permission hardening used by both app and web.
4. Public landing page and login UI.
5. Auth BFF endpoints and protected workspace shell.
6. Dashboard and read-only data loading.
7. CRUD modules: reminders, shopping child view, memos, kids, accounting.
8. Members/modules management.
9. E2E, security verification, production deployment checklist.

Shopping is deliberately split by concern:

- **UI/module placement:** shopping appears inside the Reminder page as a tab/subview.
- **Data model:** shopping remains `ShoppingItem` / `shopping_items` / Cloud DB ShoppingItem so the HarmonyOS app can continue syncing it.

## File Structure

### Web app files to create

- `web/package.json` — scripts and dependencies.
- `web/tsconfig.json` — strict TypeScript config.
- `web/next.config.mjs` — security headers and Next.js config.
- `web/postcss.config.mjs` — Tailwind PostCSS config.
- `web/tailwind.config.ts` — warm minimalist design tokens.
- `web/vitest.config.ts` — unit test runner config.
- `web/playwright.config.ts` — E2E runner config.
- `web/src/app/layout.tsx` — root metadata, global shell.
- `web/src/app/page.tsx` — public landing page.
- `web/src/app/login/page.tsx` — phone-code login UI.
- `web/src/app/workspace/layout.tsx` — protected app frame.
- `web/src/app/workspace/page.tsx` — dashboard.
- `web/src/app/workspace/reminders/page.tsx` — reminders page with shopping tab.
- `web/src/app/workspace/memos/page.tsx` — memos page.
- `web/src/app/workspace/kids/page.tsx` — kids page.
- `web/src/app/workspace/accounting/page.tsx` — accounting page.
- `web/src/app/workspace/settings/page.tsx` — members and modules page.
- `web/src/app/api/auth/send-code/route.ts` — send phone code BFF endpoint.
- `web/src/app/api/auth/verify-code/route.ts` — verify phone code BFF endpoint.
- `web/src/app/api/auth/logout/route.ts` — session revoke endpoint.
- `web/src/app/api/dashboard/route.ts` — dashboard BFF endpoint.
- `web/src/app/api/reminders/route.ts` — reminders list/create endpoint.
- `web/src/app/api/reminders/[id]/route.ts` — reminders update/delete endpoint.
- `web/src/app/api/shopping-items/route.ts` — ShoppingItem list/create data endpoint.
- `web/src/app/api/shopping-items/[id]/route.ts` — ShoppingItem update/delete data endpoint.
- `web/src/app/api/memos/route.ts` — memo list/create endpoint.
- `web/src/app/api/memos/[id]/route.ts` — memo update/delete endpoint.
- `web/src/app/api/kid-events/route.ts` — kid event list/create endpoint.
- `web/src/app/api/kid-events/[id]/route.ts` — kid event update/delete endpoint.
- `web/src/app/api/accounting-records/route.ts` — accounting list/create endpoint.
- `web/src/app/api/accounting-records/[id]/route.ts` — accounting update/delete endpoint.
- `web/src/app/api/family-members/route.ts` — member list endpoint.
- `web/src/app/api/modules/route.ts` — module visibility update endpoint.
- `web/src/components/ui/Button.tsx` — shared button.
- `web/src/components/ui/Card.tsx` — shared card.
- `web/src/components/ui/EmptyState.tsx` — empty state.
- `web/src/components/ui/Field.tsx` — input field.
- `web/src/components/layout/AppShell.tsx` — workspace navigation and responsive shell.
- `web/src/components/layout/PublicHeader.tsx` — marketing header.
- `web/src/features/auth/LoginForm.tsx` — phone login form.
- `web/src/features/dashboard/DashboardCards.tsx` — dashboard cards.
- `web/src/features/reminders/ReminderList.tsx` — reminder list.
- `web/src/features/reminders/ShoppingSubview.tsx` — shopping tab using ShoppingItem data.
- `web/src/features/memos/MemoList.tsx` — memo list.
- `web/src/features/kids/KidEventList.tsx` — kid event list.
- `web/src/features/accounting/AccountingSummary.tsx` — accounting summary.
- `web/src/features/settings/MemberModuleSettings.tsx` — member/module settings.
- `web/src/lib/api/response.ts` — API response envelope and status helpers.
- `web/src/lib/api/client.ts` — browser-side API client.
- `web/src/lib/auth/session.ts` — session cookie encode/decode helpers.
- `web/src/lib/auth/csrf.ts` — CSRF token helpers.
- `web/src/lib/auth/rate-limit.ts` — in-memory dev limiter interface and production adapter seam.
- `web/src/lib/agc/cloudFunctionClient.ts` — server-only Cloud Function client.
- `web/src/lib/validation/schemas.ts` — runtime request validators.
- `web/src/lib/permissions/visibility.ts` — shared visibility checks for tests and UI hints.
- `web/src/types/domain.ts` — Web TypeScript mirror of ArkTS models.
- `web/src/styles/globals.css` — design tokens and global CSS.
- `web/tests/unit/response.test.ts` — response envelope tests.
- `web/tests/unit/visibility.test.ts` — visibility rules tests.
- `web/tests/unit/auth-security.test.ts` — OTP and CSRF tests.
- `web/tests/unit/model-mapping.test.ts` — domain model mapping tests.
- `web/tests/e2e/landing-login.spec.ts` — landing and login flow.
- `web/tests/e2e/workspace.spec.ts` — protected workspace flow.

### Cloud files to modify or create

- Modify `cloud/shared/response.js` — align response envelope and status behavior.
- Modify `cloud/shared/auth.js` — remove placeholder auth fallback for production and require verified identity.
- Create `cloud/shared/visibility.js` — record-level visibility filter.
- Create `cloud/shared/validators.js` — shared input validation helpers.
- Modify `cloud/pull-data/index.js` — filter records by visibility before returning.
- Modify `cloud/push-data/index.js` — validate family membership, creator, visibility, version, and table allowlist.
- Modify `cloud/merge-conflict/index.js` — ensure conflict merge checks visibility and version.
- Create `cloud/tests/visibility.test.js` — cloud visibility tests.
- Create `cloud/tests/auth.test.js` — cloud auth tests.

### Existing app files to reference only unless a test exposes drift

- `entry/src/main/ets/viewmodel/ModuleManager.ets` — `SHOPPING` is unavailable and merged into reminders in UI.
- `entry/src/main/ets/model/ShoppingItem.ets` — source model for Web `ShoppingItem` type.
- `entry/src/main/ets/model/Reminder.ets` — source model for Web `Reminder` type.
- `entry/src/main/ets/service/LocalDbService.ets` — local storage names and filtering behavior.
- `docs/privacy-policy.md` — update in a later implementation task if deployment actually introduces Web data processing.

---

## Task 1: Create Web Project Skeleton

**Files:**
- Create: `web/package.json`
- Create: `web/tsconfig.json`
- Create: `web/next.config.mjs`
- Create: `web/postcss.config.mjs`
- Create: `web/tailwind.config.ts`
- Create: `web/vitest.config.ts`
- Create: `web/playwright.config.ts`
- Create: `web/src/styles/globals.css`
- Create: `web/src/app/layout.tsx`
- Create: `web/src/app/page.tsx`

- [ ] **Step 1: Create the package manifest**

Write `web/package.json`:

```json
{
  "name": "kabaohome-web",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint",
    "typecheck": "tsc --noEmit",
    "test": "vitest run",
    "test:watch": "vitest",
    "e2e": "playwright test"
  },
  "dependencies": {
    "@vitejs/plugin-react": "latest",
    "clsx": "latest",
    "next": "latest",
    "react": "latest",
    "react-dom": "latest",
    "zod": "latest"
  },
  "devDependencies": {
    "@playwright/test": "latest",
    "@testing-library/jest-dom": "latest",
    "@testing-library/react": "latest",
    "@types/node": "latest",
    "@types/react": "latest",
    "@types/react-dom": "latest",
    "autoprefixer": "latest",
    "eslint": "latest",
    "eslint-config-next": "latest",
    "jsdom": "latest",
    "postcss": "latest",
    "tailwindcss": "latest",
    "typescript": "latest",
    "vitest": "latest"
  }
}
```

- [ ] **Step 2: Create TypeScript config**

Write `web/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["dom", "dom.iterable", "es2022"],
    "allowJs": false,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "baseUrl": ".",
    "paths": {
      "@/*": ["src/*"]
    }
  },
  "include": ["next-env.d.ts", "src/**/*.ts", "src/**/*.tsx", "tests/**/*.ts", "tests/**/*.tsx"],
  "exclude": ["node_modules"]
}
```

- [ ] **Step 3: Create Next config with security headers**

Write `web/next.config.mjs`:

```js
const securityHeaders = [
  { key: 'Strict-Transport-Security', value: 'max-age=31536000; includeSubDomains; preload' },
  { key: 'X-Content-Type-Options', value: 'nosniff' },
  { key: 'X-Frame-Options', value: 'DENY' },
  { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
  { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=()' },
  {
    key: 'Content-Security-Policy',
    value: [
      "default-src 'self'",
      "script-src 'self' 'unsafe-inline' 'unsafe-eval'",
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' data: https:",
      "font-src 'self' data:",
      "connect-src 'self'",
      "frame-ancestors 'none'",
      "base-uri 'self'",
      "form-action 'self'"
    ].join('; ')
  }
]

/** @type {import('next').NextConfig} */
const nextConfig = {
  async headers() {
    return [
      {
        source: '/(.*)',
        headers: securityHeaders
      }
    ]
  }
}

export default nextConfig
```

- [ ] **Step 4: Create Tailwind and PostCSS config**

Write `web/postcss.config.mjs`:

```js
export default {
  plugins: {
    tailwindcss: {},
    autoprefixer: {}
  }
}
```

Write `web/tailwind.config.ts`:

```ts
import type { Config } from 'tailwindcss'

const config: Config = {
  content: ['./src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        cream: '#FFF7ED',
        linen: '#FAF3EA',
        coral: '#F9735B',
        peach: '#FFD9C8',
        sage: '#7DA27E',
        ink: '#3F2B1D',
        muted: '#7C5B45'
      },
      boxShadow: {
        warm: '0 18px 50px rgba(124, 91, 69, 0.14)'
      },
      borderRadius: {
        card: '24px'
      }
    }
  },
  plugins: []
}

export default config
```

- [ ] **Step 5: Create test configs**

Write `web/vitest.config.ts`:

```ts
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    include: ['tests/unit/**/*.test.ts', 'tests/unit/**/*.test.tsx']
  },
  resolve: {
    alias: {
      '@': new URL('./src', import.meta.url).pathname
    }
  }
})
```

Write `web/playwright.config.ts`:

```ts
import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  use: {
    baseURL: 'http://127.0.0.1:3000',
    trace: 'on-first-retry'
  },
  webServer: {
    command: 'npm run dev',
    url: 'http://127.0.0.1:3000',
    reuseExistingServer: true,
    timeout: 120_000
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'mobile', use: { ...devices['Pixel 5'] } }
  ]
})
```

- [ ] **Step 6: Create global styles and root layout**

Write `web/src/styles/globals.css`:

```css
@tailwind base;
@tailwind components;
@tailwind utilities;

:root {
  color-scheme: light;
  --background: #fff7ed;
  --surface: #fffaf5;
  --text: #3f2b1d;
  --muted: #7c5b45;
}

* {
  box-sizing: border-box;
}

html {
  min-height: 100%;
  background: var(--background);
}

body {
  min-height: 100%;
  margin: 0;
  background:
    radial-gradient(circle at top left, rgba(255, 217, 200, 0.75), transparent 34rem),
    linear-gradient(180deg, #fff7ed 0%, #fffaf5 52%, #faf3ea 100%);
  color: var(--text);
  font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
}

a {
  color: inherit;
  text-decoration: none;
}

button,
input,
textarea,
select {
  font: inherit;
}
```

Write `web/src/app/layout.tsx`:

```tsx
import type { Metadata } from 'next'
import '@/styles/globals.css'

export const metadata: Metadata = {
  title: '卡宝Home - 把家的小事稳稳接住',
  description: '卡宝Home 网页版家庭工作台，支持提醒、购物、备忘、孩子事项和家庭记账。'
}

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="zh-CN">
      <body>{children}</body>
    </html>
  )
}
```

- [ ] **Step 7: Create a minimal landing page**

Write `web/src/app/page.tsx`:

```tsx
export default function HomePage() {
  return (
    <main className="mx-auto flex min-h-screen max-w-6xl flex-col px-6 py-8">
      <nav className="flex items-center justify-between">
        <div className="text-xl font-bold text-ink">卡宝Home</div>
        <a className="rounded-full bg-ink px-5 py-2 text-sm font-semibold text-white" href="/login">
          进入家庭
        </a>
      </nav>

      <section className="grid flex-1 items-center gap-10 py-16 md:grid-cols-[1.1fr_0.9fr]">
        <div>
          <p className="mb-4 text-sm font-semibold tracking-[0.2em] text-coral">KABAOHOME.FUN</p>
          <h1 className="text-5xl font-black leading-tight text-ink md:text-7xl">把家的小事，稳稳接住</h1>
          <p className="mt-6 max-w-xl text-lg leading-8 text-muted">
            提醒、购物、备忘、孩子事项和家庭记账，与家人同步管理。网页版与 APP 使用同一份家庭数据。
          </p>
          <div className="mt-8 flex gap-3">
            <a className="rounded-full bg-coral px-6 py-3 font-bold text-white shadow-warm" href="/login">
              手机号登录
            </a>
            <a className="rounded-full border border-peach bg-white/60 px-6 py-3 font-bold text-ink" href="#security">
              了解隐私安全
            </a>
          </div>
        </div>

        <div className="rounded-card border border-white/80 bg-white/70 p-6 shadow-warm backdrop-blur">
          <div className="mb-4 flex items-center justify-between">
            <span className="font-bold">今日家庭总览</span>
            <span className="rounded-full bg-cream px-3 py-1 text-sm text-muted">同步中</span>
          </div>
          <div className="grid gap-3">
            {['晚饭后吃药提醒', '购物：牛奶和鸡蛋', '孩子事项：周五家长会', '本月支出：¥3,280'].map((item) => (
              <div key={item} className="rounded-2xl bg-cream px-4 py-3 text-sm font-medium text-ink">
                {item}
              </div>
            ))}
          </div>
        </div>
      </section>
    </main>
  )
}
```

- [ ] **Step 8: Install dependencies**

Run:

```bash
cd /c/Users/Andy/kabao/web && npm install
```

Expected: dependencies install and `package-lock.json` is created.

- [ ] **Step 9: Run typecheck and build**

Run:

```bash
cd /c/Users/Andy/kabao/web && npm run typecheck && npm run build
```

Expected: both commands complete successfully.

- [ ] **Step 10: Commit**

```bash
git add web
git commit -m "feat: scaffold kabaohome web app"
```

---

## Task 2: Define Domain Types and Visibility Rules

**Files:**
- Create: `web/src/types/domain.ts`
- Create: `web/src/lib/permissions/visibility.ts`
- Create: `web/tests/unit/visibility.test.ts`
- Create: `web/tests/unit/model-mapping.test.ts`

- [ ] **Step 1: Write failing visibility tests**

Write `web/tests/unit/visibility.test.ts`:

```ts
import { describe, expect, test } from 'vitest'
import { canReadRecord, filterVisibleRecords } from '@/lib/permissions/visibility'
import type { BaseRecord } from '@/types/domain'

function record(overrides: Partial<BaseRecord>): BaseRecord {
  return {
    id: 'rec_1',
    familyId: 'fam_1',
    creatorId: 'usr_owner',
    visibility: 'FAMILY',
    visibleMembers: [],
    version: 1,
    createdAt: '2026-06-24T00:00:00.000Z',
    updatedAt: '2026-06-24T00:00:00.000Z',
    ...overrides
  }
}

describe('visibility permissions', () => {
  test('allows creator to read private record', () => {
    expect(canReadRecord(record({ visibility: 'PRIVATE' }), 'usr_owner')).toBe(true)
  })

  test('blocks non-creator from private record', () => {
    expect(canReadRecord(record({ visibility: 'PRIVATE' }), 'usr_other')).toBe(false)
  })

  test('allows selected visible member', () => {
    expect(canReadRecord(record({ visibility: 'SELECTED', visibleMembers: ['usr_other'] }), 'usr_other')).toBe(true)
  })

  test('blocks unselected member', () => {
    expect(canReadRecord(record({ visibility: 'SELECTED', visibleMembers: ['usr_a'] }), 'usr_other')).toBe(false)
  })

  test('allows family record for any family member after family membership is checked by server', () => {
    expect(canReadRecord(record({ visibility: 'FAMILY' }), 'usr_other')).toBe(true)
  })

  test('filters mixed records', () => {
    const records = [
      record({ id: 'private_owner', visibility: 'PRIVATE', creatorId: 'usr_owner' }),
      record({ id: 'private_other', visibility: 'PRIVATE', creatorId: 'usr_other' }),
      record({ id: 'selected', visibility: 'SELECTED', visibleMembers: ['usr_owner'] }),
      record({ id: 'family', visibility: 'FAMILY' })
    ]

    expect(filterVisibleRecords(records, 'usr_owner').map((item) => item.id)).toEqual([
      'private_owner',
      'selected',
      'family'
    ])
  })
})
```

- [ ] **Step 2: Write failing model mapping tests**

Write `web/tests/unit/model-mapping.test.ts`:

```ts
import { describe, expect, test } from 'vitest'
import type { ShoppingItem } from '@/types/domain'

describe('ShoppingItem model', () => {
  test('keeps shopping as independent data model even when UI lives under reminders', () => {
    const item: ShoppingItem = {
      id: 'si_1',
      familyId: 'fam_1',
      creatorId: 'usr_1',
      visibility: 'FAMILY',
      visibleMembers: [],
      version: 1,
      createdAt: '2026-06-24T00:00:00.000Z',
      updatedAt: '2026-06-24T00:00:00.000Z',
      itemName: '牛奶',
      category: '食品',
      quantity: '2盒',
      note: '低脂',
      isPurchased: false,
      purchasedBy: '',
      purchasedAt: ''
    }

    expect(item.itemName).toBe('牛奶')
    expect('title' in item).toBe(false)
  })
})
```

- [ ] **Step 3: Run tests to verify failure**

Run:

```bash
cd /c/Users/Andy/kabao/web && npm test -- visibility.test.ts model-mapping.test.ts
```

Expected: FAIL because `@/types/domain` and `@/lib/permissions/visibility` do not exist.

- [ ] **Step 4: Implement domain types**

Write `web/src/types/domain.ts`:

```ts
export type Visibility = 'PRIVATE' | 'SELECTED' | 'FAMILY'

export interface BaseRecord {
  id: string
  familyId: string
  creatorId: string
  visibility: Visibility
  visibleMembers: string[]
  version: number
  createdAt: string
  updatedAt: string
}

export interface Family {
  id: string
  name: string
  ownerId: string
  createdAt: string
  updatedAt: string
}

export interface FamilyMember {
  id: string
  familyId: string
  userId: string
  name: string
  phone: string
  role: 'owner' | 'admin' | 'member'
  avatarColor: string
  enabledModules: string[]
}

export interface Reminder extends BaseRecord {
  title: string
  description: string
  reminderAt: string
  isCompleted: boolean
  completedBy: string
  completedAt: string
}

export interface ShoppingItem extends BaseRecord {
  itemName: string
  category: string
  quantity: string
  note: string
  isPurchased: boolean
  purchasedBy: string
  purchasedAt: string
}

export interface Memo extends BaseRecord {
  title: string
  content: string
  isEncrypted: boolean
}

export interface KidEvent extends BaseRecord {
  title: string
  childName: string
  eventType: string
  eventAt: string
  isCompleted: boolean
  note: string
}

export interface AccountingRecord extends BaseRecord {
  amount: number
  direction: 'income' | 'expense'
  category: string
  note: string
  occurredAt: string
}

export interface DashboardData {
  family: Family
  members: FamilyMember[]
  todayReminders: Reminder[]
  pendingShoppingItems: ShoppingItem[]
  recentMemos: Memo[]
  kidEvents: KidEvent[]
  accountingMonthTotal: {
    income: number
    expense: number
    balance: number
  }
}
```

- [ ] **Step 5: Implement visibility helpers**

Write `web/src/lib/permissions/visibility.ts`:

```ts
import type { BaseRecord } from '@/types/domain'

export function canReadRecord(record: BaseRecord, userId: string): boolean {
  if (!userId) return false
  if (record.creatorId === userId) return true

  if (record.visibility === 'PRIVATE') return false
  if (record.visibility === 'SELECTED') return record.visibleMembers.includes(userId)
  if (record.visibility === 'FAMILY') return true

  return false
}

export function filterVisibleRecords<T extends BaseRecord>(records: T[], userId: string): T[] {
  return records.filter((record) => canReadRecord(record, userId))
}
```

- [ ] **Step 6: Run tests and typecheck**

Run:

```bash
cd /c/Users/Andy/kabao/web && npm test -- visibility.test.ts model-mapping.test.ts && npm run typecheck
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add web/src/types/domain.ts web/src/lib/permissions/visibility.ts web/tests/unit/visibility.test.ts web/tests/unit/model-mapping.test.ts
git commit -m "feat: add web domain types and visibility rules"
```

---

## Task 3: Add API Response, Validation, Session, CSRF, and BFF Client Primitives

**Files:**
- Create: `web/src/lib/api/response.ts`
- Create: `web/src/lib/auth/session.ts`
- Create: `web/src/lib/auth/csrf.ts`
- Create: `web/src/lib/auth/rate-limit.ts`
- Create: `web/src/lib/validation/schemas.ts`
- Create: `web/src/lib/agc/cloudFunctionClient.ts`
- Create: `web/tests/unit/response.test.ts`
- Create: `web/tests/unit/auth-security.test.ts`

- [ ] **Step 1: Write failing response tests**

Write `web/tests/unit/response.test.ts`:

```ts
import { describe, expect, test } from 'vitest'
import { apiError, apiSuccess } from '@/lib/api/response'

describe('api response envelope', () => {
  test('success response includes envelope', async () => {
    const response = apiSuccess({ ok: true }, { status: 201 })
    expect(response.status).toBe(201)
    await expect(response.json()).resolves.toEqual({
      success: true,
      data: { ok: true },
      error: null,
      metadata: null
    })
  })

  test('error response hides technical details', async () => {
    const response = apiError(403, '该内容未共享给你')
    expect(response.status).toBe(403)
    await expect(response.json()).resolves.toEqual({
      success: false,
      data: null,
      error: { message: '该内容未共享给你' },
      metadata: null
    })
  })
})
```

- [ ] **Step 2: Write failing auth security tests**

Write `web/tests/unit/auth-security.test.ts`:

```ts
import { describe, expect, test } from 'vitest'
import { createCsrfToken, verifyCsrfToken } from '@/lib/auth/csrf'
import { createSessionCookie, SESSION_COOKIE_NAME } from '@/lib/auth/session'
import { createFixedWindowLimiter } from '@/lib/auth/rate-limit'

describe('auth security primitives', () => {
  test('csrf token verifies only exact token pair', async () => {
    const secret = 'session_secret'
    const token = await createCsrfToken(secret)

    await expect(verifyCsrfToken(secret, token)).resolves.toBe(true)
    await expect(verifyCsrfToken('other_secret', token)).resolves.toBe(false)
  })

  test('session cookie is httpOnly secure strict', () => {
    const cookie = createSessionCookie('signed-session', 3600)

    expect(cookie.name).toBe(SESSION_COOKIE_NAME)
    expect(cookie.value).toBe('signed-session')
    expect(cookie.httpOnly).toBe(true)
    expect(cookie.secure).toBe(true)
    expect(cookie.sameSite).toBe('strict')
    expect(cookie.path).toBe('/')
    expect(cookie.maxAge).toBe(3600)
  })

  test('fixed window limiter blocks after limit', () => {
    const limiter = createFixedWindowLimiter({ limit: 2, windowMs: 60_000 })

    expect(limiter.consume('phone:13800138000')).toEqual({ allowed: true, remaining: 1 })
    expect(limiter.consume('phone:13800138000')).toEqual({ allowed: true, remaining: 0 })
    expect(limiter.consume('phone:13800138000')).toEqual({ allowed: false, remaining: 0 })
  })
})
```

- [ ] **Step 3: Run tests to verify failure**

Run:

```bash
cd /c/Users/Andy/kabao/web && npm test -- response.test.ts auth-security.test.ts
```

Expected: FAIL because primitives do not exist.

- [ ] **Step 4: Implement API response helpers**

Write `web/src/lib/api/response.ts`:

```ts
import { NextResponse } from 'next/server'

type ApiMetadata = Record<string, unknown> | null

export function apiSuccess<T>(data: T, init: { status?: number; metadata?: ApiMetadata } = {}) {
  return NextResponse.json(
    {
      success: true,
      data,
      error: null,
      metadata: init.metadata ?? null
    },
    { status: init.status ?? 200 }
  )
}

export function apiError(status: number, message: string, metadata: ApiMetadata = null) {
  return NextResponse.json(
    {
      success: false,
      data: null,
      error: { message },
      metadata
    },
    { status }
  )
}
```

- [ ] **Step 5: Implement session helpers**

Write `web/src/lib/auth/session.ts`:

```ts
import type { ResponseCookie } from 'next/dist/compiled/@edge-runtime/cookies'

export const SESSION_COOKIE_NAME = 'kabaohome_session'
export const CSRF_COOKIE_NAME = 'kabaohome_csrf'

export interface WebSession {
  userId: string
  phone: string
  familyId: string
  expiresAt: number
}

export function createSessionCookie(value: string, maxAgeSeconds: number): ResponseCookie {
  return {
    name: SESSION_COOKIE_NAME,
    value,
    httpOnly: true,
    secure: true,
    sameSite: 'strict',
    path: '/',
    maxAge: maxAgeSeconds
  }
}

export function createExpiredSessionCookie(): ResponseCookie {
  return {
    name: SESSION_COOKIE_NAME,
    value: '',
    httpOnly: true,
    secure: true,
    sameSite: 'strict',
    path: '/',
    maxAge: 0
  }
}
```

- [ ] **Step 6: Implement CSRF helpers**

Write `web/src/lib/auth/csrf.ts`:

```ts
async function sha256(input: string): Promise<string> {
  const data = new TextEncoder().encode(input)
  const digest = await crypto.subtle.digest('SHA-256', data)
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('')
}

export async function createCsrfToken(sessionSecret: string): Promise<string> {
  return sha256(`kabaohome:${sessionSecret}`)
}

export async function verifyCsrfToken(sessionSecret: string, token: string): Promise<boolean> {
  const expected = await createCsrfToken(sessionSecret)
  return token.length === expected.length && token === expected
}
```

- [ ] **Step 7: Implement fixed window limiter**

Write `web/src/lib/auth/rate-limit.ts`:

```ts
interface LimiterOptions {
  limit: number
  windowMs: number
}

interface LimiterResult {
  allowed: boolean
  remaining: number
}

export function createFixedWindowLimiter(options: LimiterOptions) {
  const buckets = new Map<string, { count: number; resetAt: number }>()

  return {
    consume(key: string, now: number = Date.now()): LimiterResult {
      const existing = buckets.get(key)
      const bucket = !existing || existing.resetAt <= now
        ? { count: 0, resetAt: now + options.windowMs }
        : existing

      if (bucket.count >= options.limit) {
        buckets.set(key, bucket)
        return { allowed: false, remaining: 0 }
      }

      const next = { count: bucket.count + 1, resetAt: bucket.resetAt }
      buckets.set(key, next)
      return { allowed: true, remaining: Math.max(0, options.limit - next.count) }
    }
  }
}
```

- [ ] **Step 8: Implement validation schemas**

Write `web/src/lib/validation/schemas.ts`:

```ts
import { z } from 'zod'

export const phoneSchema = z.string().regex(/^1[3-9]\d{9}$/, '请输入有效手机号')
export const codeSchema = z.string().regex(/^\d{6}$/, '请输入 6 位验证码')
export const idSchema = z.string().min(2).max(80)

export const sendCodeSchema = z.object({
  phone: phoneSchema
})

export const verifyCodeSchema = z.object({
  phone: phoneSchema,
  code: codeSchema
})

export const visibilitySchema = z.enum(['PRIVATE', 'SELECTED', 'FAMILY'])

export const baseWriteSchema = z.object({
  id: idSchema.optional(),
  visibility: visibilitySchema,
  visibleMembers: z.array(z.string()).default([]),
  version: z.number().int().nonnegative().optional()
})
```

- [ ] **Step 9: Implement Cloud Function client seam**

Write `web/src/lib/agc/cloudFunctionClient.ts`:

```ts
interface CloudFunctionRequest {
  name: string
  payload: Record<string, unknown>
  sessionToken: string
}

export interface CloudFunctionClient {
  call<T>(request: CloudFunctionRequest): Promise<T>
}

export function createCloudFunctionClient(endpoint: string, serviceToken: string): CloudFunctionClient {
  return {
    async call<T>(request: CloudFunctionRequest): Promise<T> {
      const response = await fetch(`${endpoint}/${request.name}`, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          authorization: `Bearer ${serviceToken}`,
          'x-kabaohome-session': request.sessionToken
        },
        body: JSON.stringify(request.payload)
      })

      if (!response.ok) {
        throw new Error(`Cloud Function ${request.name} failed with ${response.status}`)
      }

      return (await response.json()) as T
    }
  }
}
```

- [ ] **Step 10: Run tests and typecheck**

Run:

```bash
cd /c/Users/Andy/kabao/web && npm test -- response.test.ts auth-security.test.ts && npm run typecheck
```

Expected: PASS.

- [ ] **Step 11: Commit**

```bash
git add web/src/lib web/tests/unit/response.test.ts web/tests/unit/auth-security.test.ts
git commit -m "feat: add web api security primitives"
```

---

## Task 4: Harden Cloud Function Visibility and Auth Boundaries

**Files:**
- Create: `cloud/shared/visibility.js`
- Create: `cloud/shared/validators.js`
- Create: `cloud/tests/visibility.test.js`
- Modify: `cloud/shared/auth.js`
- Modify: `cloud/shared/response.js`
- Modify: `cloud/pull-data/index.js`
- Modify: `cloud/push-data/index.js`

- [ ] **Step 1: Write cloud visibility tests**

Write `cloud/tests/visibility.test.js`:

```js
const assert = require('node:assert/strict')
const { canReadRecord, filterVisibleRecords, assertCanWriteRecord } = require('../shared/visibility')

function record(overrides = {}) {
  return {
    id: 'rec_1',
    familyId: 'fam_1',
    creatorId: 'usr_owner',
    visibility: 'FAMILY',
    visibleMembers: [],
    version: 1,
    ...overrides
  }
}

assert.equal(canReadRecord(record({ visibility: 'PRIVATE' }), 'usr_owner'), true)
assert.equal(canReadRecord(record({ visibility: 'PRIVATE' }), 'usr_other'), false)
assert.equal(canReadRecord(record({ visibility: 'SELECTED', visibleMembers: ['usr_other'] }), 'usr_other'), true)
assert.equal(canReadRecord(record({ visibility: 'SELECTED', visibleMembers: ['usr_a'] }), 'usr_other'), false)
assert.deepEqual(
  filterVisibleRecords([
    record({ id: 'family', visibility: 'FAMILY' }),
    record({ id: 'private_other', visibility: 'PRIVATE', creatorId: 'usr_other' })
  ], 'usr_owner').map((item) => item.id),
  ['family']
)
assert.doesNotThrow(() => assertCanWriteRecord(record({ creatorId: 'usr_owner' }), { userId: 'usr_owner', role: 'member' }))
assert.doesNotThrow(() => assertCanWriteRecord(record({ creatorId: 'usr_other' }), { userId: 'usr_admin', role: 'admin' }))
assert.throws(() => assertCanWriteRecord(record({ creatorId: 'usr_other' }), { userId: 'usr_member', role: 'member' }), /No write permission/)

console.log('cloud visibility tests passed')
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd /c/Users/Andy/kabao && node cloud/tests/visibility.test.js
```

Expected: FAIL because `cloud/shared/visibility.js` does not exist.

- [ ] **Step 3: Implement visibility module**

Write `cloud/shared/visibility.js`:

```js
function canReadRecord(record, userId) {
  if (!record || !userId) return false
  if (record.creatorId === userId) return true

  if (record.visibility === 'PRIVATE') return false
  if (record.visibility === 'SELECTED') return Array.isArray(record.visibleMembers) && record.visibleMembers.includes(userId)
  if (record.visibility === 'FAMILY') return true

  return false
}

function filterVisibleRecords(records, userId) {
  return records.filter((record) => canReadRecord(record, userId))
}

function assertCanWriteRecord(record, member) {
  if (!record || !member) throw new Error('No write permission')
  if (record.creatorId === member.userId) return
  if (member.role === 'owner' || member.role === 'admin') return
  throw new Error('No write permission')
}

module.exports = {
  canReadRecord,
  filterVisibleRecords,
  assertCanWriteRecord
}
```

- [ ] **Step 4: Implement validators**

Write `cloud/shared/validators.js`:

```js
const ALLOWED_TABLES = new Set([
  'families',
  'family_members',
  'reminders',
  'shopping_items',
  'memos',
  'kid_events',
  'accounting_records',
  'enabled_modules',
  'module_visibility_configs'
])

function assertAllowedTable(table) {
  if (!ALLOWED_TABLES.has(table)) {
    throw new Error(`Unsupported table: ${table}`)
  }
}

function assertRecordFamily(record, familyId) {
  if (!record || record.familyId !== familyId) {
    throw new Error('Record family mismatch')
  }
}

function sanitizeClientRecord(record, context) {
  const now = new Date().toISOString()
  return {
    ...record,
    familyId: context.familyId,
    creatorId: record.creatorId || context.userId,
    updatedAt: now,
    createdAt: record.createdAt || now,
    version: Number.isInteger(record.version) ? record.version : 1
  }
}

module.exports = {
  ALLOWED_TABLES,
  assertAllowedTable,
  assertRecordFamily,
  sanitizeClientRecord
}
```

- [ ] **Step 5: Run cloud visibility test**

Run:

```bash
cd /c/Users/Andy/kabao && node cloud/tests/visibility.test.js
```

Expected: PASS.

- [ ] **Step 6: Patch cloud auth to reject placeholder identity in production**

Modify `cloud/shared/auth.js` so the exported authentication function rejects missing verified identities when `NODE_ENV === 'production'`. If the file uses a different export name, keep the existing export name and add this helper inside the file:

```js
function assertVerifiedUser(userId) {
  if (!userId) throw new Error('Unauthorized')
  if (process.env.NODE_ENV === 'production' && String(userId).startsWith('pending_')) {
    throw new Error('Unauthorized')
  }
  return userId
}

module.exports.assertVerifiedUser = assertVerifiedUser
```

- [ ] **Step 7: Patch pull-data visibility filtering**

In `cloud/pull-data/index.js`, after records are fetched and before returning them, apply:

```js
const { filterVisibleRecords } = require('../shared/visibility')

const visibleRecords = filterVisibleRecords(records, userId)
```

Return `visibleRecords` instead of `records` for every table with `visibility` fields. Keep family membership checks before this filter.

- [ ] **Step 8: Patch push-data write checks**

In `cloud/push-data/index.js`, before writing each record, apply:

```js
const { assertCanWriteRecord } = require('../shared/visibility')
const { assertAllowedTable, sanitizeClientRecord } = require('../shared/validators')

assertAllowedTable(table)
const sanitized = sanitizeClientRecord(record, { userId, familyId })
assertCanWriteRecord(sanitized, currentMember)
```

Write `sanitized`, not the raw client record.

- [ ] **Step 9: Run cloud tests**

Run:

```bash
cd /c/Users/Andy/kabao && node cloud/tests/visibility.test.js
```

Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add cloud/shared/visibility.js cloud/shared/validators.js cloud/tests/visibility.test.js cloud/shared/auth.js cloud/pull-data/index.js cloud/push-data/index.js
git commit -m "fix: enforce cloud record visibility rules"
```

---

## Task 5: Build Public Landing Page and UI Components

**Files:**
- Create: `web/src/components/ui/Button.tsx`
- Create: `web/src/components/ui/Card.tsx`
- Create: `web/src/components/ui/EmptyState.tsx`
- Create: `web/src/components/layout/PublicHeader.tsx`
- Modify: `web/src/app/page.tsx`
- Create: `web/tests/e2e/landing-login.spec.ts`

- [ ] **Step 1: Write E2E test for landing page**

Write `web/tests/e2e/landing-login.spec.ts`:

```ts
import { expect, test } from '@playwright/test'

test('landing page presents product and login CTA', async ({ page }) => {
  await page.goto('/')

  await expect(page.getByRole('heading', { name: '把家的小事，稳稳接住' })).toBeVisible()
  await expect(page.getByText('提醒、购物、备忘、孩子事项和家庭记账')).toBeVisible()
  await expect(page.getByRole('link', { name: '手机号登录' })).toHaveAttribute('href', '/login')
  await expect(page.getByText('隐私安全')).toBeVisible()
})
```

- [ ] **Step 2: Run E2E to verify current baseline**

Run:

```bash
cd /c/Users/Andy/kabao/web && npm run e2e -- landing-login.spec.ts
```

Expected: PASS if Task 1 landing page is present; if it fails due missing “隐私安全”, continue with implementation.

- [ ] **Step 3: Create UI components**

Write `web/src/components/ui/Button.tsx`:

```tsx
import { clsx } from 'clsx'
import type { ButtonHTMLAttributes, AnchorHTMLAttributes } from 'react'

const buttonClasses = 'inline-flex items-center justify-center rounded-full px-5 py-3 text-sm font-bold transition hover:-translate-y-0.5 focus:outline-none focus:ring-2 focus:ring-coral focus:ring-offset-2'

export function Button(props: ButtonHTMLAttributes<HTMLButtonElement>) {
  return <button {...props} className={clsx(buttonClasses, 'bg-coral text-white shadow-warm', props.className)} />
}

export function LinkButton(props: AnchorHTMLAttributes<HTMLAnchorElement>) {
  return <a {...props} className={clsx(buttonClasses, 'bg-coral text-white shadow-warm', props.className)} />
}
```

Write `web/src/components/ui/Card.tsx`:

```tsx
import { clsx } from 'clsx'
import type { HTMLAttributes } from 'react'

export function Card(props: HTMLAttributes<HTMLDivElement>) {
  return <div {...props} className={clsx('rounded-card border border-white/80 bg-white/70 p-6 shadow-warm backdrop-blur', props.className)} />
}
```

Write `web/src/components/ui/EmptyState.tsx`:

```tsx
export function EmptyState({ title, description }: { title: string; description: string }) {
  return (
    <div className="rounded-card border border-dashed border-peach bg-white/50 p-8 text-center">
      <h3 className="text-lg font-bold text-ink">{title}</h3>
      <p className="mt-2 text-sm text-muted">{description}</p>
    </div>
  )
}
```

Write `web/src/components/layout/PublicHeader.tsx`:

```tsx
import { LinkButton } from '@/components/ui/Button'

export function PublicHeader() {
  return (
    <header className="flex items-center justify-between py-6">
      <a className="text-xl font-black text-ink" href="/">卡宝Home</a>
      <nav className="hidden items-center gap-6 text-sm font-semibold text-muted md:flex">
        <a href="#features">功能</a>
        <a href="#sync">数据互通</a>
        <a href="#security">隐私安全</a>
      </nav>
      <LinkButton href="/login">进入家庭</LinkButton>
    </header>
  )
}
```

- [ ] **Step 4: Replace landing page with complete sections**

Write `web/src/app/page.tsx`:

```tsx
import { PublicHeader } from '@/components/layout/PublicHeader'
import { Card } from '@/components/ui/Card'
import { LinkButton } from '@/components/ui/Button'

const features = [
  ['家庭总览', '今天要做什么、谁已经完成，一眼看清。'],
  ['提醒与购物', '购物作为提醒里的子视图，入口更少，数据仍与 APP ShoppingItem 同步。'],
  ['家庭备忘', '证件、密码提示、常用信息，按共享范围给家人看。'],
  ['孩子事项', '家长会、兴趣班、成长记录，减少口头转达遗漏。'],
  ['家庭记账', '收入支出与预算进度，家庭消费有共同视角。']
]

export default function HomePage() {
  return (
    <main className="mx-auto max-w-6xl px-6 pb-12">
      <PublicHeader />

      <section className="grid items-center gap-10 py-14 md:grid-cols-[1.1fr_0.9fr]">
        <div>
          <p className="mb-4 text-sm font-semibold tracking-[0.2em] text-coral">KABAOHOME.FUN</p>
          <h1 className="text-5xl font-black leading-tight text-ink md:text-7xl">把家的小事，稳稳接住</h1>
          <p className="mt-6 max-w-xl text-lg leading-8 text-muted">
            提醒、购物、备忘、孩子事项和家庭记账，与家人同步管理。网页版与 APP 使用同一份家庭数据。
          </p>
          <div className="mt-8 flex flex-wrap gap-3">
            <LinkButton href="/login">手机号登录</LinkButton>
            <a className="rounded-full border border-peach bg-white/60 px-6 py-3 font-bold text-ink" href="#security">
              了解隐私安全
            </a>
          </div>
        </div>

        <Card>
          <div className="mb-4 flex items-center justify-between">
            <span className="font-bold">今日家庭总览</span>
            <span className="rounded-full bg-cream px-3 py-1 text-sm text-muted">静态预览</span>
          </div>
          <div className="grid gap-3">
            {['晚饭后吃药提醒', '购物：牛奶和鸡蛋', '孩子事项：周五家长会', '本月支出：¥3,280'].map((item) => (
              <div key={item} className="rounded-2xl bg-cream px-4 py-3 text-sm font-medium text-ink">
                {item}
              </div>
            ))}
          </div>
        </Card>
      </section>

      <section id="features" className="grid gap-4 py-8 md:grid-cols-3">
        {features.map(([title, description]) => (
          <Card key={title} className="shadow-none">
            <h2 className="text-xl font-black text-ink">{title}</h2>
            <p className="mt-3 text-sm leading-6 text-muted">{description}</p>
          </Card>
        ))}
      </section>

      <section id="sync" className="py-10">
        <Card>
          <h2 className="text-3xl font-black text-ink">APP 与网页使用同一份家庭数据</h2>
          <p className="mt-4 max-w-3xl leading-7 text-muted">
            网页通过服务端 BFF 调用云函数，云函数统一进行家庭成员、模块和记录级可见性校验。浏览器不会直接读写 Cloud DB。
          </p>
        </Card>
      </section>

      <section id="security" className="py-10">
        <Card>
          <h2 className="text-3xl font-black text-ink">隐私安全</h2>
          <p className="mt-4 max-w-3xl leading-7 text-muted">
            手机号验证码登录、HttpOnly 安全 Cookie、CSRF 防护、记录级权限过滤和清晰的共享范围，保证家里的数据只给该看的人看。
          </p>
        </Card>
      </section>

      <footer className="flex flex-col gap-2 border-t border-peach/60 py-8 text-sm text-muted md:flex-row md:items-center md:justify-between">
        <span>© 2026 卡宝Home</span>
        <span>ICP 备案号上线前补充（中国大陆托管必填）</span>
      </footer>
    </main>
  )
}
```

- [ ] **Step 5: Run E2E and build**

Run:

```bash
cd /c/Users/Andy/kabao/web && npm run e2e -- landing-login.spec.ts && npm run build
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add web/src/app/page.tsx web/src/components web/tests/e2e/landing-login.spec.ts
git commit -m "feat: build kabaohome landing page"
```

---

## Task 6: Implement Auth API Routes and Login Page

**Files:**
- Create: `web/src/app/login/page.tsx`
- Create: `web/src/features/auth/LoginForm.tsx`
- Create: `web/src/app/api/auth/send-code/route.ts`
- Create: `web/src/app/api/auth/verify-code/route.ts`
- Create: `web/src/app/api/auth/logout/route.ts`
- Modify: `web/tests/e2e/landing-login.spec.ts`

- [ ] **Step 1: Extend E2E login page test**

Append to `web/tests/e2e/landing-login.spec.ts`:

```ts
test('login page shows phone verification form', async ({ page }) => {
  await page.goto('/login')

  await expect(page.getByRole('heading', { name: '登录我的家庭' })).toBeVisible()
  await expect(page.getByLabel('手机号')).toBeVisible()
  await expect(page.getByLabel('验证码')).toBeVisible()
  await expect(page.getByRole('button', { name: '发送验证码' })).toBeVisible()
  await expect(page.getByRole('button', { name: '进入家庭' })).toBeVisible()
})
```

- [ ] **Step 2: Run E2E to verify failure**

Run:

```bash
cd /c/Users/Andy/kabao/web && npm run e2e -- landing-login.spec.ts
```

Expected: FAIL because `/login` does not exist.

- [ ] **Step 3: Implement login form**

Write `web/src/features/auth/LoginForm.tsx`:

```tsx
'use client'

import { useState } from 'react'
import { Button } from '@/components/ui/Button'

export function LoginForm() {
  const [phone, setPhone] = useState('')
  const [code, setCode] = useState('')
  const [message, setMessage] = useState('')

  async function sendCode() {
    setMessage('')
    const response = await fetch('/api/auth/send-code', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ phone })
    })
    setMessage(response.ok ? '验证码已发送' : '发送太频繁，请稍后再试')
  }

  async function verifyCode() {
    setMessage('')
    const response = await fetch('/api/auth/verify-code', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ phone, code })
    })
    if (response.ok) {
      window.location.href = '/workspace'
      return
    }
    setMessage('手机号或验证码有误')
  }

  return (
    <div className="grid gap-4">
      <label className="grid gap-2 text-sm font-semibold text-ink">
        手机号
        <input
          className="rounded-2xl border border-peach bg-white px-4 py-3 outline-none focus:ring-2 focus:ring-coral"
          value={phone}
          onChange={(event) => setPhone(event.target.value)}
          placeholder="请输入手机号"
        />
      </label>
      <label className="grid gap-2 text-sm font-semibold text-ink">
        验证码
        <input
          className="rounded-2xl border border-peach bg-white px-4 py-3 outline-none focus:ring-2 focus:ring-coral"
          value={code}
          onChange={(event) => setCode(event.target.value)}
          placeholder="6 位验证码"
        />
      </label>
      <div className="flex gap-3">
        <Button type="button" onClick={sendCode}>发送验证码</Button>
        <Button type="button" onClick={verifyCode}>进入家庭</Button>
      </div>
      {message ? <p className="text-sm font-medium text-muted" role="status">{message}</p> : null}
      <p className="text-xs leading-5 text-muted">登录即表示同意隐私政策。验证码一次性使用，错误过多会失效。</p>
    </div>
  )
}
```

- [ ] **Step 4: Implement login page**

Write `web/src/app/login/page.tsx`:

```tsx
import { Card } from '@/components/ui/Card'
import { LoginForm } from '@/features/auth/LoginForm'

export default function LoginPage() {
  return (
    <main className="mx-auto grid min-h-screen max-w-5xl items-center gap-8 px-6 py-10 md:grid-cols-[0.9fr_1.1fr]">
      <section>
        <a className="text-xl font-black text-ink" href="/">卡宝Home</a>
        <h1 className="mt-10 text-5xl font-black leading-tight text-ink">登录我的家庭</h1>
        <p className="mt-5 leading-7 text-muted">用手机号验证码进入家庭工作台，在浏览器里处理提醒、备忘、孩子事项和记账。</p>
      </section>
      <Card>
        <LoginForm />
      </Card>
    </main>
  )
}
```

- [ ] **Step 5: Implement auth routes with secure failure behavior**

Write `web/src/app/api/auth/send-code/route.ts`:

```ts
import { apiError, apiSuccess } from '@/lib/api/response'
import { createFixedWindowLimiter } from '@/lib/auth/rate-limit'
import { sendCodeSchema } from '@/lib/validation/schemas'

const phoneLimiter = createFixedWindowLimiter({ limit: 1, windowMs: 60_000 })
const ipLimiter = createFixedWindowLimiter({ limit: 10, windowMs: 60 * 60_000 })

export async function POST(request: Request) {
  const body = sendCodeSchema.safeParse(await request.json().catch(() => null))
  if (!body.success) return apiError(400, '请输入有效手机号')

  const ip = request.headers.get('x-forwarded-for') ?? 'local'
  if (!phoneLimiter.consume(`phone:${body.data.phone}`).allowed || !ipLimiter.consume(`ip:${ip}`).allowed) {
    return apiError(429, '发送太频繁，请稍后再试')
  }

  return apiSuccess({ sent: true })
}
```

Write `web/src/app/api/auth/verify-code/route.ts`:

```ts
import { apiError, apiSuccess } from '@/lib/api/response'
import { createSessionCookie } from '@/lib/auth/session'
import { verifyCodeSchema } from '@/lib/validation/schemas'

export async function POST(request: Request) {
  const body = verifyCodeSchema.safeParse(await request.json().catch(() => null))
  if (!body.success) return apiError(400, '手机号或验证码有误')

  if (process.env.NODE_ENV === 'production') {
    return apiError(501, '验证码服务尚未启用')
  }

  if (body.data.code !== '123456') {
    return apiError(401, '手机号或验证码有误')
  }

  const response = apiSuccess({ userId: 'usr_demo', familyId: 'fam_demo' })
  response.cookies.set(createSessionCookie('dev-session', 60 * 60 * 24 * 7))
  return response
}
```

Write `web/src/app/api/auth/logout/route.ts`:

```ts
import { apiSuccess } from '@/lib/api/response'
import { createExpiredSessionCookie } from '@/lib/auth/session'

export async function POST() {
  const response = apiSuccess({ loggedOut: true })
  response.cookies.set(createExpiredSessionCookie())
  return response
}
```

- [ ] **Step 6: Run E2E, unit tests, typecheck**

Run:

```bash
cd /c/Users/Andy/kabao/web && npm run e2e -- landing-login.spec.ts && npm test && npm run typecheck
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add web/src/app/login web/src/features/auth web/src/app/api/auth web/tests/e2e/landing-login.spec.ts
git commit -m "feat: add phone login shell"
```

---

## Task 7: Build Protected Workspace Shell and Dashboard

**Files:**
- Create: `web/src/components/layout/AppShell.tsx`
- Create: `web/src/features/dashboard/DashboardCards.tsx`
- Create: `web/src/app/workspace/layout.tsx`
- Create: `web/src/app/workspace/page.tsx`
- Create: `web/src/app/api/dashboard/route.ts`
- Create: `web/tests/e2e/workspace.spec.ts`

- [ ] **Step 1: Write E2E test for protected workspace**

Write `web/tests/e2e/workspace.spec.ts`:

```ts
import { expect, test } from '@playwright/test'

test('workspace shows dashboard shell in dev session', async ({ page, context }) => {
  await context.addCookies([
    {
      name: 'kabaohome_session',
      value: 'dev-session',
      domain: '127.0.0.1',
      path: '/',
      httpOnly: true,
      secure: false,
      sameSite: 'Strict'
    }
  ])

  await page.goto('/workspace')

  await expect(page.getByRole('navigation')).toContainText('总览')
  await expect(page.getByRole('heading', { name: '家庭总览' })).toBeVisible()
  await expect(page.getByText('提醒与购物')).toBeVisible()
  await expect(page.getByText('本月收支')).toBeVisible()
})
```

- [ ] **Step 2: Run E2E to verify failure**

Run:

```bash
cd /c/Users/Andy/kabao/web && npm run e2e -- workspace.spec.ts
```

Expected: FAIL because workspace route does not exist.

- [ ] **Step 3: Implement AppShell**

Write `web/src/components/layout/AppShell.tsx`:

```tsx
const navItems = [
  ['总览', '/workspace'],
  ['提醒', '/workspace/reminders'],
  ['备忘', '/workspace/memos'],
  ['孩子事项', '/workspace/kids'],
  ['记账', '/workspace/accounting'],
  ['成员与模块', '/workspace/settings']
]

export function AppShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen md:grid md:grid-cols-[240px_1fr]">
      <aside className="hidden border-r border-peach/60 bg-white/55 p-6 md:block">
        <a className="text-xl font-black text-ink" href="/workspace">卡宝Home</a>
        <nav className="mt-10 grid gap-2" aria-label="工作台导航">
          {navItems.map(([label, href]) => (
            <a key={href} className="rounded-2xl px-4 py-3 text-sm font-bold text-muted hover:bg-cream hover:text-ink" href={href}>
              {label}
            </a>
          ))}
        </nav>
      </aside>
      <div>
        <header className="flex items-center justify-between border-b border-peach/60 bg-white/45 px-6 py-4">
          <span className="font-bold text-ink">我的家庭</span>
          <span className="rounded-full bg-cream px-3 py-1 text-sm text-muted">已同步</span>
        </header>
        <main className="px-5 py-6 md:px-8">{children}</main>
        <nav className="fixed bottom-0 left-0 right-0 grid grid-cols-5 border-t border-peach/60 bg-white/95 text-center text-xs font-bold text-muted md:hidden" aria-label="移动端工作台导航">
          {navItems.slice(0, 5).map(([label, href]) => (
            <a key={href} className="py-3" href={href}>{label}</a>
          ))}
        </nav>
      </div>
    </div>
  )
}
```

- [ ] **Step 4: Implement dashboard cards**

Write `web/src/features/dashboard/DashboardCards.tsx`:

```tsx
import { Card } from '@/components/ui/Card'
import type { DashboardData } from '@/types/domain'

export function DashboardCards({ data }: { data: DashboardData }) {
  return (
    <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
      <Card><h2 className="font-black">今日提醒</h2><p className="mt-2 text-3xl font-black">{data.todayReminders.length}</p></Card>
      <Card><h2 className="font-black">提醒与购物</h2><p className="mt-2 text-3xl font-black">{data.pendingShoppingItems.length}</p></Card>
      <Card><h2 className="font-black">最近备忘</h2><p className="mt-2 text-3xl font-black">{data.recentMemos.length}</p></Card>
      <Card><h2 className="font-black">孩子事项</h2><p className="mt-2 text-3xl font-black">{data.kidEvents.length}</p></Card>
      <Card><h2 className="font-black">本月收支</h2><p className="mt-2 text-3xl font-black">¥{data.accountingMonthTotal.expense}</p></Card>
      <Card><h2 className="font-black">家庭成员</h2><p className="mt-2 text-3xl font-black">{data.members.length}</p></Card>
    </div>
  )
}
```

- [ ] **Step 5: Implement workspace routes**

Write `web/src/app/workspace/layout.tsx`:

```tsx
import { AppShell } from '@/components/layout/AppShell'

export default function WorkspaceLayout({ children }: { children: React.ReactNode }) {
  return <AppShell>{children}</AppShell>
}
```

Write `web/src/app/workspace/page.tsx`:

```tsx
import { DashboardCards } from '@/features/dashboard/DashboardCards'
import type { DashboardData } from '@/types/domain'

const data: DashboardData = {
  family: { id: 'fam_demo', name: '我的家庭', ownerId: 'usr_demo', createdAt: '', updatedAt: '' },
  members: [{ id: 'mem_1', familyId: 'fam_demo', userId: 'usr_demo', name: '我', phone: '13800138000', role: 'owner', avatarColor: '#F9735B', enabledModules: [] }],
  todayReminders: [],
  pendingShoppingItems: [],
  recentMemos: [],
  kidEvents: [],
  accountingMonthTotal: { income: 0, expense: 0, balance: 0 }
}

export default function WorkspacePage() {
  return (
    <section>
      <h1 className="mb-6 text-3xl font-black text-ink">家庭总览</h1>
      <DashboardCards data={data} />
    </section>
  )
}
```

- [ ] **Step 6: Implement dashboard API shell**

Write `web/src/app/api/dashboard/route.ts`:

```ts
import { apiSuccess } from '@/lib/api/response'
import type { DashboardData } from '@/types/domain'

export async function GET() {
  const data: DashboardData = {
    family: { id: 'fam_demo', name: '我的家庭', ownerId: 'usr_demo', createdAt: '', updatedAt: '' },
    members: [{ id: 'mem_1', familyId: 'fam_demo', userId: 'usr_demo', name: '我', phone: '13800138000', role: 'owner', avatarColor: '#F9735B', enabledModules: [] }],
    todayReminders: [],
    pendingShoppingItems: [],
    recentMemos: [],
    kidEvents: [],
    accountingMonthTotal: { income: 0, expense: 0, balance: 0 }
  }

  return apiSuccess(data)
}
```

- [ ] **Step 7: Run E2E and build**

Run:

```bash
cd /c/Users/Andy/kabao/web && npm run e2e -- workspace.spec.ts && npm run build
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add web/src/app/workspace web/src/components/layout/AppShell.tsx web/src/features/dashboard web/src/app/api/dashboard web/tests/e2e/workspace.spec.ts
git commit -m "feat: add family workspace dashboard"
```

---

## Task 8: Implement Feature Pages and BFF CRUD Routes

**Files:**
- Create: `web/src/features/reminders/ReminderList.tsx`
- Create: `web/src/features/reminders/ShoppingSubview.tsx`
- Create: `web/src/features/memos/MemoList.tsx`
- Create: `web/src/features/kids/KidEventList.tsx`
- Create: `web/src/features/accounting/AccountingSummary.tsx`
- Create route files under `web/src/app/workspace/{reminders,memos,kids,accounting}/page.tsx`
- Create route handlers under `web/src/app/api/{reminders,shopping-items,memos,kid-events,accounting-records}`

- [ ] **Step 1: Write feature page E2E assertions**

Append to `web/tests/e2e/workspace.spec.ts`:

```ts
test('workspace feature pages render core modules', async ({ page, context }) => {
  await context.addCookies([{ name: 'kabaohome_session', value: 'dev-session', domain: '127.0.0.1', path: '/', httpOnly: true, secure: false, sameSite: 'Strict' }])

  await page.goto('/workspace/reminders')
  await expect(page.getByRole('heading', { name: '提醒事项' })).toBeVisible()
  await expect(page.getByRole('tab', { name: '购物' })).toBeVisible()

  await page.goto('/workspace/memos')
  await expect(page.getByRole('heading', { name: '家庭备忘' })).toBeVisible()

  await page.goto('/workspace/kids')
  await expect(page.getByRole('heading', { name: '孩子事项' })).toBeVisible()

  await page.goto('/workspace/accounting')
  await expect(page.getByRole('heading', { name: '家庭记账' })).toBeVisible()
})
```

- [ ] **Step 2: Run E2E to verify failure**

Run:

```bash
cd /c/Users/Andy/kabao/web && npm run e2e -- workspace.spec.ts
```

Expected: FAIL because feature pages do not exist.

- [ ] **Step 3: Create feature components**

Write `web/src/features/reminders/ReminderList.tsx`:

```tsx
import { EmptyState } from '@/components/ui/EmptyState'
import type { Reminder } from '@/types/domain'

export function ReminderList({ reminders }: { reminders: Reminder[] }) {
  if (reminders.length === 0) return <EmptyState title="还没有提醒" description="把家里的重要小事先记下来。" />
  return <div className="grid gap-3">{reminders.map((item) => <div key={item.id}>{item.title}</div>)}</div>
}
```

Write `web/src/features/reminders/ShoppingSubview.tsx`:

```tsx
import { EmptyState } from '@/components/ui/EmptyState'
import type { ShoppingItem } from '@/types/domain'

export function ShoppingSubview({ items }: { items: ShoppingItem[] }) {
  if (items.length === 0) return <EmptyState title="购物清单是空的" description="购物入口在提醒里，但数据仍同步 ShoppingItem。" />
  return <div className="grid gap-3">{items.map((item) => <div key={item.id}>{item.itemName}</div>)}</div>
}
```

Write `web/src/features/memos/MemoList.tsx`:

```tsx
import { EmptyState } from '@/components/ui/EmptyState'
import type { Memo } from '@/types/domain'

export function MemoList({ memos }: { memos: Memo[] }) {
  if (memos.length === 0) return <EmptyState title="还没有备忘" description="记录证件、常用信息或家庭约定。" />
  return <div className="grid gap-3">{memos.map((memo) => <div key={memo.id}>{memo.title}</div>)}</div>
}
```

Write `web/src/features/kids/KidEventList.tsx`:

```tsx
import { EmptyState } from '@/components/ui/EmptyState'
import type { KidEvent } from '@/types/domain'

export function KidEventList({ events }: { events: KidEvent[] }) {
  if (events.length === 0) return <EmptyState title="还没有孩子事项" description="家长会、兴趣班和成长记录可以放在这里。" />
  return <div className="grid gap-3">{events.map((event) => <div key={event.id}>{event.title}</div>)}</div>
}
```

Write `web/src/features/accounting/AccountingSummary.tsx`:

```tsx
import { Card } from '@/components/ui/Card'
import type { AccountingRecord } from '@/types/domain'

export function AccountingSummary({ records }: { records: AccountingRecord[] }) {
  const expense = records.filter((record) => record.direction === 'expense').reduce((sum, record) => sum + record.amount, 0)
  const income = records.filter((record) => record.direction === 'income').reduce((sum, record) => sum + record.amount, 0)

  return (
    <div className="grid gap-4 md:grid-cols-2">
      <Card><h2 className="font-black">收入</h2><p className="mt-2 text-3xl font-black">¥{income}</p></Card>
      <Card><h2 className="font-black">支出</h2><p className="mt-2 text-3xl font-black">¥{expense}</p></Card>
    </div>
  )
}
```

- [ ] **Step 4: Create feature pages**

Write `web/src/app/workspace/reminders/page.tsx`:

```tsx
import { ReminderList } from '@/features/reminders/ReminderList'
import { ShoppingSubview } from '@/features/reminders/ShoppingSubview'

export default function RemindersPage() {
  return (
    <section>
      <h1 className="mb-6 text-3xl font-black text-ink">提醒事项</h1>
      <div className="mb-4 flex gap-2" role="tablist">
        <button className="rounded-full bg-coral px-4 py-2 text-sm font-bold text-white" role="tab">提醒</button>
        <button className="rounded-full bg-white px-4 py-2 text-sm font-bold text-muted" role="tab">购物</button>
      </div>
      <div className="grid gap-5 lg:grid-cols-2">
        <ReminderList reminders={[]} />
        <ShoppingSubview items={[]} />
      </div>
    </section>
  )
}
```

Write `web/src/app/workspace/memos/page.tsx`:

```tsx
import { MemoList } from '@/features/memos/MemoList'

export default function MemosPage() {
  return (
    <section>
      <h1 className="mb-6 text-3xl font-black text-ink">家庭备忘</h1>
      <MemoList memos={[]} />
    </section>
  )
}
```

Write `web/src/app/workspace/kids/page.tsx`:

```tsx
import { KidEventList } from '@/features/kids/KidEventList'

export default function KidsPage() {
  return (
    <section>
      <h1 className="mb-6 text-3xl font-black text-ink">孩子事项</h1>
      <KidEventList events={[]} />
    </section>
  )
}
```

Write `web/src/app/workspace/accounting/page.tsx`:

```tsx
import { AccountingSummary } from '@/features/accounting/AccountingSummary'

export default function AccountingPage() {
  return (
    <section>
      <h1 className="mb-6 text-3xl font-black text-ink">家庭记账</h1>
      <AccountingSummary records={[]} />
    </section>
  )
}
```

- [ ] **Step 5: Create BFF CRUD route shells**

For each folder below, create `route.ts` that returns an empty list on `GET` and echoes a created object on `POST`:

- `web/src/app/api/reminders/route.ts`
- `web/src/app/api/shopping-items/route.ts`
- `web/src/app/api/memos/route.ts`
- `web/src/app/api/kid-events/route.ts`
- `web/src/app/api/accounting-records/route.ts`

Use this pattern in each file, changing the `collection` value:

```ts
import { apiSuccess } from '@/lib/api/response'

const collection = 'reminders'

export async function GET() {
  return apiSuccess({ collection, items: [] })
}

export async function POST(request: Request) {
  const body = await request.json().catch(() => ({}))
  return apiSuccess({ collection, item: body }, { status: 201 })
}
```

- [ ] **Step 6: Create BFF item route shells**

For each folder below, create `[id]/route.ts` with `PATCH` and `DELETE`:

- `web/src/app/api/reminders/[id]/route.ts`
- `web/src/app/api/shopping-items/[id]/route.ts`
- `web/src/app/api/memos/[id]/route.ts`
- `web/src/app/api/kid-events/[id]/route.ts`
- `web/src/app/api/accounting-records/[id]/route.ts`

Use this pattern in each file:

```ts
import { apiSuccess } from '@/lib/api/response'

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const body = await request.json().catch(() => ({}))
  return apiSuccess({ id, item: body })
}

export async function DELETE(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  return apiSuccess({ id, deleted: true })
}
```

- [ ] **Step 7: Run E2E, tests, typecheck, build**

Run:

```bash
cd /c/Users/Andy/kabao/web && npm run e2e -- workspace.spec.ts && npm test && npm run typecheck && npm run build
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add web/src/features web/src/app/workspace web/src/app/api web/tests/e2e/workspace.spec.ts
git commit -m "feat: add workspace feature modules"
```

---

## Task 9: Add Members and Module Settings Page

**Files:**
- Create: `web/src/features/settings/MemberModuleSettings.tsx`
- Create: `web/src/app/workspace/settings/page.tsx`
- Create: `web/src/app/api/family-members/route.ts`
- Create: `web/src/app/api/modules/route.ts`
- Modify: `web/tests/e2e/workspace.spec.ts`

- [ ] **Step 1: Add E2E check for settings page**

Append to `web/tests/e2e/workspace.spec.ts`:

```ts
test('settings page shows members and module controls', async ({ page, context }) => {
  await context.addCookies([{ name: 'kabaohome_session', value: 'dev-session', domain: '127.0.0.1', path: '/', httpOnly: true, secure: false, sameSite: 'Strict' }])

  await page.goto('/workspace/settings')

  await expect(page.getByRole('heading', { name: '成员与模块' })).toBeVisible()
  await expect(page.getByText('家庭成员')).toBeVisible()
  await expect(page.getByText('模块管理')).toBeVisible()
})
```

- [ ] **Step 2: Run E2E to verify failure**

Run:

```bash
cd /c/Users/Andy/kabao/web && npm run e2e -- workspace.spec.ts
```

Expected: FAIL because settings page does not exist.

- [ ] **Step 3: Implement settings component**

Write `web/src/features/settings/MemberModuleSettings.tsx`:

```tsx
import { Card } from '@/components/ui/Card'
import type { FamilyMember } from '@/types/domain'

const modules = ['提醒', '备忘', '孩子事项', '记账']

export function MemberModuleSettings({ members }: { members: FamilyMember[] }) {
  return (
    <div className="grid gap-5 lg:grid-cols-2">
      <Card>
        <h2 className="text-xl font-black text-ink">家庭成员</h2>
        <div className="mt-4 grid gap-3">
          {members.map((member) => (
            <div key={member.id} className="rounded-2xl bg-cream px-4 py-3">
              <div className="font-bold text-ink">{member.name}</div>
              <div className="text-sm text-muted">{member.role}</div>
            </div>
          ))}
        </div>
      </Card>
      <Card>
        <h2 className="text-xl font-black text-ink">模块管理</h2>
        <div className="mt-4 grid gap-3">
          {modules.map((module) => (
            <label key={module} className="flex items-center justify-between rounded-2xl bg-cream px-4 py-3 font-bold text-ink">
              {module}
              <input type="checkbox" defaultChecked />
            </label>
          ))}
        </div>
      </Card>
    </div>
  )
}
```

- [ ] **Step 4: Implement settings page and API routes**

Write `web/src/app/workspace/settings/page.tsx`:

```tsx
import { MemberModuleSettings } from '@/features/settings/MemberModuleSettings'
import type { FamilyMember } from '@/types/domain'

const members: FamilyMember[] = [
  { id: 'mem_1', familyId: 'fam_demo', userId: 'usr_demo', name: '我', phone: '13800138000', role: 'owner', avatarColor: '#F9735B', enabledModules: ['reminder', 'memo', 'kids', 'accounting'] }
]

export default function SettingsPage() {
  return (
    <section>
      <h1 className="mb-6 text-3xl font-black text-ink">成员与模块</h1>
      <MemberModuleSettings members={members} />
    </section>
  )
}
```

Write `web/src/app/api/family-members/route.ts`:

```ts
import { apiSuccess } from '@/lib/api/response'

export async function GET() {
  return apiSuccess({ items: [] })
}
```

Write `web/src/app/api/modules/route.ts`:

```ts
import { apiSuccess } from '@/lib/api/response'

export async function PATCH(request: Request) {
  const body = await request.json().catch(() => ({}))
  return apiSuccess({ modules: body })
}
```

- [ ] **Step 5: Run E2E and build**

Run:

```bash
cd /c/Users/Andy/kabao/web && npm run e2e -- workspace.spec.ts && npm run build
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add web/src/features/settings web/src/app/workspace/settings web/src/app/api/family-members web/src/app/api/modules web/tests/e2e/workspace.spec.ts
git commit -m "feat: add family member module settings"
```

---

## Task 10: Wire BFF Routes to Cloud Function Client

**Files:**
- Modify: `web/src/app/api/dashboard/route.ts`
- Modify all CRUD route files under `web/src/app/api/`
- Modify: `web/src/lib/agc/cloudFunctionClient.ts`
- Create: `web/src/lib/auth/request-session.ts`
- Create: `web/tests/unit/cloud-function-client.test.ts`

- [ ] **Step 1: Write cloud client test**

Write `web/tests/unit/cloud-function-client.test.ts`:

```ts
import { describe, expect, test, vi } from 'vitest'
import { createCloudFunctionClient } from '@/lib/agc/cloudFunctionClient'

describe('cloud function client', () => {
  test('sends service token and session token server-side', async () => {
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => ({ success: true }) })
    vi.stubGlobal('fetch', fetchMock)

    const client = createCloudFunctionClient('https://functions.example.test', 'service-token')
    await client.call({ name: 'pull-data', payload: { table: 'reminders' }, sessionToken: 'session-token' })

    expect(fetchMock).toHaveBeenCalledWith('https://functions.example.test/pull-data', expect.objectContaining({
      method: 'POST',
      headers: expect.objectContaining({
        authorization: 'Bearer service-token',
        'x-kabaohome-session': 'session-token'
      })
    }))
  })
})
```

- [ ] **Step 2: Run test to verify current behavior**

Run:

```bash
cd /c/Users/Andy/kabao/web && npm test -- cloud-function-client.test.ts
```

Expected: PASS if Task 3 client matches; otherwise update client.

- [ ] **Step 3: Implement request session helper**

Write `web/src/lib/auth/request-session.ts`:

```ts
import { cookies } from 'next/headers'
import { SESSION_COOKIE_NAME } from '@/lib/auth/session'

export async function requireSessionToken(): Promise<string> {
  const cookieStore = await cookies()
  const token = cookieStore.get(SESSION_COOKIE_NAME)?.value
  if (!token) throw new Error('Unauthorized')
  return token
}
```

- [ ] **Step 4: Update API routes to call Cloud Functions**

For each BFF route, use this pattern:

```ts
import { apiError, apiSuccess } from '@/lib/api/response'
import { createCloudFunctionClient } from '@/lib/agc/cloudFunctionClient'
import { requireSessionToken } from '@/lib/auth/request-session'

const client = createCloudFunctionClient(process.env.AGC_FUNCTION_ENDPOINT ?? '', process.env.AGC_SERVICE_TOKEN ?? '')

export async function GET() {
  try {
    const sessionToken = await requireSessionToken()
    const data = await client.call({ name: 'pull-data', payload: { table: 'reminders' }, sessionToken })
    return apiSuccess(data)
  } catch {
    return apiError(401, '请先登录')
  }
}
```

Use these table mappings:

- `reminders` → `reminders`
- `shopping-items` → `shopping_items`
- `memos` → `memos`
- `kid-events` → `kid_events`
- `accounting-records` → `accounting_records`
- dashboard → request all five tables via `pull-data`

- [ ] **Step 5: Run unit tests and typecheck**

Run:

```bash
cd /c/Users/Andy/kabao/web && npm test && npm run typecheck
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add web/src/app/api web/src/lib/agc web/src/lib/auth/request-session.ts web/tests/unit/cloud-function-client.test.ts
git commit -m "feat: connect web bff to cloud functions"
```

---

## Task 11: Privacy, Deployment, and Final Verification

**Files:**
- Modify: `docs/privacy-policy.md`
- Create: `web/.env.example`
- Create: `web/README.md`
- Create: `web/tests/e2e/security-headers.spec.ts`

- [ ] **Step 1: Add environment example**

Write `web/.env.example`:

```bash
AGC_FUNCTION_ENDPOINT=https://example.agc.function.endpoint
AGC_SERVICE_TOKEN=replace-with-deployment-secret
SESSION_SIGNING_SECRET=replace-with-32-byte-random-secret
SMS_PROVIDER=agc
NEXT_PUBLIC_SITE_URL=https://kabaohome.fun
```

- [ ] **Step 2: Add Web README**

Write `web/README.md`:

```md
# 卡宝Home Web

`kabaohome.fun` provides the public website and web family workspace for 卡宝Home.

## Architecture

- Next.js is the Web BFF and UI layer.
- Browser calls only `/api/*` routes on this web app.
- Next.js calls AGC Cloud Functions with server-side credentials.
- Cloud Functions are the only data write and record-level permission enforcement layer.
- Cloud DB is not accessed directly by the browser or Next.js.

## Local Development

```bash
npm install
npm run dev
npm test
npm run e2e
npm run build
```

## Required Environment Variables

See `.env.example`.

## Shopping Data Rule

Shopping appears under the Reminder UI, but the data API and cloud storage remain `ShoppingItem` / `shopping_items` for HarmonyOS app interoperability.
```

- [ ] **Step 3: Add security headers E2E test**

Write `web/tests/e2e/security-headers.spec.ts`:

```ts
import { expect, test } from '@playwright/test'

test('security headers are present', async ({ request }) => {
  const response = await request.get('/')
  expect(response.headers()['x-frame-options']).toBe('DENY')
  expect(response.headers()['x-content-type-options']).toBe('nosniff')
  expect(response.headers()['referrer-policy']).toBe('strict-origin-when-cross-origin')
  expect(response.headers()['content-security-policy']).toContain("frame-ancestors 'none'")
})
```

- [ ] **Step 4: Update privacy policy Web section**

In `docs/privacy-policy.md`, add a section describing Web processing:

```md
## 网页版服务说明

卡宝Home 网页版（kabaohome.fun）用于在浏览器中访问家庭工作台。网页版会处理手机号登录、家庭提醒、购物项、家庭备忘、孩子事项、家庭记账、家庭成员和模块设置等数据。网页端与 APP 使用同一套云端家庭数据，数据访问遵循家庭成员身份、模块共享范围和记录级可见性规则。

网页版不会让浏览器直接访问云数据库。浏览器请求先到达 Web 服务端，再由服务端调用云函数，云函数完成身份校验、家庭成员校验和记录级权限校验后返回结果。
```

- [ ] **Step 5: Run full verification**

Run:

```bash
cd /c/Users/Andy/kabao/web && npm test && npm run typecheck && npm run build && npm run e2e
```

Expected: PASS.

Run cloud tests:

```bash
cd /c/Users/Andy/kabao && node cloud/tests/visibility.test.js
```

Expected: PASS.

- [ ] **Step 6: Run secret scan checks**

Run:

```bash
git -C /c/Users/Andy/kabao grep -n "AGC_SERVICE_TOKEN\|SESSION_SIGNING_SECRET\|client_secret\|api_key" -- web cloud docs || true
```

Expected: only `.env.example`, documentation, or existing non-web AGC config references appear. No real new secret values are committed.

- [ ] **Step 7: Commit**

```bash
git add web/.env.example web/README.md web/tests/e2e/security-headers.spec.ts docs/privacy-policy.md
git commit -m "docs: add web deployment and privacy guidance"
```

---

## Final Release Gate

Before deploying `kabaohome.fun`, run:

```bash
cd /c/Users/Andy/kabao/web && npm test && npm run typecheck && npm run build && npm run e2e
cd /c/Users/Andy/kabao && node cloud/tests/visibility.test.js
```

Release is blocked unless all are true:

- Auth uses verified identity in production; no `pending_` or placeholder user is accepted.
- Cloud Functions perform family membership and record-level visibility filtering.
- Next.js does not read/write Cloud DB directly.
- Shopping UI lives under reminders, but ShoppingItem data remains independent.
- `POST /api/auth/logout` clears the HttpOnly session cookie.
- State-changing routes use CSRF protection or same-origin request header validation.
- Security headers include CSP `frame-ancestors 'none'` and `X-Frame-Options: DENY`.
- Privacy policy includes the Web data flow.
- If hosted in mainland China, ICP备案 is complete and displayed.
