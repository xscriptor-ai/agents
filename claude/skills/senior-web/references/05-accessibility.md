# Accessibility

WCAG 2.2 AA as the floor, semantic HTML first, ARIA patterns, keyboard and focus management, screen
reader behavior, and automated plus manual testing.

## Standards and Legal Baseline

- **WCAG 2.2** (W3C Recommendation since 2023) is the current conformance target. Level **AA** is
  the practical floor; Level **AAA** is selective (often body text contrast 7:1 and enhanced
  target sizes).
- The four principles: **Perceivable, Operable, Understandable, Robust** (POUR).
- WCAG 2.2 additions worth knowing: 2.4.11 Focus Not Obscured (Minimum, AA), 2.4.13 Focus
  Appearance (AAA), 2.5.7 Dragging Movements (AA), 2.5.8 Target Size Minimum 24x24 CSS px (AA),
  3.2.6 Consistent Help (A), 3.3.7 Redundant Entry (A), 3.3.8 Accessible Authentication (Minimum,
  AA).
- **European Accessibility Act** obligations apply to many digital products sold in the EU since
  mid-2025; treat AA conformance as a procurement requirement, not a courtesy. Verify local
  deadlines and exceptions upstream.
- `prefers-reduced-motion` and `prefers-contrast` are expected to be honored regardless of formal
  conformance.

## Semantic HTML First

The native element carries role, states, keyboard behavior, and screen reader semantics for free.
Custom widgets reimplement all of that and usually miss something.

| Need | Use | Not |
|---|---|---|
| Clickable action | `<button type="button">` | `<div onclick>` |
| Navigation link | `<a href>` | `<span role="link">` |
| Sections | `<header> <nav> <main> <aside> <footer>` | `<div class="header">` |
| Modal | `<dialog>` + `showModal()` | custom overlay div |
| Disclosure | `<details>/<summary>` | custom toggle div |
| Progress | `<progress>` | styled div |
| Tooltip-ish help | visible text / `<small>` + `aria-describedby` | hover-only div |
| Form fields | `<label for>` + `<input>` | placeholder-as-label |
| Data tables | `<table>` with `<th scope>` | CSS grid of divs |

```html
<dialog id="confirm" aria-labelledby="confirm-title">
  <h2 id="confirm-title">Delete project?</h2>
  <p>This cannot be undone.</p>
  <form method="dialog">
    <button value="cancel">Cancel</button>
    <button value="confirm">Delete</button>
  </form>
</dialog>
```

Modern HTML gives you free accessibility for popovers (`popover`), dialogs (`<dialog>`), and
disclosures (`<details>`) — prefer them over reinvention.

## Landmarks, Structure, and Headings

- One `<main>` per page; every page has a meaningful `<h1>`.
- Heading levels must not skip when read linearly (h1 to h3 without h2 is a defect).
- Landmarks: `<nav>` for major navigation groups; label multiple navs (`aria-label="Primary"`).
- Use lists (`<ul>/<ol>`) for enumerations; screen readers announce item counts.
- Language: `<html lang="en">`; mark inline language changes with `lang` attributes.
- Page `<title>` is unique and describes the view; SPA route changes update the title and move
  focus.

## ARIA: Use Only What Is Needed

The first rule of ARIA: do not use ARIA if a native element can do it. When it is needed:

- **Roles** — only when semantics are not native (`role="tablist"`, `role="alert"`,
  `role="status"`, `role="tree"`).
- **States/properties** — must be kept in sync with the visual state: `aria-expanded`,
  `aria-selected`, `aria-checked`, `aria-current="page"`, `aria-disabled` vs the `disabled`
  attribute (the latter removes from tab order and can hide text from AT).
- **Names** — `aria-label` for icon-only controls; `aria-labelledby` when visible text exists.
- **Relationships** — `aria-describedby` for help/errors; `aria-controls` for disclosure targets
  (use sparingly and only when it actually helps).
