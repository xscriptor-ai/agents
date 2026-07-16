# DevX Tokens And Layout

This file provides a compact reference for AI agents working on the DevX UI.

## Theme Variables

Use existing project variables first:

- `--background`
- `--foreground`
- `--primary`
- `--text-muted`
- `--border`
- `--card-bg`

## Text Roles

- **Page title**: primary route label, same visual weight as other resource pages
- **Eyebrow**: optional, compact, technical, low-volume
- **Section title**: strong but not oversized
- **Description**: readable, usually capped to `56ch` to `68ch`
- **Metadata**: smaller, quieter, never competing with the title

## Spacing Rhythm

- tight grouping: `0.25rem` to `0.5rem`
- standard inner spacing: `0.75rem` to `1rem`
- section spacing: `1.25rem` to `2rem`
- major page separation: `3.5rem` and above

## Alignment Rules

- default to left alignment
- avoid centering dense UI content
- align headings, descriptions, and actions to the same inner edge
- screenshots may fill width, but copy should stay readable

## Borders And Radius

- default section radius: `0`
- image media may use restrained rounding
- prefer subtle borders and separators over boxed card stacks

## Buttons

- primary: `--primary` background with `--background` text
- secondary: transparent background with `--primary` border and text
- mobile: stack buttons to full width when space is limited

## Motion

- use subtle opacity, blur, and translate transitions
- prefer CSS transitions for reveals and section dimming
- respect `prefers-reduced-motion`

## Responsive Rules

- set `min-width: 0` on shrinkable flex/grid children
- prevent horizontal overflow at all times
- convert horizontal lists into grids or stacked layouts on mobile
- allow wrapping for code-like content and long labels

## Preview Rules

- simulated editor windows may use local preview variables
- preview-local colors should never replace page-level theme variables
- internal scroll is allowed, but page-wide horizontal scroll is not
