# DevX Platform Mapping

This document explains where DevX-related files should live.

It is intentionally future-oriented. The current repository already follows part of this structure, but AI agents should use this mapping as the preferred target when adding or refactoring DevX UI.

## 1. Mapping Principle

Group files by responsibility, not by convenience.

The main separation is:

- route composition
- route-local UI
- reusable UI
- structured data
- shared types
- hooks and helpers
- static assets

Do not let `page.tsx` become the place where everything accumulates.

## 2. Preferred Future Structure

```text
src/
  app/
    resources/
      page.tsx
      vscode/
        page.tsx
        vscode.module.css
        _components/
          VscodePageHeader.tsx
          VscodeHero.tsx
        _lib/
          getInitialTheme.ts
        references.md
    components/
      xcomponents/
        repo-card/
          RepoCard.tsx
          RepoCard.module.css
          index.ts
        icons/
          VscodeIcon.tsx
          icons.types.ts
          index.ts
        vscode-theme-gallery/
          VscodeThemeGallery.tsx
          VscodeThemeGallery.module.css
          ThemeSelector.tsx
          ThemePalette.tsx
          VscodeEditorPreview.tsx
          VscodeIntroMedia.tsx
          index.ts
        xglass-showcase/
          XglassShowcase.tsx
          XglassShowcase.module.css
          index.ts
        vscode-resource-sections/
          VscodeResourceSections.tsx
          VscodeResourceSections.module.css
          index.ts
  data/
    resources/
      resources.data.ts
      vscode/
        vscodeThemes.data.ts
        xglass.data.ts
  types/
    resources/
      resources.types.ts
      vscode.types.ts
  lib/
    resources/
      vscode/
        preview.utils.ts
        theme.utils.ts
  hooks/
    resources/
      useThemeSelector.ts
      useSectionReveal.ts
```

This structure does not mean every folder must exist today. It means future additions should move toward this separation instead of increasing file mixing.

## 3. What Belongs In Each Area

### 3.1 `app/.../page.tsx`

Use route files to:

- compose the page
- import prepared data
- assemble major sections
- connect route-level metadata and layout

Do not use route files to:

- hold long data arrays
- define large reusable components
- keep theme preset maps
- accumulate helper functions unrelated to route composition

### 3.2 `app/.../<route>.module.css`

Use route CSS modules for:

- page spacing
- route header styling
- outer layout constraints
- route-only wrappers

Do not style deep reusable widgets here if those widgets already have their own folder.

### 3.3 `app/.../_components/`

This is the preferred place for route-local components that are not reusable outside one route.

Examples:

- a route-only header block
- a route-only hero wrapper
- a route-only layout shell

Rules:

- if the component is specific to one route, keep it near the route
- if later reused elsewhere, promote it to `xcomponents`

### 3.4 `components/xcomponents/`

This folder is for reusable or semi-reusable UI blocks.

A component belongs here when at least one of these is true:

- it can be reused by another route
- it expresses a product-level UI pattern
- it has a self-contained API
- it owns meaningful internal styling and behavior

Examples:

- `RepoCard`
- `VscodeThemeGallery`
- `XglassShowcase`
- shared icon components

### 3.5 `data/`

Put serializable structured content here.

This includes:

- card definitions
- theme lists
- palette metadata
- preview preset data
- CTA link definitions
- product showcase slides

Rules:

- prefer plain objects and arrays
- keep data inspectable
- avoid storing JSX in data unless the project has a strong reason
- keep route/domain grouping explicit

Good examples:

- `src/data/resources/resources.data.ts`
- `src/data/resources/vscode/vscodeThemes.data.ts`

### 3.6 `types/`

Put shared domain contracts here.

A type belongs in `types/` when it is used across:

- route files
- data files
- reusable components
- helper functions

Examples:

- `ResourceRepo`
- `VscodeTheme`
- preview-related domain contracts

Do not move every local prop type into `types/`.

Keep local-only prop interfaces next to the component when they are not reused.

### 3.7 `lib/`

Use `lib/` for pure helpers and transformation logic.

Examples:

- preview token derivation
- theme lookup helpers
- URL normalization
- serialization-safe formatters

Rules:

- keep helpers pure when possible
- avoid mixing React rendering with `lib/`
- if the logic depends on hooks or component lifecycle, it does not belong here

### 3.8 `hooks/`

Use `hooks/` for shared React state behavior.

Examples:

- keyboard-driven selector logic
- section visibility / intersection observer logic
- reduced-motion helpers

Rules:

- only extract a hook when the behavior is meaningful or reused
- do not create hooks just to move a few lines out of a component

## 4. File Placement Rules By Artifact

Use this decision guide when creating a new file.

### 4.1 Data

If the artifact is:

- serializable
- content-like
- theme metadata
- configuration for rendering

Place it in `data/`.

### 4.2 Types

If the artifact is:

- a shared interface
- a shared type alias
- a contract used by data plus UI

Place it in `types/`.

### 4.3 Local Prop Types

If the type is used only by one component or one folder:

- keep it next to the component
- or keep it inline when it stays small and readable

Do not globalize local implementation details.

### 4.4 Reusable Components

If the artifact is:

- a UI block reused or likely to be reused
- independently styled
- prop-driven

Place it in `components/xcomponents/`.

### 4.5 Route-Only Components

If the artifact is:

- tightly coupled to a single route
- not expected to be reused
- mostly compositional

Place it in that route's `_components/`.

## 5. Domain Grouping Strategy

Prefer grouping by domain first, then by artifact.

Good:

```text
data/
  resources/
    vscode/
      vscodeThemes.data.ts
```

Also good:

```text
types/
  resources/
    vscode.types.ts
```

Avoid flat growth like:

```text
data/
  a.ts
  b.ts
  c.ts
  d.ts
```

when the project already has clear domains.

## 6. Current vs Ideal Model

The current codebase already uses:

- `src/data/...`
- `src/types/...`
- `src/app/components/xcomponents/...`

That is a solid base.

The future improvement is not to undo that structure, but to refine it further:

- keep route-only pieces near the route
- keep reusable pieces in `xcomponents`
- keep data and types domain-grouped
- keep helpers and hooks out of `page.tsx`

## 7. Anti-Patterns

Avoid these placements:

- large arrays inside `page.tsx`
- route-specific helper logic inside reusable component folders
- shared domain types hidden inside one component folder
- deeply reusable icons stored inside a route directory
- one CSS module styling multiple unrelated widgets
- data files exporting JSX-heavy structures when plain data would work

## 8. AI Agent Checklist

Before adding a new file, decide:

1. is this composition, UI, data, type, hook, or utility?
2. is it route-local or reusable?
3. is it serializable or render-specific?
4. is the type shared across files or only local?
5. will this placement still make sense after the feature grows?

If the answer points to future reuse or shared ownership, avoid placing it in the route file by default.

The goal is a structure that remains readable after expansion, not only one that feels fast in the moment.
