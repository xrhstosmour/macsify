---
name: promo-video
description: Turn the current project into a short launch video, planned with the user and rendered locally from HTML scenes with Chrome and ffmpeg. Use for "make a launch video", "promo video", "brag about this".
model: claude-opus-5-5
effort: high
---

# Promo Video

Turn the project in front of you into a 15-25 second launch video worth sharing, one that looks like the project made it.

Planning, taste, and composition live here. The pipeline needs no installed packages: scenes are HTML rendered to PNG by headless Chrome, and `ffmpeg` adds the motion, transitions, and overlays. Everything runs locally, nothing is uploaded.

## Non-negotiables

- Their design wins. Every visual rule comes from the project: its tokens, components, rules files, landing page, and copy. Never carry another product's taste in, including anything in this skill that the project's own design contradicts.
- Ask, don't assume. What the video shows is the user's call. Run the interview in Step 2 before writing the plan, and draw every option from what Step 1 actually found in the code, never from a generic list.
- Honest claims. Show only what the project really does. A feature that is stubbed, planned, or behind a flag does not go in the video.
- Ask before publishing. Never commit, push, or post the output without being asked. Keep every rendered version rather than overwriting one.

## Requirements

- Python 3, `ffmpeg`, and a Chromium based browser (Chrome, Chromium, or Edge), on macOS, Linux, or Windows. The script uses only the Python standard library and reports a missing `ffmpeg` or browser itself (set `CHROME` to a binary to override the lookup). If anything is missing, report it and stop, don't install anything yourself.
- `ffmpeg` builds often lack the `drawtext` and `subtitles` filters, so never rely on them. All text lives in the HTML scenes and layers.
- Music is only used when the user supplies a file. Never download audio.

## Output directory

Default to `promo-output/`. If it already exists from a previous run, use a timestamped variant instead so nothing gets overwritten: `promo-output-YYYY-MM-DD-HHmmss/`. Generate the timestamp once at the start of the run and reuse it for every file below. Renders go into numbered subdirectories, `v1/`, `v2/`, so an earlier cut is always still there to compare against. Scene files go in `<output-dir>/build/`.

## Step 1: Discover the project

Read, in priority order:

- Rules and context files: `AGENTS.md`, `CLAUDE.md`, `README.md`, anything in `.agents/`. These carry the project's own vocabulary and any claims policy.
- The entry point or landing page: `index.html`, the main route, or the README "usage" section.
- Design tokens and the stylesheet: CSS custom properties, a Tailwind or theme config, a tokens file.
- The real components a user touches, not wrappers or layout scaffolding.
- The logo, wordmark, or mascot, and the manifest (`package.json` or equivalent).

Answer before moving on:

1. What does the project do, in one sentence?
2. What is the single strongest claim or line worth building the hook around, and is it one the project can actually back?
3. What is the real user flow worth showing: entry, key action, result? If this is a landing-page-only site with no app behind it, say so and fall back to its strongest visual instead.
4. What is the visual identity: background, text, and accent colors (from CSS custom properties or tokens if present), display font, body font, corner radius, border and shadow treatment?
5. Which named features and components are real and shippable today? This list becomes the interview's options, so keep it concrete.
6. What should the share caption say, one punchy sentence?

## Step 2: Interview the user

Two rounds of `AskUserQuestion`, each option named after something Step 1 actually found. A third round only if something is still genuinely unresolved.

Round one, the brief:

- Where it plays: social post, landing-page loop, README embed, conference screen. This sets the frame size, 1920x1080 by default, 1080x1920 for vertical.
- Target duration inside the 15-25 second window.
- Music, or silent. A landing-page loop has to read muted either way.
- Which two or three of the real features from Step 1 to show.

Round two, the ingredients, all optional:

- A logo or wordmark scene, or the mascot if the project has one.
- Word-by-word punchlines, plain captions, or no words at all.
- Transitions: cuts, fades, wipes, or slow camera moves.
- Extras: real screenshots of the running project, proof moments such as real output, the project's own background texture.

## Step 3: Write the brand kit and the plan

Write `<output-dir>/BRAND.md` from Step 1 plus the interview answers: colors as literal token values, fonts, radius and border treatment, logo path, tone of voice, the approved claims, and the things never to show. BRAND.md overrides every default in this skill. If the two disagree, BRAND.md wins.

Write `<output-dir>/plan.md`: the angle (the specific hook for this project, not a generic one), the hook (first 2-3 seconds), the key moments pulled from the real user flow over generic landing-page recreations, the punchline or outro line, format and target duration, and the share-copy draft.

Pick a tone and record it in the plan:

