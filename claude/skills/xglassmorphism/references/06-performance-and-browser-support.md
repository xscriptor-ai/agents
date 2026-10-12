# 06 - Performance and browser support

`backdrop-filter` is one of the most expensive compositing features available
in CSS. This reference explains the cost model, the budget rules, the engine
bug catalog, and the support matrix as of September 2026.

## 1. Why backdrop blur costs

From the Filter Effects Module Level 2 motivation: applying `backdrop-filter`
or `mix-blend-mode` requires a **separate rendering pass** to complete
partially painted stacking contexts. The spec itself warns this "would double
the required rendering time" and "twice the memory usage and GPU bandwidth",
and that **nested** backdrop filters would degrade exponentially. Backdrop
roots exist to bound this cost.

Practical consequences:

- Each glass surface is an extra texture/surface and an extra pass before the
  final composite.
- Cost grows roughly with **blurred area x kernel radius**. A 400px-wide bar
  with `blur(16px)` is far cheaper than a full-screen overlay with
  `blur(60px)`.
- Engines downscale the backdrop before blurring at large radii, which is why
  very large blurs can show banding or blockiness.
- Paint-bound work runs on the main thread; only `opacity` and `transform`
  animate on the compositor.

There are no official per-radius benchmark numbers from Chromium or WebKit;
treat exact cost curves as empirical and measure on your own target hardware.

## 2. Budget rules

| Rule | Rationale |
|------|-----------|
| At most 2-3 blurred surfaces visible in a viewport; 1 is ideal | Each is a separate pass |
| Prefer blur <= 16px for large surfaces, <= 32px for modals | Area x radius dominates |
| Never full-screen `backdrop-filter` except a modal scrim or media overlay | Full-screen pass over the whole frame |
| Full-width sticky bars use `thin` glass (8-12px) | Persistent, always visible, always paying |
| Small controls (buttons, chips) use <= 10px | They add up quickly in toolbars/lists |
| No glass inside scrolled list items by default | Dozens of blurred surfaces while scrolling = jank |
| Disable blur when the app is not focused or the surface is offscreen | Free GPU cycles |
| Animate only opacity/transform | Compositor-only properties |

Performance tiers by cost (cheapest to most expensive):

1. Solid translucent fill, no blur.
2. Small blur on a fixed-size element (`blur(8-12px)` badges, buttons).
3. Medium blur on a bounded panel (`blur(16-24px)` cards, popovers).
4. Large blur on a viewport-sized surface (`blur(32-60px)` modals, overlays).
5. Animated or nested blur (avoid outside controlled demos).

## 3. Optimization techniques

### Lazy-mount below the fold

```ts
const observer = new IntersectionObserver((entries) => {
  for (const entry of entries) {
    if (entry.isIntersecting) {
      (entry.target as HTMLElement).dataset.glassActive = "true";
      observer.unobserve(entry.target);
    }
  }
});

document.querySelectorAll("[data-glass-lazy]").forEach((el) => observer.observe(el));
```

```css
[data-glass-lazy="true"] {
  -webkit-backdrop-filter: blur(var(--xglass-blur)) saturate(180%);
  backdrop-filter: blur(var(--xglass-blur)) saturate(180%);
}
```

The element renders with the opaque fallback until it approaches the viewport,
then upgrades to glass once.

### Skip work offscreen

```css
.xglass-card {
  content-visibility: auto;
  contain-intrinsic-size: auto 320px;
}
```

`content-visibility: auto` lets the engine skip rendering completely offscreen
subtrees (Chrome 85+, Firefox 125+, Safari 18+/26; partial in early Safari 18
versions). Use it on glass cards in long lists, always with
`contain-intrinsic-size` to avoid scrollbar jumps.

### Stop paying when not visible

```ts
document.addEventListener("visibilitychange", () => {
  document.documentElement.dataset.appVisible = String(!document.hidden);
});
```

```css
:root[data-app-visible="false"] .xglass {
  -webkit-backdrop-filter: none;
  backdrop-filter: none;
  background: var(--surface);
}
```

### Do not pre-declare `will-change`

`will-change: filter`, `opacity`, `mask`, or `backdrop-filter` creates a
backdrop root (changing what gets blurred) and holds GPU memory. Add it only
for the duration of an animation and remove it after.

### Avoid blur during scroll-driven effects

Scroll-driven animations (`animation-timeline: scroll()`, supported in
Chromium 115+ and Safari 26+) are perfect for animating **opacity** of a tint
layer. Animating the blur value itself is paint-bound on every frame: do not.

