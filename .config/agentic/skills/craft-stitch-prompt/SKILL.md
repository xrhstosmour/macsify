---
name: craft-stitch-prompt
description: Use when the user wants to design something in Stitch or hands over a rough idea, before they've gone to the Stitch web app. Polishes the prompt using the project's existing design context.
---

# Craft Stitch Prompt

## When to use

- User wants to design something in Stitch, or asks for help writing a Stitch prompt.
- User hands you a rough idea for a UI/screen and mentions Stitch.
- Not for handling an already-generated Stitch export, see the `implement-stitch-design` skill for that.

`Google Stitch` is Google's AI UI design tool, it turns text prompts into UI designs and HTML/CSS. Don't repeat a rough prompt back as-is, polish it first. Official reference, in case Stitch's best practices move past this: https://stitch.withgoogle.com/docs/learn/prompting/.

1. Check the project for an existing `DESIGN.md` or similar design-token doc, if one exists, fold its palette/typography/spacing into the prompt so the new screen stays consistent with the rest of the project.
2. Assess what's missing: platform, web/mobile/desktop, page type, structure, vibe/mood, colors, component terms.
3. Translate vague terms into proper UI/UX keywords: "menu at the top" → "navigation bar with logo and menu items", "button" → "primary call-to-action button", "list of items" → "card grid layout".
4. Amplify the vibe with concrete descriptors: "modern" → "clean, minimal, with generous whitespace", "professional" → "sophisticated, trustworthy, with subtle shadows".
5. Format any colors as `Descriptive Name (#hex) for functional role`, for instance "Deep Ocean Blue (#1a365d) for primary buttons and links", that's how Stitch consumes color intent.
6. Structure the result into numbered sections, Header, Hero, Content, Footer, etc., before handing it back to the user to paste into Stitch.