| Tone | Energy | Pacing |
|---|---|---|
| `default` | Playful, clean, postable | 4-5 scenes, comfortable holds |
| `polished` | Serious, elegant, restrained | 3-4 scenes, slow reveals |
| `deadpan` | Calm, dry, plays it completely straight | 3-4 scenes, long holds |
| `cinematic` | Dramatic, trailer-scale | 4-5 scenes, wide dramatic reveals |

Check in with the user on the beat sheet before anything gets built.

Gate: scene durations in the plan sum to 15-25 seconds.

## Step 4: Build the scenes

One self-contained HTML file per scene in `<output-dir>/build/`, sized to the frame, no network requests, BRAND.md tokens as CSS custom properties, system fonts or local `@font-face` files.

- Background scenes: the full frame, opaque.
- Animated elements, such as a badge, a punchline, or one word of a word-by-word reveal: a separate layer file with a transparent background. One layer per element that must move or appear on its own.
- Real UI: screenshot the running project and use the PNG as a scene background (a `.png` works in the spec as well as an `.html`). Never mock up a screen the project does not have.

Keep each HTML file small, one scene or one element, so a fix means rewriting one short file. Never hand-write a Chrome or ffmpeg command, the bundled script does both.

## Step 5: Render

Write `<output-dir>/build/spec.txt` listing the HTML files, the script captures each to a PNG with headless Chrome (layers transparent, unchanged files reused) and composes the video:

```text
size 1920x1080
fps 30
transition fade 0.8
fadeout 0.6
scene scene1.html 5
scene scene2.html 5
layer badge.html 5.4 3.6 slide
```

Scenes play in order, each with a slow zoom and a crossfade into the next (`transition` takes any `xfade` name such as `wipeleft`, `slideleft`, `circleopen`, `dissolve`). A `layer` shows from a start second for a duration, `fade` or `slide`. Use `fadeout 0` for a loop. Run it:

```bash
python3 ~/.config/agentic/skills/promo-video/scripts/promo.py <output-dir>/build/spec.txt <output-dir>/v<n>/promo.mp4
```

On Windows use `python` instead of `python3`.

Word-by-word reveals are one transparent layer per word with staggered start times. Music, only if the user supplied a file, is added after rendering: `ffmpeg -y -i promo.mp4 -i <music> -c:v copy -af afade=t=out:st=<length minus 1>:d=1 -shortest promo-music.mp4`.

Motion is limited to zoom, slide, fade, crossfade, and wipe, plus layered elements. If the brief needs more, such as kinetic type or 3D, tell the user instead of faking it.

Gate: the script prints the rendered length, 15-25 seconds.

## Step 6: Review before delivering

Never deliver the first render. Each image read costs tokens, so look at one small contact sheet per round, never single frames. Pick 4 to 6 frame numbers, one mid-scene per scene and one mid-transition (frame = seconds times fps):

```bash
ffmpeg -y -i <file> -vf "select='eq(n,15)+eq(n,138)+eq(n,210)+eq(n,270)',scale=480:270,tile=2x2" -frames:v 1 <output-dir>/v<n>/sheet.png
```

Read the image, check the frames against the quality floor below, fix what fails (rewrite only the one HTML file that is wrong, then rerun the script), then show the user the sheet and wait. Repeat until they are happy. Three rounds without converging means something in the plan is wrong, go back to Step 3 rather than nudging pixels.

## Step 7: Deliver

Render to `<output-dir>/v<n>/promo.mp4`. Pick a genuine best frame as the poster, not an arbitrary one: `ffmpeg -y -ss <seconds> -i promo.mp4 -frames:v 1 promo.jpg` into the same directory. Write the final share line to `<output-dir>/share-copy.txt`.

Gate: `<output-dir>/v<n>/promo.mp4`, `<output-dir>/v<n>/promo.jpg`, and `<output-dir>/share-copy.txt` all exist.

## Quality floor

Applies to every video, whatever the tone and ingredients:

- Readable at the delivery size. Fewer words beat smaller words. Cut any label that restates the picture.
- Long enough to read. Every scene a viewer must read needs enough settled (fully visible, not entering or exiting) time: a short label about 0.8s, a full sentence about 0.3s per word. Pace comes from fast cuts and transitions, never from pulling text before it's readable.
- Text is never covered by another layer, and never crosses other text during a move. A line never re-centers while it builds, so keep each word's slot.
- Only the project's own surfaces. Its colors, borders, radii, and shades. Never invent a card background, outline, or tint it does not use.
- Loading and empty states keep their width, using the project's own pattern, so nothing reflows mid-scene.
- Something happens on every beat. A stretch where nothing moves reads as broken, not as restraint.
- A loop's last frame equals its first, and a landing-page loop reads with the sound off.
- No effects the project's visual language does not already use: glows, particles, click rings, bouncy easing, shaders.
