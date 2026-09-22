# Xscriptor Architecture

Technical map of xscriptor.com: stack, rendering model, route table, providers,
i18n, theming, SEO and security. Read alongside `code-structure.md` (where code
goes) and `component-catalog.md` (what each component does).

Repository: `github.com/xscriptor-web/xscriptor.com` (branch `main`, single
history). The Next.js app lives at the repository root.

---

## 1. Tech stack

| Layer | Choice | Notes |
|-------|--------|-------|
| Framework | **Next.js 16.3.x** (App Router) | `output: "export"`, `trailingSlash: true` |
| Language | TypeScript 5 + some JS | `strict: true`, path alias `@/* → ./src/*` |
| UI runtime | React 19.2 | Server Components by default |
| Styling | Tailwind CSS 4.3 (PostCSS plugin) **+ CSS Modules** | global CSS via `@import "tailwindcss"` |
| Fonts | EB Garamond (self-hosted woff2) | Regular + Italic |
| Motion | `framer-motion` 12 | route transition, modals, spans |
| Scroll | `lenis` 1.3 | smooth scrolling (`LenisProvider`) |
| Content | Markdown/MDX + `gray-matter` + `remark`/`rehype` | GFM, KaTeX, highlight |
| Markdown stack | `remark-parse`, `remark-gfm`, `remark-math`, `remark-rehype`, `rehype-katex`, `rehype-highlight`, `rehype-stringify`, `unified`, `katex` | in `src/app/lib/articles.ts` |
| Components | `@xscriptor/xcomponents` 0.2.3 (npm) + local copies | see `component-catalog.md` |
| Backgrounds | `@xscriptor/xbackgrounds` 0.1.0 | `XParticles` |
| QR | `qrcode` 1.5 | PGP fingerprint QR |
| Sitemap | `next-sitemap` 4.2 | runs on `postbuild` |
| Hosting | Static host (Apache `.htaccess`, plus `_headers`) | no server runtime |

`react-intersection-observer` and `gsap` are declared as dependencies. The app
code uses raw `IntersectionObserver` and `requestAnimationFrame` almost
everywhere; treat those two packages as candidates for removal unless a
component explicitly imports them (grep before deleting).

`tailwind.config.*` does **not** exist. Tailwind v4 is configured entirely via
`postcss.config.mjs` (`plugins: ["@tailwindcss/postcss"]`) and the
`@import "tailwindcss"` line in `globals.css`. `@theme` is not used — theming is
done with plain CSS custom properties.

---

## 2. Rendering model

- **Fully static export.** `next.config.ts`:

  ```ts
  const nextConfig: NextConfig = {
    output: "export",
    trailingSlash: true,
    images: { unoptimized: true },
  };
  ```

  There is no Node runtime in production. Every route must be pre-renderable.

- **Server/Client boundary.**
  - `page.tsx` files are Server Components. Book pages read MDX **from disk at
    build time** (`fs.readFileSync`) and pass raw text to a client reader.
  - Interactive components are marked `"use client"` (readers, navbar, home,
    contact, info, blog list, transitions, etc.).
  - Root and `[locale]` layouts are server components that mount client
    providers (`I18nProvider`, `TransitionProvider`, `LenisProvider`).

- **The `"use client"` barrel.** Local reusable components are re-exported from
  `src/app/components/xcomponents/index.ts`, which starts with `"use client"`.
  This is the boundary server components import from (see §6).

- **`generateStaticParams`.** The `[locale]` layout returns the five locales;
  book/article routes additionally enumerate their own params.

- **Data at build time.** `src/app/lib/articles.ts` and `src/lib/poemParser.ts`
  use `fs`, so they can only run inside Server Components / build.

---

## 3. Route map

All user-facing pages live under the dynamic `[locale]` segment (no separate
non-localized route tree exists in this repo).

