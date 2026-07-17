---
name: devx
description: Technical UI documentation for the DevX visual system. Invoke when extending, refactoring, or redesigning the DevX resources pages, i18n, or related components.
version: 2.0.0
allowed-tools: [Read, Glob, Grep, Edit, Write]
---

# DevX UI System

This skill documents the design and implementation logic of the DevX UI layer used across `resources/vscode`, `resources/terminal`, and `resources/xfetch` pages and their related components.

Companion references:

- `references/tokens.md`: canonical token model for DevX UI, including theme, spacing, sizing, and motion guidance
- `references/platform-mapping.md`: preferred future file placement for routes, components, data, types, hooks, and helpers
- `references/tokens-and-layout.md`: compact quick reference
- `references/code-structure.md`: current recommended structure and responsibilities

Use this skill when:

- building new sections for the DevX resources pages
- extending the VS Code showcase UI
- refactoring layout, CSS modules, or component boundaries
- adding new cards, preview areas, galleries, sliders, or CTA sections
- making UI changes that should remain visually consistent with the existing DevX direction

The goal is not to generate generic UI. The goal is to preserve a very specific product language:

- technical but elegant
- minimal, not decorative
- content-led, not card-led
- dark-mode aware through project theme variables
- responsive without horizontal overflow
- easy for AI agents to extend safely

---

## 1. Core Design Intent

The DevX page language is a hybrid of:

- editorial layout
- tool-like UI
- low-noise interface chrome
- strong visual hierarchy through spacing and contrast

It should feel closer to a carefully composed product documentation page than to a marketing landing page full of visual effects.

### 1.1 Visual Traits

- Prefer flat surfaces over elevated cards.
- Prefer lines, spacing, and alignment over heavy framing.
- Use color as accent and state, not as decoration.
- Keep large sections open and breathable.
- Let screenshots, previews, and code surfaces carry the visual richness.

### 1.2 What To Avoid

- random gradients in UI chrome
- rounded cards everywhere
- shadow-heavy surfaces
- excessive Tailwind utility styling inside page-specific UI
- decorative wrappers with no structural purpose
- deeply nested component trees for simple presentation logic

---

## 2. Theme Variable Contract

Always prefer project-level CSS variables instead of hardcoded UI colors for page chrome.

For the broader token model and future semantic token layering, see `references/tokens.md`.

Primary variables used by the current DevX page:

- `--background`
- `--foreground`
- `--primary`
- `--text-muted`
- `--border`
- `--card-bg`

### 2.1 Usage Rules

- `--background`: the main page surface
- `--foreground`: primary readable text
- `--text-muted`: secondary copy, technical descriptions, metadata
- `--primary`: active states, underline states, primary buttons, branded emphasis
- `--border`: separators, subtle outlines, technical dividers
- `--card-bg`: optional blending helper for mixed surfaces

### 2.2 Color Strategy

- Main layout chrome should derive from theme variables.
- Interactive editor previews may use derived or theme-specific preview colors when needed.
- If a showcase simulates a product UI, local CSS variables are acceptable inside that component only.
- Do not let local preview colors leak into global page chrome.

---

## 3. Typography And Hierarchy

The page uses the project font system already defined in the app. Do not replace the font stack unless explicitly requested.

### 3.1 Typography Principles

- `h1` should match the scale and weight strategy of other resource pages.
- Section titles should be strong but not oversized.
- Eyebrows should be compact, technical, and sparingly used.
- Description text should stay readable, usually within `56ch` to `68ch`.

### 3.2 Case Rules

- Avoid forcing uppercase across the interface unless there is a very specific technical label or micro-label.
- Prefer sentence case or title case for human-facing UI.

---

## 4. Layout Principles

### 4.1 Section Composition

Each large section should follow a simple structure:

1. identity or context
2. main content surface
3. supporting utility or CTA

Examples:

- `xscriptor themes`: selector, preview/video, palette, actions
- `xglass`: icon, copy, slider, CTA

### 4.2 Alignment

- Use left alignment by default.
- Avoid arbitrary centering in dense UI sections.
- Align controls and copy to consistent inner edges.
- Let media blocks fill width, but keep textual blocks within readable width.

