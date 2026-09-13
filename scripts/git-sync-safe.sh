#!/usr/bin/env bash
# git-sync-safe.sh — Synchronize a clean repository without overwriting history.
#
# Usage:
#   bash scripts/git-sync-safe.sh <source-directory> <remote-url>
#
# Examples:
#   bash scripts/git-sync-safe.sh ~/my-project https://github.com/<your-username>/my-project.git
#   bash scripts/git-sync-safe.sh ~/path/to/your/vault https://github.com/<your-username>/your-vault.git
#
# Exit codes: 0 synchronized, 1 safety/remote failure, 2 invalid usage.

set -uo pipefail

if [ $# -ne 2 ]; then
    echo "Usage: bash scripts/git-sync-safe.sh <source-directory> <remote-url>" >&2
    exit 2
fi

SOURCE_DIR="$1"
REMOTE_URL="$2"
TEMP_REMOTE=false
REMOTE_NAME=origin

cleanup() {
    if [ "$TEMP_REMOTE" = "true" ]; then
        git -C "$SOURCE_DIR" remote remove "$REMOTE_NAME" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT HUP INT TERM

if ! git -C "$SOURCE_DIR" rev-parse --verify HEAD >/dev/null 2>&1; then
    echo "ERROR: '$SOURCE_DIR' is not a Git repository with a commit" >&2
    exit 1
fi

echo "========================================="
echo "  Safe Git Sync"
echo "  Source: $SOURCE_DIR"
echo "  Remote: $REMOTE_URL"
echo "========================================="

dirty=$(git -C "$SOURCE_DIR" status --porcelain)
if [ -n "$dirty" ]; then
    echo "SAFETY STOP: Working tree is dirty. Commit or stash your work before syncing." >&2
    printf '%s\n' "$dirty" >&2
    exit 1
fi
echo "[PASS] Working tree is clean"

if git -C "$SOURCE_DIR" remote get-url origin >/dev/null 2>&1; then
    configured=$(git -C "$SOURCE_DIR" remote get-url origin)
    if [ "$configured" != "$REMOTE_URL" ]; then
        echo "SAFETY STOP: Supplied remote does not match configured origin." >&2
        exit 1
    fi
else
    REMOTE_NAME=operator-stack-sync
    if ! git -C "$SOURCE_DIR" remote add "$REMOTE_NAME" "$REMOTE_URL"; then
        echo "ERROR: Could not configure temporary remote" >&2
        exit 1
    fi
    TEMP_REMOTE=true
    echo "[WARN] No origin configured; using a temporary remote for this run"
fi

if ! git -C "$SOURCE_DIR" fetch --quiet "$REMOTE_NAME"; then
    echo "SAFETY STOP: Remote is unreachable or refused authentication." >&2
    exit 1
fi
echo "[PASS] Remote fetched without merging"

branch=$(git -C "$SOURCE_DIR" symbolic-ref --quiet --short "refs/remotes/$REMOTE_NAME/HEAD" 2>/dev/null || true)
branch="${branch#${REMOTE_NAME}/}"
if [ -z "$branch" ]; then
    current=$(git -C "$SOURCE_DIR" branch --show-current 2>/dev/null || true)
    if [ -n "$current" ] && git -C "$SOURCE_DIR" show-ref --verify --quiet "refs/remotes/$REMOTE_NAME/$current"; then
        branch="$current"
    else
        for candidate in main master trunk; do
            if git -C "$SOURCE_DIR" show-ref --verify --quiet "refs/remotes/$REMOTE_NAME/$candidate"; then
                branch="$candidate"
                break
            fi
        done
    fi
fi

if [ -z "$branch" ]; then
    echo "SAFETY STOP: Could not determine the remote branch." >&2
    exit 1
fi

behind=$(git -C "$SOURCE_DIR" rev-list --count "HEAD..$REMOTE_NAME/$branch")
ahead=$(git -C "$SOURCE_DIR" rev-list --count "$REMOTE_NAME/$branch..HEAD")
echo "STATUS: local is $ahead ahead and $behind behind $REMOTE_NAME/$branch"

if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
    echo "SAFETY STOP: Local and remote have diverged; human intervention is required." >&2
    echo "Inspect with: git log --oneline --graph --decorate --all" >&2
    exit 1
elif [ "$behind" -gt 0 ]; then
    echo "ACTION: Local is behind; applying a fast-forward-only update."
    if ! git -C "$SOURCE_DIR" merge --ff-only "$REMOTE_NAME/$branch"; then
        echo "SAFETY STOP: Fast-forward update failed; human intervention is required." >&2
        exit 1
    fi
    echo "[PASS] Fast-forward update completed"
elif [ "$ahead" -gt 0 ]; then
    echo "ACTION: Local is ahead; pushing the intended commits."
    if ! git -C "$SOURCE_DIR" push "$REMOTE_NAME" "HEAD:$branch"; then
        echo "SAFETY STOP: Push failed; inspect authentication and remote state." >&2
        exit 1
    fi
    echo "[PASS] Push completed"
else
    echo "[PASS] Local and remote are already in sync"
fi

if ! git -C "$SOURCE_DIR" fetch --quiet "$REMOTE_NAME"; then
    echo "[FAIL] Post-sync fetch failed; outcome could not be verified." >&2
    exit 1
fi
final_behind=$(git -C "$SOURCE_DIR" rev-list --count "HEAD..$REMOTE_NAME/$branch")
final_ahead=$(git -C "$SOURCE_DIR" rev-list --count "$REMOTE_NAME/$branch..HEAD")
if [ "$final_ahead" -ne 0 ] || [ "$final_behind" -ne 0 ]; then
    echo "[FAIL] Post-sync verification found $final_ahead ahead and $final_behind behind." >&2
    exit 1
fi

echo "[PASS] Verified: local and remote now point to the same history"
exit 0
