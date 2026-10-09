---
name: humanize
description: >
  Rewrite AI-sounding text as natural human writing, in English or Greek, keeping
  facts, names, numbers, quotes, code, and register. Use for "humanize this",
  "less AI", "sound less robotic", "ανθρωποποίησε αυτό το κείμενο", or pasted text
  to de-AI.
---

# Humanize

## When to use

- `/humanize`
- User says "humanize this", "make this sound less AI", "make this sound more human", "sound less robotic", "remove AI tells", "de-AI this", "rewrite this so it doesn't sound like ChatGPT".
- Greek equivalents: "ανθρωποποίησε αυτό το κείμενο", "κάνε το πιο ανθρώπινο", "να μην ακούγεται σαν να το έγραψε AI", "αφαίρεσε τα σημάδια AI".
- User pastes a paragraph, email, post, or document and asks it to sound less generated, without asking for a summary or a translation.

Not for: translating between languages, summarizing, or rewriting Claude's own live chat replies, `~/.config/agentic/instructions/communication.md` already governs that. This skill targets arbitrary text the user hands over, in English or Greek.

## Step 1: Detect the language

English, Greek, or mixed (a Greek document with English technical terms is common, treat it as Greek and leave the embedded English terms alone). If the text is in neither language, say so and ask before proceeding.

## Step 2: Infer the register

Formal email, casual message, blog post, technical doc, social post, and so on. Infer from context and any surrounding conversation. Ask only if genuinely ambiguous, for example the text could plausibly be either a formal client email or a casual internal note and the difference would change the rewrite significantly.

## Step 3: Preserve untouched content

Facts, claims, names, numbers, dates, quotes, code blocks, links, technical terms, and any structure the user explicitly needs (required headings, a form template, SEO keywords). Rewriting is about voice and rhythm, not content.

## Step 4: Apply the checklist

Use the checklist for the detected language, below.

## Step 5: Vary rhythm deliberately

Mix short and long sentences, allow a fragment where a person would naturally use one, break up any leftover uniform three-item pattern.

## Step 6: Final pass

Before returning the rewrite, scan it once more against the checklist for anything that slipped through. A rewrite that still opens with "Moreover" or "Επιπλέον" hasn't been humanized.

Never fabricate new facts, examples, or personal anecdotes the user didn't supply. Restructure and rephrase only.

## English tells checklist

**Buzzwords and vague abstraction**, cut or replace with concrete plain words:
`delve into`, `dive into`, `unpack`, `navigate`, `landscape`, `realm`, `tapestry`, `leverage`, `utilize`, `robust`, `seamless`, `holistic`, `synergy`, `paradigm`, `cutting-edge`, `game-changer`, `unlock`, `elevate`, `empower`, `harness`, `foster`, `bolster`, `underscore`, `comprehensive`, `multifaceted`, `nuanced`, `vibrant`, `dynamic`, `in today's fast-paced world`, `in the ever-evolving landscape of`, `at the end of the day`.

**Structural tells and their fix:**
- Rule-of-three overload (always exactly three examples or adjectives) → use one, two, or four, whatever the content actually calls for.
- "Not only X, but also Y" and other overly balanced parallel constructions → say it plainly, in one direction.
- Paragraphs opening with `Moreover`, `Furthermore`, `Additionally`, `In conclusion`, `Overall` → cut the transition word, let the idea start the sentence.
- Bullet-itis, turning every list into bullets or adding headers to short conversational text → let prose carry it when the original context is conversational.
- Uniform sentence length with no short punchy sentences → vary it.
- Hedging padding: "it's worth noting", "it is important to note that", "it should be noted", "this can vary depending on" → state the thing directly.
- Empty intensifiers: `very`, `quite`, `extremely`, `significantly`, `truly` → cut or replace with a specific detail.
- Closing platitudes: "I hope this helps!", "feel free to reach out", "let me know if you have any questions" → cut unless the register genuinely needs a warm sign-off.
- Emoji sprinkled for emphasis (✅ 🚀 💡) → remove unless the source text already used them that way.
- Passive voice used for false objectivity where a person would just name the actor → make it active.

## Greek tells checklist