### Respect power state when available

There is no reliable battery API in 2026 (`navigator.getBattery` is
deprecated/removed in some engines). Use coarse heuristics you control:

- App-level "reduced effects" setting, defaulting on for
  `prefers-reduced-transparency` and low `navigator.hardwareConcurrency`
  (<= 4) devices.
- Tauri: disable CSS glass when native vibrancy is active (avoid double cost),
  and prefer Mica/tabbed over Acrylic on Windows (see
  `./08-tauri-packaging.md`).

## 4. Animation rules

| You want to animate | Do this | Never this |
|---------------------|---------|------------|
| Glass appearing/disappearing | Fade `opacity` of the element | Animate `backdrop-filter` from `none` |
| Panel sliding in | `transform: translate3d()` | Animate `blur()` radius |
| Hover lift | `transform` + `box-shadow` | Animate background alpha with blur |
| Tint shift on scroll | Wrap the tint in a layer and animate its `opacity` | Change `--xglass-tint` per frame |
| Specular follow | Move a gradient layer with `transform` | Recompute `backdrop-filter` |

Interpolating `backdrop-filter` between two filter lists is technically
animatable, but it is paint-bound and causes main-thread work per frame. The
only case where it is acceptable is a small, one-shot transition (<= 200ms) on
a tiny surface, and even then prefer the opacity-crossfade of two layers.

## 5. Engine bug catalog (open as of Sep 2026)

### Firefox

| Bug | Symptom | Workaround |
|-----|---------|------------|
| 1803813 | `backdrop-filter` stops working on `position: sticky` when an ancestor has both `overflow` and `border-radius` | Put the blur on an inner absolute layer |
| 1882178, 2034651 | Backdrop not clipped correctly by parent overflow/radius | Trim with `mask-image`; test corners |
| 1909463 | Failures with sticky elements in complex pages | Simplify sticky ancestry |
| Pre-123 GPU bug (1868737, fixed 2026-04) | Property disabled on systems with unknown GPU vendor | Historical; no action |

### WebKit / Safari

| Bug | Symptom | Workaround |
|-----|---------|------------|
| 319187 | Severe initial slowdown on iOS with large fixed blurred elements | Avoid large fixed glass on iOS |
| 275305 | Text-input lag when backdrop-filter is present | Remove blur from views with active text inputs on affected versions |
| 159428 | Sticky blur boundary artifacts | Avoid sticky + blur combination if visible |
| 263194 | Blur "glow" bleeds onto elements painted above | Reduce inset/edge glow layers |
| 297620 | Safari 18.x regression: CSS variables ignored in `backdrop-filter` on some macOS versions | Inline literal values as a stopgap, or feature-detect |
| 245510, 297770 | `url()` SVG filters as backdrop/filter unreliable | Chromium-only enhancement; fallback to blur |
| 252181, 201987 | Transformed ancestors filter the wrong content | Move glass out of transforms |
| 319479, 322087, 325446 (Safari 26) | OS scroll-edge tint sampling disabled/faulty around fixed/sticky `backdrop-filter` layers | Use an opaque or gradient header in Tauri/macOS scroll-edge contexts |

### Chromium

- Overflow/clip vs mask order-of-operations (community-verified, no public
  crbug found): `overflow: hidden` trims before the filter runs, so the
  nearby-pixels extension does not work. Use `mask-image`.
- Transparent Tauri/Electron windows can show resize/scroll artifacts on
  WebView2; `noRedirectionBitmap: true` mitigates creation flash. Treat scroll
  artifacts as empirical.

### WebKitGTK (Tauri on Linux)

- Uses the WebKit engine: same class of WebKit bugs applies.
- Unprefixed `backdrop-filter` lands around WebKitGTK 2.46+; older distros need
  `-webkit-backdrop-filter`. Current WebKitGTK line is 2.54 (Sep 16, 2026).
- Compositor blur (KWin rules, Hyprland) is outside the app; the webview still
  does its own backdrop pass.

## 6. Support matrix (Sep 2026)

