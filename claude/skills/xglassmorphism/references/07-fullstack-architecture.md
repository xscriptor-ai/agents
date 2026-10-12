# 07 - Fullstack architecture

The glass system is front-end-first, but it touches the whole stack: token
build, SSR, theme persistence, an API, an admin preview, visual regression, CI,
and deployment. This is the reference for wiring it into a real TypeScript
application end to end.

## 1. Monorepo layout

```text
repo/
  apps/
    web/                    # customer-facing app (SSR/static/SPA)
    admin/                  # theme editor + glass playground
  packages/
    design-tokens/          # token source + generator
    glass-css/              # primitive CSS + tokens.css output
    glass-ui/               # typed components (framework-specific or agnostic)
    api-client/             # generated/typed client for the preferences API
  services/
    api/                    # preferences + themes endpoints
  fixtures/
    backdrops/              # worst-case backdrop images for tests
```

Build order is strict: `design-tokens` -> `glass-css` -> `glass-ui` ->
`apps/*`. The `api-client` types must be generated from the same Zod schemas
the API uses, so a token rename fails at compile time on both sides.

## 2. Tokens pipeline

The generator from `./03-design-tokens-and-theming.md` runs as a prebuild step
and as a CI check:

```json
{
  "scripts": {
    "tokens:build": "tsx packages/design-tokens/src/generate.ts",
    "tokens:check": "tsx packages/design-tokens/src/generate.ts --check",
    "prebuild": "pnpm tokens:build"
  }
}
```

`--check` regenerates into memory and diffs against the committed artifacts;
CI fails on drift. Committed artifacts: `tokens.css`, `tokens.json`, and the
Tailwind `@theme` block.

Cache busting: emit `tokens.[contenthash].css` in the app build, or import the
generated file into the bundler so the hash is automatic.

## 3. SSR, theme detection, and no flash

The theme must be known before first paint. Two-phase approach:

1. **Server**: read the theme cookie and render `<html data-theme="dark">`.
2. **Client, pre-hydration**: a tiny blocking script reconciles localStorage
   and system preference, only if the cookie is absent or stale.

```ts
// apps/web/src/theme/bootstrap.ts (inlined in <head> by the bundler)
const storageKey = "xglass.theme";

function resolveTheme(): "light" | "dark" {
  const stored = localStorage.getItem(storageKey);
  if (stored === "light" || stored === "dark") return stored;
  return matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

document.documentElement.dataset.theme = resolveTheme();
```

```html
<script>
  /* inlined bootstrap, must run before the stylesheet renders */
</script>
```

Notes:

- CSP: inline scripts require a nonce or hash. Generate the nonce per request
  and add it to both the CSP header and the script tag. Do not weaken the CSP
  to `unsafe-inline`.
- The bootstrap script is the only inline script in the system; keep it
  minimal and deterministic.
- During SSR, default to the cookie; if there is no cookie, use the `Sec-CH-Prefers-Color-Scheme`
  client hint when the platform sends it, otherwise render light and let the
  bootstrap correct before paint.
- Static export: the bootstrap is the only mechanism (no server), so it must be
  in the exported HTML head, not in a module.

## 4. Glass preferences API

Model user-visible glass settings as data, not client-only state:

```ts
// packages/api-client/src/schemas.ts
import { z } from "zod";

export const glassLevel = z.enum(["off", "thin", "regular", "thick"]);
export const themeMode = z.enum(["system", "light", "dark"]);

export const preferencesSchema = z.object({
  theme: themeMode.default("system"),
  accent: z.string().regex(/^oklch\(/).default("oklch(0.62 0.17 262)"),
  glassLevel: glassLevel.default("regular"),
  reducedTransparency: z.boolean().default(false),
  reducedMotion: z.boolean().default(false),
});

export type Preferences = z.infer<typeof preferencesSchema>;
```

Endpoints:

```text
GET    /api/preferences          -> Preferences
PUT    /api/preferences          -> Preferences (validated, partial merge)
DELETE /api/preferences          -> reset to defaults
```

Implementation rules:

- Validate on the server with the same schema the client uses; never trust the
  client for token-critical values.
- Store `reducedTransparency` and `reducedMotion` as explicit user intent,
  separate from OS queries; the effective value is `userSetting || osQuery`.
- Return an `ETag`; preferences change rarely and are read on every page load.
- The API is tiny; keep it in the same app (Next.js route handlers, SvelteKit
  endpoints) unless the product already has a separate service.

Cookie strategy for SSR: mirror only `theme` and `glassLevel` into a readable
(non-httpOnly) cookie, because the pre-hydration script needs them. Everything
else can stay server-side.

## 5. Persistence schema

```sql
create table user_preferences (
  user_id              text primary key references users(id) on delete cascade,
  theme                text not null default 'system'
                       check (theme in ('system', 'light', 'dark')),
  accent               text not null default 'oklch(0.62 0.17 262)',
  glass_level          text not null default 'regular'
                       check (glass_level in ('off', 'thin', 'regular', 'thick')),
  reduced_transparency boolean not null default false,
  reduced_motion       boolean not null default false,
  updated_at           timestamptz not null default now()
);
```

Rules:

- One row per user; upsert on write.
- Add an audit table if the admin can publish themes: `theme_revisions(id,
  author_id, payload jsonb, created_at)`.
- Do not store derived values (computed tints, contrast results). Store intent;
  derive with tokens at render time.

