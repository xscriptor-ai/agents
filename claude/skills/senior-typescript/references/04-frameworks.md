# Frameworks

> Scope: current idiom for Next.js App Router, Vue 3.5+, Svelte 5 runes, Angular signals, Solid, and Astro, plus a selection table by project type.

Version floors (verify upstream; treat as minimums):

| Framework | Current line | Signal features |
| --- | --- | --- |
| Next.js | 15/16+ | async request APIs, App Router, cache directives, PPR |
| React Router | 7+ | framework mode, loaders/actions, typegen |
| TanStack Start | current | typed full-stack React, server functions |
| Vue | 3.5+ | reactive props destructure, `useTemplateRef`, vapor preview |
| Nuxt | 3.x/4.x | Nitro, server routes, hybrid rendering |
| Svelte | 5+ | runes, snippets, event props |
| SvelteKit | 2+ | load functions, form actions |
| Angular | 20+ | signals, zoneless, resource API, standalone |
| Solid | 1.9+ | signals, stores; SolidStart verify maturity |
| Astro | 5+ | islands, content layer, server islands, actions |

## 1. Selection by project type

| Project type | Default | Alternatives | Why |
| --- | --- | --- | --- |
| Marketing/content site | Astro | Next.js static, SvelteKit | minimal JS, content collections |
| Full-stack React product | Next.js App Router | TanStack Start, React Router 7 | RSC, caching, actions, ecosystem |
| React SPA behind separate API | Vite + React Router | TanStack Router | no SSR complexity |
| Vue product | Nuxt | Vite + Vue Router | conventions, Nitro server |
| Svelte product | SvelteKit | Vite + Svelte | runes + server primitives |
| Enterprise Angular shop | Angular 20+ | Nx + Angular | DI, signals, long-term support |
| Fine-grained reactive app | Solid | Svelte | smallest runtime updates |
| Multi-runtime API | Hono | Fastify | see [06-backend-node](./06-backend-node.md) |

Decision inputs that matter: team familiarity, hiring, SSR requirement, edge deployment, content authoring, and how much server logic the frontend framework should own. Framework choice is expensive to reverse; runtime and validation choices are not.

## 2. Next.js App Router

Mental model: every component is a Server Component unless marked otherwise; the router streams server-rendered UI over HTTP and hydrates only client islands.

Core practices:

- Treat `params`, `searchParams`, `cookies()`, and `headers()` as async on current majors; `await` them.
- Cache deliberately. Recent majors moved toward explicit caching: `"use cache"` directives and cache components replace implicit fetch caching; verify the current flag names and defaults upstream.
- Prefer Server Actions for mutations from forms; route handlers for public APIs and webhooks.
- Place `"use client"` at the smallest interactive leaf; keep providers in a thin client wrapper.
- Use `loading.tsx`, `error.tsx`, `not-found.tsx` for segment-level streaming and failures; `Suspense` for finer control.
- Route handlers are public; authenticate and validate like any HTTP endpoint.
- Middleware runs on every matched request; keep it to cheap checks (headers, redirects). Recent majors renamed/exposed it differently (proxy-style naming) — verify upstream.
- Metadata via the metadata API; `generateMetadata` for dynamic pages.
- `next/image` and `next/font` remain the performance defaults; set `images.remotePatterns` explicitly.

```tsx
// app/posts/actions.ts
"use server";
import { revalidateTag } from "next/cache";
import { z } from "zod";

export async function createPost(formData: FormData) {
  const input = z.object({ title: z.string().min(1) }).parse(Object.fromEntries(formData));
  await db.post.create({ data: input });
  revalidateTag("posts");
}
```

Pitfalls: `revalidatePath` misuse (prefer tag-based invalidation), circular server/client imports, non-serializable props, layout state that survives client navigation unexpectedly, and buffering an entire page behind one slow fetch instead of streaming with Suspense.

## 3. React Router 7 and TanStack Start

Both target React full-stack without Next's opinionated caching.

- React Router 7 (framework mode): file routes, `loader`/`action`, typed route params via generated types, SSR or SPA mode. Good when the team knows RR and wants less framework magic.
- TanStack Start: typed server functions, TanStack Router search-param state, integrates with TanStack Query. Verify release maturity upstream before a long-lived bet.

Choose these over Next when you want route-level data loading without RSC, or you are already invested in TanStack tooling.

## 4. Vue 3.5+

Idioms:

- `<script setup lang="ts">` with `defineProps`/`defineEmits` generics.
- `defineModel` for two-way bindings; reactive props destructure is stable in 3.5.
- `useTemplateRef` replaces template-ref string juggling when needed.
- `shallowRef` for large arrays/objects; `readonly` for exposed state.
- Pinia for shared state; Nuxt auto-imports are convenient but keep explicit imports in libraries.
- Nuxt: `useAsyncData`/`useFetch` with keys, server routes under `server/api`, Nitro presets per deployment target; hybrid rendering per route.

```vue
<script setup lang="ts">
import { computed, ref } from "vue";

const props = defineProps<{ items: { id: string; title: string }[] }>();
const query = ref("");
const visible = computed(() => props.items.filter((i) => i.title.includes(query.value)));
</script>
```

Pitfalls: destructuring a reactive object without `toRefs` (loses reactivity — 3.5 reactive props destructure softens this for props), watchers with side effects that should be computed, and storing large non-reactive objects in `ref` (use `shallowRef`).

## 5. Svelte 5 runes

Runes replace the legacy `$:`/`export let`/`createEventDispatcher` model.

