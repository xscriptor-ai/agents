# 02 - CSS implementation

The browser mechanics behind glass. This is the reference to open when the
effect is not rendering, renders the wrong thing, or needs to be robust across
engines.

## 1. `backdrop-filter` in one page

```css
/* syntax */
backdrop-filter: none | <filter-value-list>;

/* one function */
backdrop-filter: blur(20px);

/* chained functions, applied left to right */
backdrop-filter: blur(20px) saturate(180%) brightness(1.05) contrast(1.02);

/* SVG filter reference */
backdrop-filter: url("filters.svg#glass");
```

Supported filter functions: `blur()`, `brightness()`, `contrast()`,
`drop-shadow()`, `grayscale()`, `hue-rotate()`, `invert()`, `opacity()`,
`saturate()`, `sepia()`, plus SVG filter references. The property applies the
filter to the pixels painted **behind** the element, clipped to the element's
border box (including `border-radius`), and only up to the nearest **backdrop
root**.

Key facts:

- The element must be transparent or partially transparent for the effect to be
  visible. An opaque background hides the blurred backdrop completely.
- The element's own content is drawn **after** the filter and is never blurred.
  Text inside the glass stays crisp by design.
- `backdrop-filter` is animatable as a filter function list, but you should not
  animate it (see `./06-performance-and-browser-support.md`).
- Computed value other than `none` creates a stacking context and a containing
  block for `absolute`/`fixed` descendants. Fixed-position children inside a
  glass element will position relative to the glass element, not the viewport.

## 2. Backdrop roots

An element becomes a backdrop root when it matches any of:

- the root element (`<html>`);
- `filter` other than `none`;
- `opacity` less than `1`;
- `mask`, `mask-image`, `mask-border`, or `clip-path` other than `none`;
- `backdrop-filter` other than `none`;
- `mix-blend-mode` other than `normal`;
- `will-change` naming any of the above properties.

Consequences:

- A child's blur can only see content painted **between** the child and its
  nearest backdrop root, inclusive of the root's own background.
- If an ancestor has `opacity: 0.9`, the child's `backdrop-filter` silently
  stops seeing the page background. This is the number one cause of "the blur
  did nothing".
- Nested glass: the inner element's backdrop root is the outer glass element
  (because it has `backdrop-filter`), so the inner pane blurs only the outer
  pane's content, not the page. This is structural, not a bug.

Debugging rule: when blur looks wrong, walk up the DOM and list every ancestor
with `filter`, `opacity < 1`, `mask`, `clip-path`, `mix-blend-mode`, or
`will-change`. One of them is your backdrop root.

## 3. Clipping, radius, and paint order

Paint order for a filtered element, simplified:

1. The element's backdrop is computed.
2. The backdrop is clipped to the element's border box, including
   `border-radius`.
3. The filter chain is applied to the clipped backdrop.
4. The element's own background, border, and children are painted.

There is no way to make the backdrop blur spill outside the border box. For
effects that must consider nearby content, the element itself is extended and
then trimmed with a mask (Section 5).

## 4. Prefixes and support

| Engine | `backdrop-filter` |
|--------|-------------------|
| Chrome / Edge (Blink) | 76+ (2019-07-30), unprefixed |
| Safari / WKWebView | `-webkit-` 9+; unprefixed 18+ (2024-09-16) |
| Firefox | 103+ (2022-07-26), unprefixed |
| WebKitGTK (Linux apps) | `-webkit-` in older 2.3x; unprefixed 2.46+ (approximate, verify on distro) |
| Baseline status | Newly available since 2024-09-16; ~96% global usage (Aug 2026 StatCounter) |

Always ship both declarations, prefixed first:

```css
.xglass {
  -webkit-backdrop-filter: blur(20px) saturate(180%);
  backdrop-filter: blur(20px) saturate(180%);
}
```

CSS tooling (Lightning CSS, Autoprefixer with browserslist targets) adds the
prefix automatically; do not rely on that silently, because Tauri and embedded
webviews follow the OS engine, not your browserslist.

## 5. The mask tricks (nearby pixels, rounded corners, edges)

### 5.1 Consider nearby content

