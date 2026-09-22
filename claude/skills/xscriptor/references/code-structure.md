# Xscriptor Code Structure

Where code goes, what each layer is responsible for, and the rules that keep the
site consistent. Canonical placement rules — the current tree is the source of
truth; this document explains the intent behind it.

---

## 1. Current tree

```text
xscriptor.com/
├── src/
│   ├── app/
│   │   ├── layout.tsx                  # root shell: metadata, theme script, providers, footer
│   │   ├── page.tsx                    # "/" (Spanish home)
│   │   ├── globals.css                 # Tailwind v4 import + tokens + global element rules
│   │   ├── i18n-provider.tsx           # I18nProvider, useLocale, useT (+ t.raw)
│   │   ├── not-found.tsx               # client 404
│   │   ├── favicon.ico, icon.svg       # file-convention icons
│   │   │
│   │   ├── [locale]/
│   │   │   ├── layout.tsx              # per-locale provider, hreflang, <html lang>
│   │   │   ├── page.tsx                # localized home
│   │   │   ├── UpdateHtmlLang.tsx
│   │   │   ├── blog/
│   │   │   │   ├── page.tsx            # listing (server) → BlogListClient
│   │   │   │   └── [...slug]/page.tsx  # article (server) → XBlogDecrypt
│   │   │   ├── contacto/
│   │   │   │   ├── page.tsx
│   │   │   │   └── ContactoClientPage.tsx
│   │   │   ├── info/
│   │   │   │   ├── page.tsx
│   │   │   │   └── InfoClientPage.tsx
│   │   │   ├── links/page.tsx
│   │   │   ├── obras/
│   │   │   │   ├── page.tsx
│   │   │   │   ├── ObrasClientPage.tsx
│   │   │   │   ├── boulevard/page.tsx
│   │   │   │   ├── asintota/{page.tsx, AsintotaBook.tsx}
│   │   │   │   ├── cielos-de-alquitran/{page.tsx, CielosDeAlquitranBook.tsx}
│   │   │   │   ├── colaterales/page.tsx
│   │   │   │   ├── primavera-en-el-desierto/page.tsx
│   │   │   │   ├── la-danza-de-las-amapolas/{page.tsx, AmapolasBook.tsx}
│   │   │   │   └── grafo/{page.tsx, GrafoPage.module.css}
│   │   │   └── terminos-y-condiciones/{page.tsx, TermsClientPage.tsx}
│   │   │
│   │   ├── components/
│   │   │   ├── clientcomponenthome.tsx         # home hero
│   │   │   ├── ClientComponentHome.module.css
│   │   │   ├── AsciiLoadingAnimation.tsx
│   │   │   ├── ascii-frames.json               # precomputed intro frames
│   │   │   ├── LenisProvider.tsx
│   │   │   ├── transitionProvider.tsx          # navbar + language dock + route overlay
│   │   │   ├── blog/BlogListClient.tsx
│   │   │   ├── icons/navbar/navbarIcons.tsx
│   │   │   ├── layout/ConditionalSeparator.tsx
│   │   │   ├── layout/footer/XFooterComponent.tsx
│   │   │   ├── publickey/{PublicKeyCard.tsx, PublicKeyCard.module.css}
│   │   │   ├── socialgrid/SocialGrid.tsx
│   │   │   ├── xbackgrounds/ParticlesBackground.tsx
│   │   │   ├── Xtexts/XTextDecrypt/{XTextDecrypt.tsx, index.ts}
│   │   │   └── xcomponents/                    # see below
│   │   │
│   │   ├── blog/
│   │   │   ├── BlogListPage.module.css         # CSS for BlogListClient
│   │   │   └── [slug]/ArticlePage.module.css   # CSS for the article page
│   │   ├── contacto/ContactPage.module.css
│   │   ├── info/InfoPage.module.css
│   │   ├── obras/ObrasPage.module.css
│   │   │
│   │   ├── content/                            # authored content (not code-gen)
│   │   │   ├── articulos/{locale}/**/*.md
│   │   │   └── <book>/{locale}.mdx
│   │   │
│   │   └── lib/{articles.ts, i18n-utils.ts}
│   └── lib/poemParser.ts
│
├── messages/{es,en,de,it,fr}.json
├── public/                                     # static assets + .htaccess + _headers
├── docs/{STRUCTURE.md, xcomponents-fixes.md}
├── next.config.ts, next-sitemap.config.js, postcss.config.mjs
├── eslint.config.mjs, package.json, tsconfig.json, README.md, CONTRIBUTING.md, CONTACT.md
└── LICENSE
```

