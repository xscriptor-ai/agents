---
name: xglassmorphism
description: Real glassmorphism for TypeScript + CSS web applications, with Tauri
  packaging where it applies. Covers the optics of frosted glass, backdrop-filter,
  layered surfaces, design tokens, typed components, accessibility, performance, browser
  support, fullstack architecture, and native window vibrancy (macOS, Windows, Linux
  fallback). Use when designing, building, reviewing, or debugging glass UI, frosted
  panels, translucent navigation, blur/backdrop effects, Liquid-Glass-style surfaces,
  or when packaging a web app with Tauri and deciding between CSS glass and native
  vibrancy.
allowed-tools: Read, Glob, Grep, Edit, Write, Bash
---

# xglassmorphism

Glassmorphism built as a system, not as a one-liner. The naive recipe
(`background: rgba(255,255,255,.2)` + `backdrop-filter: blur()`) produces the
flat, gray, muddy panels that gave the trend a bad name. Real glass is optics:
a stack of blur, tint, saturation, specular edge, noise, and shadow, arranged
so that content on top stays legible on the worst possible backdrop.

This skill documents the technique end to end for **TypeScript + CSS web
applications** (framework-agnostic: React 19, Vue 3.x, Svelte 5, vanilla, Web
Components), including the fullstack surfaces around it (tokens pipeline, SSR,
theme persistence, testing, deployment) and **Tauri 2.x packaging** where native
window effects apply.

The reference implementation is the `xglass` system: a token contract, a small
set of CSS primitives, typed wrappers per framework, and a platform matrix.

## When to use this skill

- Adding or restyling any glass surface: nav bars, sidebars, cards, sheets,
  modals, popovers, toasts, command palettes, toolbars, media overlays.
- Reviewing an existing glass UI that looks muddy, gray, low-contrast, janky,
  or "Vista-like".
- Designing a glass design system: tokens, levels, dark/light, motion.
- Debugging `backdrop-filter` doing nothing, blurring the wrong content,
  clipping at radius, bleeding glow, or destroying scroll performance.
- Packaging a TypeScript web app with Tauri and deciding between CSS glass and
  native window vibrancy (Acrylic, Mica, NSVisualEffectView, Liquid Glass).
- Implementing accessibility for translucent UI: WCAG contrast, reduce
  transparency, increase contrast, forced colors, focus visibility.

## Core doctrine

1. **Glass is layered optics, not transparency.** Minimum viable glass has
   five layers: backdrop blur, tint, saturation/brightness lift, edge
   (specular rim + inner highlight), and shadow. Skipping tint or edge is why
   naive glass reads as gray plastic.
2. **Text never depends on the blur.** Blur is decoration; the tint/scrim is
   what guarantees contrast. Evaluate text against the **worst-case backdrop**
   (lightest, darkest, busiest region, both themes), never the average.
3. **One backdrop pass per surface, few surfaces per view.** The spec requires
   a separate rendering pass; nested backdrop filters degrade exponentially.
   Budget: at most 2-3 simultaneous blurred surfaces in a viewport.
4. **Animate opacity and transform, never `backdrop-filter`.** Animating the
   blur chain runs on the main thread; fade/slide a pre-blurred layer instead.
5. **Progressive enhancement is mandatory.** Ship a readable opaque base, add
   glass inside `@supports`, and honor `prefers-reduced-transparency`,
   `prefers-contrast`, and `forced-colors`.
6. **No glass on glass.** A blurred layer over another blurred layer produces
   mud and double render passes. Use solid translucent fills for stacked
   surfaces.
7. **Tokens before components.** Every blur radius, alpha, edge, and shadow is
   a token consumed by both CSS and TypeScript. No magic values in components.
8. **In Tauri, native vibrancy beats CSS for window-level glass** (desktop,
   wallpaper) and CSS wins for in-page floating layers. Never blur over native
   vibrancy: it double-blurs and burns GPU for nothing.
