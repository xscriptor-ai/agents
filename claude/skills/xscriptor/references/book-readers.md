# Xscriptor Book Reader Engines

The site has **four different book-rendering engines**. They share concepts
(blank-line blocks, section titles, index, 4/5-item pagination, full-bleed
backgrounds, decrypting words) but differ in parsing detail and interaction.
Pick the engine deliberately; do not rewrite one into another.

| Engine | Origin | Used by | Signature |
|--------|--------|---------|-----------|
| `XBookReader` | npm `@xscriptor/xcomponents` | Boulevard | simplest paginated reader |
| `XCompleteBook` | npm `@xscriptor/xcomponents` | Asintota, La danza de las amapolas | section/index pages + `renderPoem` override |
| `XBookColors` | local `xcomponents/xbookcolors` | Cielos de Alquitrán, Primavera | per-block background rotation + per-word colors/decrypt |
| `BookReaderPoems` | local `xcomponents/BookReaderPoems` | Colaterales | index-driven poem reordering + titles |

> There is also an **unused local copy** at
> `xcomponents/xcompletebook/XCompleteBook.tsx`. The barrel exports the **npm**
> `XCompleteBook`, so the local file is dead code today. Verify before editing.

---

## 1. Shared content model

All engines consume the raw MDX string and split it into **blocks** on blank
lines (2+ or 3+ newlines depending on the engine). Blocks become typed items:

```ts
type PageItem = {
  type: "section_title" | "content" | "poem_block" | "image" | "index";
  content: string;
  title?: string;        // poem_block (BookReaderPoems)
  entries?: IndexEntry[];// index
  alt?: string; src?: string; // image
};
```

- **Section title** — first line matches the engine’s `SECTION_NAMES[locale]`
  (case-insensitive). Each becomes its own page.
- **Image** — block exactly `![alt](src)`.
- **Index** — trailing block beginning with the locale index header
  (`Índice`/`Index`/`Inhalt`/`Indice`/`Index`). Stripped from the body and
  rendered as a dedicated page; entry lines containing `....123` or `- 123` are
  poem entries, others are section names.
- **Content / poem** — everything else.

### Pagination grouping (identical in all engines)

```ts
function groupIntoPages(items, withCover) {
  const pages = [];
  if (withCover) pages.push([]);            // page 0 = cover
  let page = [];
  for (const item of items) {
    if (item.type === "section_title" || item.type === "index") {
      if (page.length) { pages.push(page); page = []; }
      pages.push([item]);                    // section/index always alone
      continue;
    }
    page.push(item);
    const maxPerPage = pages.length % 2 === 0 ? 4 : 5;  // alternate 4 / 5
    if (page.length >= maxPerPage) { pages.push(page); page = []; }
  }
  if (page.length) pages.push(page);
  return pages;
}
```

Cover page (`currentPage === 0 && coverImage`) shows just the cover image;
section pages show a centered title; index pages show the index list; content
pages render a zigzag of blocks. Navigation scrolls the reader into view with
`scrollIntoView({ behavior: "smooth", block: "start" })`.

### Default labels (per locale)

`DEFAULT_LABELS[locale] = { prev, next, pageOf: "Página {current} de {total}", index }`
(`Previous/Next`, `Zurück/Weiter`, `Precedente/Successivo`,
`Précédent/Suivant`). `{current}` and `{total}` are manually split around the
page-number input, not interpolated by a formatter. `BookReaderPoems` instead
pulls labels from `useT("BookReader")`.

### Word parsing (for decrypting poem text)

Every engine that renders poems converts each poem into `WordConfig[]`:

```ts
// split into lines → words → chunks of (1 + word.length % 3) words
const hash = chunkText.length + chunkIndex * 3 + lineIndex * 5;
if (hash % 7  === 0) type = "underline";
else if (hash % 11 === 0) type = "button";
else if (hash % 13 === 0) type = "blur1";
else if (hash % 17 === 0) type = "blur2";
italic = hash % 4 === 0;
bold   = hash % 9 === 0;
breakAfter = last chunk in line;
```

Then a **safety pass** guarantees at least one `underline`, `button`, `blur1`,
`blur2` exist (otherwise blurred words could never be revealed). For very short
poems (≤3 chunks) the assignment is explicit:

| chunks | distribution |
|--------|--------------|
| 1 | `underline` |
| 2 | `underline` + `blur1` |
| 3 | `underline` + `blur1` + `button` |