### `src/app/components/xcomponents/` (local reusable UI)

```text
xcomponents/
  index.ts                     # "use client" barrel (the import surface)
  xglassnavbar/{XGlassNavbar.tsx, XGlassNavbar.module.css}
  xzigzagvideo/{XZigZagLayoutVideo.tsx, .module.css}
  xhomecolors/{XHomeColors.tsx, .module.css}
  xbookcolors/{XBookColors.tsx, .module.css, README.md}
  xcompletebook/{XCompleteBook.tsx, .module.css}   # NOTE: currently unreferenced
  xminimalfooter/XMinimalFooter.tsx
  BookReaderPoems.tsx + BookReaderPoems.module.css
  grafo/{GrafoPoetico.tsx, GrafoPoetico.module.css}
  xblogdecrypt/{XBlogDecrypt.tsx, README.md, index.ts}
```

Naming quirk: most CSS modules live in **non-route sibling folders**
(`src/app/blog/`, `src/app/obras/`, `src/app/contacto/`, `src/app/info/`) while
the route pages live under `[locale]/`. Components import them with the absolute
alias, e.g. `import styles from "@/app/blog/BlogListPage.module.css"`. Follow
this pattern rather than moving CSS next to the `[locale]` page.

---

## 2. Layer responsibilities

### Route entry (`page.tsx`) — Server Component

- Export `metadata` or `generateMetadata` (SEO + Open Graph locale).
- For localized routes, `await params` to get the locale.
- Fetch build-time data (`getSortedArticles`, `getArticleData`, `getAllPoems`,
  `fs.readFileSync` for books).
- Delegate all interactivity to a client component (`*ClientPage`, readers,
  `BlogListClient`) — do not put hooks in the page.
- Keep the page thin; layout lives in CSS modules or the client component.

### `layout.tsx`

- Root: global metadata, theme `<Script>`, `I18nProvider(es)`, `LenisProvider`,
  `TransitionProvider`, separators, `main`, footer, skip link.
- `[locale]`: validate locale, inject the correct messages, `UpdateHtmlLang`,
  emit hreflang alternates.
- Do not add page-specific content to layouts.

### Client page component (`*ClientPage.tsx`)

- Owns local UI state and `useT`-based copy.
- Composes reusable components; keeps JSX declarative.
- Often pairs with `ParticlesBackground` (contact/info).

### Reusable UI

- Site-specific reusable blocks → `src/app/components/<area>/` with a colocated
  `*.module.css`, exported through the barrel if server components need them.
- Cross-project library components → `@xscriptor/xcomponents` (update the
  package + bump version; never fork).
- Animation primitives (`XTextDecrypt`, `XBlogDecrypt`) stay in the app when they
  depend on app-specific content shape.

### Data / parsing

- `src/app/lib/articles.ts` — blog markdown pipeline (build-time only).
- `src/app/lib/i18n-utils.ts` — `getMsg` for server components.
- `src/lib/poemParser.ts` — aggregate poems for the graph (build-time only).
- Any new `fs`-using parser: keep it in a `lib/` module, call it only from
  server components.

### Content

- `src/app/content/articulos/{locale}/` — blog markdown.
- `src/app/content/<book>/{locale}.mdx` — book text.
- Author content by hand; never generate it at runtime.

### Messages

- `messages/{locale}.json` — UI strings, namespaced.
- Add keys to **all five** locales simultaneously.

### CSS

- Global tokens, element resets, `.article-content`, utilities, keyframes →
  `globals.css` only.
