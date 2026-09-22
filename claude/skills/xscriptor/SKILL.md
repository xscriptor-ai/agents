---
name: xscriptor
description: Full design and development documentation for xscriptor.com, the Xscriptor
  literary portfolio (Next.js 16 App Router, static export, five locales, four book-reader
  engines, decryption animations). Use when building or modifying pages, components,
  CSS, content, i18n, book readers, or the build/deploy of xscriptor.com.
allowed-tools: Read, Glob, Grep, Edit, Write, Bash
---

# Xscriptor Site System

`xscriptor.com` is the personal literary portfolio, blog, book library and art
surface of the author/artist **Xscriptor** (Óscar Preciado). It is a **fully
static, multilingual Next.js 16 App Router** site whose signature interaction is
text that decrypts character by character, set in EB Garamond over full-bleed
art.

This skill documents the whole system — design language, architecture, routes,
components, content pipeline, book readers, i18n, theming, SEO, security and
deployment — so an agent can extend the site without breaking its voice or its
conventions.

Repository: `github.com/xscriptor-web/xscriptor.com` (branch `main`). The Next
app lives at the repository root.

## Companion references

Read the one(s) relevant to the task; they are the detailed source of truth.

| Reference | Covers |
|-----------|--------|
| `references/design-system.md` | Brand intent, color tokens, typography, surfaces (glass/neumorphism/marker chips), motion language, breakpoints, a11y |
| `references/architecture.md` | Stack, rendering model, route table, providers, i18n, theme, SEO, security, gotchas |
| `references/component-catalog.md` | Every component: location, props, behavior, recipes |
| `references/content-pipeline.md` | Blog article pipeline, book MDX format, `poemParser`, `messages` + `WordConfig` |
| `references/book-readers.md` | The four reader engines and their parsing/pagination algorithms |
| `references/build-and-deploy.md` | Scripts, static export, sitemap, `.htaccess`/`_headers`, hosting, validation |
| `references/code-structure.md` | Where code goes, responsibilities, import rules, anti-patterns, debt |

## When to use this skill

- Adding or editing any page, section or route on xscriptor.com.
- Building or refactoring components, CSS modules, or global styles.
- Working on the book readers, blog pipeline, graph, contact/PGP page or home hero.
- Adding articles, books, translations or UI strings.
- Touching i18n, theming, SEO/metadata, static export or deployment config.
- Anything that must stay visually and structurally consistent with the site.

---

## 1. Design intent (the part that matters most)

The site must read like **a printed literary edition that has learned to
decrypt itself**. Concretely:

- **Typography-first.** EB Garamond carries everything. No display font, no icon
  font. Words are the interface.
- **Marker aesthetic.** Text over imagery sits on soft `color-mix` chips so it
  stays legible.
- **One accent per theme.** Deep violet (`#5b2e8d`) in light, warm gold
  (`#ffe884`) in dark. Everything else is background/text/border.
- **Atmospheric art.** Full-viewport photographs and pre-rendered background
  frames behind a dark overlay; the art is the stage, never the subject.
- **Motion reveals, it does not decorate.** Decryption, blur-to-focus, staggered
  fades, a scroll-drawn connecting line.
- **Literary + cryptographic tension.** Poetic prose next to PGP fingerprints and
  descrambling text is the brand, not a gimmick.
- **Both themes first-class; accessible by default; static by default.**

If a proposed UI is clever but reads as generic SaaS, reject it. Choose clarity
and voice over novelty.

---

## 2. Tech stack at a glance

