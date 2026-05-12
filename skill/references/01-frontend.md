# 01 — Frontend

Patterns + code stubs per supported stack. Load when user is on a frontend
task. Stack defaults in `SKILL.md §17`.

---

## Stack matrix

| Need                  | Default                  | Alternative              |
| --------------------- | ------------------------ | ------------------------ |
| SPA                   | React + Vite + TS        | SvelteKit, Vue 3 + Nuxt  |
| SSR / SSG             | Next.js 15 (App Router)  | Remix, Nuxt              |
| Mobile                | Expo + React Native      | Flutter (if user asks)   |
| Desktop               | Tauri (Rust shell)       | Electron                 |
| Styling               | Tailwind + shadcn/ui     | Chakra, MUI              |
| State (light)         | Zustand                  | Jotai                    |
| State (heavy)         | Redux Toolkit + RTK Query| —                        |
| Server state          | TanStack Query           | SWR                      |
| Forms                 | React Hook Form + Zod    | Formik (legacy only)     |
| Routing (SPA)         | TanStack Router          | React Router 7           |
| API client            | tRPC (if BE is Node) / openapi-fetch (REST) / generated GraphQL | hand-written |
| Auth                  | Clerk / NextAuth         | Supabase Auth, custom    |
| Testing               | Vitest + Testing Library + Playwright | Jest (legacy)|

---

## React + Vite scaffold

```
apps/web/
├── public/
├── src/
│   ├── main.tsx
│   ├── app.tsx              # Router root
│   ├── routes/              # File-based routes (TanStack Router)
│   ├── components/
│   │   ├── ui/              # shadcn primitives
│   │   └── features/        # feature components
│   ├── lib/
│   │   ├── api.ts           # openapi-fetch client
│   │   ├── auth.ts
│   │   └── utils.ts
│   ├── hooks/
│   ├── stores/              # zustand stores
│   └── styles/globals.css
├── index.html
├── vite.config.ts
├── tsconfig.json
└── package.json
```

### `vite.config.ts`

```ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react-swc';
import path from 'node:path';
import tsconfigPaths from 'vite-tsconfig-paths';

export default defineConfig({
  plugins: [react(), tsconfigPaths()],
  resolve: { alias: { '@': path.resolve(__dirname, './src') } },
  server: { port: 3000 },
  build: { sourcemap: true, target: 'es2022' },
});
```

### `tsconfig.json` (strict)

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "jsx": "react-jsx",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "exactOptionalPropertyTypes": true,
    "noFallthroughCasesInSwitch": true,
    "isolatedModules": true,
    "skipLibCheck": true,
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "paths": { "@/*": ["./src/*"] }
  }
}
```

No `any`. No `// @ts-ignore` without justification comment.

---

## Next.js 15 (App Router) scaffold

```
apps/web/
├── app/
│   ├── (marketing)/         # route group, no auth
│   ├── (app)/               # route group, auth required
│   │   ├── layout.tsx
│   │   └── dashboard/page.tsx
│   ├── api/                 # route handlers
│   ├── layout.tsx
│   └── globals.css
├── components/
├── lib/
├── middleware.ts            # auth guard
├── next.config.mjs
└── package.json
```

### Server Components first

- Default to Server Components. Add `'use client'` only when needed (state,
  effects, browser APIs).
- Data fetching in Server Components, mutations via Server Actions.
- Stream where possible: `<Suspense>` + `loading.tsx`.

### Server Action pattern

```ts
// app/(app)/posts/actions.ts
'use server';

import { z } from 'zod';
import { revalidatePath } from 'next/cache';
import { requireUser } from '@/lib/auth';
import { db } from '@/lib/db';

const CreatePost = z.object({
  title: z.string().min(1).max(200),
  body: z.string().min(1).max(10_000),
});

export async function createPost(formData: FormData): Promise<
  { ok: true; id: string } | { ok: false; error: string }
> {
  const user = await requireUser();
  const parsed = CreatePost.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { ok: false, error: parsed.error.message };

  const row = await db.insert(posts).values({ ...parsed.data, userId: user.id }).returning();
  revalidatePath('/dashboard/posts');
  return { ok: true, id: row[0].id };
}
```

---

## Data fetching — TanStack Query

```ts
// hooks/use-posts.ts
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { api } from '@/lib/api';

export function usePosts() {
  return useQuery({
    queryKey: ['posts'],
    queryFn: async () => {
      const { data, error } = await api.GET('/posts');
      if (error) throw error;
      return data;
    },
    staleTime: 30_000,
  });
}

export function useCreatePost() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: { title: string; body: string }) => {
      const { data, error } = await api.POST('/posts', { body: input });
      if (error) throw error;
      return data;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['posts'] }),
  });
}
```