**Formal/bureaucratic filler**, cut or replace with plainer phrasing:
`αξίζει να σημειωθεί ότι`, `είναι σημαντικό να τονιστεί ότι`, `διαδραματίζει καθοριστικό/σημαντικό ρόλο`, `αποτελεί ζωτικής σημασίας παράγοντα`, `στο πλαίσιο αυτό`, `στη σημερινή εποχή`, `στον σύγχρονο κόσμο`, `καίριας σημασίας`, `εν κατακλείδι`, `συμπερασματικά`, `εξίσου σημαντικό είναι ότι`.

**Structural tells and their fix:**
- Impersonal/passive padding used for false objectivity: `γίνεται αντιληπτό ότι`, `παρατηρείται ότι`, `θα πρέπει να σημειωθεί ότι` → restore an active voice with a clear subject.
- Heavy nominalizations replacing a plain verb: `η πραγματοποίηση`, `η υλοποίηση`, `η διεξαγωγή` used instead of just conjugating the verb → turn the noun back into the verb it's hiding.
- Literal calques of English AI phrasing, unnatural in Greek: `στο τέλος της ημέρας` (at the end of the day), `ξεκλειδώστε τη δυναμική` (unlock the potential), `αλλάξει τους κανόνες του παιχνιδιού` (game-changer) → use a natural Greek idiom or drop the flourish.
- Overuse of `καθώς` and `ενώ` to stitch together unrelated clauses for a sophisticated sound → split into separate sentences or use a plainer connector.
- Formal impersonal-plural voice ("θα εξετάσουμε", "ας δούμε") in text that should be first-person and casual → match the actual voice of the piece.
- Long, comma-heavy, uniform sentences with no natural fragment or run-on variance → vary sentence length.
- Missing colloquial particles and contractions a real Greek writer uses in casual register: `δηλαδή`, `βασικά`, `ας πούμε`, `μάλλον`, `κάπως`, `θα 'ναι` instead of `θα είναι` → add them back when the register is casual, never in a formal document.
- Balanced parallel construction `δεν είναι μόνο [X], αλλά και [Y]` (the Greek calque of "not only X but also Y") → say it plainly, in one direction.
- Same generic sentence-opener reused across paragraphs as a crutch, `με άλλα λόγια`, `κατά κανόνα`, `για παράδειγμα`, `το πρόβλημα, βέβαια, είναι` → vary the opener or cut it, let the idea start the sentence.
- Overuse of the em dash (`—`) to introduce a mid-sentence clarification and the colon (`:`) to join two closely related independent clauses, both grammatically correct but rare in everyday Greek writing → prefer a period, comma, or parentheses instead.

## Worked examples

**English, before:**
> In today's fast-paced world, it is important to note that effective communication plays a crucial role in team success. Not only does it foster collaboration, but it also helps to build trust and unlock better outcomes for everyone involved.

**English, after:**
> Teams that communicate well work better together. It builds trust, and that trust is what makes good outcomes possible.

**Greek, before:**
> Στη σημερινή εποχή, αξίζει να σημειωθεί ότι η αποτελεσματική επικοινωνία διαδραματίζει καθοριστικό ρόλο στην επιτυχία μιας ομάδας. Επιπλέον, συμβάλλει στην οικοδόμηση εμπιστοσύνης και στην επίτευξη καλύτερων αποτελεσμάτων για όλους.

**Greek, after:**
> Οι ομάδες που επικοινωνούν καλά δουλεύουν καλύτερα μαζί. Χτίζουν εμπιστοσύνη, και αυτή είναι που φέρνει καλά αποτελέσματα.

## Guardrails

- Never change facts, numbers, names, technical terms, code, or direct quotes.
- Never invent personal anecdotes or experiences the user didn't supply, adding "I remember when..." to a piece the user has no such story for is fabrication, not humanizing.
- Match the requested register. A formal, legal, or medical document should read less stiff, not less formal, keep its formality while cutting the AI filler.
- If the user needs a specific structure kept (required headings, a template, SEO keywords), keep it and humanize the prose within it.
- Ask only when the register is genuinely ambiguous. Don't ask when a reasonable default is obvious from context.