| Route | File | Rendering | Data source |
|-------|------|-----------|-------------|
| `/` | `src/app/page.tsx` | Static (locale = `es`) | delegates to `ClientComponentHome` |
| `/[locale]` | `[locale]/page.tsx` | Static per locale | `ClientComponentHome` |
| `/[locale]/blog` | `[locale]/blog/page.tsx` | Static per locale | `getSortedArticles(locale)` → `BlogListClient` |
| `/[locale]/blog/[...slug]` | `[locale]/blog/[...slug]/page.tsx` | Static per locale + slug | `getArticleData(slug, locale)` → `XBlogDecrypt` |
| `/[locale]/contacto` | `[locale]/contacto/page.tsx` | Static | `ContactoClientPage` → `PublicKeyCard` |
| `/[locale]/info` | `[locale]/info/page.tsx` | Static | `InfoClientPage` (press cards, timeline) |
| `/[locale]/links` | `[locale]/links/page.tsx` | Static (server component) | inline `LINKS` + `LinksPage` messages |
| `/[locale]/obras` | `[locale]/obras/page.tsx` | Static | `ObrasClientPage` (book gallery) |
| `/[locale]/obras/boulevard` | `.../boulevard/page.tsx` | Static | MDX `boulevard/{locale}.mdx` → npm `XBookReader` |
| `/[locale]/obras/asintota` | `.../asintota/page.tsx` | Static | MDX `asintota/{locale}.mdx` → `AsintotaBook` → npm `XCompleteBook` |
| `/[locale]/obras/cielos-de-alquitran` | `.../cielos-de-alquitran/page.tsx` | Static | MDX `cielos-de-alquitran/{locale\|cielos-de-alquitran}.mdx` → local `XBookColors` |
| `/[locale]/obras/colaterales` | `.../colaterales/page.tsx` | Static | MDX → local `BookReaderPoems` |
| `/[locale]/obras/primavera-en-el-desierto` | `.../primavera-en-el-desierto/page.tsx` | Static | MDX → local `XBookColors` |
| `/[locale]/obras/la-danza-de-las-amapolas` | `.../la-danza-de-las-amapolas/page.tsx` | Static | MDX → local `XBookColors` (page) / `AmapolasBook` → npm `XCompleteBook` with `renderPoem` |
| `/[locale]/obras/grafo` | `.../obras/grafo/page.tsx` | Static | `getAllPoems(locale)` → `GrafoPoetico` |
| `/[locale]/terminos-y-condiciones` | `.../terminos-y-condiciones/page.tsx` | Static | `TermsClientPage` |
| `*` (404) | `src/app/not-found.tsx` | Client | `usePathname()` → locale-specific copy |

> There is **no** top-level `/blog`, `/obras`, `/contacto`, etc. Any legacy
> reference to `app/blog/page.tsx` routes is stale. `src/app/blog/` and
> `src/app/obras/` currently hold **only CSS modules** consumed by the
> `[locale]` pages; `src/app/contacto/` and `src/app/info/` hold only their
> `*.module.css`.

### Hero sequences

- **Home** (`ClientComponentHome`): a timed ASCII intro overlay
  (`AsciiLoadingAnimation`, ~1.2 s minimum, frames auto-advance every 35 ms,
  hard cap 4 s), then two `XZigZagLayoutVideo` blocks — a left-start block with
  six `XHomeColors` phrases and a right-start block with eight more. Background
  images alternate per block; a scroll-drawn SVG line connects the markers.
- **Obras / Blog galleries**: full-viewport stacked sections that blur/dim the
  non-centered item, based on a scroll listener computing the section nearest
  the viewport center (`activeIndex`).
- **Readers**: full-viewport background frames plus a paginated content column.

---

## 4. Layout shell & providers

`src/app/layout.tsx` (server) is the root:

```tsx
<html lang="es" suppressHydrationWarning>
  <head>
    <Script id="theme-init" strategy="beforeInteractive">
      {`(function(){try{var t=localStorage.getItem("theme");if(t==="dark"){document.documentElement.setAttribute("data-theme","dark")}}catch(e){}})();`}
    </Script>
  </head>
  <body className="min-h-screen flex flex-col bg-(--bg) text-(--text) overflow-x-hidden">
    <a href="#main-content" className="skip-to-content">Saltar al contenido principal</a>
    <I18nProvider locale="es" messages={esMessages}>
      <LenisProvider />
      <TransitionProvider />
      <ConditionalSeparator />
      <main id="main-content" className="px-4 sm:px-6 lg:px-8 pt-16">{children}</main>
      <ConditionalSeparator />
      <SiteXFooter />
    </I18nProvider>
  </body>
</html>
```