| Layer | Choice |
|-------|--------|
| Framework | **Next.js 16.3** App Router, `output: "export"`, `trailingSlash: true` |
| Language | TypeScript 5 (`strict`), React 19.2, some JS |
| Styling | Tailwind CSS 4.3 (PostCSS) **+ CSS Modules** |
| Font | Self-hosted **EB Garamond** (Regular + Italic, woff2) |
| Motion | `framer-motion` 12 |
| Smooth scroll | `lenis` 1.3 |
| Content | Markdown/MDX + `gray-matter` + `remark`/`rehype` (GFM, KaTeX, highlight) |
| Components | `@xscriptor/xcomponents` (npm) + local copies |
| Backgrounds | `@xscriptor/xbackgrounds` (`XParticles`) |
| Sitemap | `next-sitemap` on `postbuild` |
| Hosting | Static (Apache `.htaccess`, or `_headers` platforms) |

No server runtime, no API routes, no PHP, no env vars. Details in
`architecture.md` §1.

---

## 3. Rendering model in one minute

- **Everything is pre-rendered.** `page.tsx` files are Server Components; book
  pages read MDX from disk at build time and pass raw text to client readers.
- **Interactive code is `"use client"`**, including the `"use client"` barrel at
  `src/app/components/xcomponents/index.ts`. Server Components must import
  reusable components **only** via that barrel.
- **Two locales layers:** the root layout hardcodes `es` (so `/` is Spanish); the
  `[locale]` layout mounts a nested `I18nProvider` with the requested locale.
- **Providers wrap the app** in the root layout: `LenisProvider` (smooth scroll),
  `TransitionProvider` (glass navbar + language dock + route overlay), then
  separators, `main`, footer.
- **Theming** uses `data-theme` on `<html>` + `localStorage["theme"]`, applied
  before first paint by a `beforeInteractive` script and toggled by the navbar
  logo.

Full detail: `architecture.md` §2–§7.

---

## 4. Route map (summary)

All pages live under `[locale]` (`es`, `en`, `de`, `it`, `fr`; `es` fallback):

| Path | What |
|------|------|
| `/` and `/[locale]` | Home hero (ASCII intro → zigzag phrases) |
| `/[locale]/blog` | Article listing (search + category pills, center-blur cards) |
| `/[locale]/blog/[...slug]` | Article (markdown → KaTeX/highlight → decrypt) |
| `/[locale]/obras` | Book gallery (center-blur cards + graph card) |
| `/[locale]/obras/{boulevard,asintota,cielos-de-alquitran,colaterales,primavera-en-el-desierto,la-danza-de-las-amapolas}` | Book readers |
| `/[locale]/obras/grafo` | Canvas poem graph |
| `/[locale]/contacto` | PGP public-key card + social grid |
| `/[locale]/info` | Bio, press cards, timeline |
| `/[locale]/links` | Link list |
| `/[locale]/terminos-y-condiciones` | Terms/privacy/cookies |
| 404 | `src/app/not-found.tsx` |

Exact files and data sources: `architecture.md` §3.

---

## 5. The design system (essentials)

Full token tables and rules in `design-system.md`. The non-negotiables:

### Colors — use the variables, never raw hex

Light: `--bg #ffffff`, `--text #000000`, `--accent #5b2e8d`,
`--accent-text #ffffff`, `--border rgba(0,0,0,.1)`, `--foreground #171717`,
`--text-muted #6b7280`, `--primary #4328a8`, `--primary-hover #7c3aed`,
`--success #10b981`.

Dark (`:root[data-theme="dark"], :root.dark`): `--bg #0a0a0a`, `--text #ffffff`,
`--accent #ffe884`, `--accent-text #000000`, `--border rgba(255,255,255,.1)`,
`--foreground #ededed`, `--text-muted #9ca3af`, `--primary #fbbf24`,
`--primary-hover #f59e0b`, `--success #34d399`.

Only sanctioned raw hexes: the book word palette (`c1`–`c5`) and the graph’s
8-color palette.

### Type

EB Garamond everywhere. Global centered defaults: `h1` 400/`clamp(16px,12vw,32px)`,
`h2` 300/`clamp(24px,8vw,26px)`, `h3` 600/`clamp(20px,9vw,26px)`,
`p` 400/`clamp(18px,2.5vw,20px)` with side padding `clamp(1rem,8vw,4rem)`.
`.article-content` resets prose to left-aligned, `line-height 1.8`. Monospace is
only for code/keys/meta.