9. **TypeScript is the contract.** Tokens and component variants are typed and
   exported; CSS custom properties are the runtime channel between them.
10. **Every glass surface ships an audit line.** Contrast worst case, cost
    class, fallback, and the platform it was verified on.

## The canonical recipe

Minimum production glass (framework-agnostic CSS). This is the baseline the
whole system scales from:

```css
.xglass {
  --xglass-blur: 20px;
  --xglass-saturate: 180%;
  --xglass-tint: rgb(255 255 255 / 0.12);
  --xglass-edge: rgb(255 255 255 / 0.35);

  background: var(--xglass-tint);
  -webkit-backdrop-filter: blur(var(--xglass-blur)) saturate(var(--xglass-saturate));
  backdrop-filter: blur(var(--xglass-blur)) saturate(var(--xglass-saturate));
  border: 1px solid var(--xglass-edge);
  box-shadow:
    inset 0 1px 0 rgb(255 255 255 / 0.45),
    0 8px 32px rgb(0 0 0 / 0.18);
  border-radius: 16px;
}
```

What each layer does, and why removing it breaks the illusion, is documented in
`references/01-physics-of-glass.md`. The browser mechanics (backdrop root,
clipping, stacking, masks, fallbacks) live in
`references/02-css-implementation.md`.

## Glass levels

Three levels keep the system consistent. Names are normative; values are the
default token set and may be retuned per product.

| Level   | Blur | Tint alpha | Use for | Cost |
|---------|------|------------|---------|------|
| `thin`  | 8-12px  | 0.06-0.10 | full-width sticky bars, large panels, media overlays | low |
| `regular` | 16-24px | 0.10-0.16 | cards, popovers, dropdowns, buttons | medium |
| `thick` | 28-40px | 0.16-0.28 | modals, sheets, drawers, focused reading surfaces | high |

Rules: larger surfaces get thinner glass; smaller surfaces can afford thicker
blur. A `thin` bar must still pass contrast because it spans the whole viewport.
Details and the alpha ramp: `references/03-design-tokens-and-theming.md`.

## Stack and scope

| Layer | Choices in scope |
|-------|------------------|
| Language | TypeScript 5.x (`strict`), CSS (custom properties, nesting, `@layer`) |
| UI frameworks | React 19, Vue 3.x, Svelte 5, vanilla TS, Web Components |
| Styling | plain CSS / CSS Modules / Tailwind CSS 4 / vanilla-extract |
| Rendering | SPA, SSR (Next.js, Nuxt, SvelteKit), static export, islands |
| Packaging | npm libraries, monorepo packages, Tauri 2.x desktop apps |
| Native glass | window-vibrancy 0.8.x, Tauri `windowEffects` (macOS/Windows) |

Out of scope: React Native, native mobile UIKit/SwiftUI code, and WebGL lensing
engines. The web technique is the source of truth; Tauri adapts it.

## Tauri decision matrix (summary)

Full details, config shapes, and per-platform behavior:
`references/08-tauri-packaging.md`.

| Case | Use | Fallback |
|------|-----|----------|
| Window depth over desktop/wallpaper (macOS, Windows) | Native: `windowEffects` / window-vibrancy (`underWindowBackground`, `mica`, `acrylic`, macOS 26 `liquidGlassRegular`) | Opaque themed window background |
| Glass panels/cards over your own in-page content (all OS) | CSS `backdrop-filter` with `@supports` guard | Translucent solid color without blur |
| Hybrid (most common) | Native vibrancy for the window chrome + CSS glass only for floating layers over in-page content | Drop CSS blur where native vibrancy is active |
| Linux | CSS glass only; native vibrancy unsupported | Compositor blur (KWin/Hyprland) if user enabled it |
| macOS 26+ Liquid Glass | `Effect.liquidGlassRegular`/`liquidGlassClear` + fallback material for macOS 15- | `underWindowBackground` |
| App Store distribution | Public APIs only: `windowEffects`, no `macOSPrivateApi` | Opaque or CSS-only glass |

