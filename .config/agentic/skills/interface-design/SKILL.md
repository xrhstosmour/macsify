---
name: interface-design
description: >
  Craft-first interface design for dashboards, admin panels, SaaS apps, tools,
  settings pages, and data interfaces. Use when designing, building, reviewing,
  or refining product UI where visual hierarchy, component craft, design tokens,
  states, or design-system consistency matter.
---

# Interface Design

Build product interfaces with the craft of a top design team, Linear, Vercel, Stripe, Apple. The difference between those and generic output is not talent. It is that every decision was decided, the hierarchy is unmistakable, and a hundred small details are correct at once. This skill is how you get there.

## When to use

- User says "design a dashboard", "build a settings page", "improve the UI", "redesign the UI/UX", "Design the homepage" or "review the design".
- Building or refining any product interface: dashboards, admin panels, SaaS apps, data interfaces, tools.
- The `designer` agent is invoked for non-trivial UX/UI work.
- User asks for a visual audit, craft review, or design-system extraction.

Do not use for landing pages, marketing sites, campaigns, or brand-only work.

## 1. The Problem

You will generate generic output. Your training has seen thousands of dashboards, and the patterns are strong. You can follow this entire process and still produce a template: warm colors on cold structures, friendly fonts on generic layouts.

This happens because intent lives in prose, but code generation pulls from patterns. The gap between them is where defaults win.

The bar: If another AI, given a similar prompt, would produce substantially the same output, you have failed. Not different for its own sake, different because the interface emerged from this user, this task, this world. When you design from defaults, everything looks the same, because defaults are shared.

## 2. Where Defaults Hide

Defaults disguise themselves as infrastructure, the parts that feel like they just need to work, not be designed.

- Typography feels like a container. But type isn't holding your design, it is your design. The weight of a headline, the personality of a label, the texture of a paragraph shape how the product feels before anyone reads a word. Reaching for your usual font means you're not designing.
- Navigation feels like scaffolding. But navigation is the product, where you are, where you can go, what matters. A page floating in space is a component demo, not software.
- Data feels like presentation. But a number on screen is not design. What does it mean to the person looking? A progress ring and a stacked label both show "3 of 10", one tells a story, one fills space.
- Token names feel like implementation detail. But `--ink` and `--parchment` evoke a world; `--gray-700` and `--surface-2` evoke a template. Someone reading only your tokens should guess what product this is.

There are no structural decisions. Everything is design. The moment you stop asking "why this?" is the moment defaults take over.

## 3. Intent First

Before touching code, answer these. Keep it a compact working brief unless the direction needs user confirmation.

- Who is this human? Not "users." The actual person. Where are they when they open this? What did they do 5 minutes ago, what will they do 5 minutes after? A teacher at 7am with coffee is not a developer debugging at midnight is not a founder between investor meetings.
- What must they accomplish? The verb. Grade these submissions. Find the broken deployment. Approve the payment. The answer determines what leads, what follows, what hides.
- What should this feel like? In words that mean something. "Clean and modern" means nothing, every AI says that. Warm like a notebook? Cold like a terminal? Dense like a trading floor? Calm like a reading app? This shapes color, type, spacing, density, everything.

If the prompt is too vague to identify the human, task, and feel, ask one concise question. If context allows a responsible assumption, state it briefly and proceed.

Intent must be systemic. Saying "warm" then using cold colors is not following through. If warm: surfaces, text, borders, accents, semantic colors, type, all warm. If dense: spacing, type size, information architecture, all dense. Check every token against the stated intent. For every choice, layout, color temperature, typeface, spacing scale, hierarchy, you must be able to say why. "It's common" or "it works" means you defaulted.

## 4. Product Domain Exploration

This is where defaults get caught, or don't. Generic path: Task type → visual template → theme. Crafted path: Task type → product domain → signature → structure + expression. The difference is time spent in the product's world before any visual thinking.

Produce all four before proposing any direction:

- Domain, concepts, metaphors, vocabulary from this product's world. Not features, territory. Minimum 5.
- Color world, what colors exist naturally here? Not "warm" or "cool", go to the actual world. If this product were a physical space, what would you see? List 5+.
- Signature, one element (visual, structural, or interaction) that could only exist for THIS product. If you can't name one, keep exploring.
- Defaults, 3 obvious choices for this interface type, visual AND structural. You can't avoid patterns you haven't named.

The test: Read your proposal with the product name removed. Could someone identify what it's for? If not, explore deeper.

## 5. Visual Hierarchy and Composition