Because the blur only sees pixels directly behind the element, sticky bars do
not pick up color from content that is *about to* pass under them. The fix is
to extend a backdrop layer beyond the bar and trim it visually with a mask
(masking runs after filtering in all engines):

```css
.xglass-header {
  position: relative;
}

.xglass-header__backdrop {
  position: absolute;
  inset: 0;
  height: 200%;               /* extend downward to cover nearby content */
  pointer-events: none;       /* the extension must not block clicks */
  -webkit-backdrop-filter: blur(16px) saturate(180%);
  backdrop-filter: blur(16px) saturate(180%);
  -webkit-mask-image: linear-gradient(to bottom, black 0 50%, transparent 50% 100%);
  mask-image: linear-gradient(to bottom, black 0 50%, transparent 50% 100%);
}
```

Why a mask and not `overflow: hidden`:

- Firefox and Safari trim before/after filters in a way that makes
  `overflow: hidden` work; Chrome applies overflow clipping before the filter,
  so the blur sees nothing extra. `clip-path` has the same problem.
- `mask-image` is applied after filtering in every engine, so it is the
  portable way to trim.
- The oversized layer must be `pointer-events: none`, or it will eat clicks and
  text selection on the content it overlaps.

### 5.2 Top flicker

When content scrolls out of the viewport at the top, its pixels stop being part
of the backdrop and the blur visibly "goes goopy" at the edge. Cover it with a
gradient that fades the top of the glass into the page background:

```css
.xglass-header__backdrop {
  background: linear-gradient(
    to bottom,
    var(--surface-opaque) 0,
    transparent 50%
  );
}
```

Elements outside the viewport are never considered by `backdrop-filter`, in any
engine. The gradient is the accepted mitigation.

### 5.3 Rounded corners with the extension trick

An extended layer normalized by `height: 200%` cannot be rounded with
`border-radius` (the radius would apply to the hidden bottom edge). Use an SVG
mask when the surface must be rounded and still see nearby pixels:

```html
<svg class="xglass-mask" width="100%" height="100%" preserveAspectRatio="none">
  <mask id="xglass-rounded">
    <rect width="100%" height="100%" rx="16" ry="16" fill="white" />
  </mask>
</svg>
```

```css
.xglass-header__backdrop {
  -webkit-mask-image: url(#xglass-rounded);
  mask-image: url(#xglass-rounded);
}
```

SVG `<mask>` references from HTML elements are not supported in all WebKit
versions; test on your target. When SVG masks are not available, fall back to
no extension (plain rounded glass with `border-radius`).

### 5.4 Glass edge (thickness)

A second, shorter layer under the bottom edge with a different filter creates
the illusion of a thick pane:

```css
.xglass-header__edge {
  --thickness: 6px;
  position: absolute;
  inset: 0;
  height: 100%;
  transform: translateY(100%);
  pointer-events: none;
  background: rgb(255 255 255 / 0.1);
  -webkit-backdrop-filter: blur(8px) brightness(1.2);
  backdrop-filter: blur(8px) brightness(1.2);
  -webkit-mask-image: linear-gradient(to bottom, black 0, black var(--thickness), transparent var(--thickness));
  mask-image: linear-gradient(to bottom, black 0, black var(--thickness), transparent var(--thickness));
}
```

Use a smaller blur and a brightness lift on the edge: the edge should catch
light, not magnify the blur.

### 5.5 Gradient border rim

For a rim that is brighter on top and fades to the sides, use a masked
pseudo-element instead of `border`:

```css
.xglass {
  position: relative;
  border-radius: 16px;
}

.xglass::before {
  content: "";
  position: absolute;
  inset: 0;
  border-radius: inherit;
  padding: 1px;
  background: linear-gradient(
    to bottom,
    rgb(255 255 255 / 0.6),
    rgb(255 255 255 / 0.08)
  );
  -webkit-mask:
    linear-gradient(#000 0 0) content-box,
    linear-gradient(#000 0 0);
  -webkit-mask-composite: xor;
  mask:
    linear-gradient(#000 0 0) content-box,
    linear-gradient(#000 0 0);
  mask-composite: exclude;
  pointer-events: none;
}
```

## 6. SVG filters

### 6.1 Historical blur fallback

