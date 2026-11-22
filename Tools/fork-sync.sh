#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Fork sync: keeps this fork on the latest upstream Vorssaint release with the
# fork's own changes on top, and installs the result into /Applications.
#
# Runs every evening from launchd (Tools/io.github.iamsumanp.vorssaint-sync.plist).
# It needs no Claude and no account: only git, the Swift toolchain and build.sh.
#
#   1. Fetch upstream release tags. Nothing new → exit.
#   2. Replay the fork's commits (the branch's commits since it left upstream)
#      onto the new release tag.
#   3. Run the test suite, then build and install, then reopen Vorssaint.
#   4. Push the result to the fork (best effort).
#
# Any conflict or failure leaves the installed app and the branch as they were
# and posts a Peaky notification. Log: ~/Library/Logs/vorssaint-fork-sync.log
#
#   Tools/fork-sync.sh            normal run (only after 19:00, once per release)
#   Tools/fork-sync.sh --force    run now, rebuild even if nothing is new

set -uo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BRANCH="peaky-additions"
STATE_DIR="$HOME/Library/Application Support/VorssaintForkSync"
STATE="$STATE_DIR/last-release"
LOG="$HOME/Library/Logs/vorssaint-fork-sync.log"
LOCK="$STATE_DIR/lock"
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

mkdir -p "$STATE_DIR" "$(dirname "$LOG")"
exec >>"$LOG" 2>&1
echo
echo "=== $(date '+%Y-%m-%d %H:%M:%S') fork sync (force=$FORCE)"

notify() {
    local title="$1" detail="${2:-}"
    echo "notify: $title — $detail"
    if [[ -x "$HOME/.local/bin/peaky" ]]; then
        "$HOME/.local/bin/peaky" -s arrow.triangle.2.circlepath "$title" "$detail" >/dev/null 2>&1 && return
    fi
    osascript -e "display notification \"${detail//\"/}\" with title \"${title//\"/}\"" >/dev/null 2>&1 || true
}

fail() {
    notify "Vorssaint fork sync failed" "$1 — see ~/Library/Logs/vorssaint-fork-sync.log"
    exit 1
}

# Evenings only: launchd also fires a missed run at wake, which may be morning.
if (( !FORCE )) && (( $(date +%H) < 19 )); then
    echo "before 19:00, skipping"
    exit 0
fi

# One run at a time.
if ! mkdir "$LOCK" 2>/dev/null; then
    if [[ -n "$(find "$LOCK" -maxdepth 0 -mmin +120 2>/dev/null)" ]]; then
        rmdir "$LOCK"; mkdir "$LOCK"
    else
        echo "another run holds the lock, skipping"
        exit 0
    fi
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

cd "$REPO" || fail "repo missing at $REPO"

git fetch --quiet --tags upstream || fail "could not fetch upstream"
# Latest stable release: vX.Y.Z tags only, no betas.
LATEST="$(git tag -l 'v[0-9]*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)"
[[ -n "$LATEST" ]] || fail "no upstream release tag found"
LAST="$(cat "$STATE" 2>/dev/null || true)"
echo "latest upstream release: $LATEST, last synced: ${LAST:-none}"

if (( !FORCE )) && [[ "$LATEST" == "$LAST" ]]; then
    echo "up to date"
    exit 0
fi

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    fail "the repo has uncommitted changes; commit or stash them first"
fi

git checkout --quiet "$BRANCH" || fail "could not check out $BRANCH"
BEFORE="$(git rev-parse HEAD)"

# Replay only the fork's own commits: those since the branch last met upstream.
if ! git merge-base --is-ancestor "$LATEST" HEAD; then
    BASE="$(git merge-base HEAD "$LATEST")"
    FORK_BASE="$(git merge-base HEAD upstream/main)"
    # Commits already in the release are dropped by rebase on its own.
    echo "rebasing $(git rev-list --count "$FORK_BASE"..HEAD) fork commit(s) onto $LATEST"
    if ! git rebase --quiet --onto "$LATEST" "$FORK_BASE" "$BRANCH"; then
        git rebase --abort 2>/dev/null
        git reset --quiet --hard "$BEFORE"
        fail "$LATEST changes code the fork also changes (rebase conflict)"
    fi
else
    echo "$LATEST is already in $BRANCH"
fi

restore() {
    git reset --quiet --hard "$BEFORE"
    fail "$1"
}

echo "running tests…"
TEST_LOG="$STATE_DIR/last-test.log"
if ! ./build.sh --test >"$TEST_LOG" 2>&1; then
    grep -v sandbox_extension "$TEST_LOG" | grep -E "FAILED|  - " | head -30
    restore "tests failed on $LATEST + fork changes"
fi

echo "building and installing…"
WAS_RUNNING=0
pgrep -x Vorssaint >/dev/null 2>&1 && WAS_RUNNING=1
./build.sh --install || restore "build or install failed"
if (( WAS_RUNNING )) || ! pgrep -x Vorssaint >/dev/null 2>&1; then
    open -a "/Applications/Vorssaint.app" || true
fi

echo "$LATEST" > "$STATE"

# Publish to the fork. launchd may lack the SSH agent, so this is best effort.
if git push --quiet --force-with-lease origin "$BRANCH" "$BRANCH:main"; then
    echo "pushed to origin"
else
    echo "push failed (not fatal)"
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/Vorssaint.app/Contents/Info.plist 2>/dev/null)"
notify "Vorssaint updated to ${VERSION:-$LATEST}" "Latest release with your fork's changes"
echo "done: $LATEST"
