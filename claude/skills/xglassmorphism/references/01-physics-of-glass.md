# 01 - Physics of real glass

Glass looks like glass because light does several things at once when it passes
through a physical pane. Web glass is an approximation, but knowing which
physical effect each CSS layer stands in for is what separates a convincing
surface from a gray rectangle.

This document defines the five-layer model, how each layer maps to CSS, how to
tune intensities, and what is not reproducible on the web today.

## 1. What real glass does

| Physical effect | What happens | Web approximation |
|-----------------|--------------|-------------------|
| Scattering / diffusion | Transmitted light is spread by surface texture and internal structure | `backdrop-filter: blur()` |
| Absorption / tinting | Material absorbs part of the spectrum, coloring transmitted light | translucent `background-color` / gradient tint |
| Chroma shift | Thick glass deepens and shifts color; blur mutes chroma | `saturate()` and `brightness()` in the backdrop filter chain |
| Refraction / lensing | Light bends at curved or beveled edges; content near edges warps | Not reproducible in CSS; approximated with SVG displacement (Chromium only) |
| Specular reflection | Light sources reflect on the surface, following viewing geometry | inset highlights, gradient borders, `box-shadow` rims |
| Internal reflection / caustics | Light bounces inside the pane, creating edge glow | second backdrop layer on the edge with different filters |
| Surface grain | Micro-imperfections scatter highlights | fine noise overlay (`feTurbulence` or data-URI texture) |
| Cast shadow / depth | The pane floats above the scene and darkens what is behind | `box-shadow` ambient + direct |
| Thickness | Thicker glass distorts and darkens more | larger blur radius + higher tint alpha + stronger shadow |

Apple's Liquid Glass (announced 2025-06-09 at WWDC25, shipped with iOS 26 on
2025-09-15) formalizes this: it lenses and concentrates light, draws specular
highlights that respond to device motion, and adapts its tint to the content
behind it. It comes in **Regular** (adaptive) and **Clear** (always transparent,
requires a dimming layer) variants. iOS 26.1 (2025-11-03) added a user-facing
Clear/Tinted toggle after beta feedback about legibility. On the web you can
reproduce the specular rim, the grain, the layered tint, and (in Chromium only)
coarse edge distortion; you cannot reproduce real per-pixel lensing or the
adaptive material system. See `./08-tauri-packaging.md` for the native Tauri
side and Section 7 below for the honest limits.

## 2. The five-layer model

Every glass surface in this system is composed of these layers. A surface
missing any of them is incomplete; a surface adding more usually needs a design
reason.

1. **Backdrop** - the blur chain that processes what is behind the element.
2. **Tint** - the translucent fill that sets the color and does the contrast
   work.
3. **Edge** - the specular rim and inner highlight that suggest a bevel.
4. **Depth** - the cast shadow that lifts the pane off the scene.
5. **Texture** - optional fine grain that kills the "digital gradient" look.

### Layer 1: backdrop

```css
backdrop-filter: blur(20px) saturate(180%) brightness(1.05);
```

- `blur(len)` applies a Gaussian blur whose length maps to the standard
  deviation (same as SVG `feGaussianBlur stdDeviation`). Do not confuse it with
  `box-shadow` blur radius, where the visible falloff is roughly twice the
  standard deviation. If a shadow and a blur look mismatched at equal numbers,
  this is why.
- `saturate(150-200%)` compensates for the chroma muting that blur causes.
  Without it, colorful backdrops turn gray-beige behind the glass.
- `brightness()` above 1 lifts dark backdrops (dark theme), below 1 calms
  bright ones (light theme over media). Keep it in the 0.9-1.15 band; larger
  values destroy contrast.
- The blur considers only pixels **directly behind** the element. Content that
  is near but not behind contributes nothing, which is why a colorful blob
  sliding just under a sticky header does not tint it. The mask trick that
  fixes this is in `./02-css-implementation.md`.

### Layer 2: tint

```css
background: rgb(255 255 255 / 0.12);          /* light glass on dark scene */
background: rgb(15 18 24 / 0.55);             /* dark glass on light scene */
background: color-mix(in oklab, var(--brand) 14%, transparent); /* branded */
```

- The tint is the contrast guarantee. Blur is not a contrast device; text over
  blur alone fails WCAG on busy imagery.
- Light glass uses white at low alpha and reads as "frosted". Dark glass uses
  the theme's surface color at higher alpha and reads as "smoked".
- Tint alpha scales with the amount of text on the surface, not with taste.
  A nav bar with small links needs more tint than a decorative card.
