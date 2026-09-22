# Xscriptor Design System

Canonical reference for the visual language of xscriptor.com. Everything here is
extracted from the live source: `src/app/globals.css` (tokens + global rules),
the CSS-module files, and the inline styles inside components.

---

## 1. Design intent

Xscriptor is a **literary portfolio**: an author/poet/artist presenting books,
articles and a contact surface. The visual language is deliberately:

- **Typography-first.** EB Garamond carries the entire experience. There is no
  display font, no icon font, no decorative typeface. Words are the interface.
- **Marker / highlighter aesthetic.** Runs of text are placed on soft
  background "chips" (`color-mix(in srgb, var(--bg) 88%, transparent)`) so that
  text stays legible over photographs and full-bleed art.
- **Restrained dual palette.** One accent per theme: deep violet in light mode,
  warm gold in dark mode. Everything else is background, text and border.
- **Atmospheric imagery.** Full-viewport photographs and pre-rendered
  background frames sit behind content with a dark overlay.
- **Literary / cryptographic tension.** The site mixes emotional, poetic copy
  with PGP keys, fingerprints and decryption-style animations (text descrambles
  character by character). This is a signature motif, not a gimmick.
- **Motion as reveal.** Decryption, staggered fades and blur-to-focus are used
  to reveal content. Nothing bounces or plays for its own sake.
- **Both themes are first-class.** Light mode is the marketing default; dark
  mode is the reading default for book pages and is fully supported everywhere.

When adding UI, ask: *does this read like a printed literary edition that has
learned to decrypt itself?* If not, it is off-brand.

---

## 2. Color tokens

All colors are CSS custom properties declared in `src/app/globals.css`. Use the
variables, never raw hex values (the only sanctioned raw hexes are the book
word-color palette in §5).

### Light theme (default, `:root`)

| Token | Value | Use |
|-------|-------|-----|
| `--bg` | `#ffffff` | Page background |
| `--text` | `#000000` | Primary text |
| `--accent` | `#5b2e8d` | Links, active nav, borders, pills, decrypt reveal |
| `--accent-text` | `#ffffff` | Text on accent-filled surfaces |
| `--border` | `rgba(0, 0, 0, 0.1)` | Hairlines, card borders, dividers |
| `--foreground` | `#171717` | Near-black used by neumorphic card + social icons |
| `--text-muted` | `#6b7280` | Secondary/meta text |
| `--primary` | `#4328a8` | Deep violet (select controls, PGP card) |
| `--primary-hover` | `#7c3aed` | Hover state for `--primary` |
| `--success` | `#10b981` | Status dot (PGP key loaded) |

### Dark theme (`:root[data-theme="dark"], :root.dark`)

| Token | Value | Use |
|-------|-------|-----|
| `--bg` | `#0a0a0a` | Page background |
| `--text` | `#ffffff` | Primary text |
| `--accent` | `#ffe884` | Warm gold: links, active nav, borders |
| `--accent-text` | `#000000` | Text on gold surfaces |
| `--border` | `rgba(255, 255, 255, 0.1)` | Hairlines |
| `--foreground` | `#ededed` | Off-white |
| `--text-muted` | `#9ca3af` | Secondary text |
| `--primary` | `#fbbf24` | Amber |
| `--primary-hover` | `#f59e0b` | Amber hover |
| `--success` | `#34d399` | Status dot |

> Both selectors are required: `[data-theme="dark"]` (set by the navbar toggle)
> **and** `.dark` (set on `<html>` by `ParticlesBackground` for components that
> key off a class). PublicKeyCard CSS relies on `:root.light` / `:root.dark`.

### Semantic color rules

- Links default to `var(--accent)`. Global `a:hover` forces `#ff4141` (a hard
  red) — this is a legacy rule; prefer component-scoped hover (opacity or
  accent) for new work.
- Syntax highlighting inside `.article-content` has **two full palettes**: a
  light “One Light”-style set and a dark set scoped under `[data-theme="dark"]`.
- KaTeX gets extra left/right breathing room via `.article-content .katex`.

---

## 3. Typography

### Font family

```css
@font-face { font-family: "EB Garamond"; src: url("/fonts/EBGaramond-Regular.woff2") ...; font-weight: 400; font-style: normal; font-display: swap; }
@font-face { font-family: "EB Garamond"; src: url("/fonts/EBGaramond-Italic.woff2") ...; font-weight: 400; font-style: italic; font-display: swap; }
```

- `html, body { font-family: "EB Garamond", serif; }`
- Only **woff2** files exist in `public/fonts/` (Regular + Italic). The
  `@font-face` also lists `.ttf` sources that are **not present** — harmless
  (the woff2 loads first), but do not rely on the ttf.
- Monospace appears only for technical metadata: PGP fingerprint / key, `.asc`
  download link, code blocks (`'Fira Code', 'Monaco', monospace`), and the
  `ui-monospace` used by the ASCII intro. It is never used for body copy.

### Global element scale (in `globals.css`)

These apply site-wide and are **centered by default**:

| Element | Weight | Size | Margins |
|---------|--------|------|---------|
| `h1` | 400 | `clamp(16px, 12vw, 32px)` | `1vw` top/bottom |
| `h2` | 300 | `clamp(24px, 8vw, 26px)` | `1vw` |
| `h3` | 600 | `clamp(20px, 9vw, 26px)` | `1vw` |
| `p` | 400 | `clamp(18px, 2.5vw, 20px)` | `2vw` + side padding `clamp(1rem, 8vw, 4rem)` |

Notes:
- The `h1` clamp is unusual: `12vw` means it is small on phones and caps at
  32px. Do not “fix” it globally — page/components override it where a hero is
  needed (`ObrasPage` title, section titles use their own clamps).
- Paragraphs carry large horizontal padding so prose never spans full-bleed.

### Article typography override

`.article-content` (used by `XBlogDecrypt`) **cancels the centered prose**:

- `p` → left aligned, no side padding, `clamp(16px, 2vw, 18px)`, `line-height 1.8`.
- `h1–h4` → left aligned; `h2` gets a bottom border, `h3` smaller.
- Lists, blockquotes (accent left border), inline/fenced code, images, tables,
  `hr`, links (underlined) all get dedicated rules.
- Tables are wrapped in `.table-wrapper` (added by `articles.ts`) for horizontal
  scroll on mobile; the table gets `min-width: 600px`.

### Body-text line-height conventions

- Global paragraphs inherit the browser default; literary body copy in readers
  uses explicit `line-height` between `1.7` and `2` (e.g. `BookReaderPoems`
  sets `line-height: 2 !important` on poem paragraphs).
- Display/marker chips use `line-height: 1.8` so multi-line highlighted runs do
  not collide.

---

## 4. Surfaces, borders and effects

### Glassmorphism (`.glass`, navbar, filter bars, modals)

```css
background: color-mix(in srgb, var(--bg) 70%, transparent); /* light */
backdrop-filter: blur(18px);
border: 1px solid var(--border);
/* dark variant */
background: color-mix(in srgb, var(--bg) 15%, transparent);
```

Used by: `XGlassNavbar` (blur 20px, radius `9999px`, layered shadows),
blog filter bar (blur 18px, radius pill), graph tooltip/legend/modal
(blur 12–30px), `GrafoPoetico`.

### Marker / highlighter chip

The single most repeated visual atom:

```css
background: color-mix(in srgb, var(--bg) 88%, transparent);
padding: 0.1em 0.35em;
border-radius: 0.2em;
box-decoration-break: clone;
-webkit-box-decoration-break: clone;
```

Used for: home/book words (`XHomeColors`, `XBookColors`), section titles,
index entries, poem titles, book titles/descriptions, page indicators. It keeps
text readable over any background. Blog-list cards use a darker variant
(`color-mix(in srgb, #000 55%, transparent)` with white text) because they sit
over imagery.

### Neumorphism (PublicKeyCard only)

The PGP card is the one place with a soft-UI treatment. It uses a local
`--neumorph-bg` token (`#e9e9e9` light / `#16181d` dark) plus hand-written
dual-shadow recipes for raised and inset surfaces (card, QR frame, fingerprint
chip, buttons, key block). Theme is selected by `:root.light` / `:root.dark`.

### Shadows

- Cover images / inline images: `0 10px 25px rgba(0,0,0,0.2)`, radius 12px.
- Navbar: two stacked shadows (`0 4px 6px -1px` + `0 8px 32px`), stronger in dark.
- Modals: `0 8px 48px rgba(0,0,0,0.4)`.
- Book cards (Obras/Blog): overlay `rgba(0,0,0,0.35)`–`0.4` over the photo.

### Radii

- Pills / nav / language dock: `9999px`.
- Cards / cover / modal: `12px`–`16px` (PublicKeyCard up to `2rem`).
- Marker chips: `0.2em`; small controls `4px`–`8px`.

---

## 5. Book word-color palette

The interactive poem readers cycle a fixed palette across word chunks. This is
the only place raw hex values are allowed (they are applied inline as
`color` and `--c-word`).

| Key | Dark theme | Light theme |
|-----|-----------|-------------|
| `c1` | `#fc618d` (pink) | `#8f002a` (wine) |
| `c2` | `#7eddc9` (teal) | `#007052` (green) |
| `c3` | `#8eeca3` (green) | `#265731` (deep green) |
| `c4` | `#fce566` (yellow) | `#7a6e14` (olive) |
| `c5` | `#b8a8ff` (lavender) | `#5a4e9e` (violet) |

`c0` is the surface color (`#0a0a0a` dark / `#ffffff` light) and is used as the
foreground when a `button` word is hovered (accent fill).

Assignment rule (`WORD_COLORS`, `COLOR_INTERVAL = 2`): every third chunk gets a
color key, the two in between are `null` and inherit `var(--text)`. Dark/light
maps are selected by a `MutationObserver` on `document.documentElement`'s
`data-theme` attribute (`useDetectTheme`). There is **no** `prefers-color-scheme`
fallback: `data-theme !== "dark"` means light.

