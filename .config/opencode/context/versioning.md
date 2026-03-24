# Versioning and GitHub Conventions

## Commit Format

Use conventional commits with backtick-wrapped technical terms:

```text
feat(scope): short description with `TechnicalTerm`
fix(scope): fix `APIEndpoint` timeout issue
refactor(scope): rename `UserService` to `AccountService`
test(scope): add tests for `AuthMiddleware`
docs(scope): update `README.md` with new `CLI` commands
chore(scope): upgrade `npm` dependencies
```

**Wrap in backticks:**

- Names (classes, functions, variables, constants, services, modules, interfaces, types, enumerations): `UserService`, `getUserById`
- Technical terms and acronyms: `API`, `CLI`, `SQL`, `HTTP`
- File names and paths: `config.yaml`, `src/auth/`
- Commands and tools: `npm`, `docker`, `gh`

**Do NOT wrap:**

- Natural language words
- Regular descriptive text

## Branch Naming

```text
feature/<name>
fix/<name>
refactor/<name>
```

## Fixup vs Amend

- **Amend**: Use when changing the tip of the current branch (the latest commit)
- **Fixup**: Use when changing an earlier commit on the branch

## Fixup Workflow

When a branch already has commits and you need to amend a specific earlier commit (e.g. addressing review feedback, fixing a typo):

```bash
# Stage the fix, then create a fixup commit targeting the original.
git add <file>
git commit --fixup <SHA_of_original_commit>
```

This creates a commit named `fixup! <original message>`. Before merging, clean up with:

```bash
git rebase -i --autosquash master
```

**When to use fixup:**

- Fixing something introduced in a previous commit on the same branch
- Addressing PR review comments that apply to a specific commit
- Correcting typos, missing files, or small oversights in earlier commits

**When NOT to use fixup:**

- The branch has a single commit (use `git commit --amend` instead)
- The change is genuinely new functionality (make a normal commit)

## GitHub Access

**Always use `gh` CLI for GitHub operations. Never use WebFetch for GitHub URLs.**

```bash
# File contents.
gh api repos/<owner>/<repo>/contents/<path> --jq '.[].download_url'
gh api repos/<owner>/<repo>/contents/<path> --raw

# Pull requests.
gh pr create --title "<title>" --body-file <file>
gh pr view --web
gh pr comment <number> --body "<comment>"
gh pr merge --squash
gh pr checkout <number>

# Issues.
gh issue create --title "<title>" --body "<body>"
gh issue view <number>
gh issue list
gh issue comment <number> --body "<comment>"

# Repositories.
gh repo clone <owner>/<repo>
gh repo view --web
gh repo list <owner>

# Releases.
gh release create <tag> --title "<title>" --notes "<notes>"
gh release list

# Workflows and Actions.
gh run list
gh run watch <run-id>
gh workflow list

# Search.
gh search repos <query> --limit 10
gh search issues <query> --limit 10
```

## PR Template

Rules:

- Do not leave placeholders in final PR bodies.
- Replace all template fields with concrete page paths, commands, data IDs, and expected results.
- If no issue or task link exists, omit the "Resolves" line.

```markdown
## What

One-line change summary.

## Why

Problem being solved.

Resolves [issue_task_id](link/to/issue_or_task).

## Testing

Reviewer validation flow:

### UI flow checks

1. Open `<environment_url_or_page>`.
2. Navigate to `<page_or_section>`.
3. Perform user action: `<click/type/select exact action>`.
4. Continue flow: `<example: add item to cart and proceed to checkout>`.
5. Confirm expected result: `<visible message/state/value>`.

### Data/CLI checks

1. Fetch/setup required data:
   - `<command to seed or fetch db entry>`
2. Execute changed behavior:
   - `<command or script that runs the new method>`
3. Verify output/state:
   - `<expected output, db change, or log line>`

### Regression checks

1. Run tests:
   - `<test command>`
2. Run lint/static checks:
   - `<lint or static check command>`
```