Key points:
- Root hardcodes **Spanish** (so `/` is Spanish). The `[locale]` layout mounts a
  *nested* `I18nProvider` with the requested locale; the inner one wins for that
  subtree.
- `import "@xscriptor/xcomponents/styles.css"` is loaded in the root layout — the
  npm package's component styles ship there.
- Global chrome order: smooth-scroll provider → route-transition/navbar/language
  dock → conditional separator → `main` → separator → footer.
- `main` has `pt-16` to clear the fixed navbar and horizontal responsive padding.
- No `<head>` font preload tags; fonts are declared in `globals.css`.

`[locale]/layout.tsx`:
- `generateStaticParams()` → `["es","en","de","it","fr"]`.
- `generateMetadata()` builds `<link rel="alternate">` hreflang tags and a
  canonical URL (`https://xscriptor.com` for `es`, `.../{locale}` otherwise).
- Picks messages from the five imported JSON files, validates the locale
  (`es` fallback), mounts `I18nProvider` + `UpdateHtmlLang`.

---

## 5. i18n system

Five locales: **`es`, `en`, `de`, `it`, `fr`**. Spanish is the fallback.

### Message store

`messages/{locale}.json` — 926 lines each, identical key shape. Namespaces:

`Layout`, `Navbar`, `Footer`, `HomePage`, `BlogPage`, `ObrasPage`,
`LiteraturaPage`, `Books`, `ContactPage`, `ContactForm`, `Newsletter`,
`BookReader`, `InfoPage`, `LinksPage`, `TermsPage`, `HomePhrases`,
`UnderConstruction`.

`HomePhrases` is special: it holds `WordConfig[]` arrays (not strings) consumed
by `XHomeColors` (see `content-pipeline.md`).

### Client runtime — `src/app/i18n-provider.tsx`

- `I18nProvider({ locale, messages })` stores `{ locale, messages }` in React
  Context.
- `useLocale()` → current `Locale`, defaults to `"es"` when outside a provider.
- `useT(namespace?)` → `t(key, params?)`:
  - resolves dot-paths (`resolvePath`) against the namespace,
  - interpolates `{param}` tokens,
  - returns the key itself if a lookup misses,
  - has `t.raw<T>(key)` for arrays/objects (used for `pressCards`, `timeline`,
    `HomePhrases`).
- The `Locale` type is a strict union; adding a locale requires updating it here
  *and* in every duplicate locale list across the app (see gotchas in §9).

### Server helper — `src/app/lib/i18n-utils.ts`

`getMsg(messages, "Namespace.key")` — a non-hook dot-path resolver used by
Server Components for `generateMetadata`/`metadata`. It returns the key on miss
(no interpolation).

### Content localization

- Blog articles: `src/app/content/articulos/{locale}/**/*.md`, with `es`
  fallback handled in `articles.ts`.
- Books: `src/app/content/{book}/{locale}.mdx` (exception: `cielos-de-alquitran`
  ES file is `cielos-de-alquitran.mdx` — see `poemParser.ts`/page code).
- Pages read their locale via `params` and fall back to `es` when a file or
  locale is missing.

### Nav chrome i18n

`TransitionProvider` keeps its own per-locale label dictionaries
(`LOCALE_KEYS`, `NAV_LABELS`, `langLabels`) rather than reading `messages/`. This
is a deliberate (but duplicated) convenience — see `component-catalog.md` and
the gotchas below.

---

## 6. Component system overview

Two tiers:

1. **`@xscriptor/xcomponents` (npm)** — the published library
   (`styles.css`, `content` types). Imported through the local barrel.
