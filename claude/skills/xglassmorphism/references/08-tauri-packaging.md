# 08 - Tauri packaging

How to ship the same TypeScript + CSS glass app as a desktop app with Tauri 2.x,
when to use native window vibrancy instead of CSS `backdrop-filter`, and how to
keep both from stacking.

Scope: Tauri stable 2.x (2.12 shipped 2026-09-26; MSRV Rust 1.90; Windows 7
dropped), `@tauri-apps/api` 2.12.x, `window-vibrancy` 0.8.1 (first-party,
published 2026-09-22). The crate is being reorganized toward a
`tauri-plugin-vibrancy` name; verify the import path when upgrading.

## 1. The one rule that prevents most bugs

**`backdrop-filter` blurs only what the webview paints. It cannot blur the
desktop, the wallpaper, or native window vibrancy composited by the OS behind a
transparent webview.**

Consequences:

- A transparent Tauri window whose page has `background: transparent` and a
  CSS glass panel over empty space: the CSS blur has nothing to sample. The
  desktop shows through untinted; the "glass" is just a translucent border.
- Native vibrancy behind the window + CSS blur on a panel over in-page content:
  working combination (the panel blurs page content, not the desktop).
- Native vibrancy + CSS blur over the same pixels: double blur, wasted GPU,
  muddy result.

Choose one layer to own the window, one to own the content:

| Layer | Owns | Technology |
|-------|------|------------|
| Window chrome (titlebar, sidebar, whole background) | desktop/wallpaper depth | native: `windowEffects` / `window-vibrancy` |
| In-page floating surfaces (cards, popovers, panels over app content) | in-page content depth | CSS `backdrop-filter` |
| Full-screen scrims (modals) | page content | CSS (native vibrancy is the window, not the scrim) |

## 2. Native effects by platform

`window-vibrancy` (Rust) is the direct API; Tauri `windowEffects` config and
`setEffects` are the integrated path.

| Function | Platform | Notes |
|----------|----------|-------|
| `apply_vibrancy` / `clear_vibrancy` | macOS 10.10+ | Takes an `NSVisualEffectMaterial`, optional state, optional radius |
| `apply_liquid_glass` / `clear_liquid_glass` | macOS 26+ | `LiquidGlassOptions` with style Clear/Regular, radius, opaque, interactive (interactive is macOS 27+) |
| `apply_mica` / `clear_mica` | Windows 11 | Preferred on Win11, cheapest native effect |
| `apply_acrylic` / `clear_acrylic` | Windows 10 (1903+) / 11 | GPU-heavy; drag/resize lag on Win10 1903+ and Win11 22000 |
| `apply_blur` / `clear_blur` | Windows 7/10/11 (22H1) | Poor performance on Win11 22621+; prefer mica |
| Tabbed | Windows 11 | Available through Tauri's `Effect` enum, not as a crate function |
| Linux | - | Not supported; no first-party API. Compositor rules (KWin, Hyprland) are user-side |
| macOS 26 Liquid Glass | macOS 26+ | `liquidGlassRegular` / `liquidGlassClear`; Clear requires a dimming layer |

macOS materials (valid `Effect` values): `appearanceBased`, `light`, `dark`,
`mediumLight`, `ultraDark` (deprecated since 10.14), `titlebar`, `selection`,
`menu`, `popover`, `sidebar`, `headerView`, `sheet`, `windowBackground`,
`hudWindow`, `fullScreenUI`, `tooltip`, `contentBackground`,
`underWindowBackground`, `underPageBackground`, `liquidGlassRegular`,
`liquidGlassClear`. Practical picks: `underWindowBackground` for app windows,
`sidebar` for sidebars, `hudWindow` for floating tools.

States: `active`, `inactive`, `followsWindowActiveState` (macOS; ignored for
Liquid Glass). Radius is macOS-only. Color applies to Windows 10 1903+
Blur/Acrylic and macOS Liquid Glass.

## 3. `tauri.conf.json`

```json
{
  "app": {
    "macOSPrivateApi": true,
    "windows": [
      {
        "label": "main",
        "transparent": true,
        "decorations": true,
        "titleBarStyle": "Overlay",
        "hiddenTitle": true,
        "trafficLightPosition": { "x": 16, "y": 16 },
        "windowEffects": {
          "effects": ["underWindowBackground"],
          "state": "followsWindowActiveState",
          "radius": 12
        }
      }
    ]
  }
}
```

Field notes:

- `windowEffects` requires `transparent: true` and is **unsupported on Linux**.
- `macOSPrivateApi: true` is required for `transparent` on macOS. It uses
  private APIs: **the app is not App Store-eligible**. If App Store
  distribution matters, use `windowEffects` on a normal (non-transparent)
  window, which relies on public APIs.
