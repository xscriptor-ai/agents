# Xscriptor Code Structure

This file describes the preferred code organization for the Xscriptor site.

## Current Recommended Structure

```text
src/
  app/
    layout.tsx                    -- root layout: metadata, I18nProvider(es), theme
    page.tsx                      -- home page (delegates to ClientComponentHome)
    globals.css                   -- Tailwind v4 + CSS variables + keyframes

    [locale]/                     -- i18n locale group (SSG for es, en, de)
      layout.tsx                  -- locale-aware layout with I18nProvider
      page.tsx                    -- localized home
      blog/
        page.tsx                  -- localized blog index (locale param)
        [slug]/
          page.tsx                -- localized article page (locale-aware markdown)
      contacto/
        page.tsx                  -- localized contact form
      info/
        page.tsx                  -- localized bio, press, timeline
      obras/
        page.tsx                  -- localized book gallery
        literatura/
          page.tsx                -- localized literature landing
          boulevard/page.tsx      -- localized book reader
          asintota/page.tsx       -- under construction
          colaterales/page.tsx    -- under construction
          primavera-en-el-desierto/page.tsx -- under construction
          cielos-de-alquitran/page.tsx -- under construction
      terminos-y-condiciones/
        page.tsx                  -- localized terms

    blog/                         -- blog (Spanish fallback)
      page.tsx                    -- blog index
      BlogPage.module.css
      [slug]/
        page.tsx                  -- static article (Spanish)
        ArticlePage.module.css
      post/                       -- legacy PHP viewer

    obras/                        -- books (Spanish fallback)
      page.tsx                    -- book gallery
      ObrasPage.module.css
      literatura/
        page.jsx                  -- literature landing
        LibrosPage.module.css
        boulevard/
          page.tsx                -- boulevard reader (Spanish)
        asintota/
          page.tsx                -- under construction
        colaterales/
          page.jsx                -- under construction
        primavera-en-el-desierto/
          page.tsx                -- under construction
        cielos-de-alquitran/
          page.jsx                -- under construction

    contacto/
      page.tsx                    -- contact form (localized via I18nProvider)
      ContactPage.module.css

    info/
      page.tsx                    -- bio, press, timeline (localized)
      InfoPage.module.css

    terminos-y-condiciones/
      page.jsx                    -- terms (localized)

    components/
      UnderConstruction.tsx       -- reusable under-construction component
      ArticlesGrid.tsx            -- article grid (accepts emptyText prop)
      ClientComponentHome.module.css
      clientcomponenthome.tsx     -- home page: phrases, zigzag, videos, newsletter
      transitionProvider.tsx      -- page transition wrapper
      LoadingAnimation.tsx
      xcomponents/
        index.ts                  -- "use client" barrel re-exporting @xscriptor/xcomponents
        xsocialcontact/
          SocialIcons.tsx         -- custom SVG icons (not in npm package)
      blog/
        ArticleCard.tsx           -- article card (uses useT, useLocale)
      layout/footer/
        XFooterComponent.tsx      -- footer wrapper (uses useT("Footer"))
      contact/
        contactForm.tsx           -- legacy contact form

    content/
      articulos/
        es/*.md                   -- 11 Spanish blog articles
        en/*.md                   -- 11 English translations
        de/*.md                   -- 11 German translations
      boulevard/
        es.mdx                    -- boulevard content (Spanish)
        en.mdx                    -- boulevard content (English)
        de.mdx                    -- boulevard content (German)

    lib/
      articles.ts                 -- locale-aware markdown parsing
                                  -- getSortedArticles(locale), getArticleData(slug, locale)
                                  -- falls back to es/ if locale dir missing

messages/
  es.json                         -- Spanish messages (898+ lines, 16 namespaces)
  en.json                         -- English messages
  de.json                         -- German messages

public/
  images/
  favicon.ico
  robots.txt
```

## Route responsibilities

### `page.tsx` (route root)

- compose the route from imported sections and components
- keep inline JSX minimal; delegate layout to CSS modules
- export metadata or `generateMetadata` for SEO
- for localized routes: use `useT()` or pass locale to data functions

### `[locale]/` routes

- always define `generateStaticParams` returning `["en", "es", "de"]`
- use `useT(namespace?)` for UI text
- pass locale to data functions (`getSortedArticles(locale)`, `getArticleData(slug, locale)`)
- fall back to `es/` content when translation doesn't exist

### `module.css`

- control route-level spacing, header, and layout grid
- avoid styling deep reusable widgets here

### `xcomponents/*`

- own reusable or semi-reusable UI blocks
- keep related CSS local to the component folder
- when modifying, prefer editing the local copy over the npm dependency
- for i18n: components accept string props with Spanish defaults

### `content/articulos/{locale}/*.md`

- frontmatter: `title`, `date`, `description`, `tags`, `image`, `author`, `keywords`, `categories`
- body: markdown with optional LaTeX (math delimiters: `$$` or `\( \)`)
- same slug across locales = same article in different languages

### `content/boulevard/{locale}.mdx`

- raw text with poem sections separated by 3+ blank lines
- XBookReader splits on `\n{3,}` into poems, groups into pages
- blank line structure must be identical across languages

### `lib/articles.ts`

- locale-aware: all functions accept optional `locale` parameter
- falls back to `es/` when locale directory or file doesn't exist
- exports: `getSortedArticles(locale?)`, `getArticleData(slug, locale?)`, `getAllArticleSlugs(locale?)`, `getArticlesByCategory(category, locale?)`

### `messages/{locale}.json`

- namespace-based JSON structure
- accessed via `useT(namespace)` hook or `getMsg()` helper in server components
- arrays/objects accessed via `t.raw<T>(key)`

## Ideal rules for future changes

- if logic is route-only, keep it near the route
- if UI is reusable, move it to `xcomponents`
- if content is structured, move it to `content`
- if a component needs its own visual language, give it its own `module.css`
- prefer TypeScript for all new files; migrate `.jsx` files when editing them
- use the local xcomponents copy when the npm package needs modifications
- add new articles as `.md` files in `content/articulos/{locale}/` with proper frontmatter
- add new message keys to all 3 locale files simultaneously
- for translated content, use the same filename across locale directories

## Anti-patterns

- large data arrays inside `page.tsx`
- multiple unrelated widgets sharing one CSS module
- hardcoded colors instead of CSS custom properties
- mixing layout, data, and business logic in the same file
- adding Tailwind utility noise to components that already have dedicated CSS modules
- editing the npm `@xscriptor/xcomponents` package directly (update the package and bump version instead)
- copying npm components into `xcomponents/` (use the barrel re-export `index.ts`)
- importing `@xscriptor/xcomponents` directly in a Server Component — always go through the `"use client"` barrel at `@/app/components/xcomponents`
- putting PHP files inside `src/app/` that Next.js tries to process
- hardcoding text without adding it to messages files
- using `vw` units for padding without `clamp()` to cap on wide screens
- adding only to one locale's message file when adding new keys

## Preferred editing strategy for AI agents

1. inspect the route entry (`page.tsx` or `page.jsx`)
2. identify reusable boundaries
3. inspect nearby CSS modules and data files
4. if a new npm component is needed, add its re-export to `src/app/components/xcomponents/index.ts`
5. keep CSS local and readable
6. verify light and dark theme after edits
7. verify responsive behavior after edits
8. check all 3 locale message files when adding new text
9. **never** import `@xscriptor/xcomponents` directly in a Server Component — always use the barrel
10. run `npm run build` before finalizing