The single biggest driver of "this looks designed" versus "this looks generated." Defaults produce flatness, everything the same size, weight, and spacing, so nothing leads and the eye has nowhere to go. Craft produces hierarchy, the eye knows instantly what matters.

### One focal point per view

Every screen has one thing the user came to do. That thing dominates, through size, contrast, position, or the space around it. When everything competes equally, nothing wins and the interface reads like a parking lot. Before building, name the focal element out loud. Then make it win: bigger, higher-contrast, or ringed in whitespace. Demote everything else deliberately.

### Type scale is a ratio, and weight beats size

Don't pick sizes by feel. Pick a ratio and step it: ~1.2 (minor third) for dense/calm UI, ~1.25 for most product UI, ~1.333 for expressive. From a 14–16px body that yields a visibly distinct scale, not 15/16/17 mush. A 14px base at 1.25: `caption 11 · body 14 · h4 16 · h3 18 · h2 22 · h1 28 · display 44+`. Round to whole pixels and to your spacing grid.

The Apple/Linear move: weight and color do more hierarchy work than size. A single 14px size holds three tiers through weight + opacity alone, `value: 600 / primary`, `label: 500 / secondary`, `meta: 400 / muted`, separating more cleanly than two regular weights two points apart. Build from three levers together (size, weight, color/opacity), never size alone. If you squint and can't tell headline from body from label, the hierarchy is too weak.

### Density is a decision, expressed in px

Linear is tight; Stripe is airy. Neither is default, both are chosen, and the choice is the same number repeated everywhere. Decide the density up front and name the values: a tool panel at 12–16px padding feels workbench-tight; the same card at 24px feels like a brochure. Pick deliberately, then hold it.

### Spatial rhythm, breathe unevenly

Great interfaces don't space everything equally. Dense control zones give way to open content; heavy elements balance against light ones; the eye travels with purpose. Monotone layouts, same card size, same gap, same density everywhere, are the sound of no one deciding. Group tightly-related things, then put real air between groups.

### Proportions speak

A 280px sidebar next to full-width content says "navigation serves content." A 360px sidebar says "these are peers." The specific number declares what matters. Choose widths and ratios that state a relationship.

### Distribution and restraint (the "expensive" look)

- ~60/30/10: a dominant neutral surface, a secondary tone, and ~10% accent. Color is a scarce resource, most of the screen is structure.
- One accent, used with intention, beats five colors used without thought. Gray builds structure; color communicates (status, action, identity). Unmotivated color is noise.
- Hierarchy through space and weight, not lines. Reach for whitespace and tonal shift before borders and dividers. The most premium interfaces are mostly invisible structure.
- Optical sizing on large type: tighten letter-spacing as type gets bigger (headings slightly negative tracking); loosen line-height on body for readability (~1.5). Tight type reads as crafted; default tracking on a 32px heading reads as a document.

## 6. Infinite Expression

Every pattern has infinite expressions, no two interfaces should look the same. A metric display could be a hero number, inline stat, sparkline, gauge, progress bar, comparison delta, or trend badge. Same sidebar width, same card grid, same icon-left-number-big-label-small metric boxes every time signals AI-generated immediately and is forgettable. Linear's cards don't look like Notion's; Vercel's metrics don't look like Stripe's. Same concepts, infinite expressions. Before building, ask: what's the ONE thing users do here, and what product solves a similar problem brilliantly?

## 7. Color Lives Somewhere

Every product exists in a world, and that world has colors. Before reaching for a palette, walk into the physical version of this space, what materials, what light, what objects? Your palette should feel like it came FROM somewhere, not applied TO something. Temperature is one axis; also ask quiet or loud, dense or spacious, serious or playful, geometric or organic. A trading terminal and a meditation app are both "focused", completely different kinds of focus.

## 8. Craft Foundations

### Surface elevation

Surfaces stack: base, then increasing levels. Each jump is only a few percentage points of lightness, dark mode base → +7% → +9% → +12%; light mode stays light and adds shadow instead. You can barely see one step in isolation, but stacked, the hierarchy emerges.

- Sidebars: same background as canvas, not a different color. Different colors fragment the space. A subtle border is enough.
- Dropdowns/popovers: one level above their parent surface, or they blend in and layering is lost.
- Inputs: slightly darker than surroundings, not lighter. Inputs are inset, they receive content. A darker fill signals "type here" without heavy borders.

### Borders

