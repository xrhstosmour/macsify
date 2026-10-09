---
name: eli5
description: >
  Explain a concept, error, or code in dead-simple terms, by default as to a 5 year
  old, or at a named audience level. Use for "ELI5", "explain like I'm...", "I don't
  understand this", "break this down", "dumb this down", or going deeper or simpler.
---

# ELI5

## When to use

- User says "ELI5", "explain like I'm 5", "explain this to my `<person>`", "I don't get this", "break this down", "dumb it down", or "explain this simply".
- User points at code or an error and says they don't understand it.
- User asks for an explanation that sounds like they already know the topic, for example to relay it to someone else with confidence.
- User says "go deeper" or "make it simpler" right after an ELI5 explanation.

If no audience is named, default to age 5. That is the primary mode of this skill.

## Step 1: Pick the audience

| Audience | Voice |
|---|---|
| Age 5 (default) | Zero jargon. Toy, animal, food, playground analogies. Short sentences. Playful, like a favorite teacher. |
| Age 10-15 | Elementary/teen level. School, sports, video game, phone analogies. Can handle basic cause and effect. |
| Adult, non-technical | Clear and direct. Daily life, money, home analogies. No condescension. |
| Engineer / technical | Proper terminology, no hand-holding. Focus on the interesting parts: trade-offs, edge cases, design decisions. |
| Manager / non-engineer stakeholder | Lead with impact, timeline, risk, cost. Skip implementation detail unless asked. |
| Confident/expert mode | User asks to explain "like I have knowledge in it" or wants to relay it to someone else. Write fluent, correctly-termed, first-person-ready prose, not simplified, just clear and usable as-is. |

## Step 2: Read the source first

For code or an error, read the actual file or output before explaining. Understand the root cause, not just the surface text. Never paraphrase from a file name, function name, or guess.

## Step 3: Write the explanation

1. One line: what it is.
2. One analogy the audience already understands.
3. Layer in detail, only as deep as the audience needs.
4. Close with why it matters to them specifically.

Match length to the audience: short for age 5, more detail for technical or confident-mode requests.

## Optional: visual explanation

Text is the default output. Only reach for a picture when the user explicitly asks for something visual, "show me", "draw it", "picture", "diagram", or when the concept is inherently spatial or relational, layout, flow, hierarchy, timing, and no analogy or paragraph conveys it as clearly as a picture would.

When that applies, load the `artifact-design` skill first, and `artifact-diagramming` too if the picture is a diagram or flow, then publish a small self-contained HTML page via the `Artifact` tool: big shapes, minimal text, one idea per screen. Skip this for anything that reads fine as prose, most ELI5 requests do.

## Follow-up

"Go deeper" moves one row down the audience table, more terminology, more layers, closer to how it actually works. "Make it simpler" moves one row up, toward age 5. Adjust the same explanation, don't start over from scratch or ask which direction, the two phrases already say it. Already at an edge row, engineer/technical for "go deeper" or age 5 for "make it simpler", stay on that row and add or strip detail within it instead of moving further.

## Boundaries

ELI5 voice applies only to explanations and commentary. Code blocks, commit messages, and PR descriptions are always written normally, never simplified or made playful.

## Tone note

While explaining, drop the usual terse house style, playful analogies and a warmer voice are the point here, the same way the `caveman` skill overrides tone for its own mode. Once the explanation is delivered, resume the normal style for anything else in the response.

## Auto-clarity exception

Suspend the ELI5 voice for security warnings, irreversible-action confirmations, and any step where a wrong read could cause real damage. Also suspend it if the user asks the exact same question again in the same words, not a "go deeper"/"make it simpler" follow-up, that repeat is a sign the simplification didn't land, answer plainly instead. Resume ELI5 once the critical part is past.

## Examples

**"ELI5 what a database index is"**
Imagine a huge book with a thousand pages. Want to find the page about dinosaurs? You could flip through every page, or check the table of contents at the front. A database index is that table of contents, it helps the computer find things fast without checking every single row.

**"Explain this rate limiter like I already know it, I need to tell my team"**
This endpoint caps clients at 100 requests per minute using a sliding-window counter in Redis. Once a key crosses the threshold it gets a 429 until the window rolls over. It protects the downstream database from bursty traffic without needing a queue in front of it.
