# 05 - Accessibility and legibility

Translucent UI fails accessibility in predictable ways: contrast that varies
with the scroll position, focus rings hidden by blurred overlays, and users who
explicitly asked the OS for less transparency. This reference defines the
contract, the math, and the pre-ship checklist.

## 1. WCAG criteria that apply

| Criterion | Level | Requirement | Glass implication |
|-----------|-------|-------------|-------------------|
| 1.4.3 Contrast (Minimum) | AA | 4.5:1 normal text, 3:1 large (>=24px, or >=18.66px bold) | Text over glass must meet the ratio against the composited (tinted + backdrop) color, not the tint alone |
| 1.4.6 Contrast (Enhanced) | AAA | 7:1 normal, 4.5:1 large | Target for reading surfaces (modals, long-form panels) |
| 1.4.11 Non-text Contrast | AA | 3:1 for UI component boundaries, states, meaningful graphics | Includes **focus indicators** and input borders; translucent borders often fail |
| 2.4.11 Focus Not Obscured (Minimum) | AA (WCAG 2.2) | Focused component not entirely hidden by author content | Sticky glass headers/bars must not cover the focus ring; see failure F110 and technique C43 |
| 2.4.12 Focus Not Obscured (Enhanced) | AAA | Focused component not partially obscured | Same surfaces, stricter |
| 1.4.12 Text Spacing | AA | Content must not lose info when spacing is overridden | Glass fixed-height bars often clip when users inject spacing |
| 2.5.8 Target Size (Minimum) | AA | 24x24 CSS px minimum target | Small glass chips/buttons are a common violation |
| 2.3.3 Animation from Interactions | AAA | Motion triggered by interaction can be disabled | Pointer-following specular effects must respect reduced motion |

Ratios are exact thresholds: 4.499 fails. Background images are a documented
failure mode (F83); gradients and photos require testing the **least
contrasting area**, not the average.

## 2. Worst-case testing, not average

Blur averages pixels locally; it does not guarantee contrast. A bright blob
behind one word survives the blur and breaks that word. The evaluation method:

1. Inventory every text, icon, boundary, and focus indicator that can sit on a
   translucent layer.
2. Define the worst-case backdrop set: lightest region, darkest region, busiest
   region, both themes, scroll extremes, 200% and 400% zoom.
3. Composite the actual rendered color and measure; never eyeball.

CSS alpha compositing happens in gamma-encoded sRGB:

```
resultChannel = alpha * foreground + (1 - alpha) * background
```

Compute the ratio from that result using relative luminance:

```
L = 0.2126 R + 0.7152 G + 0.0722 B      (channels linearized)
ratio = (L1 + 0.05) / (L2 + 0.05)
```

### TypeScript contrast utility

Ship this in the design system and unit-test the palette with it. It gives the
team a single, objective definition of "readable over glass".

```ts
export type RGB = readonly [number, number, number];
export type RGBA = readonly [number, number, number, number];

function linearize(channel: number): number {
  const c = channel / 255;
  return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
}

export function luminance([r, g, b]: RGB): number {
  return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b);
}

export function over(fg: RGBA, bg: RGB): RGB {
  const a = fg[3];
  return [
    Math.round(a * fg[0] + (1 - a) * bg[0]),
    Math.round(a * fg[1] + (1 - a) * bg[1]),
    Math.round(a * fg[2] + (1 - a) * bg[2]),
  ] as const;
}

export function contrast(a: RGB, b: RGB): number {
  const [l1, l2] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (l1 + 0.05) / (l2 + 0.05);
}

export function worstCaseContrast(
  text: RGB,
  tint: RGBA,
  backdrops: readonly RGB[],
): number {
  return Math.min(
    ...backdrops.map((backdrop) => contrast(text, over(tint, backdrop))),
  );
}
```

Test:

```ts
import { worstCaseContrast } from "./contrast";

const backdrops = [
  [255, 255, 255], // white
  [0, 0, 0],       // black
  [230, 60, 80],   // brand red
  [40, 80, 220],   // brand blue
  [120, 180, 90],  // photo green
] as const;

const bodyText = [22, 25, 33] as const;

test("light regular glass keeps AA over worst-case backdrops", () => {
  const tint = [255, 255, 255, 0.58] as const;
  expect(worstCaseContrast(bodyText, tint, backdrops)).toBeGreaterThanOrEqual(4.5);
});
```

