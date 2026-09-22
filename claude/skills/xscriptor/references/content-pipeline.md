# Xscriptor Content Pipeline

How content is authored, stored, parsed and localized:
- **Blog articles** — Markdown → HTML at build time (`articles.ts`).
- **Books** — MDX per locale → raw text → one of four reader engines.
- **Poem index (graph)** — all books aggregated from disk (`poemParser.ts`).
- **UI strings / home phrases** — `messages/{locale}.json` + `I18nProvider`.

---

## 1. Directory layout

```
src/app/content/
  articulos/
    es/**/*.md          # Spanish articles (source of truth)
    en/**/*.md          # English translations (same slugs)
    de/**/*.md  it/**/*.md  fr/**/*.md
  <book>/
    es.mdx  en.mdx  de.mdx  it.mdx  fr.mdx
  cielos-de-alquitran/
    cielos-de-alquitran.mdx   # ES file uses this special name
    en.mdx  de.mdx  it.mdx  fr.mdx
messages/
  es.json  en.json  de.json  it.json  fr.json
```

Books present: `boulevard`, `asintota`, `primavera-en-el-desierto`,
`la-danza-de-las-amapolas`, `colaterales`, `cielos-de-alquitran`.

Blog articles are grouped in subfolders per topic (e.g. `chat-control/`,
`kyber/`, `obscura/`) plus flat `.md` files. The `research/` subfolder inside a
topic is **excluded from the blog listing** but still reachable (see §2).

Public imagery (covers + reader backgrounds):

```
public/images/blog/*.webp|jpg
public/images/obras/<book>/<cover>
public/images/obras/<book>/<bookbook>/bgNN.webp   # reader backgrounds
public/images/obras/grafo/background.webp
public/images/colecciones/{arte,libros}/*.webp
```

Background counts: `asintota/asintotabook` = 72, `amapolasbook` = 31,
`cielosdealquitranbook` = 30.

---

## 2. Blog articles — `src/app/lib/articles.ts`

Build-time, `fs`-based, locale-aware. These functions run only in Server
Components / build (`params`/`metadata`). JSON/disk paths are relative to
`process.cwd()`.

### Constants

```ts
const articlesBaseDir = path.join(process.cwd(), "src/app/content/articulos");
const FALLBACK_LOCALE = "es";
const SUPPORTED_LOCALES = ["es", "en", "de", "it", "fr"];
```

### Frontmatter contract

```yaml
---
title: "Article Title"
date: "2024-01-01"          # ISO; sort key (desc)
description: "Short summary"
categories: ["chat-control"] # primary taxonomy; drives listing + filters
tags: ["..."]                # fallback for keywords
keywords: ["..."]            # preferred pills on the article page
image: "/images/blog/x.webp"
author: "Xscriptor"
excerpt: "Optional custom excerpt"
---
```

### Functions

| Function | Behavior |
|----------|----------|
| `getSortedArticles(locale = es)` | Lists top-level `.md` files and one level of **non-`research`** subdirectories; parses each; sorts by `date` desc. Falls back to `es` if the locale dir is missing. |
| `getAllArticleSlugs(locale = es)` | Union of locale slugs + `es` fallback slugs (set), returned as `{ params: { slug } }`. Nested slugs keep `folder/file`. |
| `getArticleData(slug, locale = es)` | Reads `{locale}/slug.md`, falling back to `es`. Runs the full markdown→HTML pipeline. Returns `null` if absent. |
| `getArticlesByCategory(category, locale = es)` | Case-insensitive category filter over `getSortedArticles`. |

### `ArticleMetadata`

```ts
{ slug, title, description?, date, categories: string[],
  tags?, keywords?, excerpt?, readingTime: number, image?,
  author?, contentHtml? }
```

- `readingTime = ceil(words / 200)`.
- `excerpt` falls back to `description`, then to the first 150 chars of body
  with headings stripped, suffixed `"..."`.
- `toStringArray` normalizes scalar/array frontmatter.
- `date` defaults to today if missing.

### Markdown → HTML pipeline (in `getArticleData`)