| Rune | Purpose |
| --- | --- |
| `$state` | reactive state; plain objects are deeply reactive |
| `$state.raw` | replace-on-write state for large structures |
| `$derived` / `$derived.by` | computed values |
| `$effect` / `$effect.pre` | side effects tied to reactive reads |
| `$props` | component inputs; `$props.id()` for stable ids |
| `$bindable` | opt-in two-way binding props |
| `$inspect` | dev-only tracing |

SvelteKit: `load` functions for data, form actions for mutations, `+page.server.ts` for server-only logic, adapters per target.

```svelte
<script lang="ts">
  let count = $state(0);
  const doubled = $derived(count * 2);
  let { label = "Count", onchange = (n: number) => {} }: {
    label?: string; onchange?: (n: number) => void;
  } = $props();
</script>
<button onclick={() => { count += 1; onchange(count); }}>{label}: {doubled}</button>
```

Pitfalls: using `$effect` to compute state (use `$derived`), mutating props, mixing runes with legacy stores in new code, and event handlers using legacy `on:click` syntax.

## 6. Angular 20+ signals

Modern Angular is standalone components, signals, and DI via `inject()`.

```ts
import { Component, computed, inject, signal, resource } from "@angular/core";
import { HttpClient } from "@angular/common/http";

@Component({
  selector: "app-users",
  template: `@if (users.isLoading()) { <p>Loading</p> } @for (u of users.value() ?? []; track u.id) { <p>{{ u.name }}</p> }`,
})
export class UsersComponent {
  private http = inject(HttpClient);
  readonly users = resource({ loader: () => fetch("/api/users").then((r) => r.json()) });
}
```

Practices:

- `signal`, `computed`, `effect` for local state; `linkedSignal` when one signal derives from another with local overrides.
- `resource()` for async reads with loading/error states; verify API stability per version.
- Zoneless change detection is the direction of travel; remove `zone.js` when the app is ready and verify per-major support.
- `@if`/`@for`/`@switch` control flow replaces structural directives; `track` is mandatory for loops.
- `inject()` over constructor injection in new code; keep DI tokens typed.
- Forms: typed reactive forms for complex forms; signals integration is evolving — verify upstream.

Pitfalls: reading signals outside reactive contexts, effects that write other signals (use `computed`/`linkedSignal`), and mixing NgModule-era patterns into new standalone code.

## 7. Solid

Signals with fine-grained DOM updates and no virtual DOM.

```tsx
import { createSignal, createMemo } from "solid-js";

function Counter() {
  const [count, setCount] = createSignal(0);
  const doubled = createMemo(() => count() * 2);
  return <button onClick={() => setCount((c) => c + 1)}>{doubled()}</button>;
}
```

Key differences: components run once (no re-render), so destructuring props breaks reactivity (`props.x`, never `const { x } = props`). Use `<Show>`, `<For>`, `<Suspense>`; stores for nested state. Pick Solid for render-heavy UIs where update cost dominates; verify SolidStart ecosystem maturity for full-stack needs.

## 8. Astro

Content-first: ships HTML, hydrates islands on demand.

- Island directives: `client:load`, `client:idle`, `client:visible`, `client:only="react"`.
- Content Layer API (Astro 5+) unifies local and remote content in typed collections; use `getCollection` and schema validation.
- Server islands defer costly dynamic fragments; actions handle form mutations.
- Adapters: Node, Vercel, Netlify, Cloudflare — pick by deployment, not by framework.
- View transitions for MPA-level navigation polish.

Pitfalls: hydrating entire pages with `client:load`, duplicating data fetching between collections and islands, and fighting Astro for SPA-style state — if the app is mostly interactive, choose a different framework.

## 9. Cross-framework concerns

| Concern | Guidance |
| --- | --- |
| Data fetching | framework loader/RSC first; query cache second; never `useEffect` |
| Mutations | server actions/functions where first-class; otherwise route handlers |
| Validation | one schema shared client and server (zod/valibot) |
| Styling | Tailwind, CSS modules, or framework-scoped styles; do not mix three systems |
| State | local first; framework store (Pinia/Zustand/NgRx Signals/Svelte runes) when shared |
| i18n | route-prefix strategy + typed key unions; avoid runtime string maps |
| Error handling | segment-level error boundaries (`error.tsx`, `<svelte:boundary>`, Angular ErrorHandler) |

## Anti-patterns

| Anti-pattern | Framework | Fix |
| --- | --- | --- |
| `"use client"` on layout root | Next.js | move boundary to interactive leaves |
| Implicit caching assumptions | Next.js | declare cache behavior per fetch/tag |
| Destructured reactive props | Vue/Solid | `toRefs` / `props.x` access |
| `$effect` for derived values | Svelte | `$derived` |
| Writing signals inside `effect` | Angular | `computed` / `linkedSignal` |
| Hydrating everything | Astro | island directives by need |
| Framework lock-in in domain code | all | keep domain logic framework-free |

## Checklist

- [ ] Framework chosen against the decision table, documented with reasons.
- [ ] Server/client (or island) boundaries deliberate and minimal.
- [ ] Data loading idiomatic to the framework; no effect-based fetching.
- [ ] Mutations authenticated and validated server-side.
- [ ] Domain logic in framework-agnostic modules with tests.
- [ ] Rendering mode (SSR/SSG/ISR/CSR) decided per route, not globally.
- [ ] Streaming/error boundaries configured for slow segments.

Related: [03-react](./03-react.md) for React depth, [05-runtimes](./05-runtimes.md) for deployment targets, [06-backend-node](./06-backend-node.md) for APIs behind these frontends.
