---
name: xscriptor
description: Full-stack documentation for the Xscriptor literary portfolio site. Invoke when extending pages, refactoring components, managing content, or modifying the build pipeline.
version: 1.0.0
allowed-tools: [Read, Glob, Grep, Edit, Write]
---

# Xscriptor Site System

This skill documents the complete architecture of xscriptor.com -- a personal literary portfolio, blog, and art gallery built with Next.js 16 App Router and statically exported.

Companion references:

- `references/code-structure.md`: preferred file placement, responsibilities, and anti-patterns

Use this skill when:

- building new pages or sections (blog, books, info, contact)
- refactoring layout, CSS, or component boundaries
- adding or updating content (articles, book pages)
- modifying the blog pipeline or markdown processing
- making UI changes that must stay visually consistent
- configuring the static export or build process

---

## 1. Core Design Intent

The site is a personal literary portfolio for an author, poet, and artist. It must balance:

- **literary elegance** -- typography-driven, generous whitespace, restrained color
- **content-first** -- text is primary; UI decorates, never dominates
- **dark-mode aware** -- full light/dark theme with smooth transitions
- **static by default** -- every page is pre-rendered; no server runtime in production

---

## 2. Tech Stack

| Layer | Choice |
|-------|--------|
| Framework | Next.js 16 App Router |
| Language | TypeScript + JavaScript (`.jsx` in legacy pages) |
| CSS | Tailwind CSS v4 + CSS Modules |
| Animations | framer-motion (page transitions, cards), GSAP (ImageTrail) |
| Content | Markdown + gray-matter + remark/rehype pipeline |
| Blog | Static (`/blog/[slug]`) + PHP-backed (`/blog/post?slug=`) |
| Theme | `data-theme` attribute + localStorage |
| Icons | Custom SVG components in `@xscriptor/xcomponents` |
| Build | Static export (`output: "export"`) |
| Hosting | Apache with PHP (Hostinger) |
| External lib | `@xscriptor/xcomponents` (npm, v0.1.3) |

---

## 3. Project Structure

```
xscriptor/
  src/
    app/
      layout.tsx                    -- root layout (html, metadata, theme, fonts)
      page.tsx                      -- home page (delegates to ClientComponentHome)
      globals.css                   -- Tailwind v4 import + theme variables + keyframes

      [locale]/                     -- i18n locale group route
        layout.tsx                  -- locale-aware layout with I18nProvider
        page.tsx                    -- localized home
        blog/
          page.tsx                  -- localized blog index (reads locale param)
          [slug]/page.tsx           -- localized article page (locale param + fallback)
        contacto/page.tsx           -- localized contact form + social
        info/page.tsx               -- localized bio, press, timeline
        obras/
          page.tsx                  -- localized book gallery
          literatura/
            page.tsx                -- localized literature landing
            boulevard/page.tsx      -- localized boulevard reader (3 langs)
            asintota/page.tsx       -- under construction (3 langs)
            colaterales/page.tsx    -- under construction (3 langs)
            primavera-en-el-desierto/page.tsx -- under construction (3 langs)
            cielos-de-alquitran/page.tsx -- under construction (3 langs)
        terminos-y-condiciones/page.tsx -- localized terms

      blog/                         -- blog section (Spanish fallback)
        page.tsx                    -- blog index
        [slug]/page.tsx             -- static article page

      obras/                        -- books section (Spanish fallback)
        page.tsx                    -- book gallery
        literatura/
          boulevard/page.tsx        -- boulevard reader (Spanish)
          asintota/page.tsx         -- under construction
          colaterales/page.jsx      -- under construction
          primavera-en-el-desierto/page.tsx -- under construction
          cielos-de-alquitran/page.jsx -- under construction

      contacto/page.tsx             -- contact form (localized via I18nProvider)
      info/page.tsx                 -- bio, press, timeline (localized)
      terminos-y-condiciones/page.jsx -- terms (localized)

      api/subscribe/guardar_email.php  -- newsletter PHP endpoint

      components/                   -- shared local components
        xcomponents/
          index.ts                  -- "use client" barrel re-exporting @xscriptor/xcomponents
          xsocialcontact/
            SocialIcons.tsx         -- custom SVG icons (not in npm)
        UnderConstruction.tsx       -- reusable under-construction component
        ArticlesGrid.tsx            -- article card grid (accepts emptyText prop)
        clientcomponenthome.tsx     -- home page client component (phrases, videos, newsletter)
        transitionProvider.tsx      -- page transition wrapper

      content/
        articulos/                  -- blog articles by locale
          es/*.md                   -- 11 Spanish articles
          en/*.md                   -- 11 English translations
          de/*.md                   -- 11 German translations
        boulevard/
          es.mdx                    -- boulevard book content (Spanish)
          en.mdx                    -- boulevard book content (English)
          de.mdx                    -- boulevard book content (German)

      lib/
        articles.ts                 -- locale-aware markdown parsing pipeline

  messages/                         -- i18n JSON message files
    es.json                         -- Spanish (898+ lines)
    en.json                         -- English
    de.json                         -- German

  public/
    images/                         -- static images
    .htaccess                       -- Apache rewrite rules + security headers (CSP, HSTS, etc.)
    robots.txt                      -- auto-generated by next-sitemap
    sitemap.xml                     -- auto-generated by next-sitemap
```

