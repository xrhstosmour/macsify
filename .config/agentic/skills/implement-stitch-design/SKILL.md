---
name: implement-stitch-design
description: Use when the user hands off a Stitch export, HTML/CSS, or screenshot and asks to build or match it in the project.
---

# Implement Stitch Design

## When to use

- User pastes/attaches a Stitch export (HTML/CSS or screenshot) and asks to build matching UI.
- User saved a Stitch export to a file and asks you to build from it.
- Not for writing a new Stitch prompt before design, see the `craft-stitch-prompt` skill for that.

The user designs in the Stitch web app themselves, then hands the result to the agent one of these ways:

- Pastes the exported HTML/CSS directly into the chat.
- Saves the exported HTML to a file in the repo and tells the agent which path to read.
- Attaches/pastes a screenshot of the design and asks the agent to build UI to match it visually.

Do not ask the user to authenticate, generate an API key, or set up any credential for this, there's nothing to configure.

Stitch designs are static layouts. Hover states, animations, validation, and state management are not part of the export and need to be implemented separately.

Stitch exports use `Tailwind` utility classes by default. If the project doesn't already use `Tailwind`, translate the export to the project's actual styling approach, don't introduce `Tailwind` as a new dependency just because the pasted HTML happens to use it.
