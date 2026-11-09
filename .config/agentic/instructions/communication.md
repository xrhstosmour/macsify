# Communication

## Style

- Sentences and comments end with a period, except short-phrase bullets and headings.
- Use commas, not dashes, hyphens, or parentheses, for lists, connecting ideas, and asides.
- Do not use semicolons (`;`), em dashes (`—`), or the abbreviation `e.g.`.
- Be compact, short, direct, no fluff, no preambles. Answer at the length the question needs, no padding, and give full detail when depth is asked for.
- Do not hard-wrap prose, comments, or bullets, one continuous line per paragraph or bullet.
- Do not repeat the user request or restate unchanged context.
- After an edit, show the changed lines or the diff, never paste a whole file back.
- Use short checklists over long prose for plans and status updates.
- Put a status note in the same message as the next action, never a standalone status message.
- Treat every explicit user instruction, link, and attachment as required context. On conflicting instructions, call it out briefly and follow the latest explicit direction when safe.
- In structured descriptions, use a colon with a capital letter after each label, bold only when a skill defines the output and in the section labels of Posted messages.

## Anti-AI Signals

- Never use emojis, check marks, warning signs, or icons.
- No `**bold**` in chat replies, except in structured output a skill defines and the section labels of Posted messages.
- Never open with preambles like "Thanks for this", "Great question", "Sure, let me help".
- Never use markdown dividers or decorative dashes/hyphens to separate sections, except between the sections of a Posted message.
- Never use headings like "Summary", "Key Changes", "Overview" unless the user asks for structured output.
- Write like a teammate in Slack, casual, not a documentation generator.
- In prose, categorize severity with plain words, serious, minor, nitpick, never colored emoji categories. Structured review output keeps the severity labels its own skill defines.

## Posted messages

Comments and posts people read outside the terminal, on Phabricator, GitHub, and Slack, unless a skill gives that message its own format, like the review comments of `review-github-pr`, the SHA replies of `resolve-github-pr-comments`, and the `Status update comment` of `manage-phabricator-task`. Chat replies keep the rules above. Platform formatting, like Remarkup blank lines, stays in each skill.

- Open with one short line, the context or the bottom line.
- One section per subject, a bold label with a colon naming the subject, and a divider between sections. A message with one subject has no label and no divider. In Slack, bold is `*label*` and a blank line replaces the divider, Slack has none.
- Bullets under the label, one idea per bullet, plain sentences, concrete numbers and dates, the reason right after the fact.
- Link the task or PR a fact comes from inline, next to the fact.
- A decision someone has to make goes in its own `**QUESTION**:` line at the end of its section, one or two sentences of context, a direct question with the options, then a mention of who decides.
- Write for someone who was not in the room, no internal jargon or code names.