- For glass over photography, prefer a two-stop gradient tint (more opaque at
  the top and bottom edges, clearer in the middle) to preserve legibility where
  text sits while keeping the image visible at the center.

### Layer 3: edge

```css
border: 1px solid rgb(255 255 255 / 0.35);
box-shadow:
  inset 0 1px 0 rgb(255 255 255 / 0.45),   /* top inner highlight */
  inset 0 -1px 0 rgb(255 255 255 / 0.08);  /* bottom bounce */
```

- Real glass catches light on the bevel. A 1px translucent border plus an inset
  top highlight creates the bevel with two paints.
- The inner highlight is brighter on the side facing the assumed light source
  (top by convention). Inverting it makes the pane look pressed in.
- Gradient borders (brighter at the top, fading at the bottom) are the next
  step up and can be done with a masked pseudo-element; see
  `./02-css-implementation.md`.
- Avoid rainbow or high-chroma borders: they read as "gamer UI", not glass.
  Keep the edge within the tint's hue family or pure white/black.

### Layer 4: depth

```css
box-shadow:
  0 1px 2px rgb(0 0 0 / 0.10),   /* direct, tight */
  0 8px 32px rgb(0 0 0 / 0.18);  /* ambient, soft */
```

- Two shadows: a tight one for contact and a large soft one for lift. A single
  large shadow looks like a drop shadow sticker; a single tight one looks flat.
- Glass depth is subtle. Opacities above ~0.25 on the ambient shadow make the
  pane look heavy and dated.
- In dark themes, shadow still works but must be stronger to separate from
  dark scenes; consider a subtle top-edge highlight instead of pure shadow.

### Layer 5: texture (optional)

```css
.xglass::after {
  content: "";
  position: absolute;
  inset: 0;
  border-radius: inherit;
  pointer-events: none;
  opacity: 0.035;
  background-image: url("data:image/svg+xml,..."); /* feTurbulence noise */
  mix-blend-mode: overlay;
}
```

- Fine grain breaks the gradient banding that large blurs produce on 8-bit
  displays and makes glass feel physical.
- Keep opacity in the 0.02-0.05 range. Above that it becomes a texture, not a
  material.
- The noise layer must be `pointer-events: none` and inherit the radius, or it
  will intercept clicks and leak square corners over rounded glass.
- Do not animate the noise; it costs a compositing layer for no visible gain.

## 3. Anatomy diagram (ASCII)

```
        specular rim (border 1px, white/35)
   +----------------------------------------------+
   |  inner top highlight (inset 0 1px, white/45) |
   |                                              |
   |      content: text/icons drawn ON TOP        |
   |      (never blurred, always scrim-backed)    |
   |                                              |
   |  tint: rgb(255 255 255 / 0.12)               |
   |  backdrop: blur(20px) saturate(180%)         |
   |  texture: noise 3%, overlay                  |
   +----------------------------------------------+
         ambient + direct shadow lifts the pane
```

## 4. Intensity decision table

Use these as starting points, then tune against real content.

| Context | Blur | Saturate | Tint (light/dark) | Edge | Noise |
|---------|------|----------|-------------------|------|-------|
| Sticky nav over hero imagery | 12-16px | 160-180% | 0.10 / 0.45 | white/30 | 0.03 |
| Card on gradient background | 16-20px | 170-190% | 0.12 / 0.50 | white/35 | 0.03 |
| Modal over busy app | 28-36px | 180-200% | 0.20 / 0.60 | white/40 | 0.04 |
| Popover/menu over glass context | 16-20px | 170% | 0.16 / 0.55 | white/30 | 0 |
| Input field on glass | 10-14px | 150% | 0.14 / 0.50 | white/25 | 0 |
| Full-screen media overlay | 40-60px | 140-160% | 0.30 / 0.55 | none | 0.05 |
| Decorative badge/chip | 8-10px | 160% | 0.10 / 0.45 | white/35 | 0 |

Rules of thumb:

- Small text demands more tint, less blur.
- Large surfaces (full-width bars) demand less blur for performance and more
  tint for legibility.
- Bright scenes need darker or denser tint; dark scenes need a brightness lift
  and a visible edge to separate the pane from the background.

## 5. Glass and color: what blur does to hues

- Gaussian blur averages neighbors, so high-frequency detail becomes mid-tone
  mush. A black-and-white checkerboard blurs to 50% gray; saturated red next to
  green blurs toward brown. This is why saturated backdrops look muddy behind
  glass without `saturate()`.
- White text on dark glass over a bright backdrop loses contrast locally. The
  fix is tint, not more blur.