### 4.3 Spacing

- Use spacing to create hierarchy before adding borders.
- Prefer section gaps of `1rem` to `2rem` inside components.
- Prefer larger inter-section gaps across page modules.
- If a divider feels necessary, first verify whether spacing contrast is sufficient.

---

## 5. Responsive Rules

This page must work without horizontal scrolling on mobile.

### 5.1 Non-Negotiables

- Always set `min-width: 0` on grid and flex children that can shrink.
- Never leave desktop-only `min-width` values active on mobile.
- Allow text to wrap using `overflow-wrap: anywhere` where code-like or long labels appear.
- Convert horizontal selectors into stacked or grid layouts on smaller screens.
- Convert action groups to full-width buttons on mobile when needed.

### 5.2 Media Blocks

- Sliders and screenshots may be visually large, but must still respect viewport width.
- Increase height through `min-height`, not through unsafe width assumptions.
- On mobile, reduce density before reducing readability.

### 5.3 Preview Surfaces

- Editor-like previews may have internal scroll.
- Internal scroll must not cause global horizontal page overflow.
- Internal scroll areas should retain keyboard focusability when accessibility matters.

---

## 6. Motion Rules

Motion on this page should be calm, structural, and secondary.

### 6.1 Use Motion For

- section reveal on scroll
- subtle state change between preview modes
- opacity/translate entrance
- indicator transitions

### 6.2 Do Not Use Motion For

- bounce
- spring-heavy interactions
- decorative looping transforms unrelated to content
- large parallax effects

### 6.3 Motion Style

- prefer `ease` or `ease-out`
- keep durations short to medium
- respect `prefers-reduced-motion`
- use CSS transitions when possible for simple reveal and dim states

---

## 7. Component Boundaries

The DevX page already follows a useful separation pattern. Keep that logic.

For the future-oriented file placement model, see `references/platform-mapping.md`.

### 7.1 Reusable Components Belong In

`src/app/components/xcomponents/`

Examples:

- `vscode-theme-gallery`
- `xglass-showcase`
- `vscode-resource-sections`
- `repo-card`
- `icons`

### 7.2 Route-Specific Files Belong Near The Route

`src/app/resources/vscode/`

Examples:

- `page.tsx`
- `vscode.module.css`
- route-only references or static notes

### 7.3 Data And Types

Use:

- `src/data/...` for structured content/configuration
- `src/types/...` for shared types

Do not mix route data arrays directly into large page files when the structure is reusable or likely to grow.

---

## 8. Ideal Project Structure

For this project, the recommended structure is:

```text
src/
  app/
    resources/
      vscode/
        page.tsx
        vscode.module.css
        references.md
    components/
      xcomponents/
        vscode-resource-sections/
        vscode-theme-gallery/
        xglass-showcase/
        repo-card/
        icons/
  data/
    resources/
      vscode/
        vscodeThemes.data.ts
  types/
    resources/
      vscode.types.ts
```

### 8.1 Structure Rules

- page files should compose, not contain large UI logic
- route CSS modules should style layout, not complex embedded widgets
- reusable widgets should own their own `module.css`
- data should be serializable and easy to inspect
- component APIs should remain explicit and prop-driven

---

## 9. Styling Rules

### 9.1 Preferred Styling Method

- use `module.css` for page and component styling
- prefer CSS Modules as the default styling approach for feature UI
- use project theme variables
- use local CSS custom properties for component-specific preview theming

### 9.2 Tailwind Usage

- avoid depending on Tailwind for the main page composition when the section already has a dedicated CSS module
- use Tailwind only for trivial layout helpers when a dedicated CSS module would be unnecessary
- do not mix complex Tailwind class soup with carefully structured CSS modules

### 9.3 Border Radius

- default to `0` or very restrained rounding for technical UI
- reserve soft rounding only for image assets, media previews, or when explicitly part of the product visual

### 9.4 Borders And Surfaces

- use borders sparingly
- prefer one structural line over boxed components everywhere
- surfaces should feel integrated, not stacked as disconnected cards

---

## 10. Accessibility Rules

The DevX page should be easy to navigate and readable for assistive technologies.

### 10.1 Required Practices

