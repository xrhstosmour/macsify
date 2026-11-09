#!/bin/bash

# Checks `green-worktree.sh` and `green-git.sh` against local repositories
# and a stub `gh`, never the real GitHub. The worktree script puts one detached
# `resolves` worktree at the head of a pull request of the viewer, throws away a
# leftover of an earlier run, and refuses a pull request of someone else, a
# draft, one from a fork or another branch, one that moved, and `main`. The git
# script commits a fixup only of a commit of the pull request and only of
# changed files inside the worktree, rewords only through an `amend!` of one
# line, pushes only with a matching lease, signs as the git configuration
# says even from `ccy`, autosquashes without moving a branch
# of the viewer, leaves a conflicting rebase in progress and continues it only
# with exactly the conflicted files and no marker left, aborts it on request,
# triggers tests only through a push branch pattern the named workflow lists,
# never one named after a deploy target, at the head of the pull request, never
# next to a deploying workflow or local action the push starts or chains, at the
# head or on the default branch, or for a change to `.github`, never over a tests
# branch it did not push and the head does not contain, and refuses any
# folder that is not a `resolves` worktree.

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORKTREE_SCRIPT="$TESTS_SCRIPT_DIRECTORY/../.config/scripts/review/green-worktree.sh"
GIT_SCRIPT="$TESTS_SCRIPT_DIRECTORY/../.config/scripts/review/green-git.sh"
TRUST_SCRIPT="$TESTS_SCRIPT_DIRECTORY/../.config/scripts/review/green-trust.sh"

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

failures=0
fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL="$TEST_DIRECTORY/gitconfig"
# The trust file lives under `HOME`, your own must never approve a test tree.
export HOME="$TEST_DIRECTORY/home"
TRUST_FILE="$HOME/.config/green-github-prs-watcher/trusted-workflows"
export REVIEW_DEVELOPER_DIRECTORY="$TEST_DIRECTORY/developer"
UPSTREAM="$TEST_DIRECTORY/upstream.git"
SOURCE="$TEST_DIRECTORY/source"
mkdir -p "$REVIEW_DEVELOPER_DIRECTORY" "$TEST_DIRECTORY/bin"

# A rebase of the viewer's would move a branch at a rebased commit, the git script must turn it off.
cat >"$GIT_CONFIG_GLOBAL" <<EOF
[url "$UPSTREAM"]
  insteadOf = git@github.com:owner/service.git
[protocol "file"]
  allow = always
[rebase]
  updateRefs = true
EOF

# Main has `a.txt`, the pull request branch `fix/thing` changes it in one commit and adds `b.txt` in another.
git init --quiet --bare --initial-branch=main "$UPSTREAM"
git init --quiet --initial-branch=main "$SOURCE"
printf 'one\n' >"$SOURCE/a.txt"
git -C "$SOURCE" add a.txt
# A submodule `sub`, whose folder a caller could fill with a `.git` pointing at a planted configuration.
git -C "$SOURCE" update-index --add --cacheinfo "160000,0123456789012345678901234567890123456789,sub"
git -C "$SOURCE" commit --quiet -m base
BASE_SHA="$(git -C "$SOURCE" rev-parse HEAD)"
git -C "$SOURCE" checkout --quiet -b fix/thing
printf 'two\n' >"$SOURCE/a.txt"
git -C "$SOURCE" commit --quiet -am "change a"
CHANGE_SHA="$(git -C "$SOURCE" rev-parse HEAD)"
printf 'b\n' >"$SOURCE/b.txt"
git -C "$SOURCE" add b.txt
git -C "$SOURCE" commit --quiet -m "add b"
HEAD_SHA="$(git -C "$SOURCE" rev-parse HEAD)"
git -C "$SOURCE" push --quiet "$UPSTREAM" main:refs/heads/main fix/thing:refs/heads/fix/thing "fix/thing:refs/pull/7/head"

git clone --quiet "$UPSTREAM" "$REVIEW_DEVELOPER_DIRECTORY/service"
git -C "$REVIEW_DEVELOPER_DIRECTORY/service" remote set-url origin git@github.com:owner/service.git
git -C "$REVIEW_DEVELOPER_DIRECTORY/service" branch --quiet fix/thing "$HEAD_SHA"
mkdir -p "$REVIEW_DEVELOPER_DIRECTORY/service/.git/hooks"
printf '#!/bin/sh\ntouch "%s/hook-ran"\n' "$TEST_DIRECTORY" >"$REVIEW_DEVELOPER_DIRECTORY/service/.git/hooks/post-checkout"
chmod +x "$REVIEW_DEVELOPER_DIRECTORY/service/.git/hooks/post-checkout"
cp "$REVIEW_DEVELOPER_DIRECTORY/service/.git/hooks/post-checkout" "$REVIEW_DEVELOPER_DIRECTORY/service/.git/hooks/pre-push"

# The stub answers the viewer and the pull request the way the `--jq` filters of the script print them.
cat >"$TEST_DIRECTORY/bin/gh" <<'STUB'
#!/bin/bash
case "$1 $2" in
  "api user") echo me ;;
  "api repos/owner/service/pulls/7") echo "$STUB_PULL_REQUEST" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$TEST_DIRECTORY/bin/gh"
export PATH="$TEST_DIRECTORY/bin:$PATH"
pull_request() {
  export STUB_PULL_REQUEST="${1:-open} ${2:-false} ${3:-me} ${4:-owner/service} ${5:-fix/thing} ${6:-$HEAD_SHA} main"
}
prepare() {
  "$WORKTREE_SCRIPT" owner/service 7 "${1:-$HEAD_SHA}" "${2:-fix/thing}" 2>/dev/null
}

WORKTREE="$REVIEW_DEVELOPER_DIRECTORY/worktrees/service/resolves"
pull_request
[ "$(prepare)" = "$WORKTREE" ] || fail "the worktree script did not print the resolves worktree"
[ "$(git -C "$WORKTREE" rev-parse HEAD)" = "$HEAD_SHA" ] || fail "the worktree is not at the pull request head"
[ -z "$(git -C "$WORKTREE" branch --show-current)" ] || fail "the worktree is on a branch, not detached"
[ ! -e "$TEST_DIRECTORY/hook-ran" ] || fail "a hook ran in the worktree"

