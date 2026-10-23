# Onboarding and Activation

## Define activation first

Activation is the early action that predicts the user is still around weeks later, creating the first item, connecting the first account, finishing the first session. Find it from data when there is data:

1. Signup is time zero. Pick an early window, the first 7 days, and a later retention check, still active in week 4.
2. Include every signup with the full follow-up time, keep recent cohorts out instead of counting them as churned.
3. Compare actions in the early window between users who stayed and users who left. A high correlation is a hypothesis, confirm it on a later cohort.
4. Test whether pushing users toward the action actually improves retention, correlation alone does not prove it.

Without data yet, pick the action that delivers the core job once and treat it as the working definition.

## Principles

- Remove every step between install and the first real value. List all the steps, delete what is not needed for that first value, then rebuild the shortest path.
- One goal per first session, advanced features wait.
- Doing beats showing, an interactive first task over a tutorial.
- Visible progress motivates, and a checklist that starts partly done gets finished more often than one that starts at zero.
- People remember the best moment and the end, give the first session a clear win and end it on one.

## First run

| Approach | Fits | Risk |
| -------- | ---- | ---- |
| Straight into the product | Simple and mobile apps | A blank screen |
| Short guided setup | Apps that need personalizing | Friction before value |
| Sample data first | Apps whose value needs data to show | Feels unreal |

Whichever: one clear next action, no dead ends, progress shown when there are several steps. On mobile ask for permissions, notifications, location, at the moment the feature needs them, with the reason, never all at once on launch.

## Patterns

- Checklist: 3 to 7 items, most valuable first, quick wins early, a progress bar, a small celebration at the end, and dismissible.
- Empty state: what this area is for, what it looks like with data, one action to add the first item, sample data as an option. It follows the copy rules in `web-app-design`, a layout that explains itself over helper text.
- Tours: 3 to 5 steps at most, dismissible anytime, never shown again to a returning user.

## Emails and notifications

Welcome right after signup, a nudge at 24 and 72 hours when setup is unfinished, a celebration with the next step on activation, feature discovery around days 3, 7, and 14. One idea per message, each drives back into the app with a specific action, and never duplicates what the app already showed.

Stalled users, inactive for a set number of days or stuck in setup, get a short sequence reminding them of the value and offering help, and a "pick up where you left off" when they return.

## Measure

Activation rate, time to activation, setup completion, and day 1, 7, and 30 retention, plus the drop-off at each step from signup to activation. Fix the biggest drop first.

## Output

An audit lists each issue as finding, impact, fix, priority. A new flow gives the activation goal, the step-by-step path, checklist items, empty state copy, message triggers, and the metrics to track.