- Tinted glass shifts the perceived hue of everything behind it. Brand-tinted
  glass must be tested against brand-colored backgrounds, which is the worst
  case for separation.
- Dark mode is not "invert the light tokens". Dark glass is a different
  material: denser tint, stronger edge highlight, weaker cast shadow. See
  `./03-design-tokens-and-theming.md`.

## 6. Motion and specular response

Static glass already reads well. Dynamic response is the Liquid Glass layer
that is partially reproducible:

- **Specular follow** - move the inner highlight gradient origin with the
  pointer using `@property`-registered custom properties and a `pointermove`
  listener. Keep it subtle (a few degrees of gradient rotation) and disable it
  under `prefers-reduced-motion`.
- **Tint shift on scroll** - interpolate tint alpha as content scrolls under a
  sticky bar. Animate a background layer's `opacity`, never the
  `backdrop-filter` value.
- **Edge glint** - a narrow pseudo-element with `background: linear-gradient`
  and `mix-blend-mode: screen` that tracks the pointer along the rim.
- Motion is a garnish. If the glass only works when it moves, it is not glass;
  it is a demo.

## 7. What is not reproducible on the web (2026)

| Effect | Status |
|--------|--------|
| True per-pixel refraction of arbitrary page content | Not possible in CSS. `backdrop-filter: url(#svg)` with `feDisplacementMap` approximates it in Chromium only; Safari and Firefox do not support SVG filters as backdrop filters reliably. |
| Content-aware adaptive tint | No API; the backdrop pixels are not readable from JS. Approximate with scroll position + `IntersectionObserver` heuristics. |
| Specular highlights reacting to device motion/light sensor | Device orientation is available but permission-gated and noisy; treat as optional garnish, not design requirement. |
| Material morphing (gel-like transitions) | Approximate with two stacked layers cross-fading opacity + scale; the real lensing modulation is native-only. |
| Cross-engine identical rendering | Impossible; plan the fallback hierarchy from the start. |

When a stakeholder asks for "exactly like iOS", the honest answer is: the
specular rim, grain, tint, and fallback hierarchy yes; the lensing no. Deliver
the first and set expectations about the second.

## 8. Anti-patterns

- **Gray plastic**: blur with no tint/saturation. The backdrop's average color
  dominates and everything looks dirty.
- **Soap bubble**: tint with no blur or edge. Reads as a translucent sticker.
- **Vista Aero**: heavy specular gradients, visible bevels, strong shadows.
  Keep the rim at 1px and the highlight subtle.
- **Frosted everything**: dozens of blurred cards. Muddy hierarchy and jank.
- **Invisible glass**: glass whose background is so close to the page
  background that only the shadow shows. Glass needs contrast behind it to be
  perceived as glass.
- **Blur as a design smell**: using blur to hide poor image quality or
  unreadable text. Fix the asset or the text.

## 9. Worked examples

### Dark app shell with light accent

```css
:root[data-theme="dark"] .xglass {
  --xglass-blur: 24px;
  --xglass-saturate: 180%;
  --xglass-tint: rgb(18 20 26 / 0.55);
  --xglass-edge: rgb(255 255 255 / 0.14);
}
```

Dark glass is denser and relies on the edge highlight for separation. Shadow
values drop; the top rim does the lifting.

### Light marketing page with colorful hero

```css
:root[data-theme="light"] .xglass {
  --xglass-blur: 16px;
  --xglass-saturate: 190%;
  --xglass-tint: rgb(255 255 255 / 0.55);
  --xglass-edge: rgb(255 255 255 / 0.65);
}
```

Light glass over saturated imagery needs a high white alpha to keep dark text
readable. The saturation boost keeps the hero colorful through the pane.

### Compact toolbar (performance constrained)

```css
.xglass-toolbar {
  --xglass-blur: 10px;
  --xglass-saturate: 150%;
  --xglass-tint: rgb(255 255 255 / 0.72);
  border: 1px solid rgb(255 255 255 / 0.4);
  box-shadow: 0 1px 2px rgb(0 0 0 / 0.12);
}
```

Small blur, high tint, no noise: the cheapest convincing glass. Toolbars that
float for the lifetime of the app should stay in this band.

## 10. Related

- `./02-css-implementation.md` - how to express these layers in robust CSS.
- `./03-design-tokens-and-theming.md` - turning this document into tokens.
- `./05-accessibility-and-legibility.md` - the contrast math behind the tint.
- `./08-tauri-packaging.md` - when the glass is native instead of CSS.