---

## 4. Component System

### Source of truth: `@xscriptor/xcomponents` (npm)

All reusable UI components come exclusively from the `@xscriptor/xcomponents` npm package. **No local copies exist.**

The only local file is a barrel re-exporter at `src/app/components/xcomponents/index.ts`:

```tsx
"use client";
export { XNavbar } from "@xscriptor/xcomponents";
export { XFooter, XSeparator, XZigZagLayout } from "@xscriptor/xcomponents";
export { XBookReader, XBookReaderIllus, XInteractivePhrase } from "@xscriptor/xcomponents";
export { XContactForm, XNewsletter, XSocialContact } from "@xscriptor/xcomponents";
```

This file exists for one reason: the npm package's bundled dist (`chunk-*.mjs`) does **not** preserve the `"use client"` directive. Server Components (pages that use `fs.readFileSync`, like boulevard, primavera) cannot import client-hook-dependent components directly from the npm bundle without hitting `useState is not a function` errors. The barrel file adds the `"use client"` boundary that Next.js needs.

#### Exception

`src/app/components/xcomponents/xsocialcontact/SocialIcons.tsx` — custom SVG icon components (TelegramIcon, WhatsappIcon, etc.) that are not part of the npm package. Keep this file; delete everything else inside `xcomponents/`.

#### Component table

| Component | Where it comes from |
|-----------|---------------------|
| XNavbar | `@xscriptor/xcomponents` via barrel |
| XFooter | `@xscriptor/xcomponents` via barrel |
| XContactForm | `@xscriptor/xcomponents` via barrel |
| XSocialContact | `@xscriptor/xcomponents` via barrel |
| XNewsletter | `@xscriptor/xcomponents` via barrel |
| XInteractivePhrase | `@xscriptor/xcomponents` via barrel |
| XSeparator | `@xscriptor/xcomponents` via barrel |
| XZigZagLayout | `@xscriptor/xcomponents` via barrel |
| XBookReader | `@xscriptor/xcomponents` via barrel |
| XBookReaderIllus | `@xscriptor/xcomponents` via barrel |
| SocialIcons (TelegramIcon, etc.) | local only (`xsocialcontact/SocialIcons.tsx`) |

#### Important rules

- **Never** copy a component from npm into `xcomponents/`. If you need to modify a component, update `@xscriptor/xcomponents` and bump the version.
- The barrel file must remain `"use client"` — do not remove that directive.
- When adding a new component from npm to the barrel, add its re-export line to `index.ts`.
- `XBookReader` and `XBookReaderIllus` accept only `{ rawText, coverImage? }` — no `coverAlt`, `prevLabel`, `nextLabel`, `pageOfLabel`. Pagination text is hardcoded in Spanish.
- When importing in a page, use `import { Component } from "@/app/components/xcomponents"` (the barrel), **not** the npm direct path.

### Component conventions

- Tailwind utility classes are preferred for layout and spacing in pages.
- Components from `@xscriptor/xcomponents` handle their own styles internally.
- No CSS Modules are needed at the `xcomponents/` level — all styling comes from the npm package.

---

## 5. Content Management