If a surface cannot pass even with a scrim, the design changes: more tint,
darker scrim, larger text, or the text leaves the glass.

## 3. Scrims: the math

A scrim is an additional translucent layer between the backdrop and the text.
For pure white text over a black scrim on the worst-case white backdrop:

| Target ratio | Minimum black scrim alpha |
|--------------|---------------------------|
| 3:1 (large text, UI) | ~0.42 |
| 4.5:1 (AA normal) | ~0.54 |
| 7:1 (AAA normal) | ~0.65 |

These are the minimums for the absolute worst case (pure white backdrop). Real
backdrops are usually darker; still design to the worst case or document the
exception. For dark text over a white scrim on a black backdrop the mirrored
values apply.

Practical rules:

- Scrim under text, not over the whole glass; a full-surface scrim kills the
  glass effect. A text-band gradient scrim is the usual compromise.
- A scrim can be cheaper than more blur: prefer raising tint alpha over raising
  the blur radius.
- Recompute when the tint or backdrop changes; treat the numbers as token
  inputs, not one-time decisions.

## 4. Preference media queries

### `prefers-reduced-transparency`

Values: `no-preference | reduce`.

Support (Sep 2026):

| Engine | Status |
|--------|--------|
| Chrome / Edge / Opera | 118+ (2023-10-10) |
| Samsung Internet | 25+ (2024-04) |
| Firefox | 113+, behind `layout.css.prefers-reduced-transparency.enabled`, not enabled by default |
| Safari / WebKit | Not exposed as a web query yet (WebKit bug 175497 open) |

Because coverage is partial, the query is an enhancement, never the safety net.
The base declaration must already be readable (see Section 5).

```css
@media (prefers-reduced-transparency: reduce) {
  .xglass {
    background: var(--surface);
    -webkit-backdrop-filter: none;
    backdrop-filter: none;
  }
}
```

### `prefers-contrast`

Values: `no-preference | less | more | custom`. Baseline since May 2022
(Chrome 96, Firefox 101, Safari 14.1). Always qualify the value; a bare
`@media (prefers-contrast)` also matches `less`.

```css
@media (prefers-contrast: more) {
  .xglass {
    background: var(--surface);
    border-color: currentColor;
    -webkit-backdrop-filter: none;
    backdrop-filter: none;
  }
}

@media (prefers-contrast: less) {
  .xglass {
    --xglass-edge: transparent;
  }
}
```

### `forced-colors`

Baseline since Sep 2022. In forced colors, backgrounds and shadows are
replaced, but `backdrop-filter` is not in the forced-property list, so behavior
is engine-dependent - verify per target. Patch illegible spots only; do not
redesign.

```css
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
```

### `prefers-reduced-motion`

Baseline. Disable pointer-following specular effects, parallax glass, and
animated blur. Keep instant state changes.

```css
@media (prefers-reduced-motion: reduce) {
  .xglass,
  .xglass::before,
  .xglass::after {
    transition-duration: 0.01ms;
    animation-duration: 0.01ms;
    animation-iteration-count: 1;
  }
}
```

## 5. Defensive CSS order

The correct order makes the fallback structural, not conditional:

1. Opaque-enough default so text is readable with no blur support and no media
   query support.
2. `@supports` block adds the glass.
3. Preference queries collapse back to solid/high-contrast.
4. Print resets to opaque.

If a reviewer asks "what happens on Safari with reduced transparency?", the
answer is "it is already readable because the default is not glass".

## 6. Focus, selection, and controls

- **Focus ring**: the ring itself is not blurred (children paint after the
  filter), but a sticky glass bar can cover it. Set `scroll-padding-top` on the
  scroll container for sticky headers (WCAG C43), and keep sticky overlays
  below the focused element's scroll position.
- **Hit targets**: glass chips and icon buttons must keep 24x24 CSS px minimum,
  and decorative overlays must be `pointer-events: none` so they do not steal
  clicks from the content they overlap.