# A leftover edit and file of an earlier run are thrown away.
printf 'stale\n' >"$WORKTREE/a.txt"
printf 'stale\n' >"$WORKTREE/stale.txt"
prepare >/dev/null || fail "the worktree script failed on a worktree with leftovers"
[ "$(cat "$WORKTREE/a.txt")" = two ] || fail "the worktree script kept a leftover edit"
[ ! -e "$WORKTREE/stale.txt" ] || fail "the worktree script kept a leftover file"

pull_request open false someone
prepare >/dev/null && fail "the worktree script accepted a pull request of someone else"
pull_request open true
prepare >/dev/null && fail "the worktree script accepted a draft"
pull_request closed
prepare >/dev/null && fail "the worktree script accepted a closed pull request"
pull_request open false me fork/service
prepare >/dev/null && fail "the worktree script accepted a pull request from a fork"
pull_request open false me owner/service other
prepare >/dev/null && fail "the worktree script accepted a pull request of another branch"
pull_request open false me owner/service fix/thing "$CHANGE_SHA"
prepare >/dev/null && fail "the worktree script accepted a pull request that moved"
pull_request open false me owner/service main
prepare "$HEAD_SHA" main >/dev/null && fail "the worktree script accepted main"
prepare "$HEAD_SHA" -x >/dev/null && fail "the worktree script accepted a branch that reads as an option"
prepare "$HEAD_SHA" '@{-1}' >/dev/null && fail "the worktree script accepted a branch shorthand"
"$WORKTREE_SCRIPT" owner/service 7 abc fix/thing >/dev/null 2>&1 && fail "the worktree script accepted a short commit"
pull_request
prepare >/dev/null || fail "the worktree script failed to prepare the pull request again"

# A fixup only of a commit of the pull request, only of a changed file inside the worktree.
"$GIT_SCRIPT" fixup "$WORKTREE" "$CHANGE_SHA" a.txt >/dev/null 2>&1 && fail "the git script committed a file with no change"
printf 'three\n' >"$WORKTREE/a.txt"
"$GIT_SCRIPT" fixup "$WORKTREE" "$BASE_SHA" a.txt >/dev/null 2>&1 && fail "the git script committed a fixup of a commit of the base"
"$GIT_SCRIPT" fixup "$WORKTREE" "$CHANGE_SHA" ../a.txt >/dev/null 2>&1 && fail "the git script accepted a file outside the worktree"
"$GIT_SCRIPT" fixup "$WORKTREE" "$CHANGE_SHA" '*' >/dev/null 2>&1 && fail "the git script read a file name as a pattern"
"$GIT_SCRIPT" fixup "$WORKTREE" "$CHANGE_SHA" -- >/dev/null 2>&1 && fail "the git script accepted an option as a file"
# Started from `ccy`, the fixup is still signed when the git configuration signs, by a stub signer that only prints a signature.
cat >"$TEST_DIRECTORY/bin/signer" <<'EOF'
#!/bin/sh
cat >/dev/null
printf '\n[GNUPG:] SIG_CREATED D 1 8 00 0 stub\n' >&2
printf '%s\n' '-----BEGIN PGP SIGNATURE-----' 'stub' '-----END PGP SIGNATURE-----'
EOF
chmod +x "$TEST_DIRECTORY/bin/signer"
printf '[include]\n  path = %s\n[commit]\n  gpgsign = true\n[gpg]\n  format = openpgp\n  program = %s\n' "$GIT_CONFIG_GLOBAL" "$TEST_DIRECTORY/bin/signer" >"$TEST_DIRECTORY/signing-gitconfig"
FIXUP_SHA="$(GIT_CONFIG_GLOBAL="$TEST_DIRECTORY/signing-gitconfig" AGENTIC_UNSIGNED_COMMITS=1 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false "$GIT_SCRIPT" fixup "$WORKTREE" "$CHANGE_SHA" a.txt 2>/dev/null)" || fail "the git script refused a fixup of a commit of the pull request"
git -C "$WORKTREE" cat-file commit "$FIXUP_SHA" | sed '/^$/q' | grep -q '^gpgsig' || fail "the git script left a fixup unsigned under ccy"
[ "$(git -C "$WORKTREE" log -1 --format=%s)" = "fixup! change a" ] || fail "the git script did not commit a fixup of the target"
[ "$FIXUP_SHA" = "$(git -C "$WORKTREE" rev-parse HEAD)" ] || fail "the git script did not print the new head"
printf 'four\n' >"$WORKTREE/a.txt"
"$GIT_SCRIPT" fixup "$WORKTREE" "$FIXUP_SHA" a.txt >/dev/null 2>&1 && fail "the git script committed a fixup of a fixup"
git -c core.hooksPath=/dev/null -C "$WORKTREE" checkout --quiet -- a.txt

# A submodule or `.git` planted in the worktree never reaches git, its `core.fsmonitor` would run a command on the next status.
git init --quiet "$TEST_DIRECTORY/submodule"
git -C "$TEST_DIRECTORY/submodule" commit --quiet --allow-empty -m planted
git -C "$TEST_DIRECTORY/submodule" config core.fsmonitor "touch $TEST_DIRECTORY/submodule-ran #"
mkdir -p "$WORKTREE/sub"
printf 'gitdir: %s/submodule/.git\n' "$TEST_DIRECTORY" >"$WORKTREE/sub/.git"
printf 'three\n' >"$WORKTREE/a.txt"
"$GIT_SCRIPT" fixup "$WORKTREE" "$CHANGE_SHA" sub >/dev/null 2>&1 && fail "the git script committed a submodule"
"$GIT_SCRIPT" fixup "$WORKTREE" "$CHANGE_SHA" sub/.git >/dev/null 2>&1 && fail "the git script committed a .git"
"$GIT_SCRIPT" fixup "$WORKTREE" "$CHANGE_SHA" a.txt sub >/dev/null 2>&1 && fail "the git script committed a submodule next to a file"
[ ! -e "$TEST_DIRECTORY/submodule-ran" ] || fail "a planted submodule configuration ran a command"
[ "$(git -C "$WORKTREE" rev-parse HEAD)" = "$FIXUP_SHA" ] || fail "the git script committed while refusing a submodule"
rm "$WORKTREE/sub/.git"
git -c core.hooksPath=/dev/null -C "$WORKTREE" checkout --quiet -- a.txt