### Articles (blog)

Markdown files live in `src/app/content/articulos/` with frontmatter:

```yaml
---
title: "Article Title"
date: "2024-01-01"
description: "A short summary"
tags: ["literature", "philosophy"]
image: "/images/articles/og-image.jpg"
---
```

Parsed by `src/app/lib/articles.ts` using:
- `gray-matter` for frontmatter
- `remark` + `remark-html` for markdown to HTML
- `remark-math` + `rehype-katex` for LaTeX math rendering

### Books

Each book has its own page under `src/app/obras/literatura/`. Pages use `.mdx` (boulevard) or direct `.tsx`/`.jsx` content. The `XBookReader` component provides paginated reading with page-turn animations.

### Blog dual system

| Route | Type | Data Source |
|-------|------|-------------|
| `/blog/[slug]` | Static (SSG) | Local markdown files via `getArticleData()` |
| `/blog/post?slug=X` | Client-side fetch | PHP endpoint returning HTML |

The static route is the primary system. The PHP-backed route is a legacy fallback for dynamic content that could not be pre-rendered.

---

## 6. Styling Conventions

### Tailwind v4

- `globals.css` uses `@import "tailwindcss"` (v4 syntax).
- `tailwind.config.ts` still exists but is inert for v4 (kept for editor support).
- No `@apply`, no `@tailwind base/components/utilities` directives.

### Theme variables

Defined in `globals.css` under `:root` and `[data-theme="dark"]`:

```css
:root {
  --background: #fafaf9;
  --foreground: #1c1917;
  --primary: #b45309;
  --muted: #78716c;
  --border: #e7e5e4;
  --card-bg: rgba(255, 255, 255, 0.7);
}

[data-theme="dark"] {
  --background: #0c0a09;
  --foreground: #f5f5f4;
  /* ... */
}
```

### CSS Modules

- Page-specific layouts use `*.module.css` files colocated with the route.
- Component styles use `*.module.css` inside the component folder.
- Global styles, keyframes, and theme tokens stay in `globals.css`.

---

## 7. Theme System

- Toggle stored in `localStorage` as `data-theme` (values: `"light"`, `"dark"`).
- Applied via `data-theme` attribute on `<html>`.
- Script in layout sets the attribute before first paint to prevent flash.
- Tailwind uses `dark:` variants alongside CSS custom properties.

---

## 8. Animation Patterns

| Library | Usage |
|---------|-------|
| framer-motion | Page transitions (`AnimatePresence`), card hover effects, staggered reveals, scroll-triggered animations |
| GSAP | `ImageTrail` component (8 visual variants with canvas and DOM-based trailing effects) |
| lottie-react | Loading animation shown during initial page load |

### Motion rules

- Subtle, brief, purposeful. No decorative bounce or parallax.
- Page transitions: `fadeInUp` variant, 0.3-0.5s, ease-out.
- Hover: scale 1.02-1.05, color shift, shadow lift.
- Respect `prefers-reduced-motion` via `useReducedMotion()`.
- IntersectionObserver used for scroll-triggered reveals.

---

## 9. Static Export Configuration

`next.config.mjs`:

```js
output: "export",
trailingSlash: true,
images: { unoptimized: true }
```

### Build output automation

| File | Source | Auto-generated? | Notes |
|---|---|---|---|
| `out/.htaccess` | `public/.htaccess` |ok/  Copied by Next.js | Edit `public/.htaccess` directly, then rebuild |
| `out/robots.txt` | `next-sitemap` (`postbuild`) |ok/ Generated fresh | **Do not** put a `robots.txt` in `public/` — next-sitemap would skip generation |
| `out/sitemap.xml` | `next-sitemap` (`postbuild`) |ok/ Generated fresh | Domain comes from `next-sitemap.config.js` → `siteUrl` |
| `out/sitemap-0.xml` | `next-sitemap` (`postbuild`) |ok/ Generated fresh | Same |
| `out/api/subscribe/guardar_email.php` | `src/app/api/` | X/ Manual deploy | See PHP exception below |

> **Rule**: if it's in `public/`, edit the source file and rebuild. If it's generated by `next-sitemap`, don't create a source file — let the tool generate it.

### PHP exception