Rules:
- `staleTime` set explicitly per query
- Mutations always invalidate or update cache
- Errors surfaced via toast + Sentry breadcrumb
- No `useEffect` for data fetching

---

## Forms — RHF + Zod

```tsx
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';

const Schema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
});
type FormData = z.infer<typeof Schema>;

export function LoginForm() {
  const { register, handleSubmit, formState: { errors, isSubmitting } } =
    useForm<FormData>({ resolver: zodResolver(Schema) });

  const onSubmit = async (data: FormData) => { /* ... */ };

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <input {...register('email')} aria-invalid={!!errors.email} />
      {errors.email && <p role="alert">{errors.email.message}</p>}
      <input type="password" {...register('password')} />
      <button disabled={isSubmitting}>Sign in</button>
    </form>
  );
}
```

---

## State — Zustand

```ts
// stores/ui.ts
import { create } from 'zustand';
import { persist } from 'zustand/middleware';

type UiState = {
  sidebarOpen: boolean;
  toggleSidebar: () => void;
};

export const useUi = create<UiState>()(
  persist(
    (set) => ({
      sidebarOpen: true,
      toggleSidebar: () => set((s) => ({ sidebarOpen: !s.sidebarOpen })),
    }),
    { name: 'ui' }
  )
);
```

Rule: stores only for UI / client state. Server data lives in TanStack Query
cache, never duplicated.

---

## Auth — Clerk (default for new apps)

```tsx
// app/layout.tsx
import { ClerkProvider } from '@clerk/nextjs';
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return <ClerkProvider><html><body>{children}</body></html></ClerkProvider>;
}
```

```ts
// middleware.ts
import { clerkMiddleware, createRouteMatcher } from '@clerk/nextjs/server';
const isProtected = createRouteMatcher(['/dashboard(.*)', '/api/private(.*)']);
export default clerkMiddleware((auth, req) => {
  if (isProtected(req)) auth().protect();
});
export const config = { matcher: ['/((?!_next|.*\\..*).*)'] };
```

Server-side user:

```ts
import { auth } from '@clerk/nextjs/server';
export async function requireUser() {
  const { userId } = auth();
  if (!userId) throw new Error('UNAUTHORIZED');
  return { id: userId };
}
```

---

## Streaming + Suspense (RSC)

```tsx
// app/(app)/dashboard/page.tsx
import { Suspense } from 'react';
import { Stats, StatsSkeleton } from './stats';
import { RecentActivity, RecentActivitySkeleton } from './activity';

export default function Dashboard() {
  return (
    <>
      <Suspense fallback={<StatsSkeleton />}><Stats /></Suspense>
      <Suspense fallback={<RecentActivitySkeleton />}><RecentActivity /></Suspense>
    </>
  );
}
```

---

## Accessibility checklist (every UI deliverable)

- All interactive elements keyboard-reachable
- Visible focus states (Tailwind: `focus-visible:ring-2`)
- Form fields have `<label>` or `aria-label`
- Error messages associated via `aria-describedby` or `role="alert"`
- Colour contrast ≥ WCAG AA (4.5:1 body, 3:1 large)
- Image `alt` text; decorative `alt=""`
- Skip-to-content link on every page
- Test with `axe-core` in CI

---

## Performance budget

| Metric            | Target              | Tool                |
| ----------------- | ------------------- | ------------------- |
| LCP               | < 2.5s              | Lighthouse CI       |
| INP               | < 200ms             | Web Vitals          |
| CLS               | < 0.1               | Web Vitals          |
| JS bundle (init)  | < 200KB gz          | rollup-plugin-visualizer |
| Image strategy    | next/image or WebP, sized | —             |

Set Lighthouse CI threshold in `.github/workflows/lighthouse.yml`.

---

## What never to ship

- `useEffect` for data fetching (use TanStack Query or RSC)
- Inline event handlers that recreate functions inside hot lists without
  memoisation
- Untyped responses (always Zod-validate at boundary)
- `dangerouslySetInnerHTML` with user input
- Secrets in `NEXT_PUBLIC_*` env vars
- Client components reading server-only env vars
- Global stylesheet ordering bugs — Tailwind layer order: `base → components → utilities`

---

## Mobile (Expo) quick notes

- File-based routing via `expo-router`
- State: Zustand portable; TanStack Query same patterns
- Native auth: Clerk Expo SDK, or Supabase Auth + secure-store
- Build: EAS Build; profiles `development`, `preview`, `production`
- OTA: EAS Update for non-native changes

---

## CI checks for frontend

```yaml
- run: pnpm install --frozen-lockfile
- run: pnpm lint
- run: pnpm typecheck
- run: pnpm test -- --run
- run: pnpm build
- run: pnpm playwright test
- run: pnpm exec lhci autorun
```