- provide semantic headings
- use proper `aria-label` or `aria-describedby` for custom interactive areas
- keep keyboard navigation viable in tablists, sliders, and scrollable preview regions
- ensure motion has a reduced-motion fallback
- preserve sufficient contrast in primary surfaces and key UI states

### 10.2 Preview-Specific Practices

- a simulated editor preview should describe itself semantically
- if a palette hides visible labels on mobile, provide equivalent text through `aria-label` or `title`
- do not set `aria-hidden` on still-interactive visible content

---

## 11. Implementation Checklist For AI Agents

Before editing the DevX page, verify:

1. Does the new section reuse existing theme variables?
2. Is the component route-specific or reusable?
3. Will the layout remain overflow-safe on mobile?
4. Are spacing and alignment doing the hierarchy work?
5. Is motion subtle and optional?
6. Is the component accessible with keyboard and screen readers?
7. Is data separated from rendering if the content is structured?
8. Is the resulting code easier to extend than before?

If the answer to any of these is no, revise the solution before finalizing.

---

## 12. Specific Guidance For `resources/vscode`

The current page is split into two major content stories:

- Xscriptor Themes
- Xglass

### 12.1 Xscriptor Themes

This section is interactive and data-driven.

It should preserve:

- a selector that feels technical, not decorative
- a hero state that can show video or interactive preview
- preview-local colors that simulate each theme faithfully
- compact supporting metadata and actions

### 12.2 Xglass

This section is more showcase-oriented.

It should preserve:

- clear product identity through icon + copy
- visually dominant screenshots
- a restrained CTA
- a softer transition from the previous section through reveal and dim logic

---

## 13. Output Expectations

When an AI agent extends this page, the expected result is:

- structurally clean
- visually minimal
- thematically consistent
- responsive without hacks
- accessible by default
- easy to maintain by humans after the fact

If a proposed solution is clever but harder to maintain, reject it.

Choose clarity over novelty.

---

## 14. i18n — Internationalization Architecture

The project supports three locales: **English** (`en`), **Spanish** (`es`), and **German** (`de`).

### 14.1 How it works

- All routes live inside `src/app/[locale]/` (Next.js dynamic segment).
- `localePrefix: 'always'` — every URL includes the locale: `/en/`, `/es/`, `/de/`.
- The **root** `/` serves English content directly (static HTML), so users hitting the bare domain get English without a redirect.

### 14.2 Provider stack

```
src/app/i18n-provider.tsx     ← custom React context (NOT next-intl)
```

- `I18nProvider` reads locale + messages from `messages/{locale}.json`.
- `useT(namespace?)` hook returns `(key, params?) => string` for client components.
  - `.raw<T>(key)` returns structured data (e.g. arrays of skill definitions).
  - `params` supports `{var}` interpolation.
- `useLocale()` hook returns the current locale string (`"en" | "es" | "de"`).

### 14.3 Architecture rules

| Scope | Mechanism | Files |
|-------|-----------|-------|
| Layout | `[locale]/layout.tsx` loads JSON messages and passes to `I18nProvider` | `messages/{locale}.json` |
| Server component pages | Import JSON directly + prefix URLs with `params.locale` | `resources/page.tsx`, `repos/page.tsx`, `terminal/page.tsx` |
| Client component pages | Use `useT("Namespace")` hook | All `[locale]/*/page.tsx`, shared components |
| Shared components | Use `useT("Namespace")` hook | `Navbar`, `Footer`, `ContactForm`, `SkillNetwork`, etc. |

### 14.4 Navbar locale-aware linking

- All navbar links are prefixed with `/${locale}/` at render time.
- `NavLink.jsx` strips the locale prefix from `usePathname()` for active detection.
- The language selector sits on the far right with a globe SVG icon.
  - **Desktop**: hover to expand a dropdown with ES/DE options.
  - **Mobile/touch**: click to toggle; click outside to close.
  - Current locale is highlighted; switching stays on the same page path.

### 14.5 Internal link rule

Any hardcoded internal link (`/resources/vscode`, `/resources/terminal`, `/contact`, etc.)
**must** be prefixed with the current locale at render time:

```tsx
// Server component — use params.locale
const href = `/${locale}/resources/vscode`;

// Client component — use useLocale() hook
const locale = useLocale();
// ...
<Link href={`/${locale}/resources`}>Back</Link>
```

### 14.6 Translation files

```
messages/
  en.json     ← English (default, also served at /)
  es.json     ← Spanish
  de.json     ← German
```

Flat JSON structure, namespaced by component/page:

```json
{
  "Navbar": { "home": "Go home" },
  "HomePage": { "heroTitle1": "Discover the" },
  "ContactForm": { "nameLabel": "Name*://" }
}
```

Add new keys under the relevant namespace. Use `{variable}` syntax for dynamic values.

### 14.7 `_headers` + security (build output)

```
public/
  _headers               ← CSP, HSTS, X-Frame-Options (Netlify/Cloudflare format)
  robots.txt             ← allows crawlers, points to sitemap
  sitemap.xml            ← all routes × 3 locales with hreflang annotations
  .well-known/security.txt
```

These are copied verbatim to `out/` at build time by Next.js static export.

---

## 15. Specific Guidance For `resources/terminal`

The terminal resources page is a data-rich, filterable showcase of terminal themes and emulator installers. It lives at `src/app/[locale]/resources/terminal/` with its main component in `src/app/components/xcomponents/terminal-resource-sections/`.

### 15.1 Page Structure

```
section.page                  ← grid, gap: 1.5rem (mobile: 1.25rem)
  header.header               ← grid, gap: 0.25rem
    h1                        ← title + <em> emphasis
    p.description             ← max-width: 68ch, color: var(--text-muted),
                                line-height: 1.8 (mobile: 1.7), font-size: 1rem
  div.shell                   ← wrapper from TerminalResourceSections
```

The `TerminalResourceSections` shell uses `display: grid; gap: clamp(2.5rem, 6vw, 4.5rem)` for inter-section spacing.

### 15.2 Surface / Container Pattern

Every bordered container in the terminal page follows the exact same recipe:

```css
/* Standard surface — used for .controls, .commandCard, .themeCard, .installHint */
border: 1px solid color-mix(in srgb, var(--border) 66%, transparent);
background: color-mix(in srgb, var(--background) 94%, var(--card-bg) 6%);
```

Padding varies by role:
- **Controls panel** (`.controls`): `padding: 1.25rem` (mobile: `1rem`)
- **Command card** (`.commandCard`): `padding: 1.1rem` (mobile: `1rem`)
- **Theme card** (`.themeCard`): `padding: 1rem`
- **Install hint** (`.installHint`): `padding: 1.15rem` — uses `border: dashed` instead of solid

All these use `display: grid; gap: [role-specific]; min-width: 0`.

### 15.3 Section Header Pattern

```css
.sectionHeader { display: grid; gap: 0.25rem; min-width: 0; }
.sectionTitle {
  margin: 0; font-size: clamp(1.5rem, 2.2vw, 1.9rem);
  line-height: 1.05; color: var(--foreground);
}
.sectionDescription {
  margin: 0; color: var(--text-muted);
  line-height: 1.7; max-width: 68ch;
}
```

### 15.4 Controls / Filters Section

```
.controls                       ← surface (see 15.2), gap: 1rem
  .controlsHeader               ← flex, justify-content: space-between, gap: 1rem
    .controlsTitle              ← inline-flex, gap: 0.55rem, font-size: 1.1rem
    .controlsMeta               ← color: var(--text-muted), font-size: 0.88rem
  .controlsGrid                 ← grid, gap: 0.85rem, 1-col → 2-col at 820px+
    .control                    ← grid, gap: 0.35rem
      .controlLabel             ← color: var(--text-muted), font-size: 0.85rem
      .input / .select          ← see 15.5
  .terminalChips                ← flex, gap: 0.5rem, overflow-x: auto
    .chip                       ← see 15.6
```

### 15.5 Input / Select Fields

