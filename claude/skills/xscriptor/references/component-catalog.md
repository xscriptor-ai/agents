# Xscriptor Component Catalog

Every component in the project, what it does, its props/API, and where it lives.
Use this before writing anything new: most needs are already covered by an
existing component.

Legacy note: older docs list `XContactForm`, `XNewsletter` and `XSocialContact`
as actively used. They are re-exported from the barrel (npm) but **no page
currently renders them** — the contact page uses `PublicKeyCard` + `SocialGrid`.
The newsletter backend does not exist. Do not assume they are wired up.

---

## Part A — Barrel imports (`src/app/components/xcomponents/`)

`index.ts` (`"use client"`) is the only sanctioned import surface for reusable
components. Never import `@xscriptor/xcomponents` directly from a Server
Component.

### From `@xscriptor/xcomponents` (npm)

| Component | Purpose |
|-----------|---------|
| `XNavbar` | Legacy navbar (superseded by local `XGlassNavbar`) |
| `XFooter` | Legacy footer primitive |
| `XSeparator` | Decorative separator; supports `orientation`, `variant` (`dashed`), `hasX`, `color`, `xColor`, `thickness`, `gap`, `isFaded`, `xBg`, `className` |
| `XZigZagLayout` | Alternating left/right content stack with an optional scroll-drawn SVG connector. Props: `startSide`, `gap`, `offset`, `textAlign` (`inherit\|side\|left\|right`), `showLine`, `lineColor`, `lineThickness`, `className` |
| `XBookReader` | Paginated book reader (used by Boulevard) |
| `XBookReaderIllus` | Illustrated book reader variant |
| `XInteractivePhrase` | Renders `WordConfig[]` with interactive word types + per-word decrypt; prop `as` selects the tag; used by readers and `XZigZagLayoutVideo` |
| `XDecryptedText` | Text-decrypt primitive |
| `XCompleteBook` | Full book engine: cover, section titles, index, zigzag pages, pagination, optional background image/video, optional `renderPoem` override, `sectionNames`, `onPageChange`, `labels` |
| `XBookFullDecrypt` | Poem renderer variant (per-word decrypt) exported by the npm package |
| `XContactForm` / `XNewsletter` / `XSocialContact` | Re-exported but unused in current pages |

### Local components

#### `XGlassNavbar` — `xcomponents/xglassnavbar/XGlassNavbar.tsx`
Apple-style floating glass navbar. The center `logo` doubles as the theme
toggle. Desktop shows `linksLeft`/`linksRight`; below `768px` it collapses to a
fixed glass hamburger + full-screen overlay menu with a theme row.

Key props: `linksLeft`, `linksRight` (`{ url, title, external?, showExternalIcon? }`),
`logo`, `logoAsThemeToggle`, `onLogoClick`, `themeIcons: { toDark, toLight }`,
`defaultTheme`, `storageKey` (default `"theme"`), `linkColor`, `linkHoverColor`,
`linkActiveColor`, `iconColor`, `iconHoverColor`, `iconSize`,
`hamburgerBarWidth`, `hamburgerBarThickness`, `cssVars`, labels
(`labelOpen`, `labelClose`, `labelDark`, `labelLight`, `navLabel`, `menuLabel`,
`linkLabelPrefix`), `themeToggleAriaLabel`, `themeToggleTitle`, `className`.

Behavior worth knowing:
- Hydration-safe theme sync with a `themeReady` gate (see `architecture.md` §7).
- `isActive(url)`: exact match, then `startsWith(url + "/")` with guards that a
  bare `"/"` or `"/xx"` locale prefix never matches everything (patched locally —
  see `docs/xcomponents-fixes.md`).
- Locks body scroll via `body.menu-open` while the overlay is open; closes on
  route change and `Escape`.
- Theme icon reveal on logo hover is pure CSS (width/opacity transition).
- The mobile theme row is hidden when `themeIcons` is not provided.