```ts
matter(content)                              // gray-matter frontmatter
→ stripDuplicateLeadMeta(body, title)        // remove duplicate H1 + "Publicado por" block
→ unified()
    .use(remarkParse)
    .use(remarkGfm)
    .use(remarkMath)
    .use(remarkRehype)
    .use(rehypeKatex)
    .use(rehypeHighlight)
    .use(rehypeStringify)
```

Post-processing on the resulting HTML:

1. **Soft-break → `<br>`.** Converts single `\n` inside `p`, `h1-6`,
   `blockquote`, `li`, `div` (skips anything containing `katex` or
   `pre`/`code`), because `remark-rehype` does not emit `<br>` for soft breaks.
2. **Table wrapping.** Wraps every `<table…</table>` in
   `<div class="table-wrapper">` for horizontal scroll.

`stripDuplicateLeadMeta` removes a leading `# H1` (duplicate of the page title)
and an immediately following `**Publicado por …**` paragraph. This is why
article bodies never show the title/author twice.

### Consumer

- Listing: `[locale]/blog/page.tsx` → `getSortedArticles(locale)` →
  `BlogListClient`.
- Article: `[locale]/blog/[...slug]/page.tsx`:
  - `generateStaticParams` builds `{ locale, slug: slug.split('/') }` for all
    five locales × `getAllArticleSlugs()` (ES slugs).
  - `generateMetadata` calls `getArticleData`.
  - Page renders `XBlogDecrypt` with de-duplicated categories/keywords,
    localized date (`de-DE/it-IT/fr-FR/en-US/es-ES`), reading-time label from
    `BlogPage.readingTime`, and `speed={10}`.
  - `[...slug]` is a **catch-all**, so nested/folder slugs work unchanged.

> `next-sitemap.config.js` excludes `/blog/post` (a legacy route that no longer
> exists). Removing the exclude is safe.

---

## 3. Book content (MDX as plain text)

Book pages read the MDX **as a raw string** (`fs.readFileSync`) and hand it to a
client reader. No MDX runtime, no frontmatter parsing for books. The readers
parse the string themselves with blank-line-separated blocks.

### File resolution pattern (pages)

```ts
const filePath = path.join(process.cwd(), `src/app/content/${book}/${locale}.mdx`);
const fallbackPath = path.join(process.cwd(), "src/app/content/${book}/es.mdx");
const rawText = fs.readFileSync(fs.existsSync(filePath) ? filePath : fallbackPath, "utf-8");
```

Exception: `cielos-de-alquitran` ES file is `cielos-de-alquitran.mdx`, handled
explicitly by both `poemParser.ts` (`LOCALE_FILES`) and the page.

### Structural syntax understood by the readers

- **Blank line(s)** separate blocks. Readers split on `\n{2,}` (XBookColors /
  XCompleteBook) or `\n{3,}`/`\n{2,}` (poemParser / BookReaderPoems).
- **Section title**: a block whose first line matches a known section name
  (all-caps tables per book/locale). Becomes a dedicated page.
- **Image**: a whole block of the form `![alt](src)`.
- **Poem / content block**: anything else.
- **Index**: a trailing block starting with the locale’s index header
  (`Índice`/`Index`/`Inhalt`/`Indice`/`Index`) followed by entries. Entries with
  `....123` or `- 123` are poem entries; other lines are section names. The
  index is stripped from the body and rendered as its own page; `BookReaderPoems`
  also uses it to **reorder** poems.

### Section-name tables (per book/locale)

| Engine | Sections (ES) |
|--------|---------------|
| `XBookColors` default | `LUCIÉRNAGAS, UNIVERSO, CONSTELACIONES, INSTANTES, AUTOPSIA, I, II, III, IV, V` |
| `XCompleteBook` default | `CURVA, PLANO CARTESIANO, RECTA, I, II, III, IV, V` |
| `BookReaderPoems` (Colaterales) | `TACTO, TRANSFUSIONES, PERSPICACIA, INTERSECCIÓN, INCERTIDUMBRE` |
| `AmapolasBook` override | `LUCIÉRNAGAS, UNIVERSO, CONSTELACIONES, INSTANTES, AUTOPSIA` |

All books also carry translated section names in `de/it/fr/en`.