```css
.input, .select {
  width: 100%; min-width: 0; padding: 0.75rem 0.85rem;
  border: 1px solid color-mix(in srgb, var(--border) 72%, transparent);
  background: color-mix(in srgb, var(--background) 88%, var(--card-bg) 12%);
  color: var(--foreground); outline: none;
  transition: border-color 0.2s ease, background-color 0.2s ease;
}
.input::placeholder {
  color: color-mix(in srgb, var(--text-muted) 78%, transparent);
}
.input:focus, .select:focus {
  border-color: color-mix(in srgb, var(--primary) 62%, var(--border) 38%);
  background: color-mix(in srgb, var(--background) 84%, var(--card-bg) 16%);
}
```

### 15.6 Chips (Terminal Filter Buttons)

```css
.chip {
  flex: 0 0 auto; border: 1px solid color-mix(in srgb, var(--border) 72%, transparent);
  background: transparent; color: var(--text-muted);
  padding: 0.5rem 0.75rem; font-size: 0.84rem; line-height: 1;
  white-space: nowrap; cursor: pointer;
}
.chip:hover, .chip:focus-visible {
  color: var(--foreground);
  border-color: color-mix(in srgb, var(--primary) 40%, var(--border) 60%);
}
.chip[data-active="true"] {
  background: color-mix(in srgb, var(--primary) 14%, transparent);
  color: var(--primary);
  border-color: color-mix(in srgb, var(--primary) 50%, var(--border) 50%);
}
```

### 15.7 Terminal Preview Section

The preview container: `display: grid; gap: 1rem`.

Preview controls row: `display: grid; gap: 0.35rem; max-width: 26rem`.

#### 15.7.1 Preview Surface

```css
.previewSurface {
  position: relative; padding: clamp(1rem, 3vw, 1.6rem);
  border: 1px solid color-mix(in srgb, var(--border) 66%, transparent);
  background-image: url("/images/resources/terminal/terminal-background.png");
  background-size: cover; background-position: center; overflow: hidden;
  border-radius: 30px;
}
.previewSurface::after {
  content: ""; position: absolute; inset: 0;
  background: rgba(0, 0, 0, 0.1);
  mix-blend-mode: multiply; pointer-events: none; z-index: 0;
}
```

#### 15.7.2 Terminal Frame

Inside `.previewSurface` at `z-index: 1; isolation: isolate;`:

```css
.terminalFrame {
  display: grid; position: relative; max-width: 66rem; margin: 0 auto;
  border: 1px solid color-mix(in srgb, var(--border) 66%, transparent);
  border-radius: 1.15rem;
  background: color-mix(in srgb, var(--background) 92%, var(--card-bg) 8%);
  box-shadow:
    0 0 0 1px color-mix(in srgb, var(--primary) 12%, transparent),
    0 28px 64px rgba(0, 0, 0, 0.38);
  overflow: hidden; min-width: 0;
}
```

The frame uses local CSS custom properties prefixed `--t-*` set dynamically from JS:

| Variable | Default | Purpose |
|----------|---------|---------|
| `--t-bg` | `#0b0b0b` | Terminal background |
| `--t-fg` | `#ededed` | Terminal foreground |
| `--t-muted` | `rgba(255,255,255,0.65)` | Muted text |
| `--t-soft` | `rgba(255,255,255,0.5)` | Soft text |
| `--t-dim` | `rgba(255,255,255,0.4)` | Dim text |
| `--t-c2` | `#34d399` | Syntax: green |
| `--t-c3` | `#fbbf24` | Syntax: yellow |
| `--t-c4` | `#60a5fa` | Syntax: blue |
| `--t-c5` | `#a78bfa` | Syntax: purple |
| `--t-c6` | `#5ad4e6` | Syntax: cyan |

#### 15.7.3 Terminal Header

```css
.terminalHeader {
  display: flex; align-items: center; justify-content: space-between; gap: 0.75rem;
  padding: 0.75rem 0.9rem;
  background: color-mix(in srgb, var(--background) 86%, var(--card-bg) 14%);
  border-bottom: 1px solid color-mix(in srgb, var(--border) 62%, transparent);
}
.trafficLights { display: inline-flex; gap: 0.45rem; }
.light { width: 0.7rem; height: 0.7rem; border-radius: 999px; }
.light[data-variant="close"] { background: #ff5f56; }
.light[data-variant="min"]   { background: #ffbd2e; }
.light[data-variant="max"]   { background: #27c93f; }
.terminalTitle {
  color: var(--text-muted); font-size: 0.86rem;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.terminalTitleAccent { color: var(--primary); font-weight: 700; }
```

