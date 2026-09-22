# Visual System

Single image, 1080x1350 (4:5). OLED black, dot grid, hairline strokes, technical
typography, and **a single red accent**. The only visible brand is a tiny
`X - Scriptor` at the bottom right.

## Tokens

| Element | Value |
|---|---|
| Background | `#000000` |
| Dot grid | `#171717` (0.9 px dots every 16 px) |
| Hairline motif lines | `#151515` |
| Corner ticks | `#3A3A3A` |
| Ink (headline) | `#F2F2F2` |
| Top label | `#6E6E6E` (Space Mono, uppercase, 0.18em tracking) |
| Subtitle | `#7A7A7A` (Space Mono, uppercase, 0.16em tracking) |
| Doto number | `#383838` |
| Signature | `#3E3E3E` (Space Mono 19 px) |
| Accent (single) | `#D71921` (160x1.6 px rule + 3 px dot) |

## Typography and hierarchy

- **Headline**: Space Grotesk Medium, auto-fitted between 96 and 54 px, up to
  5 lines, -0.02em tracking. It is the synthesis of the copy (the hook).
- **Label**: post topic, top left.
- **Number**: Doto 46 px, top right; matches the `.md` number.
- **Subtitle**: one short line from the topic, under the headline.
- **Signature**: `X - Scriptor` at 19 px, barely visible.

## Layout

- Margins: 96 px on the sides.
- Headline vertically centered around y=700, left-aligned.
- Accent rule right above the headline; accent dot at the end of the rule.
- Corner ticks (18 px).
- Rotating background motif by `n % 4`: concentric circles, diagonal lines,
  horizontal lines, or dashed circles. Motif center alternates between
  (860, 300), (220, 1080), and (880, 1120) to vary the framing.

## Hard rules

1. **Never** put any brand name other than `X - Scriptor`; no internal system names.
2. The signature never competes with the content: small size and dark gray.
3. One color accent per image; everything else is monochrome.
4. No solid fills behind text: the background breathes.
5. The key message also lives in the copy; not every device can read text in images.

## How to change it

Everything lives in `scripts/generar.py`: color and font constants at the top,
`motif()` for background structures, and `build_svg()` for the composition.
To change the signature, edit the `BRAND` constant.

## Fonts

Space Grotesk, Space Mono, and Doto must be installed (rsvg resolves them through
fontconfig). If missing, rendering does not fail but falls back to generic
alternatives: install them to preserve the system's character.
