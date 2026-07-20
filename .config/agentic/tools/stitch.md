# Stitch

`Google Stitch` is Google's AI UI design tool, it turns text prompts into UI designs and HTML/CSS.

## Required behavior

- The user designs in the Stitch web app themselves, then hands the result to the agent one of these ways:
  - Pastes the exported HTML/CSS directly into the chat.
  - Saves the exported HTML to a file in the repo and tells the agent which path to read.
  - Attaches/pastes a screenshot of the design and asks the agent to build UI to match it visually.
- Do not ask the user to authenticate, generate an API key, or set up any credential for this, there's nothing to configure.
- Stitch designs are static layouts. Hover states, animations, validation, and state management are not part of the export and need to be implemented separately.
- Stitch exports use `Tailwind` utility classes by default. If the project doesn't already use `Tailwind`, translate the export to the project's actual styling approach, don't introduce `Tailwind` as a new dependency just because the pasted HTML happens to use it.

## Prompt Crafting

When the user wants to design something in Stitch, or hands you a rough prompt, don't repeat it back as-is, polish it first. Official reference, in case Stitch's best practices move past this: https://stitch.withgoogle.com/docs/learn/prompting/.

1. Check the project for an existing `DESIGN.md` or similar design-token doc, if one exists, fold its palette/typography/spacing into the prompt so the new screen stays consistent with the rest of the project.
2. Assess what's missing: platform (web/mobile/desktop), page type, structure, vibe/mood, colors, component terms.
3. Translate vague terms into proper UI/UX keywords: "menu at the top" → "navigation bar with logo and menu items", "button" → "primary call-to-action button", "list of items" → "card grid layout".
4. Amplify the vibe with concrete descriptors: "modern" → "clean, minimal, with generous whitespace", "professional" → "sophisticated, trustworthy, with subtle shadows".
5. Format any colors as `Descriptive Name (#hex) for functional role`, e.g. "Deep Ocean Blue (#1a365d) for primary buttons and links", that's how Stitch consumes color intent.
6. Structure the result into numbered sections (Header, Hero, Content, Footer, etc.) before handing it back to the user to paste into Stitch.