- Never override native roles (`role="button"` on a `<button>`, `role="heading"` on `<h2>`).
- Never put interactive elements inside elements with `role="button"`, or use `aria-hidden` on
  focusable content.

### Live regions

| Need | Markup | Notes |
|---|---|---|
| Polite status update | `role="status"` / `aria-live="polite"` | Toasts, save confirmations |
| Urgent error | `role="alert"` / `aria-live="assertive"` | Use sparingly; interrupts speech |
| Form errors | `aria-describedby` + `aria-invalid` | Focus first invalid field on submit |
| Progress messages | `role="status"` + text | Do not use percentages alone |

Live regions must exist in the DOM before content is inserted (or be toggled carefully); injecting
the whole region with content is unreliable.

### Canonical widget patterns

- **Disclosure**: `<button aria-expanded aria-controls>` + region.
- **Tabs**: `role="tablist"`, `role="tab"` with `aria-selected`, arrow-key navigation, `tabindex`
  roving, `role="tabpanel"` with `aria-labelledby`. Only the active tab is in the tab sequence.
- **Combobox/autocomplete**: `role="combobox"`, `aria-expanded`, `aria-activedescendant` (or
  roving focus) over a listbox; announce result counts via status.
- **Dialog**: `<dialog>` handles focus trapping and Escape. For custom dialogs, trap focus, restore
  focus to the trigger, and mark background inert.
- **Menu**: `role="menu"` is for application menus, not site navigation. Do not use menubar/menu for
  a nav bar; use a list of links.
- **Grid/tree**: follow the WAI-ARIA Authoring Practices; these are the hardest patterns and justify
  a battle-tested library.

When in doubt, copy the WAI-ARIA Authoring Practices example and test with two screen readers.

## Keyboard and Focus Management

- Every interactive element must be reachable and operable by keyboard alone.
- Native controls are focusable and provide activation keys; do not remove them from tab order.
- **Focus visible**: never `outline: none` without a replacement. Use `:focus-visible` for
  keyboard-only rings with sufficient contrast and thickness (WCAG 2.2 focus appearance guidance).
- **Focus not obscured** (2.4.11): sticky headers and cookie bars must not cover the focused
  element; use `scroll-margin-top` and `scroll-padding-top`.
- **Skip link**: first focusable element, visible on focus, targets `<main>`.
- **Roving tabindex** for composite widgets (tabs, toolbars, grids): one tab stop, arrows move
  within.
- **Focus management on navigation**: in SPAs, route changes must move focus (to the `h1` or a
  focusable wrapper) and announce the new page. For dialogs, move focus in on open and restore on
  close.
- **Focus order** must follow visual order; CSS reordering (`order`, `flex-direction: row-reverse`)
  can desynchronize them. Verify.
- Keyboard shortcuts must not conflict with AT and must be remappable or disable-able.

```css
:focus-visible {
  outline: 3px solid var(--color-focus);
  outline-offset: 2px;
}
[id] { scroll-margin-top: 5rem; } /* sticky header clearance */
```

## Color, Contrast, and Perception

| Content | Minimum (AA) | Enhanced (AAA) |
|---|---|---|
| Normal text (< 24 px, or < 18.66 px bold) | 4.5:1 | 7:1 |
| Large text | 3:1 | 4.5:1 |
| UI components and graphical objects | 3:1 | - |
| Focus indicators | 3:1 against adjacent colors (2.4.13 AAA guidance) | - |

- Never encode meaning by color alone (error red plus icon/text; chart lines plus patterns/labels).
- Placeholder text is not a label and must still meet contrast if used.
- Disabled controls are exempt from contrast but should remain recognizable; `aria-disabled` with
  visual dimming often beats the `disabled` attribute.
- Support `prefers-contrast: more` and Windows High Contrast Mode: do not rely on background images
  or `box-shadow` for essential boundaries; use borders.
- Text over images needs an overlay or measured contrast across all viewports; test the extremes.

