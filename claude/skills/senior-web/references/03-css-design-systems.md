# CSS and Design Systems

Modern CSS platform features, tokens, theming, and choosing between utility, module, and typed CSS
approaches.

## Modern CSS Baseline (2026)

The features below are baseline-available in current evergreen browsers (verify support for your
oldest target with a baseline/caniuse check before shipping):

- Cascade layers (`@layer`)
- Container queries (`container-type`, `@container`) and container query units
- `:has()` and other relational selectors
- Native nesting
- Custom properties with `@property` registration
- Wide-gamut color: `oklch()`, `color()`, `color-mix()`, relative color syntax
- Logical properties (`inline-start`, `block-end`, `margin-inline`, `padding-block`)
- `clamp()`, `min()`, `max()` for fluid sizing
- `text-wrap: balance | pretty`
- `subgrid`
- `:focus-visible`, `:user-valid`, `:user-invalid`
- View Transitions API (same-document broadly; cross-document increasingly available)
- `aspect-ratio`, `gap` in flexbox, `scrollbar-gutter`, `content-visibility`

Use these before reaching for a preprocessor or a runtime library.

## Cascade Layers

Layers make specificity a design decision instead of an accident. Order layers from least to most
specific; later layers win regardless of selector specificity, and unlayered styles beat all layers.

```css
@layer reset, tokens, base, components, utilities, overrides;

@layer reset {
  *, *::before, *::after { box-sizing: border-box; }
  body { margin: 0; }
}

@layer components {
  .btn { background: var(--color-accent); }
}

@layer utilities {
  .text-center { text-align: center; }
}
```

Rules:
- Import third-party CSS into a layer so your styles can override it without `!important`:
  `@import url("lib.css") layer(vendor);`
- Treat `utilities` as the topmost author layer; keep `overrides` empty unless debugging.
- Do not mix layered and unlayered author styles; unlayered always wins and destroys the model.
- `!important` in a layer **reverses** layer order for that declaration; avoid relying on it.

## Container Queries

Components should respond to their container, not the viewport. This is the biggest CSS architectural
shift of the decade: it makes components truly reusable across layouts.

```css
.card-grid { container-type: inline-size; }

.card { display: grid; gap: 1rem; }

@container (min-width: 30rem) {
  .card { grid-template-columns: 12rem 1fr; }
}

/* Named containers disambiguate when nesting */
.sidebar { container: sidebar / inline-size; }
@container sidebar (min-width: 20rem) { .nav-link { font-size: 1rem; } }
```

- `container-type: inline-size` for width-based queries; `size` also enables block queries but
  requires explicit height.
- Container query units (`cqw`, `cqh`, `cqi`, `cqb`) enable fluid sizing relative to the component.
- Use named containers in any design-system component; anonymous containers become ambiguous when
  composed.
- Pair with `:has()` for parent-aware styling:

```css
/* Style the card only when it contains an image */
.card:has(> img) { padding-top: 0; }
/* Float a label when the field has content */
.field:has(input:not(:placeholder-shown)) label { transform: translateY(-1.2em); }
```

## Native Nesting and Selectors

```css
.nav {
  display: flex;
  & a { color: inherit; }
  &:focus-within { outline: 2px solid var(--color-focus); }
  @media (min-width: 48rem) { gap: 2rem; }
}
```

- Nesting uses `&` for compound selectors; do not nest more than two or three levels.
- Avoid selector weight creep: prefer flat class selectors plus `:where()` to zero specificity.
- `:where()` for resets and defaults; `:is()` for grouping that should adopt the highest specificity.
- `:has()` is powerful but can trigger style recalculation on broad DOM changes; scope it tightly
  and measure on large pages.

## Color and OKLCH

Use OKLCH for perceptually uniform palettes: lightness is predictable across hues, and chroma
adjustments do not shift perceived lightness.

```css
:root {
  --brand-500: oklch(62% 0.19 255);
  --brand-600: oklch(55% 0.19 255);
  --surface: oklch(98% 0.01 255);
}
```

```css
/* Derive hover states without hand-picking colors */
.button {
  background: var(--brand-500);
  &:hover { background: oklch(from var(--brand-500) calc(l * 0.92) c h); }
}
```

- **P3 / wide gamut** — `oklch()` can express colors outside sRGB; browsers map into the display
  gamut. Provide sRGB fallbacks only if you still target old engines.
- **`color-mix()`** for tints, alpha blending, and theme derivation:
  `color-mix(in oklch, var(--brand) 20%, transparent)`.
- **Contrast** — compute against the actual rendered background; OKLCH lightness differences are a
  heuristic, not a WCAG check. Verify with tooling — see [05-accessibility.md](./05-accessibility.md).
- Keep the number of brand steps small (e.g. 50/100/300/500/700/900) and generate via lightness
  scale, not ad-hoc hex.

## Logical Properties and Internationalization

Logical properties are mandatory for any product that may add an RTL locale. They map to physical
edges based on `writing-mode` and `direction`.

| Physical (avoid) | Logical (prefer) |
|---|---|
| `margin-left/right` | `margin-inline-start/end` |
| `padding-top/bottom` | `padding-block-start/end` |
| `left/right` | `inset-inline-start/end` |
| `width/height` | `inline-size/block-size` |
| `border-top-left-radius` | `border-start-start-radius` |
| `text-align: left` | `text-align: start` |