`XBookColors` (XBookFullDecrypt) and `XCompleteBook` implement this safety pass;
`BookReaderPoems` overrides the last `normal` as `button` if none exists.

---

## 2. `XBookColors` (local) — deep dive

File: `src/app/components/xcomponents/xbookcolors/XBookColors.tsx` (+ `.module.css`).

### Props

```ts
{
  rawText: string;
  coverImage?: string;
  backgroundImage?: string;
  backgroundVideo?: string;
  bgConfig?: { basePath: string; total: number; digits?: number; format?: string };
  locale?: "es"|"en"|"de"|"it"|"fr";
  overlayColor?: string;                 // default rgba(0,0,0,0.45)
  labels?: { prev?; next?; pageOf?; index? };
  onPageChange?: (page: number) => void;
  sectionNames?: Record<Locale, string[]>;
}
```

### Backgrounds

`resolvedBg = bgConfig
  ? `${basePath}${pad((bgIndex % total) + 1, digits ?? 2)}.${format ?? "webp"}`
  : backgroundImage`.

`bgIndex` is set to the current page on navigation, so backgrounds rotate in
lockstep with pages. The wrapper fixed-bleeds a `<video>` or `<img>` plus a
`bgOverlay` tint.

### Rendering

- Cover page, section-title page, index page exactly as the shared model.
- Content pages: `XZigZagLayout` (`startSide="left"`, `gap 6`,
  `offset clamp(1rem,4vw,4rem)`, `textAlign="side"`, `showLine`,
  `lineColor = wordHex[BLOCK_COLORS[currentPage % 5]]`, `lineThickness 0.5`) with
  each item either an image block or a `XBookFullDecrypt` poem block.
- Pagination: SVG chevrons, split `pageOf` template + numeric input
  (digits-only, Enter/blur to jump, resets out-of-range).

### Theme + colors

`useDetectTheme` (MutationObserver on `data-theme`) selects `DARK_WORD_HEX` /
`LIGHT_WORD_HEX` and `DARK_COLORS` / `LIGHT_COLORS` (sets `--c0…--c7`), applied
as inline `style` on the wrapper. `XBookFullDecrypt` cycles `WORD_COLORS` every
2 chunks and applies color + `--c-word` inline; blur is applied via **inline
styles** (`filter: blur(10px); opacity:.3`) because CSS-class swapping did not
reliably win the cascade (documented in `xbookcolors/README.md`).

### Wrappers that rotate backgrounds

`CielosDeAlquitranBook` and `AmapolasBook` are client wrappers that keep their
own `bgIndex`, compute the next frame, and preload it with `new Image()` before
passing `backgroundImage` to `XCompleteBook`. Note the **page routes** for
Cielos/Primavera/Amapolas use `XBookColors` directly with `bgConfig` when a
background set exists (Amapolas page uses `XBookColors` + `bgConfig`; the
`AmapolasBook` wrapper is a separate `XCompleteBook` variant — inspect the route
before editing to know which is live).

---

## 3. `XCompleteBook` (npm, via barrel) — deep dive

File: npm `@xscriptor/xcomponents`; local duplicate at
`xcomponents/xcompletebook/XCompleteBook.tsx` mirrors the logic.

### Props

```ts
{
  rawText: string;
  coverImage?: string;
  backgroundImage?: string;
  backgroundVideo?: string;
  locale?: "es"|"en"|"de"|"it"|"fr";
  overlayColor?: string;
  labels?: { prev?; next?; pageOf?; index? };
  onPageChange?: (page: number) => void;
  sectionNames?: string[];                       // for THIS book, current locale
  renderPoem?: (content: string) => ReactNode;   // replaces XInteractivePhrase
}
```

### Differences from `XBookColors`

- Content pages use `XZigZagLayout` with `lineColor="var(--accent)"`,
  `lineThickness 0.2`, and each poem is rendered by `XInteractivePhrase`
  (npm) **unless** `renderPoem` is supplied.
- Default section names are geometry-themed (`CURVA, PLANO CARTESIANO, RECTA,
  I…V`); `AmapolasBook` overrides them with the poppy sections.
- No per-block background rotation; the wrapper passes a single rotating
  `backgroundImage`.

### Usage

- **Asintota**: `AsintotaBook` rotates 72 backgrounds (`bgConfig` equivalent)
  and passes per-locale labels; `renderPoem` not set (uses `XInteractivePhrase`).