## Motion, Timing, and Input Modality

- Honor `prefers-reduced-motion: reduce`: remove parallax, auto-play, and large transitions; keep
  essential state changes instantaneous.
- No content may flash more than three times per second (seizure risk).
- Avoid time limits; if unavoidable, allow extension (2.2.1). Session timeouts must warn and allow
  extension.
- Support touch, keyboard, and pointer. Dragging interactions (sliders, sortable lists) need a
  pointer-free alternative (2.5.7) — buttons, menus, or click-to-place.
- Target size: minimum 24x24 CSS px (AA, 2.5.8); aim for 44x44 for primary mobile actions.
- Avoid gesture-only interactions; provide visible controls.

## Screen Readers and Assistive Tech

- Test with real AT, at minimum: **VoiceOver (Safari/macOS + iOS)** and **NVDA (Firefox/Chrome on
  Windows)**. JAWS for enterprise/legal contexts. TalkBack for Android-heavy audiences.
- Screen reader + keyboard is the primary validation for composite widgets; browser accessibility
  tree inspection (DevTools) is a debugging aid, not proof.
- Dynamic content: use live regions deliberately; ensure SPA route changes announce.
- Text expansions: abbreviations with `<abbr>`, expanded acronyms on first use.
- Zoom/reflow: 200% browser zoom without loss of content or function; 400% with reflow to a single
  column (WCAG 1.4.10) requires no horizontal scrolling except for two-dimensional content.
- Text spacing overrides (line height 1.5x, letter spacing 0.12em) must not clip content.

## Testing

### Automated (necessary, not sufficient)

- **axe-core** via browser extension, `@axe-core/playwright`, or CI integration: catches ~30-40% of
  issues (missing labels, contrast, landmark structure, ARIA misuse).
- **Lighthouse/Pa11y** in CI as a gate for regressions on audited routes.
- **ESLint jsx-a11y** (or framework equivalents) at author time.
- Treat automated results as a triage list; false positives and false negatives are both common.

### Manual (where most defects hide)

1. **Keyboard-only pass** — unplug the mouse; complete every task; verify focus order, visibility,
   dialogs, and escape paths.
2. **Screen reader pass** — one desktop, one mobile; complete the same tasks; verify names, states,
   announcements.
3. **Zoom/reflow** — 200% and 400%, narrow viewport.
4. **Contrast** — automated scan plus manual checks for states (hover, disabled, focus, dark theme).
5. **Forms** — labels, error identification, error suggestion, autocomplete attributes
   (`autocomplete="email"`, `current-password`, `one-time-code`), redundant entry (3.3.7).
6. **Auth flows** — accessible authentication (3.3.8): allow paste, avoid cognitive tests, support
   password managers and passkeys.

### CI approach

- Run axe on every route in a Playwright suite; fail on new violations.
- Keep a documented allowlist for known false positives; review it quarterly.
- Add component-level a11y tests for the design system; fixing there fixes everywhere.

## Anti-Patterns

- `div`/`span` click handlers without role, tabindex, and key handling.
- `outline: none` with no replacement.
- Placeholder used as the only label.
- `aria-hidden="true"` on focusable or content-bearing elements.
- Focus traps without escape; modals that restore focus to the wrong place.
- Hover-only menus; drag-only controls.
- Toast messages that vanish before they can be read; status updates with no live region.
- Auto-playing carousels/videos; motion without a reduced-motion path.
- Fixing automated audit findings while the keyboard experience remains broken.

## Checklist

- [ ] Semantic elements used; ARIA only where native is insufficient.
- [ ] Every flow completable by keyboard; focus visible and never obscured.
- [ ] Focus managed on route change and dialog open/close; skip link present.
- [ ] Text and UI contrast verified in all themes and states.
- [ ] Forms: labels, errors, suggestions, autocomplete, no redundant entry.
- [ ] Reduced motion and contrast preferences honored.
- [ ] axe in CI plus documented manual SR and keyboard passes.
