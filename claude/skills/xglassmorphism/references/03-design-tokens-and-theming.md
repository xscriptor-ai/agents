# 03 - Design tokens and theming

Glass values are physics, not taste. They must be declared once, themed per
mode, and shared between CSS and TypeScript. This document defines the token
contract, the light/dark model, the generation pipeline, and the Tailwind 4
mapping.

## 1. Token architecture

Two tiers, strictly one-directional:

1. **Primitives** - raw values: alpha steps, blur steps, radius steps. Not used
   by components directly.
2. **Semantic tokens** - named by role: `--xglass-tint`, `--xglass-edge`,
   `--xglass-blur`. Components consume only these.

```css
@layer tokens {
  :root {
    /* primitives */
    --alpha-04: 0.04;
    --alpha-06: 0.06;
    --alpha-08: 0.08;
    --alpha-10: 0.10;
    --alpha-12: 0.12;
    --alpha-16: 0.16;
    --alpha-20: 0.20;
    --alpha-28: 0.28;
    --alpha-45: 0.45;
    --alpha-55: 0.55;
    --blur-08: 8px;
    --blur-12: 12px;
    --blur-16: 16px;
    --blur-24: 24px;
    --blur-32: 32px;
    --blur-40: 40px;
    --radius-sm: 8px;
    --radius-md: 12px;
    --radius-lg: 16px;
    --radius-xl: 24px;
  }
}
```

Alpha primitives are shared with the rest of the design system; do not invent
glass-only steps.

## 2. The glass token set

| Token | Meaning | Type |
|-------|---------|------|
| `--xglass-blur` | Backdrop Gaussian std deviation | length |
| `--xglass-saturate` | Chroma compensation | percentage |
| `--xglass-brightness` | Backdrop luminance lift/calm | number |
| `--xglass-tint` | Translucent fill (contrast carrier) | color |
| `--xglass-edge` | 1px border color | color |
| `--xglass-highlight` | Inner top highlight | color |
| `--xglass-shadow` | Cast shadow stack | shadow list |
| `--xglass-radius` | Surface radius | length |
| `--xglass-noise-opacity` | Grain strength, 0 disables | number |
| `--xglass-scrim` | Overlay behind text when needed | color |
| `--xglass-text` | Text color guaranteed on this surface | color |
| `--xglass-text-muted` | Secondary text on this surface | color |
| `--xglass-transition` | Hover/press transition | time + easing |

Naming is normative for this system. A component that needs a value not in
this list either uses a level variant (`--thin`, `--regular`, `--thick`) or
proposes a new semantic token, never a hard-coded `blur(20px)`.

## 3. Levels

```css
.xglass {
  --xglass-blur: var(--blur-24);
  --xglass-saturate: 180%;
  --xglass-brightness: 1;
  --xglass-tint: var(--glass-tint-regular);
  --xglass-edge: var(--glass-edge-regular);
  --xglass-highlight: var(--glass-highlight);
  --xglass-radius: var(--radius-lg);
  --xglass-shadow: var(--shadow-glass-regular);
  --xglass-noise-opacity: 0.03;
  --xglass-scrim: transparent;
}

.xglass--thin {
  --xglass-blur: var(--blur-12);
  --xglass-tint: var(--glass-tint-thin);
  --xglass-edge: var(--glass-edge-thin);
  --xglass-shadow: var(--shadow-glass-thin);
  --xglass-noise-opacity: 0.02;
}

.xglass--thick {
  --xglass-blur: var(--blur-32);
  --xglass-tint: var(--glass-tint-thick);
  --xglass-edge: var(--glass-edge-thick);
  --xglass-shadow: var(--shadow-glass-thick);
  --xglass-noise-opacity: 0.04;
}
```

Levels are semantic aliases, not new materials. A fourth level is a sign the
design needs fewer surfaces, not more tokens.

## 4. Light and dark are different materials

Do not derive dark glass by inverting light tokens. Dark glass is denser, uses
its edge for separation, and casts less shadow.