`GrafoPoetico` uses its own 8-color graph palette:
`#ff6b6b, #ffd93d, #6bcb77, #4d96ff, #ff6bff, #ff9f43, #22d3ee, #54a0ff`,
overridable via `color1`…`color8` props.

---

## 6. Motion & animation language

| Effect | Where | Spec |
|--------|-------|------|
| Route transition | `transitionProvider.tsx` | Two black `border-radius:100px` panels collapse `100vh → 0` (top delay 0, bottom delay 0.2s, total ~0.4s) + a fading path label |
| Page/reader fade | `XCompleteBook`, `XBookColors`, `BookReaderPoems` | `fadeSlideIn`: `translateY(20px)→0`, opacity 0→1, 0.5s–0.8s ease-out |
| Zigzag stagger | `XZigZagLayoutVideo` | `fadeInUp` 0.5s per item, `animationDelay = index * 0.12s`, triggered by `IntersectionObserver` |
| Scroll line draw | `XZigZagLayout` / `XZigZagLayoutVideo` | SVG path `strokeDashoffset` tied to scroll progress |
| Text decrypt | `XTextDecrypt`, `XBlogDecrypt`, `X*Colors` | Character-by-character reveal, scrambled tail in `scrambleColor`; default speed 50 ms (blog body uses 10 ms) |
| Blur reveal | `XBookColors`/`XHomeColors` blur words | `filter: blur(10px) opacity .3` → `blur(0)` over 0.7s cubic-bezier(0.4,0,0.2,1) |
| Smooth scroll | `LenisProvider` | `duration: 1.2`, exponential ease, anchor offset 80, `autoRaf` |
| Graph physics | `GrafoPoetico` | Custom canvas spring: repulsion `1200α`, centering `.002α`, edge `.003α`, alpha decay `×0.992`, live `requestAnimationFrame` |
| Card hover (info) | `InfoPage.module.css` | `translateY(-5px)` + stronger shadow |
| Button/pill hover | everywhere | color swap, background fill, opacity |

### Reduced motion

`globals.css` globally neutralizes animation/transition durations under
`@media (prefers-reduced-motion: reduce)`. Components also guard individually:

- `LenisProvider` disables smooth scroll entirely.
- `XZigZagLayoutVideo` hides the background video and disables `itemReveal`.
- `XCompleteBook`/`XBookColors` disable `bookContent` animation.
- `XGlassNavbar` disables nav/hamburger/overlay transitions.
- Blog/Obras blur-on-inactive is disabled and content shown at full opacity.

> New animated components **must** honor `prefers-reduced-motion`, either via
> the global rule or a component-level guard.

---

## 7. Responsive breakpoints

The site uses Tailwind's default breakpoints where utilities are used, and
hand-written media queries elsewhere. Observed working set: `640px`, `768px`,
`1024px`, `1200px` (max content width).

Key behavior:
- `XGlassNavbar`: desktop link sections (`12rem` → `14rem` at `lg`); below
  `768px`, link sections are hidden and a fixed glass hamburger + full-screen
  overlay menu appear.
- Full-bleed sections use the “breakout” trick:
  `width: 100vw; margin-left: calc(-50vw + 50%);` (Obras/blog cards, zigzag/video
  wrappers). Never use raw `vw` padding without `clamp()`.
- Book readers stack a `readerContainer` (`min-height: 100vh`,
  `justify-content: space-between`) so pagination pins to the bottom.
- `InfoPage` bio/timeline use `padding: 0 15vw` on desktop (a candidate for a
  `clamp()` cleanup — see anti-patterns).

---

## 8. Accessibility rules already in the codebase

Preserve these patterns in new work:

- **Skip link**: `.skip-to-content` in `globals.css` + `<a href="#main-content">`
  in the root layout; it slides in on `:focus`.
- **`.sr-only`** utility (defined globally, also expected by npm components)
  backs every decryption animation: visible text is `aria-hidden="true"`, and a
  hidden `.sr-only` span carries the real text for screen readers.
- **Focus-visible outlines** (`2px solid var(--accent)`) on navbar logo,
  hamburger and mobile theme button.
- Navbar exposes `aria-label`, `aria-expanded`, `aria-controls`; the language
  dock uses `aria-current="true"` for the active locale.
- `<html lang>` is corrected per locale by `UpdateHtmlLang`.
- `html { scroll-padding-top: 5rem }` keeps anchored content clear of the navbar.
- `suppressHydrationWarning` on `<html>` is intentional (theme attribute set
  before hydration).

---

## 9. Design-system checklist for new UI

1. Use `var(--bg)`, `var(--text)`, `var(--accent)`, `var(--border)` — never raw
   hex except the documented book/graph palettes.
2. Set text on a marker chip when it floats over imagery.
3. Prefer `clamp()` for fluid type and spacing; cap wide-screen padding.
4. Verify both themes (toggle is the navbar logo).
5. Verify `<768px` (navbar collapses) and reduced-motion.
6. Keep animation subtle and purposeful; reveal, don't decorate.
7. Reuse the existing components (see `component-catalog.md`) before writing new
   ones.
