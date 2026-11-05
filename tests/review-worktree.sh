#!/bin/bash

# Checks `review-worktree.sh` against local repositories and a stub `gh`, never
# the real GitHub. It finds a checkout under the developer directory by its
# `origin` whatever the folder is called, never clones one that exists nor into
# a folder of another repository, puts one detached `reviews` worktree at the pull
# request head and moves it for the next one, runs no hook from the pull request,
# refuses a pull request that moved or a worktree of another repository, and
# rejects a bad repository, number or commit.

TESTS_SCRIPT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WRAPPER="$TESTS_SCRIPT_DIRECTORY/../.config/scripts/review/review-worktree.sh"

TEST_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

failures=0
fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL="$TEST_DIRECTORY/gitconfig"
export REVIEW_DEVELOPER_DIRECTORY="$TEST_DIRECTORY/developer"
export STUB_GH_LOG="$TEST_DIRECTORY/gh.log"
export STUB_UPSTREAM="$TEST_DIRECTORY/upstream.git"
mkdir -p "$REVIEW_DEVELOPER_DIRECTORY" "$TEST_DIRECTORY/bin"

# The upstream has a main commit and two pull request heads, each with its own file.
# The branch is named here, a runner defaults to another one and leaves the clones empty.
git init --quiet --bare --initial-branch=main "$STUB_UPSTREAM"
git init --quiet --initial-branch=main "$TEST_DIRECTORY/source"
git -C "$TEST_DIRECTORY/source" commit --quiet --allow-empty -m base
for number in 7 8; do
  git -C "$TEST_DIRECTORY/source" checkout --quiet -b "pull$number" main
  echo "change $number" >"$TEST_DIRECTORY/source/change.txt"
  git -C "$TEST_DIRECTORY/source" add change.txt
  git -C "$TEST_DIRECTORY/source" commit --quiet -m "pull $number"
  git -C "$TEST_DIRECTORY/source" push --quiet "$STUB_UPSTREAM" "HEAD:refs/pull/$number/head"
  if [ "$number" = 7 ]; then
    SHA_7="$(git -C "$TEST_DIRECTORY/source" rev-parse HEAD)"
  else
    SHA_8="$(git -C "$TEST_DIRECTORY/source" rev-parse HEAD)"
  fi
done
git -C "$TEST_DIRECTORY/source" push --quiet "$STUB_UPSTREAM" main:refs/heads/main

# Fetching the GitHub address of the repository reads the local upstream instead.
cat >"$GIT_CONFIG_GLOBAL" <<EOF
[url "$STUB_UPSTREAM"]
  insteadOf = git@github.com:owner/service.git
  insteadOf = git@github.com:acme/app.git
[protocol "file"]
  allow = always
EOF

git clone --quiet "$STUB_UPSTREAM" "$REVIEW_DEVELOPER_DIRECTORY/checkout-under-another-name"
git -C "$REVIEW_DEVELOPER_DIRECTORY/checkout-under-another-name" remote set-url origin git@github.com:owner/service.git
# A hook of the checkout must not run, the wrapper switches hooks off.
mkdir -p "$REVIEW_DEVELOPER_DIRECTORY/checkout-under-another-name/.git/hooks"
printf '#!/bin/sh\ntouch "%s/hook-ran"\n' "$TEST_DIRECTORY" >"$REVIEW_DEVELOPER_DIRECTORY/checkout-under-another-name/.git/hooks/post-checkout"
chmod +x "$REVIEW_DEVELOPER_DIRECTORY/checkout-under-another-name/.git/hooks/post-checkout"

# The stub only knows a clone, it logs the call and clones the local upstream, then points
# `origin` at the GitHub address the way a real clone has it.
cat >"$TEST_DIRECTORY/bin/gh" <<'STUB'
#!/bin/bash
echo "$*" >>"$STUB_GH_LOG"
if [ "$1 $2" = "repo clone" ]; then
  git clone --quiet "$STUB_UPSTREAM" "$4"
  git -C "$4" remote set-url origin "git@github.com:$3.git"
fi
STUB
chmod +x "$TEST_DIRECTORY/bin/gh"
export PATH="$TEST_DIRECTORY/bin:$PATH"

