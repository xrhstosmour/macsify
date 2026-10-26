# Documentation

## Docs

- Code comments and doc comments say why, not what. They hold intent, architecture and business logic: why this way, what was rejected, what it must never do. They never retell the code.
- A business claim carries a status and a date. Say whether it is verified in code, naming the code, stated by the business, naming the task, or open. Stated and open claims get a last verified date so someone can re-check them. This applies to business rules only, not to every sentence.
- Docs are for humans. Short, readable, no fluff, if we cannot understand it, that is a bug. Cut before adding.
- Markdown docs also say what the code does and where it lives, just enough that an agent or a colleague finds it before searching.

## Tests

Test rules live in the `test-quality` skill.

## Commits and PRs

- The PR description carries the detail that would otherwise be lost, short, never a document.
- Commit messages stay single-line per `versioning.md`, so extra detail goes in the PR description, not a commit body.

## Code

- Less code, same behavior. Flag duplication, and DRY it only inside code the task already touches, per `standards.md` Simplicity.
- Keep refactors separate from features.