```css
:root,
:root[data-theme="light"] {
  color-scheme: light;

  --surface: oklch(0.99 0.003 250);
  --glass-tint-thin: rgb(255 255 255 / 0.42);
  --glass-tint-regular: rgb(255 255 255 / 0.58);
  --glass-tint-thick: rgb(255 255 255 / 0.72);

  --glass-edge-thin: rgb(255 255 255 / 0.55);
  --glass-edge-regular: rgb(255 255 255 / 0.65);
  --glass-edge-thick: rgb(255 255 255 / 0.75);

  --glass-highlight: rgb(255 255 255 / 0.8);

  --shadow-glass-thin: 0 1px 2px rgb(15 18 24 / 0.08);
  --shadow-glass-regular:
    0 1px 2px rgb(15 18 24 / 0.08),
    0 8px 28px rgb(15 18 24 / 0.12);
  --shadow-glass-thick:
    0 2px 4px rgb(15 18 24 / 0.10),
    0 24px 64px rgb(15 18 24 / 0.22);

  --xglass-text: oklch(0.22 0.02 260);
  --xglass-text-muted: oklch(0.45 0.02 260);
  --xglass-scrim: rgb(255 255 255 / 0.35);
}

:root[data-theme="dark"] {
  color-scheme: dark;

  --surface: oklch(0.17 0.015 260);
  --glass-tint-thin: rgb(22 25 33 / 0.45);
  --glass-tint-regular: rgb(22 25 33 / 0.58);
  --glass-tint-thick: rgb(22 25 33 / 0.72);

  --glass-edge-thin: rgb(255 255 255 / 0.10);
  --glass-edge-regular: rgb(255 255 255 / 0.14);
  --glass-edge-thick: rgb(255 255 255 / 0.18);

  --glass-highlight: rgb(255 255 255 / 0.20);

  --shadow-glass-thin: 0 1px 2px rgb(0 0 0 / 0.25);
  --shadow-glass-regular:
    0 1px 2px rgb(0 0 0 / 0.30),
    0 8px 28px rgb(0 0 0 / 0.35);
  --shadow-glass-thick:
    0 2px 4px rgb(0 0 0 / 0.35),
    0 24px 64px rgb(0 0 0 / 0.50);

  --xglass-text: oklch(0.96 0.01 260);
  --xglass-text-muted: oklch(0.75 0.015 260);
  --xglass-scrim: rgb(10 12 16 / 0.35);
}
```

Observations:

- Text tokens are per-material, because text contrast over glass depends on the
  tint, not only on the theme.
- Dark glass barely uses cast shadow to separate; the highlight and edge do the
  work.
- The scrim is never fully transparent; even 0.2-0.35 gives text a stable base
  on busy backdrops.

`light-dark()` shortens this when a token only flips value and no other logic
changes:

```css
:root {
  color-scheme: light dark;
  --xglass-tint: light-dark(rgb(255 255 255 / 0.58), rgb(22 25 33 / 0.58));
}
```

Support: `light-dark()` is Baseline since May 2024 (Chrome 123, Firefox 120,
Safari 17.5). Safe for 2026 targets.

## 5. Deriving tints at runtime

When the brand color must tint the glass, derive instead of hard-coding:

```css
:root {
  --brand: oklch(0.62 0.17 262);
}

.xglass--brand {
  --xglass-tint: color-mix(in oklab, var(--brand) 18%, transparent);
  --xglass-edge: color-mix(in oklab, var(--brand) 45%, white);
  --xglass-highlight: color-mix(in oklab, white 70%, var(--brand));
}
```

You can also shift an existing tint with relative color syntax:

```css
.xglass--hover {
  --xglass-tint: rgb(from var(--xglass-tint) r g b / calc(alpha + 0.06));
}
```

Support: `color-mix()` Baseline May 2023; relative color syntax Baseline Jul
2024. Both are safe for 2026, but note that variadic `color-mix()` with more
than two colors is newer (Safari 27, Firefox 150; Chrome pending as of Sep
2026) - stick to two-color mixes in shared CSS.

## 6. TypeScript token contract

The canonical tokens live in TypeScript so components, tests, and CSS share one
source. The CSS custom properties remain the runtime channel; TypeScript is the
build-time contract.

```ts
// src/design/tokens.ts
export const glassLevels = ["thin", "regular", "thick"] as const;
export type GlassLevel = (typeof glassLevels)[number];

export type GlassTokenName =
  | "blur"
  | "saturate"
  | "brightness"
  | "tint"
  | "edge"
  | "highlight"
  | "shadow"
  | "radius"
  | "noiseOpacity"
  | "scrim";

export type GlassTokenMap = Record<GlassTokenName, string>;

export const glassTokens: Record<GlassLevel, GlassTokenMap> = {
  thin: {
    blur: "var(--blur-12)",
    saturate: "160%",
    brightness: "1",
    tint: "var(--glass-tint-thin)",
    edge: "var(--glass-edge-thin)",
    highlight: "var(--glass-highlight)",
    shadow: "var(--shadow-glass-thin)",
    radius: "var(--radius-lg)",
    noiseOpacity: "0.02",
    scrim: "transparent",
  },
  regular: {
    blur: "var(--blur-24)",
    saturate: "180%",
    brightness: "1",
    tint: "var(--glass-tint-regular)",
    edge: "var(--glass-edge-regular)",
    highlight: "var(--glass-highlight)",
    shadow: "var(--shadow-glass-regular)",
    radius: "var(--radius-lg)",
    noiseOpacity: "0.03",
    scrim: "transparent",
  },
  thick: {
    blur: "var(--blur-32)",
    saturate: "190%",
    brightness: "1",
    tint: "var(--glass-tint-thick)",
    edge: "var(--glass-edge-thick)",
    highlight: "var(--glass-highlight)",
    shadow: "var(--shadow-glass-thick)",
    radius: "var(--radius-xl)",
    noiseOpacity: "0.04",
    scrim: "var(--xglass-scrim)",
  },
};
```