Should disappear when you're not looking for them, but be findable when you need structure. Low-opacity rgba blends with the background and defines an edge without demanding attention; solid hex borders look harsh by comparison. Dark mode lives around `rgba(255,255,255,0.06–0.12)`, light mode slightly higher. Build a progression, standard, softer separation, emphasis, focus-ring, and match intensity to the importance of the boundary.

### The squint test

Blur your eyes at the interface. You should still perceive hierarchy, what's above what, where sections divide, but nothing should jump out. No harsh lines, no jarring shifts. Just quiet structure. Get this wrong and nothing else matters.

## 9. Before Writing Each Component

Every time you write UI code, even small additions, state:

```
Intent:     [who is this human, what must they do, how should it feel]
Hierarchy:  [the focal element, and how it wins, size / weight / contrast / space]
Palette:    [colors from your exploration, and WHY they fit this world]
Depth:      [borders / subtle shadows / layered, and WHY it fits the intent]
Surfaces:   [your elevation scale, and WHY this temperature]
Typography: [typeface + the size/weight/color levers, and WHY]
Spacing:    [base unit + chosen density]
```

This checkpoint is mandatory. If you can't explain WHY for each, you're defaulting, stop and think.

## 10. Use What Exists

The most common way AI degrades a codebase: it hand-rolls what already exists. A bespoke `<div onClick>` "button" beside the project's real `Button`. A from-scratch dropdown with no keyboard support beside an installed primitive that has it. A 14-class `Tailwind` string copy-pasted onto every card instead of the component or token that's right there.

### Controls: native → primitive → hand-roll

1. Native `HTML` first where it works. A `<button>` is a button; an `<a>` is a link; `<input type="text">`, `<dialog>`, `<details>` exist. Never `<div onClick>` something the platform already provides, you lose focus, keyboard, and semantics for free.
2. A battle-tested headless primitive for anything stateful and hard to get right, select, combobox, dialog, popover, tooltip, dropdown menu, tabs, date picker. These ship keyboard navigation, focus management, `ARIA`, and collision/positioning that take days to reproduce.
3. Hand-roll only as a genuine last resort, no primitive fits, or there's no dependency budget. Then you owe the complete behavior contract: keyboard nav, focus trap/return, full `ARIA` roles and state, click-outside, and scroll-lock for overlays. A styled control missing these is broken.

### Styling: system → component → token → utility

1. If the project has a design system, use it. `shadcn/Button`, a `CVA` variant set, a theme, a component library, use `<Button variant="…">` before writing a one-off. Match the codebase's styling convention.
2. When a styled element repeats, extract a component. The same utility string on nine buttons is duplication, not design. One component owns it; call sites stay clean. Extract on the second real reuse, not the first.
3. Bind to semantic tokens, not hardcoded literals. `bg-card border-border text-muted-foreground`, not `bg-white border-gray-200 text-gray-500`. Hardcoded raw values break theming and dark mode.
4. Inline utilities are for genuine one-offs, a layout nudge used once. The tell of slop is the same long className sprayed everywhere; that's a missing component or token.

## 11. Design System Essentials

- Token architecture. Every color traces to a small set of primitives: foreground (text), background (surface), border, brand, semantic (destructive/warning/success). No random hex.
- Text hierarchy, four levels. Primary, secondary, tertiary, muted (default / supporting / metadata / disabled). Using only two means the hierarchy is too flat.
- Spacing. Pick a base unit (4 or 8px), use multiples only. Scale by context: micro (icon gaps), component (within buttons/cards), section (between groups), major (between areas).
- Padding. Symmetrical, if one side has a value, the others match unless content genuinely demands asymmetry.
- Depth, choose ONE and commit. Borders-only (clean, technical, dense tools) · subtle shadows (approachable) · layered shadows (premium, dimensional) · surface-color shifts (tints, no shadows). Don't mix strategies.
- Border radius, a scale. Small for inputs/buttons, medium for cards, large for modals. Don't mix sharp and soft randomly.
- Control tokens. Inputs/selects/checkboxes get dedicated background, border, and focus tokens, don't reuse surface tokens, so you can tune controls independently.
- Dark mode. Shadows are weak on dark, lean on borders. Desaturate semantic colors slightly. Same hierarchy system, inverted values. Keep one hue; shift only lightness across surfaces.

## 12. Polish and Motion

A hundred small details compound into "feels great."

### Static polish