#### `XZigZagLayoutVideo` — `xcomponents/xzigzagvideo/XZigZagLayoutVideo.tsx`
`XZigZagLayout` with an optional full-bleed background `videoSrc`/`imageSrc` and
an overlay. Measures each child's center point with `getBoundingClientRect`,
builds an SVG polyline, and animates `strokeDashoffset` with scroll progress
(clamped `[0,1]`, start at viewport mid). Adds `fadeInUp` on items when the
wrapper enters the viewport (`IntersectionObserver`, threshold 0.15). Props:
`startSide`, `gap`, `offset`, `textAlign`, `showLine`, `lineColor`,
`lineThickness`, `videoSrc`, `imageSrc`, `overlayColor`, plus div props.
Renders no background wrapper when neither `videoSrc` nor `imageSrc` is given.

#### `XHomeColors` — `xcomponents/xhomecolors/XHomeColors.tsx`
Renders a `WordConfig[]` phrase (`tag` selects `h1..span`) with the marker chip
background, cycling book colors every third chunk. Word types:
`underline` (toggles blur group 1), `button` (toggles blur group 2),
`blur1`/`blur2` (blur until their toggle is on), `normal`. Supports `italic`,
`bold`, `breakAfter`; an empty `text` renders a line break. Focusable/clickable
word types get `role="button"` + Enter/Space handling. Text is rendered through
an inline per-char decrypt that animates on first view. Reads the theme via
`MutationObserver`.

#### `XBookColors` — `xcomponents/xbookcolors/XBookColors.tsx`
Local reader used by Cielos de Alquitrán, Primavera and La danza de las
amapolas (page-level). Parses raw MDX into `section_title | image | content`
items + a trailing `index`, groups into pages alternating 4/5 items, renders
each content page through `XZigZagLayout` + `XBookFullDecrypt` (private), and
supports backgrounds from `bgConfig` (`basePath`, `total`, `digits`, `format`),
`backgroundImage` or `backgroundVideo` with `overlayColor`. Also accepts
`coverImage`, `locale`, `labels`, `sectionNames`, `onPageChange`. See
`book-readers.md` for the parsing algorithm. Its README documents the resolved
bugs: blur applied via inline styles, explicit short-poem type assignment,
`sr-only` duplication, Roman-numeral sections, sequential decrypt, theme
detection without system fallback, color cycling.

#### `BookReaderPoems` — `xcomponents/BookReaderPoems.tsx`
Index-driven reader used by Colaterales. Reads the trailing “Índice/Index/…”
block to build a title→order map, identifies section titles and poem titles,
reorders poems to match the index, merges trailing title-only blocks with the
following content block, then paginates with the standard 4/5 scheme. Section
names and index headers are per-locale tables. Uses `useT("BookReader")` for
`prev/next/pageOf/index/coverAlt`. See `book-readers.md`.

#### `XMinimalFooter` — `xcomponents/xminimalfooter/XMinimalFooter.tsx`
Props `copyright`, `links: { label, href }[]`. Renders a centered, low-opacity
footer line with ` · ` separators.

#### `GrafoPoetico` — `xcomponents/grafo/GrafoPoetico.tsx` (+ `GrafoPage.module.css` in the route)
Canvas force-directed graph of all poems. Nodes come from `poemParser`
(`getAllPoems`), colored by `bookIndex`; edges connect each node to the next two
in the same book. Features: custom physics (repulsion/centering/edge/alpha),
pan (drag background), zoom (wheel/pinch, clamp `0.12–4`), node drag, hover
highlight + radial glow, connected-node highlight, live search with match
highlighting and a result count, a legend, a tooltip, and a framer-motion modal
showing the full poem (markdown bold/italic converted to HTML via `formatLine`).
Per-locale book labels and UI strings are inline tables. Default 8-color
palette, overridable. The page wraps it in a fixed full-screen container.

#### `XBlogDecrypt` — `xcomponents/xblogdecrypt/XBlogDecrypt.tsx`
Renders article HTML with a decrypt animation on every non-LaTeX text node.
Props: `contentHtml` (required), `title`, `image`, `author`, `date`, `isoDate`,
`categories`, `keywords`, `readingTime`, `speed` (default 50, article page
passes 10), `revealColor` (default `var(--accent, #e3342f)`), `scrambleColor`
(default `#b8a8ff`), `startDelay` (default 450 ms). Renders title → meta →
pills → image → body. The body lives in a `React.memo` child (`XBlogBody`) so
React never re-applies `dangerouslySetInnerHTML` and wipes the hand-injected
`span.xblog-text` wrappers. A single shared `IntersectionObserver` reveals text
on scroll after `startDelay` (so it plays after the route-transition overlay
clears). Skips `PRE`/`CODE`/`.katex`. Idempotent and StrictMode-safe. The README
in `xblogdecrypt/` is the authoritative explanation.