Before Firefox 103, `backdrop-filter` was unavailable, and the workaround was
to duplicate the background inside the element and blur it with an SVG
`feGaussianBlur`. This is now historical: the opaque fallback in Section 7 is
cheaper and safer. Keep this only if you must support very old Firefox.

### 6.2 Noise texture

```svg
<filter id="xglass-noise">
  <feTurbulence type="fractalNoise" baseFrequency="0.8" numOctaves="2" stitchTiles="stitch"/>
  <feColorMatrix type="saturate" values="0"/>
</filter>
```

Reference it as a background layer on a pseudo-element with low opacity. A
`feTurbulence` data-URI avoids shipping an image and stays resolution
independent.

### 6.3 Refraction / displacement

```svg
<filter id="xglass-refraction">
  <feImage href="data:image/png;base64,..." result="map"/>
  <feDisplacementMap in="SourceGraphic" in2="map" scale="12"
    xChannelSelector="R" yChannelSelector="G"/>
</filter>
```

```css
.xglass-edge {
  backdrop-filter: url(#xglass-refraction);
}
```

Reality check (2026): SVG filters as `backdrop-filter` values work in
Chromium; Safari and Firefox do not reliably support them (WebKit bugs 245510
and 297770 are open around `url()` filters). Treat refraction as a
Chromium-only enhancement with a normal blur fallback. In Tauri, this means
macOS/WKWebView and Linux/WebKitGTK do not get it.

## 7. Fallbacks and preference queries

Progressive enhancement contract:

1. Base declaration: opaque-enough background that is readable with no blur
   support at all.
2. Inside `@supports`, replace it with glass.
3. Inside preference media queries, collapse back to a more opaque or solid
   version.

```css
.xglass {
  /* 1. readable everywhere */
  background: color-mix(in oklab, var(--surface) 94%, var(--brand) 6%);
  border: 1px solid var(--edge);
  border-radius: 16px;
}

@supports ((backdrop-filter: blur(12px)) or (-webkit-backdrop-filter: blur(12px))) {
  .xglass {
    /* 2. glass */
    background: var(--xglass-tint);
    -webkit-backdrop-filter: blur(var(--xglass-blur)) saturate(180%);
    backdrop-filter: blur(var(--xglass-blur)) saturate(180%);
    box-shadow: var(--xglass-shadow);
  }
}

@media (prefers-reduced-transparency: reduce) {
  .xglass {
    background: var(--surface);
    -webkit-backdrop-filter: none;
    backdrop-filter: none;
  }
}

@media (prefers-contrast: more) {
  .xglass {
    background: var(--surface);
    border-color: currentColor;
    -webkit-backdrop-filter: none;
    backdrop-filter: none;
  }
}

@media (forced-colors: active) {
  .xglass {
    background: Canvas;
    color: CanvasText;
    border: 1px solid ButtonText;
    -webkit-backdrop-filter: none;
    backdrop-filter: none;
    box-shadow: none;
  }
}

@media (prefers-reduced-motion: reduce) {
  .xglass,
  .xglass * {
    transition-duration: 0.01ms;
    animation-duration: 0.01ms;
  }
}
```

Support reality for `prefers-reduced-transparency`: Chrome/Edge 118+
(2023-10-10), Firefox 113 behind a flag (not default as of Sep 2026),
Safari/WebKit no web query yet (WebKit bug 175497). Therefore the **base
declaration must always be readable**; the query is an enhancement, not the
safety net. Details in `./05-accessibility-and-legibility.md`.

`prefers-contrast` values are `no-preference | less | more | custom`. Never use
the bare `@media (prefers-contrast)` form for "more" behavior: it also matches
`less`. Always qualify the value.

## 8. Traps

### `will-change`

`will-change: backdrop-filter` (or `filter`, `opacity`, `mask`) makes the
element a backdrop root, which can change what gets blurred, and holds GPU
memory forever. Never pre-declare it on glass. If an animation needs it, add it
transiently before the animation and remove it after.

### Transform ancestors

A transformed ancestor does not create a backdrop root per spec, but engines
have historically mishandled `backdrop-filter` inside 3D-transformed contexts
(WebKit bug 252181, 201987). If glass inside a transformed container renders
wrong, test moving the glass out of the transform.