# A push needs the lease of the head on the remote.
"$GIT_SCRIPT" push "$WORKTREE" "$CHANGE_SHA" >/dev/null 2>&1 && fail "the git script pushed with a stale lease"
"$GIT_SCRIPT" push "$WORKTREE" "$HEAD_SHA" >/dev/null 2>&1 || fail "the git script refused to push with the right lease"
[ "$(git -C "$UPSTREAM" rev-parse fix/thing)" = "$FIXUP_SHA" ] || fail "the git script did not push the head to the branch"
[ ! -e "$TEST_DIRECTORY/hook-ran" ] || fail "a hook ran on a push"

# The autosquash leaves no fixup, pushes, and keeps the viewer's own branch where it was.
SQUASHED_SHA="$("$GIT_SCRIPT" autosquash "$WORKTREE" "$FIXUP_SHA" 2>/dev/null)" || fail "the git script failed to autosquash"
[ "$(git -C "$UPSTREAM" log --format=%s main..fix/thing | tr '\n' ' ')" = "add b change a " ] || fail "the autosquash left a fixup on the branch"
[ "$(git -C "$UPSTREAM" rev-parse fix/thing)" = "$SQUASHED_SHA" ] || fail "the git script did not push the squashed head"
[ "$(git -C "$UPSTREAM" show fix/thing:a.txt)" = three ] || fail "the autosquash lost the fix"
[ "$(git -C "$REVIEW_DEVELOPER_DIRECTORY/service" rev-parse fix/thing)" = "$HEAD_SHA" ] || fail "the autosquash moved the viewer's own branch"

# A reword is an empty `amend!` of a commit of the pull request, the autosquash gives the target the new message.
MESSAGE_DIRECTORY="$(mktemp -d)"
printf 'change a to three\n' >"$MESSAGE_DIRECTORY/message.txt"
printf 'first line\nsecond line\n' >"$MESSAGE_DIRECTORY/lines.txt"
"$GIT_SCRIPT" reword "$WORKTREE" "$BASE_SHA" "$MESSAGE_DIRECTORY/message.txt" >/dev/null 2>&1 && fail "the git script reworded a commit of the base"
"$GIT_SCRIPT" reword "$WORKTREE" "$(git -C "$WORKTREE" rev-parse HEAD~1)" "$MESSAGE_DIRECTORY/lines.txt" >/dev/null 2>&1 && fail "the git script accepted a message of two lines"
"$GIT_SCRIPT" reword "$WORKTREE" "$(git -C "$WORKTREE" rev-parse HEAD~1)" "$MESSAGE_DIRECTORY/message.txt" >/dev/null 2>&1 || fail "the git script refused to reword a commit of the pull request"
[ "$(git -C "$WORKTREE" log -1 --format=%s)" = "amend! change a" ] || fail "the git script did not commit an amend of the target"
REWORDED_SHA="$("$GIT_SCRIPT" autosquash "$WORKTREE" "$SQUASHED_SHA" 2>/dev/null)" || fail "the git script failed to autosquash a reword"
[ "$(git -C "$UPSTREAM" log --format=%s main..fix/thing | tr '\n' ' ')" = "add b change a to three " ] || fail "the autosquash did not reword the target"
rm -r "$MESSAGE_DIRECTORY"