A small helper keeps inline styles type-safe when a component must set tokens
dynamically (for example a scrim strength from data):

```ts
import type { CSSProperties } from "react";

export function glassStyleVars(
  level: GlassLevel,
  overrides: Partial<GlassTokenMap> = {},
): CSSProperties {
  const tokens = { ...glassTokens[level], ...overrides };
  const vars: Record<string, string> = {};
  for (const [name, value] of Object.entries(tokens)) {
    const kebab = name.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`);
    vars[`--xglass-${kebab}`] = value;
  }
  return vars as CSSProperties;
}
```

Prefer classes over inline vars. Use `glassStyleVars` only for values that
genuinely change at runtime (scrim strength, per-data tint).

## 7. Generation pipeline

One build script emits all consumers from `tokens.ts`:

1. `styles/tokens.css` - the `:root`/`[data-theme]` custom properties.
2. `styles/xglass.css` - the primitive classes.
3. Tailwind `@theme` block (or `tokens.tailwind.css` imported by it).
4. `tokens.json` for docs, Figma sync, and tests.
5. A type-checked manifest so component code cannot reference a token that the
   CSS does not define.

Sketch in plain Node (no dependency required):

```ts
// scripts/build-tokens.ts
import { writeFileSync } from "node:fs";
import { glassTokens } from "../src/design/tokens";

const lines: string[] = [":root {"];
for (const [level, tokens] of Object.entries(glassTokens)) {
  for (const [name, value] of Object.entries(tokens)) {
    const kebab = name.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`);
    lines.push(`  --xglass-${kebab}: ${value};`);
  }
  void level;
}
lines.push("}");
writeFileSync("src/styles/tokens.css", lines.join("\n"));
```

The real pipeline should include the literal light/dark token values (Section
4), not only the semantic aliases, and must be deterministic so CI diffs are
meaningful.

## 8. Tailwind CSS 4 mapping

Tailwind 4 exposes theme values as CSS variables through `@theme`. Map glass
tokens so utilities and custom classes stay in sync:

```css
@import "tailwindcss";

@theme {
  --blur-glass-thin: 12px;
  --blur-glass-regular: 24px;
  --blur-glass-thick: 32px;

  --radius-glass: 16px;

  --color-glass-tint-thin: rgb(255 255 255 / 0.42);
  --color-glass-tint-regular: rgb(255 255 255 / 0.58);
  --color-glass-tint-thick: rgb(255 255 255 / 0.72);
}

/* utilities */
@utility xglass {
  border-radius: var(--radius-glass);
  border: 1px solid var(--glass-edge-regular);
  background: var(--glass-tint-regular);
}

@utility xglass-blur {
  -webkit-backdrop-filter: blur(var(--blur-glass-regular)) saturate(180%);
  backdrop-filter: blur(var(--blur-glass-regular)) saturate(180%);
}
```

Rules:

- Do not use bare `backdrop-blur-*` utilities for glass surfaces; they omit
  saturation and the fallback contract.
- Put the `@supports` guard and preference queries in the design-system layer,
  not in ad-hoc utility chains.
- Arbitrary values (`backdrop-blur-[37px]`) are banned in component code; add a
  token instead.

## 9. Platform overrides

When the app runs inside Tauri with native vibrancy, glass tokens must not add
a second blur (see `./08-tauri-packaging.md`):

```css
:root[data-runtime="tauri"][data-native-glass="active"] .xglass--window {
  -webkit-backdrop-filter: none;
  backdrop-filter: none;
  background: transparent;
  border-color: rgb(255 255 255 / 0.08);
  box-shadow: none;
}
```

The runtime attribute is set once at boot from `isTauri()` plus platform
detection; components stay unaware of the platform.

## 10. Anti-patterns

- Hard-coded blur/alpha values in components.
- Dark theme as inverted light tokens.
- One tint for all levels ("thin" and "thick" with the same alpha).
- Text color defined globally instead of per material.
- Using `rgba()` with a brand color and assuming it is "on brand" without
  compositing checks.
- Adding a token per component instead of per role.
- Shipping tokens only in CSS while TypeScript duplicates strings.
- Forgetting `color-scheme` on the root, which breaks native controls
  (scrollbars, inputs) inside glass surfaces.

## 11. Related

- `./02-css-implementation.md` - the primitive that consumes these tokens.
- `./04-typescript-components.md` - typed components built on this contract.
- `./05-accessibility-and-legibility.md` - contrast math for the tint values.
- `./07-fullstack-architecture.md` - where the generator runs in the pipeline.