- **Text selection**: define `::selection` with a solid enough background over
  glass; default translucent selection can drop below contrast.

```css
.xglass ::selection {
  background: color-mix(in oklab, var(--brand) 70%, black 10%);
  color: white;
}
```

- **Forms**: placeholders are text and are subject to 1.4.3; do not use them as
  labels. Input backgrounds must be opaque enough for the caret and selection
  to be visible. Autofill styles (`:-webkit-autofill`) often paint an opaque
  yellow that breaks glass; override with a box-shadow inset in the surface
  color.
- **Dialogs**: native `<dialog>`/popover handles focus trap, Escape, and
  top-layer ordering. If you build custom overlays, use `inert` on the
  background and restore focus on close.
- **Screen readers**: transparency is irrelevant to the accessibility tree;
  glass only matters visually. Do not add ARIA to decorative layers, and hide
  noise/edge pseudo-elements from the tree (pseudo-elements already are).

## 7. Platform guidance worth mirroring

- **Apple HIG**: treat WCAG AA as the floor; provide a higher-contrast variant
  when Increase Contrast is on; use vibrancy text levels deliberately (the
  quaternary level is too low for body text); thicker materials improve
  contrast. Native APIs exist to detect Reduce Transparency
  (`UIAccessibility.isReduceTransparencyEnabled`,
  `NSWorkspace.accessibilityDisplayShouldReduceTransparency`).
- **Microsoft Fluent/Acrylic**: the recipe is background + blur + exclusion
  blend (used specifically to preserve text contrast) + tint + noise. Acrylic
  is disabled automatically in Battery Saver, when Transparency effects are
  off, on low-end hardware, and in High Contrast; apps replace it with a solid
  color. Mirror this: build the solid fallback first, glass second.
- **Windows/Linux**: the OS transparency switch is a real user preference even
  when the web query is not available. Expose an in-app "reduce transparency"
  setting for the gap.

## 8. Pre-ship checklist

- [ ] Every glass surface is inventoried (`data-glass-level` attribute helps).
- [ ] Worst-case fixtures exist: light, dark, busy, brand-colored backdrop.
- [ ] Contrast measured from rendered pixels (screenshot + color picker or
  TPGi Colour Contrast Analyser), not guessed.
- [ ] Automated tests acknowledge their blind spots: axe and Lighthouse do not
  report text over `background-image` or understand blur/scrim compositing;
  they return "incomplete" and require manual review.
- [ ] DevTools > Rendering emulation checked for `prefers-reduced-motion`,
  `prefers-contrast` (more/less/custom), `forced-colors`, and
  `prefers-reduced-transparency` (Chrome 118+).
- [ ] Keyboard tab-through: sticky bars and overlays never cover the focus ring.
- [ ] OS-level toggles tested: macOS/iOS Reduce Transparency, Windows
  Transparency effects off + Contrast themes, Battery Saver.
- [ ] Fallback verified with `backdrop-filter` forced off (DevTools or a
  build flag).
- [ ] Zoom to 200% and 400%: no clipped text in fixed-height glass bars.
- [ ] Text spacing override applied: no loss of content.
- [ ] Print preview: opaque, readable.
- [ ] Optional: APCA as a secondary check (flat colors only, not normative in
  WCAG 2.2; WCAG 3 is still a draft).

## 9. Anti-patterns

- Declaring accessibility "handled" because the theme has a dark mode.
- Using blur to make low-contrast text "work".
- Relying on `prefers-reduced-transparency` alone (Safari/WebKit and default
  Firefox do not honor it).
- Testing only the first viewport; the worst-case backdrop is usually further
  down the page.
- Full-screen scrims that swallow the page when no modal is open.
- Focus rings in a translucent brand color that composites below 3:1.
- Animated pointer-following highlights for users who asked for reduced motion.

## 10. Related

- `./02-css-implementation.md` - the fallback and preference CSS blocks.
- `./03-design-tokens-and-theming.md` - scrim and text tokens.
- `./06-performance-and-browser-support.md` - support matrix details.
- `./07-fullstack-architecture.md` - visual regression fixtures for these
  worst-case backdrops.