- `titleBarStyle`: `"Visible" | "Transparent" | "Overlay"`. `Overlay` puts the
  traffic lights over your content and requires a custom drag region; dragging
  is disabled while the window is unfocused (tauri#4316).
- `hiddenTitle` and `trafficLightPosition` are macOS-specific;
  `trafficLightPosition` requires `Overlay` + `decorations: true`.
- Windows: `transparent: true` can flash white on creation;
  `"noRedirectionBitmap": true` mitigates it. With decorations, Windows 11
  rounds corners automatically; for borderless rounded windows call
  `DwmSetWindowAttribute(DWMWA_WINDOW_CORNER_PREFERENCE)` yourself (no Tauri
  config field; DIY).

## 4. Runtime APIs

### JavaScript

```ts
import { getCurrentWindow, Effect, EffectState } from "@tauri-apps/api/window";

await getCurrentWindow().setEffects({
  effects: [
    Effect.UnderWindowBackground, // macOS + fallback
    Effect.Mica,                  // Windows 11
    Effect.Acrylic,               // Windows 10 fallback
  ],
  state: EffectState.Active,
  radius: 8,
});

await getCurrentWindow().clearEffects();
```

The first supported effect wins. On macOS you can list a Liquid Glass style
plus a material fallback for macOS 15 and older in the same array.

### Capabilities

`setEffects` and `clearEffects` need `core:window:allow-set-effects`, which is
not included in `core:window:default`:

```json
{
  "identifier": "main-capability",
  "windows": ["main"],
  "permissions": [
    "core:window:default",
    "core:window:allow-set-effects",
    "core:window:allow-start-dragging"
  ]
}
```

Grant only what the app uses; window effects do not justify broad permissions.

### Rust

```rust
use tauri::utils::config::{WindowEffect, WindowEffectState, WindowEffectsConfig};

let effects = WindowEffectsConfig {
    effects: vec![WindowEffect::Mica, WindowEffect::UnderWindowBackground],
    state: Some(WindowEffectState::Active),
    radius: Some(8.0),
    color: None,
};
window.set_effects(Some(effects))?;
```

Verify exact field names against docs.rs for your Tauri minor; the effects
config has evolved between 2.x minors.

## 5. CSS inside the Tauri webview

Engine map:

| Platform | Webview | `backdrop-filter` |
|----------|---------|-------------------|
| macOS | WKWebView | `-webkit-` long-standing; unprefixed 18+ |
| Windows | WebView2 (Chromium, evergreen) | 76+, unprefixed |
| Linux | WebKitGTK | `-webkit-` in older 2.3x; unprefixed around 2.46+; current line 2.54 (2026-09) |

Always ship both declarations.

### Transparent window baseline

```css
html,
body {
  background: transparent;
}
```

If the page paints an opaque background, native vibrancy is invisible. Keep
app surfaces translucent and only the content-heavy areas opaque.

### Drag regions

```css
[data-tauri-drag-region] {
  app-region: drag;
  user-select: none;
}

[data-tauri-drag-region] button,
[data-tauri-drag-region] input,
[data-tauri-drag-region] a,
[data-tauri-drag-region] [role="button"] {
  app-region: no-drag;
}
```

- `data-tauri-drag-region` applies only to the element it is set on, not its
  children. That is deliberate: buttons inside a glass titlebar stay clickable.
- `app-region: drag` is needed for Windows touch/pen input; keyboard users do
  not drag.
- Manual fallback: call `getCurrentWindow().startDragging()` on `mousedown`
  with `event.buttons === 1`; on double-click call `toggleMaximize()`.
- On macOS add `-webkit-user-select: none` and `-webkit-touch-callout: none`
  to chrome surfaces to prevent text selection and link callouts.

### Detecting the runtime and platform

```ts
import { isTauri } from "@tauri-apps/api/core";
import { platform } from "@tauri-apps/plugin-os";

export async function applyRuntimeAttributes() {
  const root = document.documentElement;
  if (!isTauri()) {
    root.dataset.runtime = "web";
    return;
  }
  root.dataset.runtime = "tauri";
  root.dataset.platform = await platform(); // "macos" | "windows" | "linux" | ...
}
```

Notes:

- `isTauri()` semantics changed in 2.12 (checks `globalThis.isTauri`; older
  releases checked `window.__TAURI_INTERNALS__`, which still exists). Use the
  function, not the internals, and guard platform calls behind it.
- Set attributes before first paint when possible (top of the entry module) to
  avoid a flash of the web glass over native vibrancy.
- Components never branch on platform; CSS does, via
  `:root[data-runtime="tauri"][data-platform="macos"]`.

### Reduced transparency inside Tauri

- WebKit (macOS) exposes the system setting natively, but the **web media
  query is not exposed in WKWebView** as of Sep 2026; you cannot rely on
  `prefers-reduced-transparency` there.
- Chromium/WebView2 does not ship the query either (limited availability), even
  though desktop Chrome 118+ does.
- Practical approach: read the OS setting from Rust and forward it as an app
  event, or expose an in-app "reduce transparency" setting persisted through
  the preferences API (`./07-fullstack-architecture.md`).

Sketch of a native-forwarded flag (Windows registry
`HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize\EnableTransparency`,
macOS `NSWorkspace.accessibilityDisplayShouldReduceTransparency`), emitted to
the webview as:

```ts
import { emit, listen } from "@tauri-apps/api/event";

await listen<boolean>("system://reduce-transparency", (event) => {
  document.documentElement.dataset.reduceTransparency = String(event.payload);
});
```

Treat this as a small platform shim, not part of the design system's core.

## 6. Decision matrix

| Scenario | Native | CSS | Notes |
|----------|--------|-----|-------|
| Whole window over wallpaper (macOS/Windows) | yes | no | `underWindowBackground`, `mica`/`acrylic` |
| Sidebar over wallpaper | yes | no | `sidebar` material on macOS |
| Cards/popovers over app content | no | yes | Native vibrancy cannot follow in-page content |
| Modal scrim | no | yes | Blurs page content; native would blur desktop |
| macOS 26+ Liquid Glass chrome | yes | no | `liquidGlassRegular`; Clear needs a dimming layer |
| macOS 15 and older | yes | no | fallback material `underWindowBackground` |
| Windows 11 | yes | no for window; yes for panels | Mica cheapest; tabbed for tabs |
| Windows 10 1903+ | yes, careful | yes for panels | Acrylic works but is heavy; blur on 22H1- only |
| Linux | no | yes | Native unsupported; CSS only |
| App Store distribution | public APIs only | n/a | No `macOSPrivateApi`, no `transparent` window macOS |

## 7. Performance and packaging

- Microsoft documents Acrylic as GPU-intensive with battery impact and disables
  it automatically in Battery Saver, when Transparency effects are off, and in
  High Contrast. Mica and Tabbed are cheaper. Prefer Mica on Win11.
- Avoid Acrylic as the base of large scrolling surfaces; known drag/resize lag
  on Win10 1903+ and Win11 22000. Prefer Mica, or CSS glass on bounded panels.
- Do not stack acrylic surfaces: seams become visible.
- WebView2 transparent windows can show artifacts while resizing/scrolling;
  `noRedirectionBitmap: true` mitigates creation flash, treat the rest as
  empirical per machine.
- CSS glass on Tauri still pays the same cost as on the web; the budgets in
  `./06-performance-and-browser-support.md` apply unchanged.

Bundling (`tauri build`, `bundle.targets`): `deb`, `rpm`, `appimage`, `nsis`,
`msi`, `app`, `dmg`, or `"all"`. Updater: `bundle.createUpdaterArtifacts` plus
`tauri-plugin-updater` with signed artifacts. With `macOSPrivateApi: true`,
plan for direct distribution (codesigning + notarization, `hardenedRuntime`
defaults true) instead of the App Store.

Automated UI testing of the packaged app is limited: `tauri-driver` covers
Linux (WebKitWebDriver) and Windows (msedgedriver); macOS is not supported by
the driver as of Sep 2026. Keep the web build testable in Playwright
(`./07-fullstack-architecture.md`) and use the packaged app for manual
platform checks.

## 8. Shipping checklist

- [ ] Decision made per surface: native, CSS, or neither (Section 1).
- [ ] No CSS blur over native vibrancy pixels.
- [ ] `html, body { background: transparent }` only when native vibrancy is
  active; opaque otherwise.
- [ ] `windowEffects` arrays ordered with a fallback per OS.
- [ ] Capability grants `core:window:allow-set-effects` (and only that).
- [ ] Drag region tested with buttons, inputs, and double-click maximize.
- [ ] macOS: `macOSPrivateApi` implication accepted (no App Store) or avoided.
- [ ] Windows: Mica preferred; Acrylic only when required by Win10 support.
- [ ] Linux: CSS-only path verified on WebKitGTK.
- [ ] Reduced transparency handled through the app setting / native flag.
- [ ] Packaged build tested on each target OS, including window resize and
  scroll.

## 9. Anti-patterns

- Copying a CSS glass recipe into a transparent Tauri window with nothing
  behind the webview, then wondering why there is no blur.
- `transparent: true` with an opaque page background.
- Using `macOSPrivateApi` without accepting the App Store consequence.
- Acrylic on Win11 when Mica exists.
- Putting `data-tauri-drag-region` on a container and expecting child buttons
  to work; the attribute does not propagate (by design), and the container may
  still swallow events if styled with `pointer-events: none`.
- Platform detection in components instead of CSS attributes.
- Testing only the web build and assuming the packaged webview renders
  identically (WebKitGTK and old WKWebView will differ).

## 10. Related

- `./01-physics-of-glass.md` - the layers native vibrancy replaces or complements.
- `./02-css-implementation.md` - the CSS that runs inside the webview.
- `./06-performance-and-browser-support.md` - budgets shared with the web build.
- `./07-fullstack-architecture.md` - the web build packaged by Tauri.
