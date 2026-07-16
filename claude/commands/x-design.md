---
description: Review UI components, design tokens, and CSS architecture
argument-hint: '[target]'
allowed-tools: Task, Read, Glob, Grep, Bash(git diff:*), Bash(git status:*)
---
Delegate this task to the `css-ui-specialist` subagent via the Task tool, passing along the context below.

Review the design system and UI implementation in $ARGUMENTS.

!`find $ARGUMENTS -type f \( -name '*.css' -o -name '*.tsx' -o -name '*.jsx' -o -name '*.vue' -o -name '*.scss' -o -name '*.module.css' \) 2>/dev/null | head -20`

Evaluate:
- **Design tokens**: Are colors, spacing, typography, and shadows using CSS custom properties or a token system?
- **Responsiveness**: Are layouts responsive without horizontal overflow or magic breakpoints?
- **Accessibility**: Color contrast (4.5:1 WCAG AA), focus indicators, aria attributes, semantic HTML
- **Performance**: Unused CSS, render-blocking resources, layout shifts
- **Consistency**: Repeated patterns that should be unified
- **Dark mode**: Are there hardcoded light colors that break in dark mode?
- **Animation**: Respects `prefers-reduced-motion`, purposeful not decorative