- Use `dir="rtl"` on `<html>` and let logical properties do the mirroring; never maintain a
  separate RTL stylesheet.
- Icons and directional affordances (arrows, chevrons) usually need explicit flipping; text does
  not. See [09-seo-i18n-analytics.md](./09-seo-i18n-analytics.md).
- Fluidity should come from `clamp()` and container units, not from viewport-only breakpoints.

## Styling Approaches Compared

| Approach | Strengths | Weaknesses | Choose when |
|---|---|---|---|
| Utility CSS (Tailwind) | Consistency, no dead CSS, fast iteration, tokens in config | Verbose markup, class-string review noise | Teams want speed and a constrained palette |
| CSS Modules | Plain CSS locally scoped, zero runtime, gradual adoption | No token system; naming discipline needed | Existing CSS skills, component libraries |
| Typed/static CSS (vanilla-extract, StyleX) | Type-safe theme contracts, static extraction | Build coupling, smaller ecosystem | Large systems with strict token governance |
| Runtime CSS-in-JS | Dynamic values, co-location | Runtime cost, SSR complexity | Legacy only; do not start new work here |
| Native CSS (+ nesting, layers, `:has`) | Zero tooling, future-proof | Requires team restraint and conventions | New components, design systems foundation |

Most 2026 codebases mix these deliberately: utilities for layout and spacing, component CSS (modules
or CSS-in-CSS) for complex states, tokens everywhere.

### Tailwind Notes

- Configure design tokens in the theme (colors, spacing scale, fonts, radii, breakpoints) rather
  than using arbitrary values `[13px]`; arbitrary values defeat the system.
- Extract repeated class clusters into components, not `@apply`-based CSS; `@apply` recreates the
  abstraction problem utilities solved.
- Keep variant logic (responsive, state) close to the markup; long class lists are acceptable when
  the design is systematic.
- Tailwind v4+ is CSS-first configuration (`@theme`, `@import "tailwindcss"`); verify syntax against
  your installed major.

## Design Tokens

Tokens are the contract between design and code. Three tiers work well:

1. **Primitive** — raw values with no intent: `--blue-500`, `--space-4`, `--radius-2`.
2. **Semantic** — intent mapped to primitives: `--color-action`, `--color-surface`,
   `--color-danger`, `--space-card-gap`.
3. **Component** — optional, scoped: `--button-padding-x`.

```css
:root {
  /* primitives */
  --space-1: 0.25rem; --space-2: 0.5rem; --space-3: 0.75rem; --space-4: 1rem;
  --brand-500: oklch(62% 0.19 255);

  /* semantic */
  --color-bg: oklch(100% 0 0);
  --color-fg: oklch(20% 0.01 255);
  --color-action: var(--brand-500);
  --radius-md: 0.5rem;
}
```

- Consume semantic tokens in components; never primitives directly.
- Keep the token set small enough to memorize (roughly 50-150 semantic tokens).
- Ship tokens as CSS custom properties so runtime theming works without a build step.
- If a token is never used, delete it; unused tokens are documentation debt.
- Version token names; renaming a semantic token is a breaking API change for consumers.

## Theming

- Drive light/dark with `prefers-color-scheme` plus an explicit override attribute:

```css
:root { color-scheme: light dark; }
:root[data-theme="dark"] {
  --color-bg: oklch(18% 0.01 255);
  --color-fg: oklch(96% 0 0);
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) { --color-bg: oklch(18% 0.01 255); --color-fg: oklch(96% 0 0); }
}
```

- Persist the choice in a cookie (SSR-visible, no flash) or `localStorage` with an inline
  pre-hydration script; a cookie is preferred to avoid theme flash on first paint.
- Set `color-scheme` so native controls, scrollbars, and form widgets follow the theme.
- Do not invert images with `filter: invert()`; art-direct real assets for dark mode.
- Respect `prefers-reduced-motion` and `prefers-contrast` media features in the base design.
- Test all themes for contrast, focus visibility, and disabled states — dark mode commonly breaks
  focus rings and placeholder contrast.

## Performance Notes

- Prefer CSS animations using `transform`/`opacity`; avoid animating layout properties.
- `content-visibility: auto` with `contain-intrinsic-size` to skip offscreen rendering on long pages.
- Be careful with costly selectors: universal `:has()` on large DOMs, `filter`/`backdrop-filter` in
  scroll containers, and large box-shadow blurs.
- Inline critical CSS for above-the-fold content on server-rendered pages; load the rest normally.
- Avoid loading multiple icon fonts; use inline SVG sprites.

## Anti-Patterns

- `!important` as a specificity workaround instead of layers or `:where()`.
- Deep descendant selectors (`.page .sidebar ul li a`) that break on refactor.
- Physical properties in an app with RTL locales.
- Hard-coded hex colors in components instead of semantic tokens.
- `@apply` clusters instead of components.
- Theme flash on load from client-only theme detection.
- Multiple icon fonts and sprite duplication.

## Checklist

- [ ] Layer order declared once and respected; third-party CSS layered.
- [ ] Components respond to containers, not only viewports.
- [ ] All colors come from tokens, authored in OKLCH; contrast verified in every theme.
- [ ] Logical properties used for spacing/inset; RTL renders correctly.
- [ ] Dark/light verified at first paint without flash.
- [ ] `:focus-visible` styles exist in all themes.