Even though `output: "export"` is set, the `api/subscribe/guardar_email.php` file is kept in `src/app/api/` and deployed manually to the server. It is excluded from the Next.js build and served directly by Apache.

### `.htaccess`

Located at `public/.htaccess`. Provides Apache rewrite rules, security headers, cache control, compression, and file blocking. Copied to the build output by Next.js automatically.

**To modify**: edit `public/.htaccess` and rebuild. No other step needed.

| Security measure | Value |
|---|---|
| HSTS | `max-age=31536000; includeSubDomains; preload` |
| X-Content-Type-Options | `nosniff` |
| X-Frame-Options | `SAMEORIGIN` |
| Referrer-Policy | `strict-origin-when-cross-origin` |
| Permissions-Policy | `camera=(), microphone=(), geolocation=(), interest-cohort=()` |
| CSP | `default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; ...` |

> `'unsafe-inline'` is required for Next.js static export inline scripts/styles. A nonce-based CSP would require server-side rendering.

---

## 10. SEO and Metadata

- Comprehensive `layout.tsx` metadata: OpenGraph, Twitter cards, title template, description, keywords.
- Per-page `generateMetadata()` or `export const metadata` overrides for all routes.
- `next-sitemap` generates `sitemap.xml` with per-page priorities.
- `robots.txt` allows all crawlers, points to sitemap.

---

## 11. i18n System

The site supports **3 languages** (Spanish, English, German) via a custom i18n system:

### Message files
- `messages/{es,en,de}.json` — JSON files with namespace-based structure
- Namespaces: `Layout`, `Navbar`, `Footer`, `HomePage`, `BlogPage`, `ObrasPage`, `Books`, `ContactPage`, `ContactForm`, `Newsletter`, `BookReader`, `InfoPage`, `TermsPage`, `HomePhrases`, `UnderConstruction`

### Provider and hooks
- `i18n-provider.tsx` — React Context-based provider
- `I18nProvider` wraps the app with `locale` and `messages`
- `useLocale()` — returns current locale string
- `useT(namespace?)` — returns `t(key, params?)` function with dot-path resolution and `{param}` interpolation
- `t.raw<T>(key)` — for non-string values (arrays, objects)

### Routing
- `[locale]/` route group for localized pages (SSG with `generateStaticParams`)
- Root layout hardcodes `es` (fallback for non-prefixed routes)
- `[locale]/layout.tsx` auto-loads the correct message file per locale

### Article content
- Blog articles stored in `content/articulos/{locale}/*.md`
- `articles.ts` functions accept `locale` parameter and fall back to `es/`
- `getSortedArticles(locale)` — list articles for a locale
- `getArticleData(slug, locale)` — get single article with locale fallback
- Translated articles use the same slug, different frontmatter and body

### Book content
- `content/boulevard/{locale}.mdx` — locale-specific book reader content
- Same fallback logic as articles

### Component i18n
- XBookReader: `coverAlt`, `prevLabel`, `nextLabel`, `pageOfLabel` props
- XNavbar: `navLabel`, `menuLabel`, `linkLabelPrefix`, `themeToggleAriaLabel`, `themeToggleTitle` props
- XContactForm: `nameLabel`, `emailLabel`, `submitText`, etc. props
- XNewsletter: `loadingText` prop
- All components maintain Spanish defaults for backward compatibility

---

## 12. Future Improvement Areas

- **Migrate all `.jsx` pages to `.tsx`** for consistent type safety.
- **Standardize blog on static route** and remove the legacy PHP-backed `/blog/post` route.
- **Remove unused dependencies** (`gsap`, `lottie-react` if not actively used; audit `react-intersection-observer` necessity).
- **Add i18n** if multi-language content is needed.
- **Replace PHP newsletter endpoint** with a serverless alternative (Formspree, Web3Forms) for simpler hosting.
- **Audit the local xcomponents** against the npm package to identify drift.

---

## 13. Output Expectations

When an AI agent extends this site, the expected result is:

- structurally clean and consistent with existing patterns
- visually minimal and typography-driven
- thematically consistent (light/dark)
- responsive without hacks
- accessible by default
- easy to maintain by humans after the fact

If a proposed solution is clever but harder to maintain, reject it. Choose clarity over novelty.
