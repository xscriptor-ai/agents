---
name: linkedin
description: Generates LinkedIn post copies and images to position a technical brand
  (X - Scriptor) around web development, accessibility, usability, programming, TypeScript,
  JavaScript, VS Code, extensions, dev ecosystem, Linux distros, and career. Use when
  the user asks for LinkedIn posts, copies, hooks, hashtags, publishing calendar,
  personal-brand positioning, or 1080x1350 post images; also to continue or regenerate
  a numbered content series.
---

# LinkedIn Content (X - Scriptor)

Complete LinkedIn content system: publication-ready copies plus 1080x1350 images
on OLED black with the tiny `X - Scriptor` signature.
Everything is deterministic and numbered: the `.md` **NNN** always matches the image **NNN**.

## When to use this skill

- Create or extend a series of LinkedIn posts.
- Generate the image for a copy (1080x1350, 4:5).
- Plan cadence, publishing windows, and topic blocks.
- Review or rewrite hooks, hashtags, and post structure.

## Quick start

```bash
# 200 full posts (copies + images + index) into ./contenido
python3 scripts/generar.py --out contenido --count 200

# single topic, 20 posts
python3 scripts/generar.py --topic typescript --count 20 --out out-ts

# continue an existing series from 201
python3 scripts/generar.py --out contenido --count 50 --start 201

# copies only (fast drafts, no rsvg)
python3 scripts/generar.py --out drafts --count 30 --text-only
```

Output:

```
<out>/
├── indice.md      # table: Nº | topic | hook | image
├── posts/NNN-slug.md
└── img/NNN-slug.png
```

Each `.md` contains: topic, image path, **ALT text**, suggested publishing
window, hashtags, and the copy ready to paste (no markdown, line breaks included).

## Workflow

1. Run the generator with the desired `--count` and `--out`.
2. Review 2-3 random `.md` files and one full-size image (not only thumbnails).
3. Tune content in `scripts/temas.py` (ideas per topic) and `scripts/ganchos.py`
   (new hooks); run again.
4. When publishing: copy the text, upload the image with the same number, and
   paste the ALT text into LinkedIn.

## Quality rules (non-negotiable)

- The hook fits in the first 2 lines (≈140-210 characters).
- Copy is at least 800 characters; paragraphs of 1-3 lines; arrows `→` or lists.
- Maximum **3 niche hashtags**; never 6+.
- No external links in the body (nor in the first comment).
- The image carries ALT text and its number matches the `.md` number.
- The image signature is only `X - Scriptor`, small and barely visible.
  **Never** mention any internal brand name in the content or the images.

## Customization

| I want to | Where |
|---|---|
| Add/change topics, hashtags, subtitles | `scripts/temas.py` (`TOPICS`) |
| Add new hooks | `scripts/ganchos.py` (`HOOKS`) |
| Change CTAs, intros, windows | `scripts/temas.py` (`CLOSERS`, `OPENERS`, `WINDOWS`) |
| Change colors, fonts, layout | constants and `build_svg()` in `scripts/generar.py` |
| Change the signature brand | `BRAND` constant in `scripts/generar.py` |

## References

- `references/linkedin-strategy.md` — what the algorithm rewards (with numbers) and mistakes to avoid.
- `references/copy-structure.md` — hooks, the 4 post structures, hashtags, CTAs.
- `references/visual-system.md` — tokens, grid, motifs, and signatures for the images.
- `references/publishing.md` — cadence, windows, golden hour, topic blocks, and metrics.

## Requirements

- Python 3 (standard library only).
- `rsvg-convert` (`librsvg2-bin` package) to rasterize the images.
- Installed fonts: **Space Grotesk**, **Space Mono**, and **Doto**. If missing,
  rsvg falls back to generic fonts and the design loses character (see `references/visual-system.md`).
