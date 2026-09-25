---
name: promo-video
description: Turn the current project into a short, shareable launch video. Plans the story, tone, and storyboard, then renders it locally with the free, open-source Hyperframes CLI (`npx hyperframes`, Apache-2.0, no account or fees). Use when the user says "make a launch video", "promo video", "brag about this", "turn this into a video", or wants to share what they built.
---

# Promo Video

Turn the project in front of you into a 15-25 second launch video worth sharing.

Planning and taste live here. Composition, animation timing, and audio sourcing are delegated to [Hyperframes](https://github.com/heygen-com/hyperframes), a separately maintained, Apache-2.0, fully local renderer (headless Chromium + `ffmpeg`, no account, no per-render fee). Its creation skills are vendored into this repository alongside this one, see "Vendored Hyperframes skills" below. The renderer itself is never installed persistently, every invocation goes through `npx`.

## Requirements

- Node.js 22+ and `ffmpeg` on `PATH`.
- Check readiness before starting: `npx hyperframes doctor`. If it fails, report the missing piece and stop, don't try to install `ffmpeg` or Node yourself.

## Output directory

Default to `promo-output/`. If it already exists from a previous run, use a timestamped variant instead so nothing gets overwritten: `promo-output-YYYY-MM-DD-HHmmss/`. Generate the timestamp once at the start of the run and reuse it for every file below.

## Step 1: Inspect the project

Read, in priority order: the app's entry point or landing page (`index.html`, main route, or README "usage" section), its stylesheet or design tokens, `package.json` or equivalent manifest, and the 2-3 screens or components a real user actually touches.

Answer before moving on:

1. What does the project do, in one sentence?
2. What is the single strongest claim or line worth building the hook around?
3. What is the real user flow worth showing: entry, key action, result? If this is a landing-page-only site with no app behind it, say so and fall back to its strongest visual instead.
4. What is the visual identity: background, text, and accent colors (from CSS custom properties or tokens if present), display font, body font?
5. What is the shortest video that still lands the point, 15 to 25 seconds?
6. What should the share caption say, one punchy sentence?

## Step 2: Write the plan

Write `<output-dir>/plan.md`: the angle (the specific hook for this project, not a generic one), the hook (first 2-3 seconds), 2-3 key moments pulled from the real user flow over generic landing-page recreations, the punchline or outro line, the visual identity from Step 1, format and target duration, and the share-copy draft.

Pick a tone and record it in the plan:

| Tone | Energy | Pacing |
|---|---|---|
| `default` | Playful, clean, postable | 4-5 scenes, comfortable holds |
| `polished` | Serious, elegant, restrained | 3-4 scenes, slow reveals |
| `deadpan` | Calm, dry, plays it completely straight | 3-4 scenes, long holds |
| `cinematic` | Dramatic, trailer-scale | 4-5 scenes, wide dramatic reveals |

Every scene a viewer must read needs enough settled (fully visible, not entering or exiting) time to actually read it: a short label needs about 0.8s, a full sentence about 0.3s per word. Pace comes from fast cuts and transitions, never from pulling text before it's readable.

**Gate**: scene durations in the plan sum to 15-25 seconds.

## Step 3: Hand off to Hyperframes

Hyperframes' creation skills are already installed, including the `product-launch-video` and `general-video` workflows, so there is nothing to fetch. Do not run `npx hyperframes skills update`, including the named form the vendored `hyperframes` skill itself tells you to run: it rewrites the installed skill tree other tools read from, and that tree is a copy of this repository, not this checkout, so the divergence leaves no trace in `git status` here. See "Vendored Hyperframes skills" below for what to do if it runs anyway.

Follow `/product-launch-video` (or `/general-video` if Step 1 found no marketing site to draw from), handing it `<output-dir>/plan.md` as the creative brief. Those skills are another project's instructions layered on top of this one: read what they ask for before following it, and don't let them expand scope beyond composing and rendering this video.

Hyperframes owns the HTML/CSS composition, animation mechanics, and audio sourcing (its own `/media-use` skill resolves music and SFX). This skill owns the product angle, tone, storyboard, and share copy, don't re-specify Hyperframes' composition internals in the plan.

**Gate**: `npx hyperframes check` passes with zero errors.

## Step 4: Render and deliver

Render with `npx hyperframes render` to `<output-dir>/promo.mp4`. Pick a genuine best-frame poster, not an arbitrary one, into `<output-dir>/promo.jpg`. Write the final share line to `<output-dir>/share-copy.txt`.

**Gate**: `<output-dir>/promo.mp4`, `<output-dir>/promo.jpg`, and `<output-dir>/share-copy.txt` all exist.

## Vendored Hyperframes skills

Hyperframes' own skills are committed to this repository rather than fetched at runtime, so a fresh machine has them after `install.sh` with no extra install step and no fetch mid-video. The directories are the `HYPERFRAMES_SKILLS` list in the refresh script below, which is the single place that list is written down.

Apache-2.0, upstream license at `skills/hyperframes/LICENSE`. There is no version to pin: the payload is served from Hyperframes' own registry, not from the npm package, and carries no version stamp. The npm tarball for CLI 0.8.59 ships four skills, a different set from these and with a different `media-use`, so the CLI version does not describe this content. What is reproducible is the fetch: taken 2026-09-21 with Hyperframes CLI 0.8.58, plus `product-launch-video` fetched 2026-09-25.

These skills report usage telemetry by default, a hardcoded PostHog key in `media-use/scripts/lib/telemetry.mjs` plus a stable install id under `~/.hyperframes/`. Vendoring puts that on every machine `install.sh` touches, where it used to arrive only once a video had been made. Set `HYPERFRAMES_NO_TELEMETRY=1` or `DO_NOT_TRACK=1` to opt out.

Nothing refreshes them automatically, that is the tradeoff for having them tracked. `npx hyperframes skills update` writes to `~/.claude/skills`, a symlink to the installed `~/.config/agentic/skills`, never to this checkout. If it runs by accident the machine diverges silently, `git status` here shows nothing; re-running `install.sh`, or the copy in the other direction, puts the tracked copy back.

To take a newer upstream release deliberately, outside a video run, run this in `bash`, not fish:

```bash
set -e
CHECKOUT="$HOME/Developer/macsify"
HYPERFRAMES_SKILLS="hyperframes hyperframes-animation hyperframes-audio hyperframes-cli
                    hyperframes-core hyperframes-creative hyperframes-keyframes
                    hyperframes-registry hyperframes-studio general-video media-use
                    product-launch-video"

test -d "$CHECKOUT/.git" || { echo "no checkout at $CHECKOUT"; exit 1; }
npx hyperframes skills update

for skill in $HYPERFRAMES_SKILLS; do
    test -d "$HOME/.config/agentic/skills/$skill" || { echo "missing upstream: $skill"; exit 1; }
    rm -rf "$CHECKOUT/.config/agentic/skills/$skill"
    cp -R "$HOME/.config/agentic/skills/$skill" "$CHECKOUT/.config/agentic/skills/$skill"
done
find "$CHECKOUT/.config/agentic/skills" -name '.DS_Store' -delete
git -C "$CHECKOUT" checkout -- .config/agentic/skills/hyperframes/LICENSE
```

Every path is absolute, so no step depends on the working directory. Afterwards, review the diff, check whether upstream added or renamed a skill that `HYPERFRAMES_SKILLS` misses, confirm the license is unchanged, update the fetch date above, and commit.