### Marker chip (the signature atom)

```css
background: color-mix(in srgb, var(--bg) 88%, transparent);
padding: 0.1em 0.35em; border-radius: 0.2em;
box-decoration-break: clone; -webkit-box-decoration-break: clone;
```

### Glass

`color-mix(in srgb, var(--bg) 70%, transparent)` (light) / `15%` (dark) +
`backdrop-filter: blur(18–20px)` + `1px solid var(--border)`.

### Neumorphism

Only `PublicKeyCard`, via `--neumorph-bg` and `:root.light` / `:root.dark`.

### Motion

Subtle, brief, purposeful; reveal not decorate. Respect
`prefers-reduced-motion` (global rule + component guards). Decrypt speed default
50 ms (article body 10 ms). See `design-system.md` §6.

---

## 6. The book reader engines (choose deliberately)

Four engines share the block/section/index/4-5-per-page model but differ:

| Engine | Books | Signature |
|--------|-------|-----------|
| `XBookReader` (npm) | Boulevard | simplest paginated reader |
| `XCompleteBook` (npm, via barrel) | Asintota, Amapolas | section/index pages + `renderPoem` override |
| `XBookColors` (local) | Cielos de Alquitrán, Primavera, Amapolas page | rotating full-bleed backgrounds + per-word colors/decrypt |
| `BookReaderPoems` (local) | Colaterales | index-driven poem reordering + titles |

Poem words become `WordConfig[]` with hashed `underline`/`button`/`blur1`/
`blur2`/`normal` types plus a safety fallback so blurred words are always
revealable. Deep dive, parsing algorithms and pitfalls: `book-readers.md`.

---

## 7. Content & i18n essentials

- **Blog**: `src/app/content/articulos/{locale}/**/*.md`; parsed by
  `src/app/lib/articles.ts` (frontmatter → markdown → GFM/KaTeX/highlight → HTML;
  duplicate H1/author stripped; soft lines → `<br>`; tables wrapped;
  `readingTime = ceil(words/200)`); `es` fallback; `research/` excluded from
  listings.
- **Books**: `src/app/content/<book>/{locale}.mdx`, read as raw text
  (`cielos-de-alquitran` ES file is `cielos-de-alquitran.mdx`).
- **UI strings**: `messages/{locale}.json`, namespaced; consume with
  `useT(namespace)` (client) or `getMsg` (server); add keys to **all five**
  locales.
- **`HomePhrases`** holds `WordConfig[]` arrays consumed by `XHomeColors`.
- **Graph**: `src/lib/poemParser.ts` aggregates all books + flat blog articles.
- Full contracts and checklists: `content-pipeline.md`.

---

## 8. Components (quick index)

Barrel import surface: `import { ... } from "@/app/components/xcomponents"`.

- **npm**: `XNavbar`, `XFooter`, `XSeparator`, `XZigZagLayout`, `XBookReader`,
  `XBookReaderIllus`, `XInteractivePhrase`, `XDecryptedText`, `XCompleteBook`,
  `XBookFullDecrypt`, `XContactForm`, `XNewsletter`, `XSocialContact`.
- **local reusable**: `XGlassNavbar`, `XZigZagLayoutVideo`, `XHomeColors`,
  `XBookColors`, `BookReaderPoems`, `XMinimalFooter`.
- **app-level**: `ClientComponentHome`, `AsciiLoadingAnimation`, `LenisProvider`,
  `transitionProvider`, `ConditionalSeparator`, `XFooterComponent`,
  `PublicKeyCard`, `SocialGrid`, `ParticlesBackground`, `BlogListClient`,
  `ObrasClientPage`, `XBlogDecrypt`, `XTextDecrypt`, `GrafoPoetico`, reader
  wrappers (`AsintotaBook`, `CielosDeAlquitranBook`, `AmapolasBook`),
  `navbarIcons`.