#### 15.7.4 Terminal Body

```css
.terminalBody {
  padding: 0.85rem 0.95rem 0.95rem;
  background: var(--t-bg); color: var(--t-fg);
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas,
    "Liberation Mono", "Courier New", monospace;
  font-size: 0.72rem; line-height: 1.5; overflow: hidden;
}
```

Typography tokens inside the terminal body:
| Class | Color Variable | Weight |
|-------|---------------|--------|
| `.noticeTag` | `var(--t-c6)` | 700 |
| `.promptUser` | `var(--t-c2)` | 700 |
| `.promptHost` | `var(--t-c5)` | 700 |
| `.promptSigil` | `var(--t-c3)` | normal |
| `.promptCommand` | `var(--t-c4)` | 700 |
| `.fetchHeading` | `var(--t-c2)` | 700 |
| `.fetchRow dt` | `var(--t-soft)` | normal |
| `.fetchRow dd` | `var(--t-fg)` | normal |
| `.tokenDim` | `var(--t-muted)` | normal |
| `.tokenKey` | `var(--t-c3)` | normal |
| `.tokenString` | `var(--t-c2)` | normal |
| `.tokenPunct` | `var(--t-soft)` | normal |
| `.tokenNumber` | `var(--t-c5)` | normal |
| `.inlinePath` | `var(--t-c4)` | normal |

#### 15.7.5 Fetch Grid Layout

At 820px+: `grid-template-columns: minmax(0, 0.62fr) minmax(0, 1fr)`. Below 820px: single column.

Fetch swatch: `width/height: 0.55rem; border-radius: 999px; border: 1px solid rgba(0,0,0,0.35)`.

### 15.8 Command Cards

```css
.commandCard {
  display: grid; gap: 0.75rem;
  border: 1px solid color-mix(in srgb, var(--border) 66%, transparent);
  background: color-mix(in srgb, var(--background) 94%, var(--card-bg) 6%);
  padding: 1.1rem; min-width: 0;
}
.commandHeader { display: flex; align-items: center; justify-content: space-between; gap: 0.75rem; }
.commandTitle { margin: 0; font-weight: 700; letter-spacing: 0.01em; }
```

Copy button:
```css
.copyButton {
  border: 1px solid color-mix(in srgb, var(--primary) 64%, transparent);
  background: transparent; color: var(--primary);
  padding: 0.55rem 0.85rem; font-size: 0.78rem; font-weight: 700;
  cursor: pointer; flex: 0 0 auto;
}
.copyButton:hover {
  background: color-mix(in srgb, var(--primary) 12%, transparent);
  border-color: color-mix(in srgb, var(--primary) 78%, transparent);
}
```

### 15.9 Code Blocks

```css
.codeBlock, .themeJson {
  margin: 0;
  border: 1px solid color-mix(in srgb, var(--border) 58%, transparent);
  background: color-mix(in srgb, var(--background) 86%, #050505 14%);
  padding: 0.9rem 1rem; overflow-x: auto; min-width: 0;
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas,
    "Liberation Mono", "Courier New", monospace;
  font-size: 0.85rem; line-height: 1.55;
}
```

The `.themeJson` variant caps height at `max-height: 9.5rem` with `overflow: auto`.

Scrollbar styling for code blocks:
```css
.codeBlock::-webkit-scrollbar { width: 10px; height: 10px; }
.codeBlock::-webkit-scrollbar-track {
  background: color-mix(in srgb, var(--background) 86%, #050505 14%);
}
.codeBlock::-webkit-scrollbar-thumb {
  background: color-mix(in srgb, var(--primary) 78%, transparent);
  border-radius: 999px;
  border: 2px solid color-mix(in srgb, var(--background) 86%, #050505 14%);
}
```

### 15.10 Theme Cards