- **Amapolas wrapper**: passes `sectionNames` and
  `renderPoem={(c) => <XBookFullDecrypt content={c} />}` to get the colored
  per-word decrypt. (The Amapolas **route** currently uses `XBookColors` with
  `bgConfig` instead — confirm which is active before changing.)

---

## 4. `BookReaderPoems` (local) — deep dive

File: `src/app/components/xcomponents/BookReaderPoems.tsx` (+ `.module.css`).

Used by **Colaterales**. Its distinguishing feature is that it treats the index
as a **table of contents that dictates poem order**.

### Parsing pipeline

1. `parseIndex(rawText, locale)`:
   - finds the trailing index header block,
   - walks its lines: known section names start a section; lines with
     `....123` are poem titles (normalized whitespace, lowercased as keys);
   - returns `{ knownTitles: Map<key, displayTitle>, sectionTitles: Set,
     orderedTitles: Map<section, key[]> }`.
2. `parseContent`:
   - removes the index from the body, splits into blank-line blocks;
   - section-title and image blocks as usual;
   - inside a poem section, a line matching a known title starts a new
     `poem_block`; remaining lines become its content;
   - outside sections, a single all-caps line becomes an empty `poem_block`.
3. Merge pass: a `poem_block` with empty content followed by a `content` block
   is merged into one poem.
4. `reorderPoems`: for each section, sorts its `poem_block`s by the index order,
   re-attaching any non-poem blocks to the poem that preceded them (or moving
   them to the section start if they preceded all poems).
5. Index page re-appended as a `PageItem`.

### Render

Content pages use `XZigZagLayout` (accent line, thickness 0.2) and render each
poem as `<h3 class=poemTitle>` + `XInteractivePhrase`. `poemWrapper p` forces
`line-height: 2 !important`. Pagination mirrors the shared pattern but uses
`useT("BookReader")`. The container is a plain column (`min-height: 80vh`) — no
full-bleed background.

Section names (Colaterales) per locale: `TACTO/TRANSFUSIONES/PERSPICACIA/
INTERSECCIÓN/INCERTIDUMBRE` (translated for all five). Index headers here use
`Inhaltsverzeichnis` for German (different from the other engines’ `Inhalt`) —
a known inconsistency.

---

## 5. `XBookReader` (npm) — Boulevard

`[locale]/obras/boulevard/page.tsx` renders the npm `XBookReader` directly:

```tsx
<XBookReader
  rawText={rawText}
  coverImage="/images/colecciones/libros/boulevard.webp"
/>
```

Minimal wrapper (`main.min-h-screen.py-16.px-4.md:px-8.max-w-7xl.mx-auto`). No
background rotation, no section overrides. Boulevard content files:
`src/app/content/boulevard/{locale}.mdx`.

---

## 6. Choosing / adding an engine

- Plain paginated poems, no art → `XBookReader`.
- Section pages + index + a single background, generic word interaction →
  `XCompleteBook`.
- Rotating full-bleed backgrounds and/or per-word color + decrypt →
  `XBookColors` (+ a wrapper if you want preloading).
- Poems whose reading order is defined by an index / titles → `BookReaderPoems`.

When adding a book:

1. Author the five MDX files.
2. Add cover + background frames to `public/images/obras/<book>/`.
3. Create `[locale]/obras/<book>/page.tsx` using the file-resolution pattern
   from `content-pipeline.md`.
4. If backgrounds rotate, add a client wrapper (copy `AsintotaBook`) with the
   correct `TOTAL_BG`.
5. Register the book in `ObrasClientPage` and (optionally) `poemParser`.
6. Translate section-name tables and `Books.*` strings into all locales.

## 7. Known reader pitfalls

- **Background frame counts** must match `TOTAL_BG` / `bgConfig.total`, else the
  reader requests a missing `bgNN.webp` (blank frame).
- **Section-name tables are per-engine and duplicated** across locales; adding a
  section only in one locale makes it render as plain content in the others.
- **Index parsing differences** (German `Inhalt` vs `Inhaltsverzeichnis`) mean
  the same book content cannot be moved between engines without adjusting the
  index header.
- **`groupIntoPages` alternates 4/5 items** based on the *current* `pages.length`
  parity, so inserting/removing a section page shifts pagination for everything
  after it — expected, not a bug.
- **Short poems** rely on the explicit type-assignment fallback; do not remove
  it or blurred-only poems become unrevealable.
- **Theme** is read from `data-theme` only (no system preference); reader colors
  update via `MutationObserver` when the navbar toggles the theme.
