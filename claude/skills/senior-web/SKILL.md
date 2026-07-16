---
name: senior-web
description: Deep web patterns for full-stack architecture, state management, CSS,
  performance, accessibility, and edge
---

# Web

## Full-Stack Architecture Patterns

| Pattern | Use Case | Examples |
|---------|----------|----------|
| Server-rendered SPA | SEO + interactivity | Next.js App Router, Nuxt 3 |
| Static site | Content sites | Astro, 11ty, Hugo |
| API + SPA | Decoupled frontend/backend | Vite + Express, Remix |
| Islands | Partial hydration | Astro, Fresh, Qwik |

## Server Components vs Client Components (React)

```typescript
// Server Component - runs on server, no client JS
// app/page.tsx
async function Page() {
  const data = await db.query(); // direct DB access
  return <div>{data.map(item => <Item key={item.id} item={item} />)}</div>;
}

// Client Component - interactive, runs in browser
"use client";
function Counter() {
  const [count, setCount] = useState(0);
  return <button onClick={() => setCount(c => c + 1)}>{count}</button>;
}
```

- Server components: direct data access, smaller bundles, no state/hooks.
- Client components: interactivity, browser APIs, state.
- Data flows down from server to client via props.

## State Management Across Frameworks

| Framework | Local | Global | Server |
|-----------|-------|--------|--------|
| React | useState/useReducer | Zustand, Jotai | TanStack Query, SWR |
| Vue | ref/reactive | Pinia | TanStack Query |
| Angular | Signals | NgRx, SignalStore | Angular HTTP |

## CSS Architecture

### Tailwind
```html
<div class="flex items-center gap-4 p-6 rounded-xl shadow-sm bg-white">
  <h2 class="text-lg font-semibold text-gray-900">Title</h2>
</div>
```

### CSS Modules
```css
/* Button.module.css */
.primary { background: var(--color-primary); }
```

### CSS-in-JS (styled-components / vanilla-extract)
```typescript
import { style } from "@vanilla-extract/css";
export const button = style({
  background: "var(--color-primary)",
  padding: "12px 24px",
});
```

## Web Performance

### Core Web Vitals
- **LCP** < 2.5s: Optimize images (next/image, lazy loading), preload fonts.
- **FID / INP** < 200ms: Avoid long tasks, use `requestIdleCallback`.
- **CLS** < 0.1: Set explicit dimensions on images/embeds.

### RAIL Model
- **Response**: < 50ms (user input to visual feedback).
- **Animation**: < 10ms per frame (60fps).
- **Idle**: Use idle time for deferred work.
- **Load**: < 5s initial load (3s on mobile).

### Optimization
```typescript
// Dynamic import for code splitting
const HeavyComponent = dynamic(() => import("./Heavy"), { ssr: false });

// Preload critical resources
<link rel="preload" href="/font.woff2" as="font" crossorigin />
```

## Accessibility (WCAG 2.2 AA)

- Semantic HTML: `<nav>`, `<main>`, `<aside>`, `<button>`.
- ARIA: `aria-label`, `aria-describedby`, `role="alert"`.
- Keyboard: all interactive elements focusable, visible focus rings.
- Color contrast: 4.5:1 (normal text), 3:1 (large text).
- Testing: axe-core (axe DevTools), Lighthouse, screen reader testing.

## Progressive Web Apps

```json
// manifest.json
{
  "name": "App",
  "start_url": "/",
  "display": "standalone",
  "icons": [{ "src": "/icon-192.png", "sizes": "192x192" }]
}
```

```typescript
// Service Worker (Workbox)
import { precacheAndRoute } from "workbox-precaching";
precacheAndRoute(self.__WB_MANIFEST);
```

## Edge Computing

- **Vercel Edge Functions**: < 50ms cold start, 1MB limit.
- **Cloudflare Workers**: Isolates, 10MB script size, Workers KV / D1 / R2.
- **Deno Deploy**: V8 isolates, Deno runtime.
- Use edge for: auth checks, header rewriting, geo-routing, A/B testing.