#### `XTextDecrypt` — `components/Xtexts/XTextDecrypt/XTextDecrypt.tsx`
General-purpose decrypt text (`HTMLMotionProps<'span'>`). Props: `text`,
`speed`, `maxIterations`, `sequential`, `revealDirection` (`start|end|center`),
`useOriginalCharsOnly`, `characters`, `className`, `encryptedClassName`,
`parentClassName`, `animateOn` (`view|hover`), `delay`. Exposes a `.sr-only`
copy plus an `aria-hidden` animated copy. Used by `PublicKeyCard` for the PGP
fingerprint.

---

## Part B — App-level components (`src/app/components/`, not in the barrel)

### `ClientComponentHome` — `clientcomponenthome.tsx` (+ `ClientComponentHome.module.css`)
The home page hero. Shows an `AsciiLoadingAnimation` overlay for at least
1.2 s, then two `XZigZagLayoutVideo` blocks. It reads 14 `WordConfig[]` arrays
from `useT("HomePhrases")` and renders them as `XHomeColors` with mixed tags
(`h1`, `h2`, `p`). Right block has `startSide="right"`. Background images:
`/images/blog/conocerlamorfologiadeloindeterminado.webp` (block 1) and
`/images/colecciones/arte/arte006.webp` (block 2). Line uses `var(--accent)`,
thickness 0.3.

### `AsciiLoadingAnimation` — `AsciiLoadingAnimation.tsx`
Full-screen `<pre>` ASCII intro. Loads precomputed frames from
`ascii-frames.json` (top-level JSON import), advances one frame every 35 ms,
fades out after the last frame or after a 4 s hard cap, then calls `onDone`.
Font size is `min(100vw / 150, 100vh / 84)`, monospace, `user-select: none`.
`aria-busy` + `aria-live="polite"`.

### `LenisProvider` — `LenisProvider.tsx`
Mounts Lenis smooth scroll (`duration 1.2`, exponential easing,
`anchors.offset 80`, `autoRaf`). Disabled under `prefers-reduced-motion`.
Renders `null`.

### `transitionProvider` — `transitionProvider.tsx`
The dominant client chrome component:
1. Renders `XGlassNavbar` with locale-aware links:
   - left: Home `/`, Obras `/obras`, Info `/info`
   - right: Contacto `/contacto`, Blog `/blog`, external `https://xscriptor.io`
     (`</>` dev link).
2. Renders a **fixed bottom-center language dock** (ES/DE/EN/IT/FR pills,
   `aria-current`, `switchLocale()` which rewrites the path preserving the rest
   of the route).
3. Renders the route-transition overlay: two black rounded panels
   (`border-radius: 100px`) collapsing from `100vh` to 0 (top immediately,
   bottom delayed 0.2 s) plus a fading path label, keyed by `pathname` inside
   `AnimatePresence mode="wait"`.

Locale/label maps (`LOCALE_KEYS`, `NAV_LABELS`, `langLabels`) are inline,
per-locale. Icons come from `icons/navbar/navbarIcons.tsx`.

### `ConditionalSeparator` — `layout/ConditionalSeparator.tsx`
Renders an `XSeparator` (dashed, accent, `hasX`, faded, `my-8`) **except** on a
hardcoded list of paths: home, obras, blog, grafo, contacto (all locales), plus
any path containing `asintota`/`asíntota`/`cielos-de-alquitran`/
`la-danza-de-las-amapolas`. Rendered both above and below `main`.

### `XFooterComponent` (default export `SiteXFooter`) — `layout/footer/XFooterComponent.tsx`
Client component: derives locale from `usePathname()` (note: only `en/es/de`),
picks footer strings from the message JSONs via `getMsg`, and renders
`XMinimalFooter` with the current year and links to terms + contact.

