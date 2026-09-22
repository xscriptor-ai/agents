# Copy Structure

The generator builds every post as: **hook + intro + 4 ideas + closing**, rotating
one of four shapes so no two publications look the same.

## Hook rules

- Two lines maximum (≈140-210 characters). It must fit "above the fold".
- Formulas that work: a short debatable claim, a concrete data point, a common
  mistake, a promise of usefulness, a question with tension.
- No empty clickbait: if the hook promises and the body does not deliver, dwell
  time drops.
- Write the hook last, once you know what the post actually says.

Examples from the pack:

- "any is not a type: it is turning the compiler off with style."
- "Users do not wait 3 s: they leave before your spinner loads."
- "If the save button needs explaining, the design fails."

## The 4 structures

| Mode | Shape | Best for |
|---|---|---|
| 0 | `hook → intro → 4 "→" bullets → question` | tip lists |
| 1 | `hook → intro → 4 numbered points → question` | steps or levels |
| 2 | `hook → 4 short paragraphs → question` | developing one idea |
| 3 | `hook → intro → 4 "•" bullets → question` | mistakes and nuances |

## Body

- 4 concrete ideas, each 1-2 sentences with at least one data point, API name,
  or verifiable consequence.
- No markdown (LinkedIn does not render it): backticks are stripped at
  generation time. Arrows and numbers are the format.
- Neutral Spanish, "tú/ustedes"; concrete verbs; short sentences.

## Closing and hashtags

- Closing = open question, specific and answerable in one comment.
  Avoid generic "what do you think?".
- Hashtags: exactly 3, niche and related to the post topic.
  Never 6+; the net impact of more hashtags is negative.
- The closing question is also an honest invitation: replying to every comment
  is part of the strategy (golden hour).

## Content bank

- `scripts/temas.py` → `TOPICS`: each topic has 16 concrete ideas, an image label,
  hashtags, and 3 subtitles.
- `scripts/ganchos.py` → `HOOKS`: 200 unique hooks grouped by topic.
- The generator interleaves topics round-robin (never two consecutive posts on
  the same topic) and picks 4 ideas with a different rotation per post, so
  combinations do not repeat across the series.