> These tables live inside the components, not in `messages/`. When a new book
> is added with custom sections, pass `sectionNames` (XCompleteBook /
> XBookColors) or extend `SECTION_NAMES` (BookReaderPoems).

---

## 4. Poem index for the graph — `src/lib/poemParser.ts`

`getAllPoems(locale)` builds the node set for `GrafoPoetico`.

- Iterates `BOOKS = [boulevard, asintota, primavera-en-el-desierto,
  la-danza-de-las-amapolas, colaterales, cielos-de-alquitran]`; `bookIndex`
  (0–5) drives graph node color. Blog blocks get `book: "blog"`, `bookIndex: 6`.
- For each book, resolves the locale file (special-casing `cielos`), falling back
  to `es.mdx`.
- `isVerseBlock`: a block is verse if it has ≥2 lines and **average line length
  < 60** chars.
- `PROSE_BOOKS = new Set(["colaterales"])` allows prose blocks (capped at 600
  chars via `PROSE_CONTENT_MAX`); other books skip non-verse blocks.
- Titles: first short line if plausible, else first ~5 words + `…`.
- Blog contributions: reads the locale’s flat `.md` files (not nested), strips
  images/headings, splits on `\n{2,}` blocks >30 chars, and titles them
  `"{articleTitle} — {firstLine}"` or `"{articleTitle} ({n})"`.

`PoemData = { id, title, content, book, bookIndex }`.

---

## 5. UI strings and `HomePhrases`

`messages/{locale}.json` is the interface string store (see
`architecture.md` §5 for namespaces). Two consumption patterns:

- **Client components**: `const t = useT("BlogPage"); t("readingTime", { minutes })`.
- **Server components**: `getMsg(msgs, "BlogPage.metadataTitle")` (no params).

### `WordConfig` (used by `HomePhrases` and poem rendering)

```ts
type WordConfig = {
  text: string;                      // empty string = hard line break
  type?: "underline" | "button" | "blur1" | "blur2" | "normal";
  bold?: boolean;
  italic?: boolean;
  breakAfter?: boolean;
};
```

Consumed as `t.raw<WordConfig[]>("phraseN")`. `HomePhrases` holds `phrase1` …
`phrase14`; `ClientComponentHome` distributes them across two zigzag blocks.

Semantics of `type`:
- `underline` — clickable; toggles the `blur1` group.
- `button` — clickable; toggles the `blur2` group.
- `blur1` / `blur2` — start blurred, unblur when their group is toggled.
- `normal` — plain text.
- `breakAfter` / empty `text` — force a line break.

> When authoring HomePhrases, always include at least one `underline` and one
> `button` in a phrase that uses `blur1`/`blur2`, otherwise blurred words can
> never be revealed. The generated poem pipelines apply a similar safety
> fallback (see `xbookcolors/README.md`).

---

## 6. Adding content — checklists

### Add a blog article

1. Create `src/app/content/articulos/es/<slug>.md` with the frontmatter
   contract. Nested slugs → put it in a topic folder.
2. Add the translation(s) with the **same slug path** under `en/de/it/fr/`.
3. Ensure a cover image exists at the referenced `image` path under `public/`.
4. Optionally add categories/`keywords`; the listing derives its filters from
   `categories`.
5. `npm run build` (validates `generateStaticParams` and the pipeline).

### Add or update a book

1. Drop `src/app/content/<book>/<locale>.mdx` (all five locales; `es` required).
2. Add cover + background frames under `public/images/obras/<book>/`.
3. Pick an engine (see `book-readers.md`), add the route page under
   `[locale]/obras/<book>/`, and — for rotating backgrounds — a thin wrapper.
4. Register the book in `ObrasClientPage`'s `BOOKS` array (title/description
   keys `Books.<key>` / `Books.<key>Desc` in all message files).
5. If it has custom sections, add the per-locale section-name tables.
6. If the graph should include it, append to `BOOKS` in `poemParser.ts` and add
   its `BOOK_LABELS` translations in `GrafoPoetico`.

### Add a UI string

Add the key to **all five** `messages/*.json` files under the right namespace,
then consume via `useT(namespace)` (client) or `getMsg` (server).