2. **Local components** — either bespoke (`XGlassNavbar`, `XBookColors`,
   `XHomeColors`, `BookReaderPoems`, `XZigZagLayoutVideo`, `XMinimalFooter`) or
   app-level (`XBlogDecrypt`, `XTextDecrypt`, `GrafoPoetico`, `PublicKeyCard`,
   `SocialGrid`, `ParticlesBackground`, `AsciiLoadingAnimation`,
   `ClientComponentHome`, `LenisProvider`, `TransitionProvider`,
   `ConditionalSeparator`, `XFooterComponent`, navbar icons).

The barrel `src/app/components/xcomponents/index.ts` is **the** import surface:

```ts
"use client";
export { XNavbar } from "@xscriptor/xcomponents";
export { XGlassNavbar } from "./xglassnavbar";
export { XZigZagLayoutVideo } from "./xzigzagvideo";
export { XFooter, XSeparator, XZigZagLayout } from "@xscriptor/xcomponents";
export { XBookReader, XBookReaderIllus, XInteractivePhrase, XDecryptedText, XCompleteBook, XBookFullDecrypt } from "@xscriptor/xcomponents";
export { default as XMinimalFooter } from "./xminimalfooter/XMinimalFooter";
export { XBookColors } from "./xbookcolors";
export { XHomeColors } from "./xhomecolors";
export { BookReaderPoems } from "./BookReaderPoems";
export { XContactForm, XNewsletter, XSocialContact } from "@xscriptor/xcomponents";
```

Why the barrel exists: the npm bundle's `chunk-*.mjs` does **not** preserve the
`"use client"` directive, so Server Components that `fs.readFileSync` (book
pages) would crash with `useState is not a function` when importing client-hook
components directly. The barrel re-adds the boundary.

Install docs and patches:
- `docs/STRUCTURE.md` — high-level structure (Spanish).
- `docs/xcomponents-fixes.md` — **required reading** before upgrading
  `@xscriptor/xcomponents`; documents the two local `XGlassNavbar` patches
  (active-link detection, theme persistence) and why they exist.

---

## 7. Theme system

- Attribute **`data-theme`** on `<html>`; values `"dark"` (attribute present) or
  light (attribute absent). `:root.dark` / `:root.light` classes coexist for
  component CSS that keys off classes.
- Persisted in `localStorage` under the key **`theme`** (`"dark"` | `"light"`).
- **Before first paint:** a `next/script` `beforeInteractive` snippet in the root
  layout reads `localStorage` and sets `data-theme="dark"` to avoid a flash.
- **Toggle:** the navbar logo (center) is the theme button (`XGlassNavbar`
  `logoAsThemeToggle`), with sun/moon icons from `navbarIcons.tsx`. Mobile has a
  dedicated theme row in the overlay menu.
- **Hydration-safe sync:** the navbar renders the same default on server and
  client, reads `localStorage` in a post-hydration `useEffect`, and gates
  persistence behind a `themeReady` flag so the default light value never
  overwrites a stored `"dark"`. (`<html suppressHydrationWarning>` absorbs the
  attribute difference.)
- `ParticlesBackground` mirrors `data-theme` to `dark`/`light` classes on
  `<html>` so `PublicKeyCard`'s `:root.light`/`:root.dark` neumorphism responds.
- Components that need live theme reads use a `MutationObserver` on
  `documentElement` filtered to `data-theme` (`useDetectTheme` in `XHomeColors`,
  `XBookColors`, `GrafoPoetico`).
- Global theme transition: `background/color 0.3s ease` on `html, body`.

---

## 8. SEO & metadata

- Root `metadata` provides `metadataBase: https://xscriptor.com`, a title
  template `%s | Xscriptor`, description, OpenGraph (`es_ES`, 1200×1200
  `/xscriptor-signature.png`), Twitter `summary_large_image`, robots
  `index,follow`.
- Each page exports `generateMetadata` (or `metadata`) and sets a per-page
  `openGraph.locale` via the same inline ternary
  `es_ES/en_US/de_DE/it_IT/fr_FR`.
- `[locale]/layout.tsx` adds canonical + hreflang alternates for the five
  locales.