```css
.grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(16.5rem, 1fr));
  gap: 1.1rem;
}
.themeCard {
  display: grid; gap: 0.85rem;
  border: 1px solid color-mix(in srgb, var(--border) 66%, transparent);
  background: color-mix(in srgb, var(--background) 94%, var(--card-bg) 6%);
  padding: 1rem;
}
.themeHeader { display: flex; align-items: center; justify-content: space-between; gap: 0.75rem; }
.themeTitle {
  margin: 0; font-size: 1.15rem; line-height: 1.1; letter-spacing: 0.01em;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
```

Color swatches:
```css
.swatches { display: grid; grid-template-columns: repeat(8, minmax(0, 1fr)); gap: 0.25rem; }
.swatch { width: 100%; aspect-ratio: 1 / 1; border: 1px solid rgba(0, 0, 0, 0.2); }
```

### 15.11 Install Hint Box

```css
.installHint {
  border: 1px dashed color-mix(in srgb, var(--border) 66%, transparent);
  padding: 1.15rem;
  background: color-mix(in srgb, var(--background) 96%, var(--card-bg) 4%);
}
```

### 15.12 Responsive Thresholds

| Breakpoint | Changes |
|------------|---------|
| 820px+ | `.controlsGrid` → 2 columns, `.fetchGrid` → 2 columns, `.fetchColumns` → 2 columns |
| max-width: 767px | `.controls` padding → 1rem, `.commandCard` padding → 1rem, `.terminalBody` padding → 0.8rem, `.fetchRow` grid → 6.25rem 1fr |

---

## 16. Specific Guidance For `resources/xfetch`

The xfetch page is a single-file client component at `src/app/[locale]/resources/xfetch/page.tsx`. It uses a stage-based scroll reveal system with no external component dependencies.

### 16.1 Page Structure

```
section.page
  div.stack                   ← grid, gap: clamp(4.5rem, 12vh, 14rem) (mobile: 3.5rem)
    section[data-stage="0"]   ← stageSurface (header + icon)
    section[data-stage="1"]   ← stageSurface (screenshots slider)
    section[data-stage="2"]   ← stageSurface (layout examples)
    section[data-stage="3"]   ← stageSurface (install commands)
    section[data-stage="4"]   ← stageSurface (configuration)
    section[data-stage="5"]   ← stageSurface (usage)
    section[data-stage="6"]   ← stageSurface (uninstall + CTA)
```

Each stage section uses the scroll-reveal pattern via IntersectionObserver (see page.tsx).

### 16.2 Stage Reveal Pattern

Every `.stageSurface` starts invisible and reveals on scroll:

```css
.stageSurface {
  display: grid; gap: 2rem; min-width: 0;
  opacity: 0; filter: blur(8px);
  transform: translateY(2rem);               /* mobile: 1.5rem */
  transition: opacity 0.55s ease, filter 0.55s ease, transform 0.55s ease;
}
.stageSurface[data-visible="true"] {
  opacity: 1; filter: blur(0); transform: translateY(0);
}
.stageSurface[data-dimmed="true"] {
  opacity: 0.34;                              /* mobile: 0.28 */
  filter: blur(6px) saturate(0.72) brightness(0.78);
  transform: scale(0.985);                    /* mobile: scale(0.99) */
}
```

### 16.3 Header Section (Stage 0)

```css
.header { display: grid; gap: 0.25rem; min-width: 0; }
.description {
  margin: 0; max-width: 68ch; color: var(--text-muted);
  line-height: 1.8 (mobile: 1.7); font-size: 1rem;
}
.iconWrap { display: flex; justify-content: center; width: 100%; }
.icon { display: block; width: clamp(4.5rem, 16vw, 5.5rem); height: auto; }
```

### 16.4 Screenshots Slider (Stage 1)

```css
.media {
  position: relative; overflow: hidden; width: 100%; min-width: 0;
  min-height: 40rem;                         /* mobile: 24rem */
  border-radius: 1rem;
  border: 1px solid color-mix(in srgb, var(--border) 66%, transparent);
  background: color-mix(in srgb, var(--background) 94%, var(--card-bg) 6%);
}
.sliderTrack {
  display: flex; width: 300%; height: 100%;
  animation: xfetchSlide 15s ease-in-out infinite;
}
.slide {
  position: relative; flex: 0 0 33.333%; width: 33.333%;
  min-width: 0; min-height: 40rem;           /* mobile: 24rem */ margin: 0;
}
.slideImage { object-fit: cover; }
```

