# 04 - TypeScript components

How to expose glass as typed, composable components instead of scattering CSS
classes through the app. Framework-agnostic core with concrete recipes for
React 19, Vue 3, Svelte 5, and vanilla/Web Components.

## 1. Principles

1. **One primitive, many skins.** A single `GlassSurface` owns the five layers;
   features compose it instead of re-declaring blur.
2. **Typed variants.** Variants (`thin | regular | thick`, `tone`, `as`) are
   union types, not free-form strings.
3. **CSS custom properties cross the boundary.** Components set `--xglass-*`
   vars; they never write `backdrop-filter` inline.
4. **Polymorphism without loss.** `as` allows semantic elements (`nav`, `aside`,
   `dialog`, `li`) while keeping props typed.
5. **Accessibility is part of the API.** Components that can host text require
   a contrast-level contract; components that animate respect
   `prefers-reduced-motion`.
6. **No component knows about Tauri.** Platform adaptation is a data attribute
   on the root plus CSS (see `./03-design-tokens-and-theming.md`, Section 9).

## 2. The core component

### React 19

React 19 passes `ref` as a normal prop, so no `forwardRef` is needed.

```tsx
import type { ComponentPropsWithoutRef, ElementType, ReactNode } from "react";

export type GlassLevel = "thin" | "regular" | "thick";
export type GlassTone = "neutral" | "brand" | "danger";

type GlassSurfaceOwnProps<E extends ElementType> = {
  as?: E;
  level?: GlassLevel;
  tone?: GlassTone;
  scrim?: boolean;
  children?: ReactNode;
};

export type GlassSurfaceProps<E extends ElementType> =
  GlassSurfaceOwnProps<E> &
    Omit<ComponentPropsWithoutRef<E>, keyof GlassSurfaceOwnProps<E>>;

export function GlassSurface<E extends ElementType = "div">({
  as,
  level = "regular",
  tone = "neutral",
  scrim = false,
  className,
  children,
  ...rest
}: GlassSurfaceProps<E>) {
  const Component = (as ?? "div") as ElementType;
  const classes = [
    "xglass",
    `xglass--${level}`,
    tone !== "neutral" ? `xglass--${tone}` : "",
    scrim ? "xglass--scrim" : "",
    className ?? "",
  ]
    .filter(Boolean)
    .join(" ");

  return (
    <Component className={classes} {...rest}>
      {children}
    </Component>
  );
}
```

Usage:

```tsx
<GlassSurface as="nav" level="thin" aria-label="Main">
  <NavItems />
</GlassSurface>

<GlassSurface as="section" level="thick" scrim>
  <h2>Settings</h2>
</GlassSurface>
```

### Vue 3

```vue
<script setup lang="ts">
import { computed } from "vue";

const props = withDefaults(
  defineProps<{
    as?: string;
    level?: "thin" | "regular" | "thick";
    tone?: "neutral" | "brand" | "danger";
    scrim?: boolean;
  }>(),
  { as: "div", level: "regular", tone: "neutral", scrim: false },
);

const classes = computed(() => [
  "xglass",
  `xglass--${props.level}`,
  props.tone !== "neutral" ? `xglass--${props.tone}` : "",
  props.scrim ? "xglass--scrim" : "",
]);
</script>

<template>
  <component :is="as" :class="classes">
    <slot />
  </component>
</template>
```

### Svelte 5

```svelte
<script lang="ts">
  type GlassLevel = "thin" | "regular" | "thick";
  let {
    level = "regular",
    tone = "neutral",
    scrim = false,
    children,
  }: {
    level?: GlassLevel;
    tone?: "neutral" | "brand" | "danger";
    scrim?: boolean;
    children?: import("svelte").Snippet;
  } = $props();
</script>

<div class="xglass xglass--{level} {scrim ? 'xglass--scrim' : ''}">
  {@render children?.()}
</div>
```

### Vanilla / Web Components

For embedded widgets or a framework-free design system, a custom element with
`adoptedStyleSheets` keeps the contract:

```ts
export class XGlassElement extends HTMLElement {
  static observedAttributes = ["level", "tone"] as const;

  #root: ShadowRoot;

  constructor() {
    super();
    this.#root = this.attachShadow({ mode: "open" });
    const sheet = new CSSStyleSheet();
    sheet.replaceSync(
      ":host { display: block; } :host([level='thin']) { --xglass-blur: var(--blur-12); }",
    );
    this.#root.adoptedStyleSheets = [sheet];
  }

  connectedCallback() {
    if (!this.#root.querySelector("slot")) {
      this.#root.append(document.createElement("slot"));
    }
    this.setAttribute("class", "xglass");
  }
}

customElements.define("x-glass", XGlassElement);
```