Props, behavior and recipes: `component-catalog.md`.

> `XContactForm`, `XNewsletter` and `XSocialContact` are re-exported but **not
> rendered** by any page today; there is no newsletter backend. Don’t assume they
> are wired up.

---

## 9. Build & deployment

```bash
npm install
npm run dev            # http://localhost:3000
npx tsc --noEmit       # authoritative type check (next lint is flaky on Next 16)
npm run build          # next build → out/ + postbuild next-sitemap
```

- Static export to `out/`; `robots.txt` + sitemaps are **generated**.
- Security headers live in `public/.htaccess` (Apache: HSTS, CSP, nosniff,
  frame/referrer/permissions, sensitive-file block, cache, deflate) and
  `public/_headers` (subset for `_headers` platforms). `'unsafe-inline'` is
  required by the static export.
- `public/x-public.asc` is fetched at runtime by `PublicKeyCard`.
- Background frame counts must match each reader’s `TOTAL_BG`
  (asintota 72, amapolas 31, cielos 30).

Details and failure modes: `build-and-deploy.md`.

---

## 10. Conventions & guardrails

1. **Use tokens**, not raw colors (except the documented palettes).
2. **Text over art goes on a marker chip.**
3. **Import reusable components via the `"use client"` barrel.**
   Never import `@xscriptor/xcomponents` directly in a Server Component.
4. **Never fork npm components locally** — update `@xscriptor/xcomponents` and
   bump the version. Re-apply the patches in `docs/xcomponents-fixes.md` if you
   upgrade.
5. **Pages are thin server components**; interactivity lives in client
   components.
6. **Copy goes in `messages/*.json` for all five locales** (plus the documented
   in-component dictionaries where they exist).
7. **Add keys to every locale** and, for content, add the same slug across
   locale folders.
8. **Respect `prefers-reduced-motion`** in any new animation.
9. **Use `clamp()`** for fluid padding; avoid bare `vw`.
10. **No runtime/server features** (route handlers, middleware, revalidate).
11. **Validate before finalizing**: `npx tsc --noEmit` then `npm run build`.
12. **Don’t commit secrets** (there are none by design).

### Known gotchas (see `architecture.md` §11 / `code-structure.md` §6)

- Locale list is duplicated in ~9 files; the footer and 404 only handle
  `en|es|de` and fall back to Spanish for `it`/`fr`.
- Two UI-text systems (messages vs in-component dictionaries) must be kept in
  sync.
- A local unreferenced `xcompletebook/XCompleteBook.tsx` duplicate exists.
- `gsap` and `react-intersection-observer` are installed but unused in app code.
- Global `a:hover { color:#ff4141 }` fights accent links.
- `.htaccess` blocks direct `.json`/`.md` serving (fine for this build).

---

## 11. Editing recipe (agent checklist)

1. **Locate** the route entry and its client component; read the matching
   reference (`component-catalog.md`, `book-readers.md`, …).
2. **Plan** against the design system: tokens, marker chips, motion budget.
3. **Implement** at the right layer (route vs reusable vs lib vs content vs
   messages).
4. **Localize** every string across the five locales; add content slugs in all
   five folders.
5. **Verify** light/dark, `<768px`, and reduced-motion.
6. **Type-check** with `npx tsc --noEmit`, then **build** with `npm run build`.
7. **Report** what changed and any structural debt you encountered.

---

## 12. Output expectations

A correct change to this site is:

- structurally consistent with the existing layers and import rules,
- visually quiet, typography-driven, on the marker/glass system,
- correct in light **and** dark themes and on mobile,
- localized in all five languages,
- accessible (sr-only text for decrypt animations, focus states, reduced motion),
- static-export-safe,
- and easy for a human to maintain afterwards.

If a solution is clever but harder to keep consistent with the above, reject it.