### `isolation` and stacking

`isolation: isolate` creates a stacking context but is not a spec backdrop
root. Don't use it expecting to bound a blur; use an explicit `filter` or
`opacity` ancestor only if you actually want a backdrop root, and document why.

### Sticky + overflow + radius (Firefox)

Known bug: `backdrop-filter` stops rendering on `position: sticky` elements
when an ancestor has both `overflow` and `border-radius` (Firefox bug 1803813).
Workaround: apply the blur to an inner absolute layer instead of the sticky
element itself.

### Overscroll flicker

Community-reported flicker of blur while overscrolling; setting
`overscroll-behavior: contain` on the scroll container has worked for several
teams. Treat as empirical, test per engine.

### Fixed backgrounds in Safari

`background-attachment: fixed` plus blur samples incorrectly in some Safari
versions. Prefer `position: fixed` background layers to `attachment: fixed`.

### Print

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

Printers do not composite blur; force opaque.

## 9. Production primitive

The complete primitive used by this system. Copy into a design-system CSS
layer, then theme via custom properties.

```css
@layer xglass {
  .xglass {
    --xglass-blur: 20px;
    --xglass-saturate: 180%;
    --xglass-brightness: 1;
    --xglass-tint: rgb(255 255 255 / 0.12);
    --xglass-edge: rgb(255 255 255 / 0.35);
    --xglass-highlight: rgb(255 255 255 / 0.45);
    --xglass-radius: 16px;
    --xglass-shadow:
      0 1px 2px rgb(0 0 0 / 0.10),
      0 8px 32px rgb(0 0 0 / 0.18);

    position: relative;
    isolation: isolate;
    border-radius: var(--xglass-radius);
    border: 1px solid var(--xglass-edge);
    background: var(--xglass-tint);
    box-shadow: inset 0 1px 0 var(--xglass-highlight), var(--xglass-shadow);
  }

  @supports ((backdrop-filter: blur(1px)) or (-webkit-backdrop-filter: blur(1px))) {
    .xglass {
      -webkit-backdrop-filter:
        blur(var(--xglass-blur))
        saturate(var(--xglass-saturate))
        brightness(var(--xglass-brightness));
      backdrop-filter:
        blur(var(--xglass-blur))
        saturate(var(--xglass-saturate))
        brightness(var(--xglass-brightness));
    }
  }

  .xglass--thin   { --xglass-blur: 10px; --xglass-tint: rgb(255 255 255 / 0.08); }
  .xglass--thick  { --xglass-blur: 32px; --xglass-tint: rgb(255 255 255 / 0.20); }
}
```

Notes:

- `isolation: isolate` keeps the element's children from blending with the
  backdrop unexpectedly; it does not affect the backdrop filter itself.
- The base rule works without blur; the `@supports` block only adds the filter
  chain. This ordering is what makes the fallback automatic.
- Components consume `--xglass-*` tokens; they never set `blur()` values
  directly.

## 10. Debugging checklist

- Blur invisible?
  1. Is the element's background fully opaque?
  2. Is there a backdrop root between the element and the page background?
  3. Is the browser/webview actually supporting the property (check
     `CSS.supports('backdrop-filter', 'blur(1px)')`)?
  4. Is the element painted over the content you expect (z-index/stacking)?
- Blur sees less than expected? Extend the layer and mask it (Section 5.1).
- Blur extends beyond the radius? You added a mask or a pseudo-element with the
  wrong `border-radius`; verify `border-radius: inherit` and `overflow` on the
  right element.
- Clicks blocked near the glass? The oversized backdrop layer is missing
  `pointer-events: none`.
- Jank while scrolling? See `./06-performance-and-browser-support.md`; reduce
  radius and area before anything else.
- Works in Chrome, not Safari/Firefox? Check for `url()` filters, `mask`
  without `-webkit-`, or `mask-composite` syntax differences.

## 11. Related

- `./01-physics-of-glass.md` - why these layers exist.
- `./03-design-tokens-and-theming.md` - the token names used here.
- `./06-performance-and-browser-support.md` - costs and engine bug catalog.
- `./08-tauri-packaging.md` - webview differences that change these rules.