The host page still provides `--xglass-*` tokens; the element only maps level
names to tokens.

## 3. Component recipes

Each recipe lists only what is specific to glass. Layout, data fetching, and
business logic follow the app's normal conventions.

### 3.1 Sticky glass header

```tsx
<GlassSurface as="header" level="thin" className="xglass-header">
  <Brand />
  <Nav />
</GlassSurface>
```

Component-specific CSS contract:

- The blurred layer is a child (`.xglass-header__backdrop`) so the nearby-pixel
  extension and pointer-events rules from `./02-css-implementation.md` apply.
- `scroll-padding-top: var(--header-height)` is set on the scrolling container
  so anchor navigation is not hidden under the bar (WCAG 2.4.11, see
  `./05-accessibility-and-legibility.md`).
- The header reserves its exact block size (`block-size` or `min-height`) to
  avoid layout shift when content changes.

### 3.2 Card

```tsx
<GlassSurface level="regular" className="xglass-card">
  <img src={cover} alt="" className="xglass-card__media" />
  <div className="xglass-card__body">
    <h3>{title}</h3>
    <p>{summary}</p>
  </div>
</GlassSurface>
```

Rules: media inside a card is not blurred by the card's own backdrop filter
(children paint after the filter). If the image must appear behind frost, it
has to be the page background, not a child.

### 3.3 Modal dialog

Use the native `<dialog>` element; it handles focus trapping, Escape, and the
top layer. Style `::backdrop` as the scrim rather than a separate overlay div.

```css
dialog.xglass-dialog {
  border: none;
  padding: 0;
  background: transparent;   /* the GlassSurface child paints the glass */
}

dialog.xglass-dialog::backdrop {
  background: var(--xglass-scrim, rgb(10 12 16 / 0.45));
  -webkit-backdrop-filter: blur(4px);
  backdrop-filter: blur(4px);
}
```

```tsx
function SettingsDialog({ open }: { open: boolean }) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    if (open && !dialog.open) dialog.showModal();
    if (!open && dialog.open) dialog.close();
  }, [open]);

  return (
    <dialog ref={ref} className="xglass-dialog" aria-labelledby="settings-title">
      <GlassSurface level="thick" scrim>
        <h2 id="settings-title">Settings</h2>
        {/* content */}
      </GlassSurface>
    </dialog>
  );
}
```

Notes:

- `::backdrop` sits in the top layer; it blurs the page behind without
  competing with the dialog's own glass (still two backdrop passes; acceptable
  because a modal is exclusive).
- Do not put `backdrop-filter` on the `<dialog>` itself and on a child; choose
  one (prefer `::backdrop` for the scrim and the child for the pane).
- Keep a solid fallback: if `::backdrop` blur is unsupported, the scrim color
  alone is already readable.

### 3.4 Popover and menus

Prefer the Popover API plus CSS anchor positioning when available; fall back to
a JavaScript positioning library when the target browsers do not ship anchor
positioning.

```tsx
<>
  <button popoverTarget="user-menu" aria-haspopup="menu" aria-expanded={open}>
    Account
  </button>
  <GlassSurface as="div" level="regular" popover="auto" id="user-menu">
    <Menu />
  </GlassSurface>
</>
```

Support notes (2026): the Popover API is Baseline; CSS anchor positioning
shipped in Chromium 125+ and Safari 26, and is still settling in Firefox -
verify before dropping the JS fallback. A popover over glass must not itself be
glass if it overlaps a glass parent; use an opaque translucent fill (no second
blur).

### 3.5 Sheet / drawer

```tsx
<div className="xglass-sheet" data-state={open ? "open" : "closed"}>
  <GlassSurface level="thick" scrim className="xglass-sheet__panel">
    <SheetContent />
  </GlassSurface>
</div>
```

Motion contract:

- Animate only `opacity` and `transform` on the panel.
- The scrim animates opacity.
- Under `prefers-reduced-motion: reduce`, replace the slide with an instant
  state change (or a short fade).
- Never animate `backdrop-filter`; the blur is static while the panel moves.

### 3.6 Glass button

```tsx
<button className="xglass xglass--control xglass--thin">Save</button>
```

Glass buttons are small surfaces; keep tint high (0.12-0.2) and blur low
(8-12px). States:

```css
.xglass--control {
  transition:
    background-color var(--xglass-transition),
    transform var(--xglass-transition),
    box-shadow var(--xglass-transition);
}

.xglass--control:hover {
  background: color-mix(in oklab, var(--xglass-tint) 80%, white 20%);
}

.xglass--control:active {
  transform: translateY(1px) scale(0.99);
}

.xglass--control:disabled {
  opacity: 0.55;
  -webkit-backdrop-filter: none;
  backdrop-filter: none;
  background: var(--surface);
}
```

Disabled glass disables the blur: it is a performance and honesty win (a
disabled control should not advertise depth).

### 3.7 Input on glass

Inputs need opacity for text and caret contrast:

```css
.xglass-input {
  background: color-mix(in oklab, var(--xglass-tint) 70%, var(--surface) 30%);
  border: 1px solid var(--xglass-edge);
  color: var(--xglass-text);
  caret-color: currentColor;
}

.xglass-input::placeholder {
  color: color-mix(in oklab, var(--xglass-text-muted) 70%, transparent);
}
```

Never make an input fully transparent over imagery: the caret and selection
become invisible.

### 3.8 Toast and command palette

- Toasts: `thin` glass, high tint (0.7+), positioned in a safe area, no
  `backdrop-filter` animation; enter/exit with `transform` + `opacity`.
- Command palette: `thick` glass, scrim behind, native `<dialog>` for focus
  management, results list with a non-blurred inner container. This is the
  highest-value glass surface in an app and the one worth spending render
  budget on.

## 4. Focus and keyboard behavior

- **Focus visible**: style `:focus-visible` with an outline in a color that
  survives the glass (use `--xglass-text` or a high-contrast ring token). A
  blurred backdrop does not blur the focused element's own outline, but a
  sticky glass bar can cover it (WCAG 2.4.11).
- **Focus not obscured**: when a glass overlay opens, move focus into it; when
  it closes, restore focus to the trigger. Use the native `<dialog>`/popover
  machinery first.
- **Inert background**: for custom overlays, set `inert` on the app root while
  the overlay is open instead of relying on a click-catching scrim.
- **Escape and scroll lock**: overlays close on Escape; scroll lock must not
  shift layout (compensate scrollbar width) or the glass will jump.

## 5. Tauri-specific component behavior

When the app runs in Tauri (see `./08-tauri-packaging.md`):

- Add `data-tauri-drag-region` to the glass titlebar element itself, not to its
  children. Buttons and inputs inside must remain clickable, which the Tauri
  implementation guarantees by not inheriting the attribute.
- On Windows, also declare the CSS `app-region: drag` rule for touch and pen
  input:

```css
[data-tauri-drag-region] {
  app-region: drag;
  user-select: none;
}

[data-tauri-drag-region] button,
[data-tauri-drag-region] input,
[data-tauri-drag-region] a {
  app-region: no-drag;
}
```

- On macOS, add `-webkit-user-select: none` and `-webkit-touch-callout: none`
  to chrome surfaces to avoid text selection and link callouts on what is
  supposed to feel like native chrome.
- Double-click on the drag region should `toggleMaximize()`; Tauri handles this
  by default for `data-tauri-drag-region`.

## 6. Testing hooks

- `data-glass-level`, `data-glass-tone` attributes on every surface: used by
  visual regression tests and by audit scripts that enumerate glass surfaces.
- A render test per level asserting the primitive class combination
  (`xglass xglass--regular`) protects against accidental variant drift.
- A Playwright visual test that screenshots each surface over a light, a dark,
  and a busy backdrop fixture (see `./07-fullstack-architecture.md`).

## 7. Anti-patterns

- A `GlassCard`, `GlassModal`, `GlassNav` each re-declaring blur values.
- Inline `style={{ backdropFilter: "blur(20px)" }}` anywhere.
- Wrapping every layout container in `GlassSurface` "for consistency".
- Making the glass component own content padding, radius, and layout; those
  belong to the feature, the material only owns the surface.
- Using `<div>` for interactive glass when `<button>`, `<a>`, or `<dialog>`
  fits.
- Ignoring `prefers-reduced-transparency` in component CSS because "the theme
  handles it"; the theme sets tokens, the component must consume the fallback.

## 8. Related

- `./02-css-implementation.md` - the primitive these components render.
- `./03-design-tokens-and-theming.md` - token contract consumed here.
- `./05-accessibility-and-legibility.md` - focus and contrast rules.
- `./08-tauri-packaging.md` - runtime detection and native effects.