- Route/section layout → the route’s `*.module.css`.
- Component internals → the component folder’s `*.module.css`.
- Prefer Tailwind utilities for spacing/layout in simple JSX; use CSS modules
  for anything stateful or repeated. Do not mix heavy Tailwind noise into a
  component that already has a module.

---

## 3. Import rules

- Use the path aliases: `@/app/...`, `@/lib/...`.
- Import reusable components from the barrel:
  `import { XBookColors } from "@/app/components/xcomponents";`
- **Never** import `@xscriptor/xcomponents` directly from a Server Component —
  go through the `"use client"` barrel (see `architecture.md` §6).
- The barrel must stay `"use client"`. If you add a component that needs client
  hooks, add its re-export line to `index.ts`.

---

## 4. Ideal rules for future changes

- Route-only logic stays near the route; shared logic moves to `lib/`.
- Reusable UI moves to `xcomponents/` and, if browser-only, through the barrel.
- Structured content moves to `content/`; interface copy moves to `messages/`.
- Give a component its own `module.css` the moment it develops a visual language.
- Prefer TypeScript for all new files; migrate stray `.jsx`/`.js` when touched.
- Add new locales to every locale list (or better, centralize them — see §6).
- Use `clamp()` for fluid sizing; cap wide-screen padding.
- Verify both themes and `<768px` after any visual change.
- Run `npx tsc --noEmit` then `npm run build` before finalizing.

---

## 5. Anti-patterns

- Large inline data arrays inside `page.tsx` (put them in a `const` beside the
  route or in `lib/`).
- Multiple unrelated widgets sharing one CSS module.
- Hardcoded colors instead of `var(--bg|--text|--accent|--border)` (the book /
  graph palettes are the only exceptions).
- Hardcoded user-facing text that never reaches `messages/*.json` (or, for the
  documented per-component dictionaries, at least translated in place).
- Copying npm components into `xcomponents/` instead of using the barrel.
- Editing the npm `@xscriptor/xcomponents` package inside `node_modules`.
- Importing `@xscriptor/xcomponents` directly in a Server Component.
- Using `vw` for padding without `clamp()`.
- Adding a key to only one locale’s message file.
- Hand-authoring `robots.txt`/`sitemap.xml` in `public/` (next-sitemap owns them).
- Adding server-only APIs (`route.ts`, middleware, revalidate) — export is static.
- Using `dangerouslySetInnerHTML` on untrusted input (XBlogDecrypt/Grafo inject
  generated HTML into trusted, in-repo content only).

---

## 6. Known structural debt (fix opportunistically)

1. **Locale list duplication** across ~9 files. A single
   `src/lib/locales.ts` exporting `LOCALES`, `Locale`, `FALLBACK_LOCALE`,
   `INDEX_HEADERS`, `OG_LOCALE` would remove most of it.
2. **Two locale regexes** — `XFooterComponent` and `not-found.tsx` only handle
   `en|es|de`, so Italian/French fall back to Spanish. Align them with
   `transitionProvider`.
3. **Inline nav/reader dictionaries** in components vs `messages/`. Migrate
   `TransitionProvider` labels and reader section names into messages when
   convenient.
4. **Unreferenced local `XCompleteBook.tsx`** — delete or wire it up.
5. **Unused deps** (`gsap`, `react-intersection-observer`) — confirm and prune.
6. **`a:hover { color:#ff4141 }`** global override fights accent links; scope it.
7. **`InfoPage` 15vw padding** should become `clamp()` for small screens.

---

## 7. Preferred editing strategy for AI agents

1. Read the route entry (`page.tsx`) and its client component.
2. Read the relevant CSS module and the data file it depends on.
3. If a reusable block is needed, add it under `components/` and, if it must be
   server-importable, to the barrel.
4. Keep new copy in `messages/*.json` for all five locales (plus per-component
   tables where the codebase already does so).
5. Respect the design system (`design-system.md`): tokens, marker chips, motion
   budget, reduced motion.
6. Verify light/dark and mobile.
7. `npx tsc --noEmit` → `npm run build`.
8. Never commit secrets; never add a runtime server dependency.
