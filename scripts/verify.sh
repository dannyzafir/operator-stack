#!/usr/bin/env bash
# verify.sh — Did the expected outcome actually happen?
# Exit codes: 0 verified, 1 outcome not verified, 2 invalid usage.

set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
VERBOSE="${VERBOSE:-false}"
MAX_TASK_AGE_HOURS="${MAX_TASK_AGE_HOURS:-48}"
PASSED=0
FAILED=0
SKIPPED=0

pass() { echo "[PASS] $*"; ((PASSED++)) || true; }
fail() { echo "[FAIL] $*" >&2; ((FAILED++)) || true; }
skip() { echo "[SKIP] $*"; ((SKIPPED++)) || true; }
info() { [ "$VERBOSE" = "true" ] && echo "[INFO] $*" || true; }

usage() {
    cat <<'EOF'
Usage:
  bash scripts/verify.sh
  bash scripts/verify.sh --check git-divergence [repo-path]
  bash scripts/verify.sh --check file-recent <file> [max-age-hours]
  bash scripts/verify.sh --check backup-arrival <source-repo> <destination-repo>
  bash scripts/verify.sh --check schedule-fired <output-file> [max-age-hours]

Checks return 0 only when the requested outcome is verified, 1 when it is not,
and 2 for invalid or incomplete arguments. The default run checks repository
divergence when origin exists and verifies that README.md is recent and non-empty.
EOF
}

require_positive_integer() {
    case "$1" in
        ''|*[!0-9]*|0) echo "Invalid positive integer: $1" >&2; exit 2 ;;
    esac
}