Keyframes:
```css
@keyframes xfetchSlide {
   0%,  28% { transform: translateX(0); }
  36%,  61% { transform: translateX(-33.333%); }
  69%,  94% { transform: translateX(-66.666%); }
  100%      { transform: translateX(0); }
}
@media (prefers-reduced-motion: reduce) {
  .sliderTrack { animation: none; transform: translateX(0); }
}
```

### 16.5 Section Containers (Stages 2-6)

```css
.section { display: grid; gap: 0.75rem; min-width: 0; }
.sectionTitle { margin: 0; font-size: 1.15rem; color: var(--foreground); }
```

### 16.6 Layout Examples (Stage 2)

```css
.layoutsGrid { display: grid; gap: 1rem; }
@media (min-width: 768px) { .layoutsGrid { grid-template-columns: 1fr 1fr; } }
@media (max-width: 767px) { .layoutsGrid { grid-template-columns: 1fr; } }
```

Layout stack (first 3 examples in a column):
```css
@media (min-width: 768px) {
  .layoutStack { display: grid; gap: 1rem; align-content: start; }
}
```

### 16.7 Install Section (Stage 3)

```css
.installStack { display: grid; gap: 1rem; }
.installBlock { display: grid; gap: 0.5rem; }
.installLabel { margin: 0; font-size: 0.85rem; color: var(--text-muted); font-weight: 600; }
```

### 16.8 Configuration Section (Stage 4)

```css
.configDescription { margin: 0; color: var(--text-muted); line-height: 1.6; font-size: 0.95rem; }
.configList { display: grid; gap: 0.4rem; margin: 0; padding: 0; list-style: none; }
.configItem {
  padding: 0.5rem 0.75rem;
  background: color-mix(in srgb, var(--background) 86%, #050505 14%);
  border-radius: 0.4rem;
  border: 1px solid color-mix(in srgb, var(--border) 58%, transparent);
  font-family: ui-monospace, monospace; font-size: 0.82rem; color: var(--foreground);
}
.modulesGrid { display: flex; flex-wrap: wrap; gap: 0.4rem; }
.moduleTag {
  display: inline-block; padding: 0.25rem 0.5rem; border-radius: 0.3rem;
  border: 1px solid color-mix(in srgb, var(--border) 58%, transparent);
  background: color-mix(in srgb, var(--background) 90%, var(--primary) 10%);
  font-family: ui-monospace, monospace; font-size: 0.78rem; color: var(--primary);
}
```

### 16.9 CTA Button (Stage 6)

⚠️ **Do NOT hardcode colors.** The current button uses `#ffc400` / `#1a1a1a` which breaks the theme contract. Use this pattern:

```css
.button {
  display: inline-flex; align-items: center; justify-content: center;
  min-height: 2.85rem; padding: 0.78rem 1.8rem;
  border: 1px solid var(--primary); color: var(--background); background: var(--primary);
  font-size: 0.85rem; font-weight: 700; letter-spacing: 0.02em;
  text-decoration: none;
  transition: opacity 0.2s ease, border-color 0.2s ease, background-color 0.2s ease;
}
.button:hover, .button:focus-visible { outline: none; opacity: 0.88; }
@media (max-width: 767px) { .button { width: 100%; text-align: center; } }
```

The `.viewSourceWrap` centers the button: `display: flex; justify-content: center; padding-top: 0.5rem`.

### 16.10 What NOT To Do On xfetch

- Do NOT use hardcoded hex colors for chrome — always use `var(--primary)`, `var(--background)`, etc.
- Do NOT change the gap rhythm of `.stack` — uses `clamp(4.5rem, 12vh, 14rem)` (mobile: `3.5rem`)
- Do NOT add borders or rounded corners to `.stageSurface` — they are layout-only wrappers
- Do NOT nest bordered containers without using the standard formula:
  ```css
  border: 1px solid color-mix(in srgb, var(--border) 66%, transparent);
  background: color-mix(in srgb, var(--background) 94%, var(--card-bg) 6%);
  ```
- Do NOT add arbitrary card styles — all surfaces must match the surface pattern above