WORKTREE="$REVIEW_DEVELOPER_DIRECTORY/worktrees/checkout-under-another-name/reviews"
[ "$("$WRAPPER" owner/service 7 "$SHA_7" 2>/dev/null)" = "$WORKTREE" ] || fail "the wrapper did not print the reviews worktree"
[ ! -e "$STUB_GH_LOG" ] || fail "the wrapper cloned a repository that is already on the machine"
[ "$(git -C "$WORKTREE" rev-parse HEAD)" = "$SHA_7" ] || fail "the worktree is not at the pull request head"
[ -z "$(git -C "$WORKTREE" branch --show-current)" ] || fail "the worktree is on a branch, not detached"
[ ! -e "$TEST_DIRECTORY/hook-ran" ] || fail "a hook ran from the pull request"
"$WRAPPER" owner/service 8 "$SHA_8" >/dev/null 2>&1 || fail "the wrapper failed to move the worktree to the next pull request"
[ "$(cat "$WORKTREE/change.txt")" = "change 8" ] || fail "the worktree did not move to the next pull request"
"$WRAPPER" owner/service 8 "$SHA_7" >/dev/null 2>&1 && fail "the wrapper accepted a pull request that moved to another commit"
[ ! -e "$REVIEW_DEVELOPER_DIRECTORY/checkout-under-another-name/.git/review-worktree.lock" ] || fail "the wrapper left its lock behind"
mkdir "$REVIEW_DEVELOPER_DIRECTORY/checkout-under-another-name/.git/review-worktree.lock"
REVIEW_LOCK_ATTEMPTS=1 "$WRAPPER" owner/service 7 "$SHA_7" >/dev/null 2>&1 && fail "the wrapper ran while another review held the repository"
rmdir "$REVIEW_DEVELOPER_DIRECTORY/checkout-under-another-name/.git/review-worktree.lock"

# A symlink of the pull request lands as a plain file, never a link out of the worktree.
git -C "$TEST_DIRECTORY/source" checkout --quiet -b pull9 main
ln -s /etc/hosts "$TEST_DIRECTORY/source/link"
git -C "$TEST_DIRECTORY/source" add link
git -C "$TEST_DIRECTORY/source" commit --quiet -m "pull 9"
git -C "$TEST_DIRECTORY/source" push --quiet "$STUB_UPSTREAM" HEAD:refs/pull/9/head
SHA_9="$(git -C "$TEST_DIRECTORY/source" rev-parse HEAD)"
"$WRAPPER" owner/service 9 "$SHA_9" >/dev/null 2>&1 || fail "the wrapper failed on a pull request with a symlink"
[ ! -L "$WORKTREE/link" ] || fail "a symlink of the pull request was written as a link"

# The folder `app` belongs to another owner, so the clone goes next to it.
git clone --quiet "$STUB_UPSTREAM" "$REVIEW_DEVELOPER_DIRECTORY/app"
git -C "$REVIEW_DEVELOPER_DIRECTORY/app" remote set-url origin git@github.com:owner/app.git
"$WRAPPER" acme/app 7 "$SHA_7" >/dev/null 2>&1 || fail "the wrapper failed to clone a repository that is not on the machine"
[ -d "$REVIEW_DEVELOPER_DIRECTORY/acme-app/.git" ] || fail "the wrapper did not clone next to a folder of another repository"
grep -q 'repo clone acme/app' "$STUB_GH_LOG" || fail "the wrapper did not clone through gh"

# A worktree of another repository is never moved.
git -C "$REVIEW_DEVELOPER_DIRECTORY/acme-app" worktree remove --force "$REVIEW_DEVELOPER_DIRECTORY/worktrees/acme-app/reviews"
git -C "$REVIEW_DEVELOPER_DIRECTORY/app" worktree add --quiet --detach "$REVIEW_DEVELOPER_DIRECTORY/worktrees/acme-app/reviews" HEAD
"$WRAPPER" acme/app 7 "$SHA_7" >/dev/null 2>&1 && fail "the wrapper moved the worktree of another repository"

"$WRAPPER" 'owner/service extra' 7 "$SHA_7" >/dev/null 2>&1 && fail "the wrapper accepted a repository with a space"
"$WRAPPER" owner/service x "$SHA_7" >/dev/null 2>&1 && fail "the wrapper accepted a non numeric pull request"
"$WRAPPER" owner/service 7 abc >/dev/null 2>&1 && fail "the wrapper accepted a short commit"
"$WRAPPER" "$(printf 'owner/service\nx/y')" 7 "$SHA_7" >/dev/null 2>&1 && fail "the wrapper accepted a repository with a newline"

if [ "$failures" -gt 0 ]; then
  exit 1
fi
echo "PASS: review worktree script"