## 6. Theme publishing and admin preview

When designers can edit tokens:

1. **Draft**: token JSON edited in the admin app (`apps/admin`), validated
   against a schema that mirrors `design-tokens`.
2. **Preview**: render inside an iframe pointed at the real app with
   `?previewTheme=<revisionId>`; the app loads the draft token JSON before
   first paint (same bootstrap mechanism) and sets `data-preview="true"`.
3. **Publish**: write a `theme_revisions` row and invalidate the public token
   JSON cache.
4. **Rollback**: republish a previous revision; the public token JSON is
   immutable per revision.

```ts
// iframe preview handshake
const frame = document.querySelector<HTMLIFrameElement>("#preview");
frame?.contentWindow?.postMessage(
  { type: "xglass:preview", tokens: draftTokens },
  window.location.origin,
);
```

Validate `event.origin` on the receiving side. The preview route must never be
indexable and must be excluded from caching.

Publishing tokens is a security boundary: treat token values as untrusted
input (`url()` values, `expression()`-like payloads). Validate that color and
length tokens match strict patterns before persisting.

## 7. Rendering strategy per app type

| App type | Glass strategy |
|----------|----------------|
| SSR (Next.js, Nuxt, SvelteKit) | Emit full CSS; theme from cookie; glass in the server-rendered markup so first paint is final |
| Static export | Same, plus inline bootstrap; verify with JS disabled that the opaque fallback is readable |
| SPA | Bootstrap theme in `index.html`; lazy-mount below-fold glass; prefetch token CSS |
| Islands (Astro) | Static glass by default; hydrate only interactive glass (command palette, menus) |
| Tauri (desktop) | Same web build; runtime flag swaps window-level glass to native vibrancy (see `./08-tauri-packaging.md`) |

Glass must never depend on client JavaScript to be legible. The fallback is a
CSS baseline, not a hydrated state.

## 8. Testing

### Unit

- Token snapshot: generated CSS matches committed artifacts.
- Contrast tests using the utility from `./05-accessibility-and-legibility.md`,
  run against a fixture palette of worst-case backdrops.
- Component render tests asserting variant classes.

### Integration

- Preference API round-trip with schema validation and ETag behavior.
- SSR render with each theme cookie asserts `data-theme` on `<html>`.

### Visual regression

Playwright with fixed backdrops:

```ts
// tests/visual/glass.spec.ts
import { test, expect } from "@playwright/test";

const themes = ["light", "dark"] as const;
const backdrops = ["plain", "busy", "brand"] as const;

for (const theme of themes) {
  for (const backdrop of backdrops) {
    test(`glass surfaces: ${theme} over ${backdrop}`, async ({ page }) => {
      await page.goto(`/fixtures/glass?theme=${theme}&backdrop=${backdrop}`);
      await page.emulateMedia({ reducedMotion: "reduce" });
      await expect(page).toHaveScreenshot(`glass-${theme}-${backdrop}.png`, {
        animations: "disabled",
        maxDiffPixelRatio: 0.01,
      });
    });
  }
}
```

Fixtures required: plain, busy (high-frequency photo), brand (saturated
gradient), and a scroll extreme of each. Store the backdrops in
`fixtures/backdrops/` so they are deterministic across machines.

### Accessibility in CI

- axe scan per fixture for structural issues (noting its contrast blind spots).
- A keyboard test tabbing through sticky glass asserting the focused element
  is not obscured (`document.elementFromPoint` over the focus ring center).

## 9. CI pipeline

```yaml
name: ci
on: [push, pull_request]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - run: pnpm install --frozen-lockfile
      - run: pnpm tokens:check
      - run: pnpm typecheck
      - run: pnpm test
      - run: pnpm --filter web build
      - run: pnpm exec playwright install --with-deps chromium firefox webkit
      - run: pnpm test:visual
```

Order matters: token drift first, then types, then tests, then build, then
visual. Add a budget check step that fails when
`countGlassSurfaces()` (from `./06-performance-and-browser-support.md`)
exceeds the per-route maximum.

## 10. Deployment

- Static/CDN: serve hashed token CSS with `immutable` caching; the HTML must
  reference theme state without a server round-trip.
- The preferences API gets its own cache policy: `private, max-age=0,
  must-revalidate` with ETag.
- Feature-flag new glass levels (`glassLevel: "regular-v2"`) so rollouts can
  revert without a deploy.
- Monitor Core Web Vitals (INP especially) per theme; glass regressions show up
  as INP spikes, not CLS.
- Tauri builds use the same web bundle; desktop packaging and native effects
  are covered in `./08-tauri-packaging.md`.

## 11. Anti-patterns

- Tokens generated at runtime in the browser instead of build time.
- Theme stored only in localStorage: SSR renders the wrong theme and users see
  a flash.
- Two sources of truth for schema (Zod vs TypeScript interfaces drifting).
- Admin preview that writes directly to production tokens with no revision or
  rollback.
- Visual regression tests that only cover the default backdrop.
- Enabling glass for all users at once with no flag.
- Shipping the inlined theme bootstrap without a CSP nonce.

## 12. Related

- `./03-design-tokens-and-theming.md` - the token source this pipeline builds.
- `./05-accessibility-and-legibility.md` - the contrast tests used in CI.
- `./06-performance-and-browser-support.md` - the performance budgets.
- `./08-tauri-packaging.md` - the desktop target of the same build.