| Feature | Chrome/Edge | Firefox | Safari/WKWebView | Notes |
|---------|-------------|---------|------------------|-------|
| `backdrop-filter` | 76+ (2019) | 103+ (2022) | `-webkit-` 9+, unprefixed 18+ | Baseline newly available 2024-09-16; ~96% usage |
| `mask-image` | 120+ unprefixed (`-webkit-` long before) | 53+ (2017) | 15.4+ unprefixed (`-webkit-` long before) | Baseline Dec 2023 |
| `color-mix()` | 111+ (2023) | 113+ (2023) | 16.2+ (2022) | Baseline May 2023; >2 colors is newer |
| Relative color syntax | 119+ (2023) | 128+ (2024) | 16.4+ partial, 18 fixed | Baseline Jul 2024 |
| `light-dark()` | 123+ (2024) | 120+ (2023) | 17.5+ (2024) | Baseline May 2024 |
| `prefers-reduced-transparency` | 118+ (2023) | 113+ flag only | Not exposed | Not Baseline; treat as enhancement |
| `prefers-contrast` | 96+ | 101+ | 14.1+ | Baseline May 2022 |
| `forced-colors` | 89+ | 89+ | 16+ | Baseline Sep 2022 |
| `corner-shape` (squircles) | 139+ (Aug 2025) | 159 | TP only | ~71% usage; progressive enhancement |
| Popover API | 114+ | 125+ | 17+ | Baseline 2024; anchor positioning still settling in Firefox |

Policy recommendation for 2026 internal apps: target the Baseline of
`backdrop-filter` (Sep 2024) for glass, keep the opaque fallback forever, and
treat refraction, squircle corners, and reduced-transparency queries as
enhancements.

## 7. SSR, static export, and hydration

- Emit the full glass CSS (both prefixes) in the stylesheet. Never gate glass
  behind hydration: first paint would show a different material and then flash.
- First paint still pays the blur raster cost. Do not stack above-the-fold
  glass on a slow device; the loading experience should already be readable.
- `backdrop-filter` is paint-only, so it causes no layout shift by itself. The
  usual CLS source is a sticky glass header whose height changes with content.
  Reserve its block size.
- Stagger hydration of below-fold glass components (mount a few per frame or on
  intersection) so the main thread is not blocked compositing many surfaces at
  once.
- In static exports (Next.js `output: "export"`, Astro, Astro islands), glass
  is a pure CSS concern; keep the token generator deterministic so the exported
  CSS is stable and cacheable.

## 8. Measuring

Practical methods that surface glass cost:

1. Chrome DevTools Performance: record a scroll and look for long
   `Paint`/`Composite Layers` frames on glass elements. Compare with glass
   disabled.
2. DevTools Rendering panel: "Paint flashing" shows the backdrop area repaint
   per frame.
3. Lighthouse/INP: a glass-heavy page usually shows INP and Total Blocking Time
   regressions, not CLS.
4. A page-level audit script that counts blurred elements:

```ts
export function countGlassSurfaces(root: ParentNode = document): number {
  let count = 0;
  for (const el of root.querySelectorAll<HTMLElement>("*")) {
    const style = getComputedStyle(el);
    if (
      style.backdropFilter !== "none" &&
      style.backdropFilter !== "" &&
      style.display !== "none" &&
      style.visibility !== "hidden"
    ) {
      count++;
    }
  }
  return count;
}
```

Add a CI budget: fail if `countGlassSurfaces()` exceeds the agreed maximum per
route fixture.

5. Test on a mid-range Android device, not only on a developer laptop.

## 9. Print

```css
@media print {
  .xglass {
    -webkit-backdrop-filter: none;
    backdrop-filter: none;
    background: #fff;
    color: #000;
    box-shadow: none;
  }
}
```

Printers do not composite blur, and browsers often strip backgrounds anyway.
Force opaque for legibility rather than fighting with `print-color-adjust`.

## 10. Checklist

- [ ] Glass surfaces per viewport within budget (default max 3).
- [ ] Blur radii small unless there is a documented exception.
- [ ] No animated `backdrop-filter`.
- [ ] No permanent `will-change` on glass.
- [ ] Below-fold glass lazy-mounts or uses `content-visibility`.
- [ ] Scroll test on a mid-range device passes without dropped frames.
- [ ] Fallback verified in Firefox/Safari/WebKitGTK when relevant.
- [ ] Tauri: native vibrancy and CSS glass not stacked.
- [ ] Print stylesheet opaque.

## 11. Related

- `./02-css-implementation.md` - the CSS that implements these rules.
- `./03-design-tokens-and-theming.md` - levels map to cost tiers.
- `./05-accessibility-and-legibility.md` - reduced transparency support.
- `./08-tauri-packaging.md` - webview and native effect costs.
