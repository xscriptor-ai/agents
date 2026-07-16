# DevX Tokens

This document defines the preferred token model for the DevX UI system.

It is intentionally future-facing. Some of these tokens are already reflected in the current implementation, while others describe the structure that AI agents should preserve or move toward in future refactors.

## 1. Token Layers

DevX uses three token layers:

1. app-level theme tokens
2. DevX semantic UI tokens
3. component-local preview tokens

Keep these layers separate.

### 1.1 App-Level Theme Tokens

These come from the project theme and must drive page chrome first:

- `--background`
- `--foreground`
- `--primary`
- `--text-muted`
- `--border`
- `--card-bg`

Use them for:

- page backgrounds
- route headers
- section framing
- separators
- default buttons
- default text

Do not replace these with hardcoded colors in route UI unless the component is simulating a product preview.

### 1.2 DevX Semantic UI Tokens

When DevX grows, prefer introducing semantic aliases instead of repeating raw project tokens everywhere.

Examples:

- `--devx-page-bg`
- `--devx-page-fg`
- `--devx-accent`
- `--devx-muted`
- `--devx-line`
- `--devx-surface`
- `--devx-surface-strong`
- `--devx-action-bg`
- `--devx-action-fg`

Recommended mapping:

```css
:root {
  --devx-page-bg: var(--background);
  --devx-page-fg: var(--foreground);
  --devx-accent: var(--primary);
  --devx-muted: var(--text-muted);
  --devx-line: var(--border);
  --devx-surface: var(--card-bg);
  --devx-surface-strong: color-mix(in srgb, var(--card-bg) 72%, var(--background));
  --devx-action-bg: var(--primary);
  --devx-action-fg: var(--background);
}
```

These semantic aliases are optional today, but they are the preferred future model if DevX expands beyond one page.

### 1.3 Component-Local Preview Tokens

Preview components may define local custom properties when they simulate a product UI, such as a VS Code window.

Examples:

- `--preview-editor-bg`
- `--preview-editor-chrome`
- `--preview-sidebar-bg`
- `--preview-panel-bg`
- `--preview-status-bg`
- `--preview-status-fg`
- `--preview-terminal-bg`
- `--preview-terminal-header`

Rules:

- local preview tokens belong inside the preview component
- they must not become page-level styling defaults
- they may be derived from theme data files
- they may change per showcased product theme

## 2. Color Roles

DevX should feel technical, minimal, and low-noise.

### 2.1 Primary Roles

- **background**: main page surface
- **foreground**: main readable text
- **muted**: supporting descriptions and metadata
- **accent**: active underline, key CTA, focused state
- **line**: dividers, section separators, subtle technical framing
- **surface**: optional distinct blocks when a visual grouping is needed

### 2.2 Usage Rules

- use accent color to indicate state, not decoration
- prefer one active signal over multiple competing highlights
- rely on spacing before adding extra borders
- keep large surfaces visually flat
- avoid shadow-heavy elevation

## 3. Typography Tokens

DevX inherits the project font stack. Do not introduce a new font system unless explicitly requested.

Recommended semantic typography tokens:

```css
:root {
  --devx-text-page-title: clamp(2.2rem, 4vw, 3.6rem);
  --devx-text-section-title: clamp(1.35rem, 2vw, 1.9rem);
  --devx-text-body: 1rem;
  --devx-text-body-sm: 0.9375rem;
  --devx-text-meta: 0.8125rem;
  --devx-text-label: 0.75rem;
}
```

### 3.1 Typography Rules

- page titles must match the scale strategy of other resource pages
- section titles should be strong but restrained
- labels should be compact and quiet
- long descriptions should usually stay within `56ch` to `68ch`
- avoid forced uppercase for user-facing interface labels

## 4. Spacing Scale

Use a restrained spacing rhythm.

Recommended scale:

```css
:root {
  --devx-space-2xs: 0.25rem;
  --devx-space-xs: 0.5rem;
  --devx-space-sm: 0.75rem;
  --devx-space-md: 1rem;
  --devx-space-lg: 1.5rem;
  --devx-space-xl: 2rem;
  --devx-space-2xl: 3rem;
  --devx-space-3xl: 4.5rem;
}
```

Suggested usage:

- `2xs` to `xs`: micro gaps, icon alignment, token chips
- `sm` to `md`: standard inner padding and control spacing
- `lg` to `xl`: section-internal grouping
- `2xl` and above: major page separation

## 5. Sizing Tokens

DevX should favor layout clarity over decorative scaling.

Recommended future tokens:

```css
:root {
  --devx-content-max-width: 84rem;
  --devx-copy-max-width: 68ch;
  --devx-preview-min-height: 26rem;
  --devx-slider-min-height: 28rem;
  --devx-control-height: 2.75rem;
  --devx-action-height: 2.875rem;
}
```

Rules:

- keep copy width readable
- let media be large, but still overflow-safe
- increase media height with `min-height`, not with unsafe fixed widths
- preserve `min-width: 0` on shrinkable layout children

## 6. Borders, Radius, and Surfaces

DevX is not a card-heavy language.

Recommended tokens:

```css
:root {
  --devx-radius-none: 0;
  --devx-radius-soft: 0.75rem;
  --devx-border-width: 1px;
}
```

Rules:

- default to `--devx-radius-none` for technical UI
- use soft radius only for media, video, or image treatments when requested
- prefer single structural lines over fully boxed stacks
- use surfaces only when grouping materially improves comprehension

## 7. Motion Tokens

Motion should be subtle and structural.

Recommended tokens:

```css
:root {
  --devx-motion-fast: 160ms;
  --devx-motion-base: 240ms;
  --devx-motion-slow: 420ms;
  --devx-ease-standard: ease;
  --devx-ease-exit: ease-out;
}
```

Rules:

- use motion for reveal, dim, active-state transition, and mode switching
- avoid bounce, elastic, or decorative looping motion in page chrome
- respect `prefers-reduced-motion`
- use CSS transitions first for simple state changes

## 8. Token Naming Conventions

Use names that communicate role instead of appearance.

Prefer:

- `--devx-action-bg`
- `--devx-line`
- `--preview-status-bg`

Avoid:

- `--yellow-1`
- `--dark-border-2`
- `--button-blue`

### 8.1 Prefix Rules

- use `--devx-*` for page/system-level tokens
- use `--preview-*` for component-local simulated UI tokens
- reuse project tokens directly when no semantic alias is needed

## 9. Token Ownership

This is the preferred future ownership model:

- global theme tokens live in the app theme layer
- DevX semantic aliases live in a DevX-specific shared stylesheet if the system expands
- component-local preview tokens live inside the relevant component module or component root
- theme-specific preview values come from `src/data/...`, not from route files

### 9.1 Future File Placement

If DevX becomes a broader system, the preferred future token placement is:

```text
src/
  styles/
    tokens/
      theme.css
      devx.css
```

If DevX remains route-scoped, keep semantic aliases local and minimal instead of creating an unnecessary global layer.

## 10. AI Agent Guidance

Before introducing a new token, ask:

1. is this already covered by the project theme?
2. is this a DevX semantic role reused across sections?
3. is this only needed inside one preview component?

Choose the narrowest correct scope.

- if the token is global, keep it global
- if it belongs to DevX UI chrome, use a `--devx-*` semantic token
- if it only styles one simulated product window, keep it local to that component

The goal is not to create more tokens. The goal is to create a cleaner token hierarchy.