remote_branch() {
    local repo="$1" branch
    branch=$(git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
    if [ -n "$branch" ]; then printf '%s\n' "${branch#origin/}"; return 0; fi
    branch=$(git -C "$repo" branch --show-current 2>/dev/null || true)
    if [ -n "$branch" ] && git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        printf '%s\n' "$branch"; return 0
    fi
    for branch in main master trunk; do
        if git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
            printf '%s\n' "$branch"; return 0
        fi
    done
    return 1
}

check_git_divergence() {
    local repo="${1:-$REPO_ROOT}" branch ahead behind
    echo "--- Git divergence check ---"
    if ! command -v git >/dev/null 2>&1; then fail "git is unavailable"; return; fi
    if ! git -C "$repo" rev-parse --verify HEAD >/dev/null 2>&1; then fail "Not a Git repository with a commit: $repo"; return; fi
    if ! git -C "$repo" remote get-url origin >/dev/null 2>&1; then fail "No origin remote configured: $repo"; return; fi
    if ! git -C "$repo" fetch --quiet origin; then fail "Cannot fetch origin"; return; fi
    if ! branch=$(remote_branch "$repo"); then fail "Cannot determine the remote branch"; return; fi
    behind=$(git -C "$repo" rev-list --count "HEAD..origin/$branch")
    ahead=$(git -C "$repo" rev-list --count "origin/$branch..HEAD")
    info "Ahead: $ahead; behind: $behind"
    if [ "$ahead" -eq 0 ] && [ "$behind" -eq 0 ]; then
        pass "In sync with origin/$branch"
    elif [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
        fail "Local and origin/$branch have diverged ($ahead ahead, $behind behind)"
    elif [ "$behind" -gt 0 ]; then
        fail "Local is $behind commit(s) behind origin/$branch"
    else
        fail "Local is $ahead commit(s) ahead of origin/$branch"
    fi
}

check_file_recent() {
    local target="$1" max_age="${2:-$MAX_TASK_AGE_HOURS}" mtime now age
    echo "--- File recent check ---"
    require_positive_integer "$max_age"
    if [ ! -f "$target" ]; then fail "File not found: $target"; return; fi
    if [ ! -s "$target" ]; then fail "File is empty: $target"; return; fi
    mtime=$(stat -c '%Y' "$target" 2>/dev/null || stat -f '%m' "$target" 2>/dev/null || true)
    if [ -z "$mtime" ]; then fail "Cannot read modification time: $target"; return; fi
    now=$(date +%s)
    age=$((now - mtime))
    if [ "$age" -le $((max_age * 3600)) ]; then
        pass "File is non-empty and $((age / 3600))h old (limit: ${max_age}h): $target"
    else
        fail "File is $((age / 3600))h old (limit: ${max_age}h): $target"
    fi
}

check_backup_arrival() {
    local source="$1" destination="$2" source_hash destination_repo temporary="" ref arrived=false
    echo "--- Backup arrival check ---"
    if ! source_hash=$(git -C "$source" rev-parse --verify HEAD 2>/dev/null); then
        fail "Source is not a Git repository with a commit: $source"; return
    fi
    if [ -d "$destination" ]; then
        destination_repo="$destination"
    else
        temporary=$(mktemp -d)
        if ! git clone --quiet --mirror "$destination" "$temporary/destination.git"; then
            rm -rf -- "$temporary"
            fail "Destination remote is unreachable or unreadable: $destination"; return
        fi
        destination_repo="$temporary/destination.git"
    fi
    if git -C "$destination_repo" cat-file -e "$source_hash^{commit}" 2>/dev/null; then
        while IFS= read -r ref; do
            if git -C "$destination_repo" merge-base --is-ancestor "$source_hash" "$ref" 2>/dev/null; then
                arrived=true
                break
            fi
        done < <(git -C "$destination_repo" for-each-ref --format='%(refname)' refs/heads refs/remotes)
    fi
    [ -z "$temporary" ] || rm -rf -- "$temporary"
    if [ "$arrived" = "true" ]; then
        pass "Source HEAD is present in destination history"
    else
        fail "Source HEAD has not arrived in destination history"
    fi
}

check_schedule_fired() {
    local output="$1" max_age="${2:-$MAX_TASK_AGE_HOURS}"
    echo "--- Schedule outcome check ---"
    require_positive_integer "$max_age"
    if [ ! -f "$output" ]; then fail "Scheduled output not found: $output"; return; fi
    if [ ! -s "$output" ]; then fail "Scheduled output is empty: $output"; return; fi
    check_file_recent "$output" "$max_age"
}

TARGET_CHECK="all"
if [ $# -gt 0 ]; then
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --check)
            [ $# -ge 2 ] || { echo "Missing check name after --check" >&2; usage >&2; exit 2; }
            TARGET_CHECK="$2"; shift 2
            ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
fi

echo "========================================="
echo "  The Operator Stack — Verification"
echo "========================================="

case "$TARGET_CHECK" in
    all)
        [ $# -eq 0 ] || { usage >&2; exit 2; }
        if git -C "$REPO_ROOT" remote get-url origin >/dev/null 2>&1; then
            check_git_divergence "$REPO_ROOT"
        else
            skip "Git divergence (no origin configured yet)"
        fi
        check_file_recent "$REPO_ROOT/README.md" "$MAX_TASK_AGE_HOURS"
        skip "Backup arrival (requires source and destination inputs)"
        skip "Schedule outcome (requires an output-file input)"
        ;;
    git-divergence)
        [ $# -le 1 ] || { usage >&2; exit 2; }
        check_git_divergence "${1:-$REPO_ROOT}"
        ;;
    file-recent)
        [ $# -ge 1 ] && [ $# -le 2 ] || { echo "file-recent requires <file> [max-age-hours]" >&2; exit 2; }
        check_file_recent "$1" "${2:-$MAX_TASK_AGE_HOURS}"
        ;;
    backup-arrival)
        [ $# -eq 2 ] || { echo "backup-arrival requires <source-repo> <destination-repo>" >&2; exit 2; }
        check_backup_arrival "$1" "$2"
        ;;
    schedule-fired)
        [ $# -ge 1 ] && [ $# -le 2 ] || { echo "schedule-fired requires <output-file> [max-age-hours]" >&2; exit 2; }
        check_schedule_fired "$1" "${2:-$MAX_TASK_AGE_HOURS}"
        ;;
    *) echo "Unknown check: $TARGET_CHECK" >&2; usage >&2; exit 2 ;;
esac

echo "========================================="
echo "  Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
echo "========================================="
[ "$FAILED" -eq 0 ] || exit 1
exit 0