### `PublicKeyCard` — `publickey/PublicKeyCard.tsx` (+ `.module.css`)
Neumorphic PGP card. Fetches `/x-public.asc` and renders it in a `<pre>`.
Generates a QR of the hardcoded fingerprint
`43086B71054295FF252949AD3F03BDE89BE5176F` (`qrcode`, EC level M, 168px), shows
`.asc` download, a per-char decrypt of the formatted fingerprint via
`XTextDecrypt`, a copy-to-clipboard button with a `copied` confirmation state, and the
`SocialGrid`. Labels come from `useT("ContactPage")`. Theme via
`:root.light`/`:root.dark` neumorphic shadows.

### `SocialGrid` — `socialgrid/SocialGrid.tsx`
Five hand-drawn SVG icon links (GitHub, Telegram, Instagram, WhatsApp, Email)
in a circular “badge” style with an `XCorner` mark. Hover via inline styles
using `color-mix` on `var(--foreground)`.

### `ParticlesBackground` — `xbackgrounds/ParticlesBackground.tsx`
Wraps `XParticles` from `@xscriptor/xbackgrounds`
(`particleCount 1200`, `trailOpacity 0.07`, `speed 0.8`, light `255,255,255`,
dark `10,10,10`). Mirrors `data-theme` to `dark`/`light` classes on `<html>`.
Used on Contacto and Info.

### `BlogListClient` — `blog/BlogListClient.tsx`
Blog index body. Fixed glass filter bar with a search input and category pills
(derived from article categories, single-select toggle). Renders full-viewport
stacked article cards; the card nearest viewport center is `articleActive`
(others blurred/dimmed). Each card shows image (or accent gradient), title,
excerpt, up to 2 category pills, localized date, and reading time. Uses
`useT('BlogPage')` and `useLocale()`; date locale mapping
`de-DE/it-IT/fr-FR/en-US/es-ES`. Links to `/{locale}/blog/{slug}`.

### `ObrasClientPage` — `[locale]/obras/ObrasClientPage.tsx`
Book gallery. Hardcoded `BOOKS` array (slug/key/img) plus a final graph card.
Same center-detection + blur-on-inactive behavior as the blog list. Uses
`useT()` for `Books.*` titles/descriptions and `ObrasPage.*`, links to
`/{locale}/obras/{slug}`.

### Reader wrappers (`[locale]/obras/*/*.tsx`)
- `AsintotaBook`, `CielosDeAlquitranBook`, `AmapolasBook`: thin client wrappers
  that own a page→background rotation (`TOTAL_BG` 72 / 30 / 31), preload the
  next background with `new Image()`, and pass labels (and, for Amapolas,
  `sectionNames` + `renderPoem={<XBookFullDecrypt/>}`) into the reader.
- Boulevard page inlines the npm `XBookReader` directly.

### Icons — `icons/navbar/navbarIcons.tsx`
`SunIcon` and `MoonIcon` (stroke, `currentColor`, size/strokeWidth/title props,
`role="img"` + `aria-hidden`/`aria-label`).

### `not-found.tsx`
Client 404: a dashed book SVG in accent color, big `404`, localized message and
“back home” link. Locale is derived from `usePathname()` with
`/^\/(en|es|de|it|fr)/` (unlike `XFooterComponent`, which only matches
`en|es|de`).

### `UpdateHtmlLang`
Tiny client effect that sets `document.documentElement.lang = locale`.

---

## Part C — Component recipes

### “Animated word / phrase”
Use `XHomeColors` (home) or `XInteractivePhrase` / `XBookFullDecrypt`
(books). Words are `WordConfig[]` (see `content-pipeline.md`).

### “Text that decrypts on scroll”
Wrap with `XTextDecrypt` (`animateOn="view"`) or, for whole HTML articles,
`XBlogDecrypt`.

### “Full-bleed art section with text”
`XZigZagLayoutVideo` with `imageSrc`/`videoSrc` + `overlayColor`, children as
`XHomeColors`/marker chips.

### “Paginated book”
Pick the engine from `book-readers.md`; never hand-roll pagination.

### “New reusable UI block”
1. If it belongs to the shared library, add it to `@xscriptor/xcomponents` and
   bump the version — do **not** fork it locally.
2. If it is site-specific, add it under `src/app/components/...` with a CSS
   module, and — if it must be importable from Server Components — export it
   through the `"use client"` barrel.
3. Honor reduced motion and both themes.