- `next-sitemap.config.js`: `siteUrl: https://xscriptor.com`,
  `generateRobotsTxt: true`, `sitemapSize: 10000`,
  `exclude: ['/api/*', '/blog/post']` (the excludes are legacy but harmless).
- `robots.txt` and `sitemap.xml`/`sitemap-0.xml` are **generated** by the
  `postbuild` step — never hand-author them in `public/`.
- Icons: `src/app/favicon.ico` and `src/app/icon.svg` use Next's file
  conventions. `public/xscriptor-favicon.png` and `xscriptor-signature.*` are
  static assets referenced by metadata/UI.

---

## 9. Security & hosting headers

Two header sources ship in `public/`:

- **`public/.htaccess`** (Apache — primary production target):
  - Static-export rewrite: clean URLs → `$1.html`, unknown paths → `index.html`.
  - Headers: HSTS (`max-age=31536000; includeSubDomains; preload`),
    `X-Content-Type-Options: nosniff`, `X-Frame-Options: SAMEORIGIN`,
    `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy`
    (camera/microphone/geolocation/interest-cohort all `()`), and a CSP:
    `default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self'
    'unsafe-inline'; img-src 'self' data:; font-src 'self'; media-src 'self';
    connect-src 'self'; frame-ancestors 'self'; form-action 'self'`.
  - Blocks direct access to `.env|.git|.json|.lock|.md|.mdx` files.
  - Cache-Control via `mod_expires` (media/fonts 1 year, css/js 1 month) and
    `mod_deflate`.
- **`public/_headers`** (Netlify/Cloudflare-Pages style): a subset
  (`nosniff`, `X-Frame-Options: DENY`, referrer policy, permissions policy).

> `'unsafe-inline'` in the CSP is required by Next.js static export. A hash/nonce
> CSP would require server rendering, which this site does not have.

There is **no PHP endpoint, no API route, and no newsletter backend** in the
current repository. `public/x-public.asc` is a static PGP public key fetched by
`fetch("/x-public.asc")`.

---

## 10. Environment variables

None. The project runs with zero env configuration: all URLs are hardcoded
(`https://xscriptor.com`), all data is on disk, all external contact channels
are static links (`mailto:`, Telegram, WhatsApp, social).

---

## 11. Known architectural gotchas

1. **Duplicated locale lists.** The five-locale set is re-declared in
   `i18n-provider.tsx`, `articles.ts`, `poemParser.ts`, `[locale]/layout.tsx`,
   `transitionProvider.tsx`, `ConditionalSeparator.tsx`, `not-found.tsx`,
   `XFooterComponent.tsx`, and `GrafoPoetico` label maps. Adding/removing a
   locale is a multi-file change.
2. **Inconsistent locale regex.** `TransitionProvider` and `ConditionalSeparator`
   match all five locales; `XFooterComponent` and `not-found.tsx` use
   `/^\/(en|es|de)/` and therefore fall back to `es` for Italian and French
   paths. Fix both when touching footer/404 locale detection.
3. **Two UI text systems.** `messages/*.json` (namespaced, provider-based) *and*
   hardcoded per-locale dictionaries inside components (`TransitionProvider`,
   `GrafoPoetico`, reader section names, `not-found`). Keep both in sync.
4. **Unused local duplicate.** `src/app/components/xcomponents/xcompletebook/XCompleteBook.tsx`
   is a local implementation, but the barrel exports the **npm** `XCompleteBook`.
   The local file is currently unreferenced — confirm before editing or
   deleting.
5. **`gsap` / `react-intersection-observer`** are installed but not imported in
   app code; candidates for dependency cleanup.
6. **`.htaccess` blocks `.json`/`.md` serving.** Does not affect the built site
   (data is inlined into JS/HTML), but do not plan to serve raw content files.
7. **Path aliases.** Use `@/app/...` and `@/lib/...` (mapped to `./src/*`).
   Relative imports with deep `../../../../messages/...` also appear in pages —
   both styles exist; prefer `@/`.
8. **`next lint`** is unreliable on Next 16; validate types with
   `npx tsc --noEmit` (see `build-and-deploy.md`).