- Concentric radius. Nested rounded elements: `outerRadius = innerRadius + padding`. Same radius on parent and child is the most common thing that makes UI feel off.
- Tabular numbers. Any dynamic number (counters, prices, timers, table columns) gets `font-variant-numeric: tabular-nums` to prevent layout shift.
- Optical alignment. When geometric centering looks off, fix it optically, icon-side padding ≈ text-side − 2px; nudge play triangles ~2px right.
- States are not optional. Every interactive element needs default, hover, active, focus, disabled. Data needs loading, empty, error. Missing states feel broken.
- Hit areas, 44×44px (`WCAG`), 40 at minimum. If the visible control is smaller (a 20px checkbox), extend with a pseudo-element. Never let two hit areas overlap.
- Shadows over borders for elevation. For cards/buttons/containers that lift, prefer a layered transparent `box-shadow`; keep real borders for dividers and input outlines. Light-mode lift stacks three layers; dark mode collapses to a single ring.
- Text wrapping. `text-wrap: balance` on headings; `text-wrap: pretty` on body/captions to kill orphans.
- Font smoothing. `-webkit-font-smoothing: antialiased` on the root (macOS renders heavy otherwise).
- Image outlines. 1px inset outline, pure `rgba(0,0,0,0.1)` light / `rgba(255,255,255,0.1)` dark, never a tinted near-black/white.

### Motion

Motion should be felt, not watched. Fast, purposeful, and never in the way.

- Should it animate at all? Actions repeated 100+×/day (keyboard shortcuts, command palette) get no animation, it makes them feel slow. Occasional surfaces (modals, drawers, toasts) get standard animation. Rare/first-run moments can add delight.
- Duration < 300ms for UI. Button press 100–160ms; tooltips/popovers 125–200ms; dropdowns 150–250ms; modals/drawers 200–500ms.
- Custom ease-out, never ease-in. Built-in curves are too weak. Use `cubic-bezier(0.23, 1, 0.32, 1)` for entering/interactive; ease-in-out for on-screen movement. `ease-in` feels sluggish.
- Press feedback. `transform: scale(0.97)` on `:active` (never below 0.95).
- Never animate from `scale(0)`. Start at `scale(0.95)` + `opacity: 0`.
- Origin-aware popovers. Popovers scale from their trigger, not center. Modals are the exception.
- Only animate `transform` and `opacity` (`GPU`-composited). Animating width/height triggers layout + paint. Never `transition: all`, name exact properties.
- Stagger entrances 30–80ms between items for a natural cascade; keep exits faster and subtler than enters.
- Respect `prefers-reduced-motion`, keep opacity/color transitions, drop movement.

## 13. Design System Persistence

After completing a task, always offer to save the patterns: "Want me to save these for future sessions?" If yes, write to `.interface-design/system.md`:

- Direction and feel
- Depth strategy (borders/shadows/layered) and spacing base unit
- Hierarchy decisions (type scale ratio, density values, focal pattern)
- Key component patterns, record when a component is used 2+ times, is reusable, or has measurements worth remembering

Consistency checks. If `system.md` defines values, hold to them: spacing on the grid, the declared depth strategy throughout, colors from the palette, documented patterns reused not reinvented. This compounds, each save makes future work faster and more consistent.

## 14. The Checks

Run these against your output before presenting; if any fails, iterate first.

- Swap test, swap your typeface for the usual one, your layout for a standard template: would anything feel different? Where swapping wouldn't matter is where you defaulted.
- Squint test, blur your eyes: hierarchy still readable? Nothing jumping out harshly?
- Signature test, point to five specific elements where your signature appears. "The overall feel" doesn't count.
- Token test, read your `CSS` variables aloud: do they belong to this product's world, or any project?

## 15. Suggest and Ask

Lead with exploration and recommendation, then confirm:

```
Domain: [5+ concepts from the product's world]
Color world: [5+ colors that exist in this domain]
Signature: [one element unique to this product]
Rejecting: [default 1] → [alternative], [default 2] → [alternative], [default 3] → [alternative]
Direction: [approach connecting to the above]
```

Then ask: "Does that direction feel right?"

## Rules

- Do not announce modes or narrate process. Jump into the work; state suggestions with reasoning.
- Inspect the existing app, design tokens, component patterns, and `.interface-design/system.md` if present before proposing anything.
- Make the domain exploration concrete before choosing layout, color, type, density, and navigation.
- Keep user-facing updates short. Don't expose long private design monologues, surface the useful recommendation or decision.
- Harsh borders, dramatic surface jumps, flat hierarchy, monotone layout, inconsistent spacing, mixed depth strategies, missing states, dramatic drop shadows, large radius on small elements, gradients for decoration, multiple accent colors, different hues for different surfaces, and default typography are all signs of defaults winning. Catch them and fix them.