## Anti-patterns (reject on sight)

- `rgba(...)` + `blur()` with no tint, edge, or shadow (flat gray glass).
- Text over glass with no scrim and no worst-case check.
- Glass surfaces nested inside glass surfaces.
- Animating `backdrop-filter`, `filter`, or `background` on scroll.
- `will-change: backdrop-filter` or `will-change: filter` left on permanently
  (it creates a backdrop root and can silently disable the blur behind it).
- `overflow: hidden` on a glass parent to trim an oversized backdrop layer
  (works in Firefox/Safari, fails in Chrome; use `mask-image`).
- Full-page glass walls with dozens of blurred cards ("frosted everything").
- Blur over native Tauri vibrancy (double blur, wasted GPU).
- Glass only in dark mode with no light-mode token set.
- Treating blur as a contrast device and skipping WCAG evaluation.

## Companion references

Load only what the task needs; each reference is the detailed source of truth.

| Reference | Covers | Load when |
|-----------|--------|-----------|
| `references/01-physics-of-glass.md` | Optics of real glass: blur, tint, saturation, refraction, specularity, noise, depth; the five-layer model; Liquid Glass principles; intensity decision tables | Designing a glass look, tuning effect strength, deciding what "real" means |
| `references/02-css-implementation.md` | `backdrop-filter` API and functions, backdrop root, clipping, stacking/containing block, mask tricks, SVG filters, fallback CSS, prefixing, `@supports` | Writing or debugging the actual CSS |
| `references/03-design-tokens-and-theming.md` | Token model, alpha ramps, blur scale, light/dark, `color-mix()`, relative colors, `oklch`, `light-dark()`, Tailwind 4 `@theme`, token generation in TypeScript | Building the token layer or theming glass |
| `references/04-typescript-components.md` | Typed primitives, polymorphic components, variants, React/Vue/Svelte/vanilla patterns, popover/dialog/sheet recipes, focus management, Tauri drag regions | Implementing components that use glass |
| `references/05-accessibility-and-legibility.md` | WCAG 1.4.3/1.4.6/1.4.11/2.4.11, worst-case evaluation, scrim math, `prefers-*` and `forced-colors`, focus visibility, test checklist | Auditing or shipping accessible glass |
| `references/06-performance-and-browser-support.md` | Rendering cost model, budgets, animation rules, engine bugs (Chrome/Firefox/Safari/WebKitGTK), support matrix 2026, SSR/static export notes, print | Fixing jank or deciding support policy |
| `references/07-fullstack-architecture.md` | Fullstack integration: monorepo layout, tokens pipeline, SSR/streaming, theme API and persistence schema, admin preview, visual testing, CI, deploy | Wiring glass into a real app end to end |
| `references/08-tauri-packaging.md` | Tauri 2.x config and APIs, window-vibrancy effects, macOS/Windows/Linux behavior, detection, drag regions, packaging, performance, App Store constraints | Packaging the app with Tauri or choosing native vs CSS glass |

## Fast checklist before calling a glass surface done

- [ ] All five layers present (blur, tint, saturation, edge, shadow).
- [ ] Contrast verified at worst-case backdrop, both themes, 200% zoom.
- [ ] `@supports` fallback is readable and shipped in the base CSS.
- [ ] `prefers-reduced-transparency`, `prefers-contrast`, `forced-colors` handled.
- [ ] No animating of the blur chain; only opacity/transform.
- [ ] Blur radius and surface area within budget; no nested glass.
- [ ] Tokens used; no hard-coded blur/alpha in components.
- [ ] Keyboard focus visible and not obscured by sticky glass.
- [ ] Verified in Chromium, Firefox, and WebKit (Safari or Tauri webview).
- [ ] If Tauri: native effect or CSS chosen deliberately, not both stacked.