# Tests are triggered only through a push pattern of the workflow the caller names, only at the head of the pull request.
"$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "tests/**" >/dev/null 2>&1 && fail "the git script triggered a workflow that does not exist"
git -C "$SOURCE" checkout --quiet main
mkdir -p "$SOURCE/.github/workflows"
printf 'on:\n  push:\n    paths:\n      - "paths/**"\n    branches:\n      - "tests/**"\n      - "main/**"\n      - "staging/*"\n    branches-ignore:\n      - "ignored/**"\n  pull_request:\n    branches:\n      - "requests/**"\njobs:\n  test:\n    push:\n      branches:\n        - "steps/**"\n' >"$SOURCE/.github/workflows/tests.yaml"
printf 'on:\n  push:\n    branches:\n      - main\njobs:\n  deploy:\n    steps:\n      - run: ./deploy\n' >"$SOURCE/.github/workflows/deploy.yaml"
git -C "$SOURCE" add .github
git -C "$SOURCE" commit --quiet -m "add tests workflow"
git -C "$SOURCE" push --quiet "$UPSTREAM" main:refs/heads/main
REWORDED_SHA="$("$GIT_SCRIPT" autosquash "$WORKTREE" "$REWORDED_SHA" 2>/dev/null)" || fail "the git script failed to rebase onto the tests workflow"
for pattern in "paths/**" "ignored/**" "requests/**" "steps/**"; do
  "$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "$pattern" 2>&1 >/dev/null | grep -q 'does not run on a push' || fail "the git script read $pattern as a push branch pattern"
done
# A pattern the workflow lists is still refused when it is named after a deploy target.
for pattern in "main/**" "staging/*" "stage-eu/**" "uat/*" "hotfix/**" "preview/*"; do
  "$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "$pattern" 2>&1 >/dev/null | grep -q 'named after a deploy target' || fail "the git script accepted the branch pattern $pattern"
done
for pattern in "tests" "tests/x/**" "-x/**"; do
  "$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "$pattern" >/dev/null 2>&1
  [ $? -eq 2 ] || fail "the git script accepted the branch pattern $pattern"
done
"$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" ../tests.yaml "tests/**" >/dev/null 2>&1 && fail "the git script accepted a workflow path outside the workflows folder"
"$GIT_SCRIPT" tests "$WORKTREE" "$CHANGE_SHA" tests.yaml "tests/**" >/dev/null 2>&1 && fail "the git script triggered tests of a commit that is not the head"
git -C "$UPSTREAM" rev-parse --quiet --verify refs/heads/tests/fix/thing >/dev/null && fail "the git script pushed tests of a commit that is not the head"
# A deploy on `main` is not started by the push, so it does not block the tests.
"$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "tests/**" >/dev/null 2>&1 || fail "the git script refused to trigger tests of the head"
[ "$(git -C "$UPSTREAM" rev-parse tests/fix/thing)" = "$REWORDED_SHA" ] || fail "the git script did not push the head to tests/fix/thing"
[ ! -e "$TEST_DIRECTORY/hook-ran" ] || fail "a hook ran on a tests push"
# A tests branch the watcher did not push, and the head does not contain, may be a person's work, so it is never overwritten.
SIDE_SHA="$(git -C "$SOURCE" commit-tree "$BASE_SHA^{tree}" -p "$BASE_SHA" -m side)"
git -C "$SOURCE" push --quiet --force "$UPSTREAM" "$SIDE_SHA:refs/heads/tests/fix/thing"
"$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "tests/**" 2>&1 >/dev/null | grep -q 'not pushed by the watcher' || fail "the git script overwrote a tests branch it did not push"
[ "$(git -C "$UPSTREAM" rev-parse tests/fix/thing)" = "$SIDE_SHA" ] || fail "the git script moved a tests branch it did not push"
# One it pushed itself, at an older head, or one the head contains, is replaced.
git -c core.hooksPath=/dev/null -C "$WORKTREE" fetch --quiet origin refs/heads/tests/fix/thing
git -C "$WORKTREE" update-ref refs/green-trigger/tests/fix/thing "$SIDE_SHA"
"$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "tests/**" >/dev/null 2>&1 || fail "the git script refused to replace a tests branch it pushed"
[ "$(git -C "$UPSTREAM" rev-parse tests/fix/thing)" = "$REWORDED_SHA" ] || fail "the git script did not replace a tests branch it pushed"
git -C "$UPSTREAM" update-ref refs/heads/tests/fix/thing "$REWORDED_SHA~1"
"$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "tests/**" >/dev/null 2>&1 || fail "the git script refused to move a tests branch the head contains"
[ "$(git -C "$UPSTREAM" rev-parse tests/fix/thing)" = "$REWORDED_SHA" ] || fail "the git script did not move a tests branch the head contains"
# A workflow changed by the pull request would run with the secrets of the repository.
printf '      - "other/**"\n' >>"$WORKTREE/.github/workflows/tests.yaml"
WORKFLOW_FIXUP_SHA="$("$GIT_SCRIPT" fixup "$WORKTREE" "$(git -C "$WORKTREE" rev-parse HEAD~1)" .github/workflows/tests.yaml 2>/dev/null)" || fail "the git script refused a fixup of a workflow"
"$GIT_SCRIPT" push "$WORKTREE" "$REWORDED_SHA" >/dev/null 2>&1 || fail "the git script refused to push a fixup of a workflow"
"$GIT_SCRIPT" tests "$WORKTREE" "$WORKFLOW_FIXUP_SHA" tests.yaml "tests/**" 2>&1 >/dev/null | grep -q 'changes .github' || fail "the git script triggered tests of a pull request that changes .github"
[ "$(git -C "$UPSTREAM" rev-parse tests/fix/thing)" = "$REWORDED_SHA" ] || fail "the git script pushed tests of a pull request that changes .github"
git -c core.hooksPath=/dev/null -C "$WORKTREE" reset --quiet --hard "$REWORDED_SHA"
git -C "$UPSTREAM" update-ref refs/heads/fix/thing "$REWORDED_SHA"
# A `workflow_run` runs the file of the default branch, so a deploy chained there blocks the tests even when the head does not have it.
git -C "$SOURCE" checkout --quiet main
printf 'on:\n  workflow_run:\n    workflows: [tests]\njobs:\n  ship:\n    steps:\n      - run: ./deploy\n' >"$SOURCE/.github/workflows/chained.yml"
git -C "$SOURCE" add .github
git -C "$SOURCE" commit --quiet -m "add chained workflow"
git -C "$SOURCE" push --quiet "$UPSTREAM" main:refs/heads/main
"$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "tests/**" 2>&1 >/dev/null | grep -q 'chained.yml mentions a deploy' || fail "the git script triggered tests next to a deploy chained on the default branch"
git -C "$SOURCE" rm --quiet .github/workflows/chained.yml
git -C "$SOURCE" commit --quiet -m "remove chained workflow"
git -C "$SOURCE" push --quiet "$UPSTREAM" main:refs/heads/main
# A deploy that runs on a push to any branch, to a branch item with a comment, through a YAML alias, on a new branch or after another workflow would run next to the tests.
for trigger in 'on: [push]' $'on:\n  push:\n    branches:\n      - main\n      - "tests/**" # the tests' $'triggers: &triggers\n  push:\n    branches: ["tests/**"]\non: *triggers' $'on:\n  create:' $'on:\n  workflow_run:\n    workflows: [tests]'; do
  git -C "$SOURCE" checkout --quiet main
  printf '%s\njobs:\n  ship:\n    steps:\n      - run: ./deploy\n' "$trigger" >"$SOURCE/.github/workflows/ship.yml"
  git -C "$SOURCE" add .github
  git -C "$SOURCE" commit --quiet -m "change ship workflow"
  git -C "$SOURCE" push --quiet "$UPSTREAM" main:refs/heads/main
  REWORDED_SHA="$("$GIT_SCRIPT" autosquash "$WORKTREE" "$REWORDED_SHA" 2>/dev/null)" || fail "the git script failed to rebase onto the ship workflow"
  "$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "tests/**" 2>&1 >/dev/null | grep -q 'ship.yml mentions a deploy' || fail "the git script triggered tests next to a deploy on $trigger"
  [ "$(git -C "$UPSTREAM" rev-parse tests/fix/thing)" != "$REWORDED_SHA" ] || fail "the git script pushed tests next to a deploy on $trigger"
done
# A local action the started workflow calls runs with it.
git -C "$SOURCE" checkout --quiet main
mkdir -p "$SOURCE/.github/actions/ship"
printf 'on: [push]\njobs:\n  ship:\n    steps:\n      - uses: ./.github/actions/ship\n' >"$SOURCE/.github/workflows/ship.yml"
printf 'runs:\n  using: composite\n  steps:\n    - run: ./deploy\n' >"$SOURCE/.github/actions/ship/action.yml"
git -C "$SOURCE" add .github
git -C "$SOURCE" commit --quiet -m "call the ship action"
git -C "$SOURCE" push --quiet "$UPSTREAM" main:refs/heads/main
REWORDED_SHA="$("$GIT_SCRIPT" autosquash "$WORKTREE" "$REWORDED_SHA" 2>/dev/null)" || fail "the git script failed to rebase onto the ship action"
"$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "tests/**" 2>&1 >/dev/null | grep -q 'actions/ship/action.yml: .*deploy' || fail "the git script triggered tests next to a local action that deploys"
[ "$(git -C "$UPSTREAM" rev-parse tests/fix/thing)" != "$REWORDED_SHA" ] || fail "the git script pushed tests next to a local action that deploys"

# Another workflow the push starts exits 5 and is never offered for trust, approving the tests must not approve a deploy next to them.
"$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "tests/**" >/dev/null 2>"$TEST_DIRECTORY/refused"
[ $? -eq 5 ] || fail "the git script did not exit 5 on a started workflow that deploys"
grep -q 'green-trust.sh' "$TEST_DIRECTORY/refused" && fail "the git script offered to trust a workflow it was not asked to run"
# The named workflow calling the same action exits 5 with its files, the lines matched and the command that trusts it.
git -C "$SOURCE" checkout --quiet main
git -C "$SOURCE" rm --quiet .github/workflows/ship.yml
printf '    steps:\n      - uses: ./.github/actions/ship\n' >>"$SOURCE/.github/workflows/tests.yaml"
git -C "$SOURCE" commit --quiet -am "call the ship action from the tests"
git -C "$SOURCE" push --quiet "$UPSTREAM" main:refs/heads/main
REWORDED_SHA="$("$GIT_SCRIPT" autosquash "$WORKTREE" "$REWORDED_SHA" 2>/dev/null)" || fail "the git script failed to rebase onto the tests calling the ship action"
"$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "tests/**" >/dev/null 2>"$TEST_DIRECTORY/refused"
[ $? -eq 5 ] || fail "the git script did not exit 5 on a named workflow tree that mentions a deploy"
grep -qx '  .github/actions/ship/action.yml' "$TEST_DIRECTORY/refused" || fail "the refusal did not name a file the workflow calls"
grep -q 'action.yml: .*deploy' "$TEST_DIRECTORY/refused" || fail "the refusal did not show the matched line"
TRUST_ARGUMENTS="$(grep -oE 'green-trust\.sh owner/service \.github/workflows/tests\.yaml [0-9a-f]{64}$' "$TEST_DIRECTORY/refused" | cut -d ' ' -f 2-)"
[ -n "$TRUST_ARGUMENTS" ] || fail "the refusal did not print the command that trusts the tree"
[ "$(git -C "$UPSTREAM" rev-parse tests/fix/thing)" != "$REWORDED_SHA" ] || fail "the git script pushed tests of an untrusted tree"
# shellcheck disable=SC2086
"$TRUST_SCRIPT" $TRUST_ARGUMENTS >/dev/null || fail "green-trust.sh refused the printed line"
grep -qxF "$TRUST_ARGUMENTS" "$TRUST_FILE" || fail "green-trust.sh did not write the printed line"
"$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "tests/**" >/dev/null 2>&1 || fail "the git script refused a trusted workflow tree"
[ "$(git -C "$UPSTREAM" rev-parse tests/fix/thing)" = "$REWORDED_SHA" ] || fail "the git script did not push tests of a trusted workflow tree"
# A line of another repository approves nothing here.
cp "$TRUST_FILE" "$TEST_DIRECTORY/trusted"
sed 's|^owner/service |other/service |' "$TEST_DIRECTORY/trusted" >"$TRUST_FILE"
"$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "tests/**" >/dev/null 2>&1
[ $? -eq 5 ] || fail "the git script took a trust line of another repository"
# A trust file it cannot read in full, or a link to one, approves nothing and is never written.
cp "$TEST_DIRECTORY/trusted" "$TRUST_FILE"
printf 'owner/service .github/workflows/tests.yaml anything\n' >>"$TRUST_FILE"
"$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "tests/**" 2>&1 >/dev/null | grep -q 'fix or remove it' || fail "the git script read a malformed trust file"
# shellcheck disable=SC2086
"$TRUST_SCRIPT" $TRUST_ARGUMENTS >/dev/null 2>&1 && fail "green-trust.sh wrote into a malformed trust file"
rm "$TRUST_FILE"
ln -s "$TEST_DIRECTORY/trusted" "$TRUST_FILE"
"$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "tests/**" 2>&1 >/dev/null | grep -q 'fix or remove it' || fail "the git script read a trust file through a link"
# shellcheck disable=SC2086
"$TRUST_SCRIPT" $TRUST_ARGUMENTS >/dev/null 2>&1 && fail "green-trust.sh wrote through a link"
rm "$TRUST_FILE"
cp "$TEST_DIRECTORY/trusted" "$TRUST_FILE"
# Only a whole trust line is written, never a workflow outside the workflows folder or a fingerprint of another shape.
for arguments in "owner/service .github/workflows/tests.yaml anything" "owner/service ../tests.yaml ${TRUST_ARGUMENTS##* }" "owner/service .github/workflows/tests.yaml"; do
  # shellcheck disable=SC2086
  "$TRUST_SCRIPT" $arguments >/dev/null 2>&1 && fail "green-trust.sh accepted $arguments"
done
cmp -s "$TRUST_FILE" "$TEST_DIRECTORY/trusted" || fail "green-trust.sh changed the trust file on a bad line"
# A workflow the push also starts is not trusted by the named one, even through the same action.
git -C "$SOURCE" checkout --quiet main
printf 'on: [push]\njobs:\n  ship:\n    steps:\n      - uses: ./.github/actions/ship\n' >"$SOURCE/.github/workflows/ship.yml"
git -C "$SOURCE" add .github
git -C "$SOURCE" commit --quiet -m "call the ship action from ship again"
git -C "$SOURCE" push --quiet "$UPSTREAM" main:refs/heads/main
REWORDED_SHA="$("$GIT_SCRIPT" autosquash "$WORKTREE" "$REWORDED_SHA" 2>/dev/null)" || fail "the git script failed to rebase onto the ship workflow again"
"$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "tests/**" 2>&1 >/dev/null | grep -q 'ship.yml mentions a deploy' || fail "a trusted workflow let another one calling the same action through"
[ "$(git -C "$UPSTREAM" rev-parse tests/fix/thing)" != "$REWORDED_SHA" ] || fail "the git script pushed tests next to an untrusted workflow calling a trusted action"
git -C "$SOURCE" checkout --quiet main
git -C "$SOURCE" rm --quiet .github/workflows/ship.yml
git -C "$SOURCE" commit --quiet -m "remove ship workflow"
git -C "$SOURCE" push --quiet "$UPSTREAM" main:refs/heads/main
# A change to any file of the tree, the called action here, needs a new trust, which replaces the older line.
printf '    - run: ./deploy --again\n' >>"$SOURCE/.github/actions/ship/action.yml"
git -C "$SOURCE" commit --quiet -am "change the ship action"
git -C "$SOURCE" push --quiet "$UPSTREAM" main:refs/heads/main
REWORDED_SHA="$("$GIT_SCRIPT" autosquash "$WORKTREE" "$REWORDED_SHA" 2>/dev/null)" || fail "the git script failed to rebase onto the changed ship action"
"$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "tests/**" >/dev/null 2>"$TEST_DIRECTORY/refused"
[ $? -eq 5 ] || fail "the git script ran a trusted tree after a file it calls changed"
CHANGED_ARGUMENTS="$(grep -oE 'green-trust\.sh owner/service \.github/workflows/tests\.yaml [0-9a-f]{64}$' "$TEST_DIRECTORY/refused" | cut -d ' ' -f 2-)"
[ -n "$CHANGED_ARGUMENTS" ] && [ "$CHANGED_ARGUMENTS" != "$TRUST_ARGUMENTS" ] || fail "the refusal did not print a new fingerprint for the changed tree"
# shellcheck disable=SC2086
"$TRUST_SCRIPT" $CHANGED_ARGUMENTS >/dev/null || fail "green-trust.sh refused the changed tree"
[ "$(grep -c ' .github/workflows/tests.yaml ' "$TRUST_FILE")" -eq 1 ] || fail "green-trust.sh kept the older line of the workflow"
"$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "tests/**" >/dev/null 2>&1 || fail "the git script refused the trusted changed tree"
# A lock left by another run stops the write, the two would drop each other's line.
cp "$TRUST_FILE" "$TEST_DIRECTORY/trusted"
mkdir "$TRUST_FILE.lock"
# shellcheck disable=SC2086
"$TRUST_SCRIPT" $TRUST_ARGUMENTS 2>&1 >/dev/null | grep -q 'another green-trust.sh is running' || fail "green-trust.sh wrote while another run held the lock"
cmp -s "$TRUST_FILE" "$TEST_DIRECTORY/trusted" || fail "green-trust.sh changed the trust file while another run held the lock"
rmdir "$TRUST_FILE.lock"
# The named workflow chained by a `workflow_run` also runs the default branch's file, which passes as the tree approved at the head and is never offered as a second version.
git -C "$SOURCE" checkout --quiet main
{
  printf 'on:\n  workflow_run:\n    workflows: [lint]\n'
  tail -n +2 "$SOURCE/.github/workflows/tests.yaml"
} >"$TEST_DIRECTORY/tests.yaml"
mv "$TEST_DIRECTORY/tests.yaml" "$SOURCE/.github/workflows/tests.yaml"
git -C "$SOURCE" commit --quiet -am "chain the tests after lint"
git -C "$SOURCE" push --quiet "$UPSTREAM" main:refs/heads/main
REWORDED_SHA="$("$GIT_SCRIPT" autosquash "$WORKTREE" "$REWORDED_SHA" 2>/dev/null)" || fail "the git script failed to rebase onto the chained tests"
"$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "tests/**" >/dev/null 2>"$TEST_DIRECTORY/refused"
CHAINED_ARGUMENTS="$(grep -oE 'green-trust\.sh owner/service \.github/workflows/tests\.yaml [0-9a-f]{64}$' "$TEST_DIRECTORY/refused" | cut -d ' ' -f 2-)"
# shellcheck disable=SC2086
"$TRUST_SCRIPT" $CHAINED_ARGUMENTS >/dev/null || fail "green-trust.sh refused the chained tests"
"$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "tests/**" >/dev/null 2>&1 || fail "the git script refused the trusted tests chained on the default branch"
git -C "$SOURCE" checkout --quiet main
printf '    - run: ./deploy --default\n' >>"$SOURCE/.github/actions/ship/action.yml"
git -C "$SOURCE" commit --quiet -am "change the ship action on the default branch only"
git -C "$SOURCE" push --quiet "$UPSTREAM" main:refs/heads/main
"$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "tests/**" >/dev/null 2>"$TEST_DIRECTORY/refused"
[ $? -eq 5 ] || fail "the git script ran another version of the named workflow chained on the default branch"
grep -q 'green-trust.sh' "$TEST_DIRECTORY/refused" && fail "the git script offered to trust the default branch version of the named workflow"
REWORDED_SHA="$("$GIT_SCRIPT" autosquash "$WORKTREE" "$REWORDED_SHA" 2>/dev/null)" || fail "the git script failed to rebase onto the default branch ship action"
"$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "tests/**" >/dev/null 2>"$TEST_DIRECTORY/refused"
CHAINED_ARGUMENTS="$(grep -oE 'green-trust\.sh owner/service \.github/workflows/tests\.yaml [0-9a-f]{64}$' "$TEST_DIRECTORY/refused" | cut -d ' ' -f 2-)"
# shellcheck disable=SC2086
"$TRUST_SCRIPT" $CHAINED_ARGUMENTS >/dev/null || fail "green-trust.sh refused the rebased chained tests"
"$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "tests/**" >/dev/null 2>&1 || fail "the git script refused the trusted tests once the head caught up"
# A deploy word in a condition runs nothing, another workflow the push starts is still scanned on its own.
git -C "$SOURCE" checkout --quiet main
printf 'on: [push]\njobs:\n  check:\n    if: github.ref != '"'"'refs/heads/deploy'"'"'\n    steps:\n      - run: ./check\n' >"$SOURCE/.github/workflows/check.yml"
git -C "$SOURCE" add .github
git -C "$SOURCE" commit --quiet -m "add check workflow"
git -C "$SOURCE" push --quiet "$UPSTREAM" main:refs/heads/main
REWORDED_SHA="$("$GIT_SCRIPT" autosquash "$WORKTREE" "$REWORDED_SHA" 2>/dev/null)" || fail "the git script failed to rebase onto the check workflow"
"$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "tests/**" >/dev/null 2>&1 || fail "the git script refused a workflow with a deploy word only in a condition"
git -C "$SOURCE" checkout --quiet main
printf '      - run: ./publish\n' >>"$SOURCE/.github/workflows/check.yml"
git -C "$SOURCE" commit --quiet -am "publish from the check workflow"
git -C "$SOURCE" push --quiet "$UPSTREAM" main:refs/heads/main
REWORDED_SHA="$("$GIT_SCRIPT" autosquash "$WORKTREE" "$REWORDED_SHA" 2>/dev/null)" || fail "the git script failed to rebase onto the publishing check workflow"
"$GIT_SCRIPT" tests "$WORKTREE" "$REWORDED_SHA" tests.yaml "tests/**" 2>&1 >/dev/null | grep -q 'check.yml mentions a deploy' || fail "a trusted workflow let another one that deploys through"
git -C "$SOURCE" checkout --quiet main
git -C "$SOURCE" rm --quiet .github/workflows/check.yml
git -C "$SOURCE" commit --quiet -m "remove check workflow"
git -C "$SOURCE" push --quiet "$UPSTREAM" main:refs/heads/main
REWORDED_SHA="$("$GIT_SCRIPT" autosquash "$WORKTREE" "$REWORDED_SHA" 2>/dev/null)" || fail "the git script failed to rebase past the check workflow"

# A rebase that conflicts stays in progress, names the commit and the files, and pushes nothing.
git -C "$SOURCE" checkout --quiet main
printf 'conflict\n' >"$SOURCE/a.txt"
git -C "$SOURCE" commit --quiet -am "conflict on main"
git -C "$SOURCE" push --quiet "$UPSTREAM" main:refs/heads/main
"$GIT_SCRIPT" autosquash "$WORKTREE" "$REWORDED_SHA" >"$TEST_DIRECTORY/conflict" 2>/dev/null
[ $? -eq 3 ] || fail "the git script did not exit 3 on a conflicting rebase"
[ -d "$(git -C "$WORKTREE" rev-parse --path-format=absolute --git-path rebase-merge)" ] || fail "the git script did not leave the rebase in progress"
[[ "$(head -1 "$TEST_DIRECTORY/conflict")" == *" change a to three" ]] || fail "the git script did not name the commit that conflicts"
[ "$(tail -n +2 "$TEST_DIRECTORY/conflict")" = a.txt ] || fail "the git script did not name the conflicted file"
[ "$(git -C "$UPSTREAM" rev-parse fix/thing)" = "$REWORDED_SHA" ] || fail "the git script pushed after a conflict"

# A continue needs every conflict resolved, no marker left, and nothing but the conflicted files.
"$GIT_SCRIPT" continue "$WORKTREE" "$REWORDED_SHA" a.txt >/dev/null 2>&1 && fail "the git script continued with conflict markers left"
printf 'resolved\n' >"$WORKTREE/a.txt"
printf 'extra\n' >"$WORKTREE/b.txt"
"$GIT_SCRIPT" continue "$WORKTREE" "$REWORDED_SHA" a.txt b.txt >/dev/null 2>&1 && fail "the git script continued with a file that did not conflict"
rm "$WORKTREE/b.txt"
"$GIT_SCRIPT" continue "$WORKTREE" "$REWORDED_SHA" ../a.txt >/dev/null 2>&1 && fail "the git script continued with a file outside the worktree"
"$GIT_SCRIPT" continue "$WORKTREE" "$CHANGE_SHA" a.txt >/dev/null 2>&1 && fail "the git script pushed a resolution with a stale lease"
RESOLVED_SHA="$(git -C "$WORKTREE" rev-parse HEAD)"
[ "$(git -C "$UPSTREAM" rev-parse fix/thing)" = "$REWORDED_SHA" ] || fail "the git script pushed a resolution with a stale lease"
"$GIT_SCRIPT" push "$WORKTREE" "$REWORDED_SHA" >/dev/null 2>&1 || fail "the git script refused to push the resolved rebase"
[ "$(git -C "$UPSTREAM" show fix/thing:a.txt)" = resolved ] || fail "the resolution did not reach the branch"
[ "$(git -C "$UPSTREAM" rev-parse fix/thing)" = "$RESOLVED_SHA" ] || fail "the git script did not push the resolved head"
[ ! -d "$(git -C "$WORKTREE" rev-parse --path-format=absolute --git-path rebase-merge)" ] || fail "the rebase is still in progress after the resolution"

# A conflicted file with a non-ASCII name is named as it is, not quoted, so a continue with that name matches it.
printf 'branch\n' >"$WORKTREE/β.txt"
"$GIT_SCRIPT" fixup "$WORKTREE" "$(git -C "$WORKTREE" rev-parse HEAD~1)" β.txt >/dev/null 2>&1 || fail "the git script refused a fixup of a non-ASCII file"
git -C "$SOURCE" checkout --quiet main
printf 'main\n' >"$SOURCE/β.txt"
git -C "$SOURCE" add β.txt
git -C "$SOURCE" commit --quiet -m "add β on main"
git -C "$SOURCE" push --quiet "$UPSTREAM" main:refs/heads/main
"$GIT_SCRIPT" autosquash "$WORKTREE" "$RESOLVED_SHA" >"$TEST_DIRECTORY/conflict" 2>/dev/null
[ $? -eq 3 ] || fail "the git script did not exit 3 on a conflicting non-ASCII file"
[ "$(tail -n +2 "$TEST_DIRECTORY/conflict")" = β.txt ] || fail "the git script quoted the conflicted non-ASCII file"
printf 'resolved\n' >"$WORKTREE/β.txt"
RESOLVED_SHA="$("$GIT_SCRIPT" continue "$WORKTREE" "$RESOLVED_SHA" β.txt 2>/dev/null)" || fail "the git script refused to continue with the non-ASCII file"

# A conflict in a later commit stops the continue again, and an abort gives the rebase up without a push.
git -C "$SOURCE" checkout --quiet main
printf 'again\n' >"$SOURCE/a.txt"
printf 'main b\n' >"$SOURCE/b.txt"
git -C "$SOURCE" add a.txt b.txt
git -C "$SOURCE" commit --quiet -m "conflict on main again"
git -C "$SOURCE" push --quiet "$UPSTREAM" main:refs/heads/main
"$GIT_SCRIPT" autosquash "$WORKTREE" "$RESOLVED_SHA" >/dev/null 2>&1
[ $? -eq 3 ] || fail "the git script did not exit 3 on the first conflict"
# The pattern argument must reach the script as it is, not as the files it matches.
set -f
for arguments in "fixup $CHANGE_SHA a.txt" "reword $CHANGE_SHA message.txt" "push $RESOLVED_SHA" "autosquash $RESOLVED_SHA" "tests $RESOLVED_SHA tests.yaml tests/**"; do
  # shellcheck disable=SC2086
  "$GIT_SCRIPT" ${arguments%% *} "$WORKTREE" ${arguments#* } 2>&1 >/dev/null | grep -q 'a rebase is in progress' || fail "the git script ran ${arguments%% *} in the middle of a rebase"
done
set +f
[ "$(git -C "$UPSTREAM" rev-parse fix/thing)" = "$RESOLVED_SHA" ] || fail "the git script moved the branch in the middle of a rebase"
printf 'resolved again\n' >"$WORKTREE/a.txt"
"$GIT_SCRIPT" continue "$WORKTREE" "$RESOLVED_SHA" a.txt >"$TEST_DIRECTORY/conflict" 2>/dev/null
[ $? -eq 3 ] || fail "the git script did not exit 3 on a conflict in a later commit"
[ "$(tail -n +2 "$TEST_DIRECTORY/conflict")" = b.txt ] || fail "the git script did not name the file of the later conflict"
"$GIT_SCRIPT" abort "$WORKTREE" >/dev/null 2>&1 || fail "the git script refused to abort"
[ ! -d "$(git -C "$WORKTREE" rev-parse --path-format=absolute --git-path rebase-merge)" ] || fail "the abort left the rebase in progress"
[ "$(git -C "$UPSTREAM" rev-parse fix/thing)" = "$RESOLVED_SHA" ] || fail "the git script pushed after an abort"
"$GIT_SCRIPT" continue "$WORKTREE" "$RESOLVED_SHA" a.txt >/dev/null 2>&1 && fail "the git script continued with no rebase in progress"
SQUASHED_SHA="$RESOLVED_SHA"

# Only a resolves worktree under the developer directory.
"$GIT_SCRIPT" push "$REVIEW_DEVELOPER_DIRECTORY/service" "$SQUASHED_SHA" >/dev/null 2>&1 && fail "the git script pushed from a checkout of the viewer"
git -C "$REVIEW_DEVELOPER_DIRECTORY/service" worktree add --quiet --detach "$REVIEW_DEVELOPER_DIRECTORY/worktrees/service/other" HEAD
"$GIT_SCRIPT" push "$REVIEW_DEVELOPER_DIRECTORY/worktrees/service/other" "$SQUASHED_SHA" >/dev/null 2>&1 && fail "the git script pushed from a worktree that is not resolves"
ln -s "$REVIEW_DEVELOPER_DIRECTORY/worktrees/service/other" "$TEST_DIRECTORY/resolves"
"$GIT_SCRIPT" push "$TEST_DIRECTORY/resolves" "$SQUASHED_SHA" >/dev/null 2>&1 && fail "the git script followed a symlink named resolves"
"$GIT_SCRIPT" push "$WORKTREE/b" "$SQUASHED_SHA" >/dev/null 2>&1 && fail "the git script accepted a folder inside the worktree"
"$GIT_SCRIPT" push "$WORKTREE" abc >/dev/null 2>&1 && fail "the git script accepted a short lease"
"$GIT_SCRIPT" rebase "$WORKTREE" "$SQUASHED_SHA" >/dev/null 2>&1 && fail "the git script accepted an unknown command"

# A `.git` of the worktree edited to point at a repository with a planted configuration, which would run a command on the first git call.
git init --quiet "$TEST_DIRECTORY/planted"
git -C "$TEST_DIRECTORY/planted" config core.fsmonitor "touch $TEST_DIRECTORY/planted-ran #"
printf 'main\n' >"$TEST_DIRECTORY/planted/.git/resolve-base"
printf 'fix/thing\n' >"$TEST_DIRECTORY/planted/.git/resolve-branch"
cp "$WORKTREE/.git" "$TEST_DIRECTORY/pointer"
printf 'gitdir: %s\n' "$TEST_DIRECTORY/planted/.git" >"$WORKTREE/.git"
printf 'three\n' >"$WORKTREE/b.txt"
"$GIT_SCRIPT" fixup "$WORKTREE" "$CHANGE_SHA" b.txt >/dev/null 2>&1 && fail "the git script committed in a worktree whose .git points elsewhere"
"$GIT_SCRIPT" push "$WORKTREE" "$SQUASHED_SHA" >/dev/null 2>&1 && fail "the git script pushed from a worktree whose .git points elsewhere"
"$GIT_SCRIPT" autosquash "$WORKTREE" "$SQUASHED_SHA" >/dev/null 2>&1 && fail "the git script rebased a worktree whose .git points elsewhere"
# At the head of the pull request, so the refusal comes from the worktree check and not from a moved head.
"$WORKTREE_SCRIPT" owner/service 7 "$HEAD_SHA" fix/thing 2>"$TEST_DIRECTORY/stderr" >/dev/null && fail "the worktree script moved a worktree whose .git points elsewhere"
grep -q 'is not a worktree of' "$TEST_DIRECTORY/stderr" || fail "the worktree script refused a .git pointing elsewhere for another reason"
printf 'gitdir: %s/service/.git/worktrees\n' "$REVIEW_DEVELOPER_DIRECTORY" >"$WORKTREE/.git"
"$GIT_SCRIPT" push "$WORKTREE" "$SQUASHED_SHA" >/dev/null 2>&1 && fail "the git script accepted a .git pointing at the worktrees folder itself"
rm "$WORKTREE/.git"
ln -s "$TEST_DIRECTORY/pointer" "$WORKTREE/.git"
"$GIT_SCRIPT" push "$WORKTREE" "$SQUASHED_SHA" >/dev/null 2>&1 && fail "the git script followed a symlinked .git"
[ ! -e "$TEST_DIRECTORY/planted-ran" ] || fail "a planted configuration ran a command"
rm "$WORKTREE/.git"
cp "$TEST_DIRECTORY/pointer" "$WORKTREE/.git"
pull_request
prepare >/dev/null || fail "the worktree script refused the worktree once its .git was put back"

if [ "$failures" -gt 0 ]; then
  exit 1
fi
echo "PASS: green worktree and git scripts"
