# DevX Code Structure

This file describes the preferred code organization for the DevX UI.

> ⚠️ The project now uses a **locale-based route structure** (`src/app/[locale]/`).
> See `SKILL.md §14 i18n` for the full i18n architecture.

## Current Recommended Structure

```text
messages/
  en.json              ← translations (English)
  es.json              ← translations (Spanish)
  de.json              ← translations (German)

public/
  _headers             ← CSP / security headers (Netlify/Cloudflare)
  robots.txt
  sitemap.xml           ← full locale-aware sitemap
  .well-known/
    security.txt

src/
  app/
    layout.tsx          ← root layout (html/body + globals only)
    page.tsx            ← English default at / (wraps [locale]/page with en)
    globals.css
    i18n-provider.tsx   ← I18nProvider + useT() + useLocale() hooks

    [locale]/           ← locale dynamic segment
      layout.tsx        ← I18nProvider, Navbar, Footer, ThemeScript
      page.tsx          ← home page (client, useT)
      contact/
        page.tsx
        contact.module.css
      portfolio/
        page.tsx
      resources/
        page.tsx
        resources.module.css
        vscode/
          page.tsx
          vscode.module.css
          references.md
        terminal/
          page.tsx
          terminal.module.css
          emulators.md
          xfetchlogologo.md
          examples/
        xfetch/
          page.tsx
          xfetch.module.css
      x/
        page.tsx

    components/          ← shared client components (NOT locale-scoped)
      navbar/
        navbar.jsx       ← locale-aware links + language selector
        navLink.jsx      ← locale-aware active detection
      footer/footer.tsx
      contactform/ContactForm.tsx
      HeroImageSlider.tsx
      SkillNetwork.tsx
      DecryptedText.tsx
      previewshome/
      previewsresources/
      xcomponents/
        vscode-resource-sections/
        vscode-theme-gallery/
        xglass-showcase/
        terminal-resource-sections/
        repo-card/       ← ⚠️ RepoCard still used by resources page
        icons/

  data/
    resources/
      resources.data.ts
      terminal/
        terminalResources.data.ts   ← reads colors.md + emulators.md (fs)
      vscode/
        vscodeThemes.data.ts

  types/
    resources/
      resources.types.ts
      terminal.types.ts
      vscode.types.ts
```

## Responsibilities

### `page.tsx` (inside `[locale]/*/`)

- compose the route
- use either direct JSON import (server) or `useT()` (client) for text
- **must** prefix internal links with the current locale

### `[locale]/layout.tsx`

- loads `messages/{locale}.json`
- wraps children in `I18nProvider`
- renders Navbar, Footer, ThemeScript
- exports `generateStaticParams()` returning `["en", "es", "de"]`

### `i18n-provider.tsx`

- exports `I18nProvider`, `useT(namespace?)`, `useLocale()`
- `useT` returns a function `(key, params?) => string`
- `.raw<T>(key)` returns structured data (arrays, objects)

### `messages/*.json`

- flat JSON, namespaced by component/page
- use `{variable}` for interpolation
- all three files must stay in sync (same keys, different values)

### `xcomponents/*`

- own reusable or semi-reusable UI blocks
- keep related CSS local to the component folder
- expose an `index.ts` when the folder is intended to be imported from elsewhere

### `data/*`

- store structured content, arrays, configuration, preview presets, and theme definitions
- keep data serializable when possible

### `types/*`

- store shared contracts used across route, data, and components
- avoid duplicating local prop types as global types unless reuse justifies it

## Ideal Rules For Future Changes

- if logic is route-only, keep it near the route
- if UI is reusable, move it to `xcomponents`
- if content is structured, move it to `data`
- if a type is shared across files, move it to `types`
- if a component needs its own visual language, give it its own `module.css`
- **all internal links must be prefixed with the current locale**
- **always add new translation keys to all three `messages/*.json` files**
- **server components that render directly from fs (like `terminalResources.data.ts`) stay server; those pages use JSON imports for i18n, not `useT()`**

## Anti-Patterns

- large data arrays inside `page.tsx`
- multiple unrelated widgets sharing one CSS module
- hardcoded page chrome colors instead of theme variables
- mixing layout, data, and business logic in the same file
- adding Tailwind utility noise to components that already have dedicated CSS modules
- **hardcoded internal paths without locale prefix** (will 404)
- **forgetting to add a key to `messages/de.json` or `messages/es.json`**
- **using `next-intl` server APIs** (`getTranslations`, `getMessages`) — they call `headers()` which fails in static export

## Preferred Editing Strategy For AI Agents

1. inspect route entry and identify locale (`[locale]` segment)
2. read the relevant messages file for existing keys
3. identify reusable boundaries
4. inspect nearby data and types
5. add or update a dedicated component folder if needed
6. keep CSS local and readable
7. verify responsive behavior after edits
8. verify the translation key exists in all three locale files
9. verify internal links include the locale prefix
