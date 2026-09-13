#!/usr/bin/env bash
# doctor.sh — Is The Operator Stack environment ready?
# PASS = healthy, WARN = optional or not configured, FAIL = required breakage.
# Exit codes: 0 no required failures, 1 required failure, 2 invalid usage.

set -uo pipefail

if [ $# -gt 0 ]; then
    case "$1" in
        --help|-h)
            echo "Usage: bash scripts/doctor.sh"
            echo "Optional environment: HERMES_REQUIRED, HERMES_PROFILE, VAULT_PATH, MAX_TASK_AGE_HOURS"
            exit 0
            ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
fi

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

pass() { echo "[PASS] $*"; ((PASS_COUNT++)) || true; }
warn() { echo "[WARN] $*" >&2; ((WARN_COUNT++)) || true; }
fail() { echo "[FAIL] $*" >&2; ((FAIL_COUNT++)) || true; }

# Read only known key=value settings. Do not execute .env as shell code.
ENV_FILE="$REPO_ROOT/.env"
if [ -f "$ENV_FILE" ]; then
    while IFS='=' read -r key value; do
        case "$key" in
            HERMES_REQUIRED) [ -n "${HERMES_REQUIRED+x}" ] || HERMES_REQUIRED="$value" ;;
            HERMES_PROFILE) [ -n "${HERMES_PROFILE+x}" ] || HERMES_PROFILE="$value" ;;
            VAULT_PATH) [ -n "${VAULT_PATH+x}" ] || VAULT_PATH="$value" ;;
            MAX_TASK_AGE_HOURS) [ -n "${MAX_TASK_AGE_HOURS+x}" ] || MAX_TASK_AGE_HOURS="$value" ;;
        esac
    done < "$ENV_FILE"
fi

HERMES_REQUIRED="${HERMES_REQUIRED:-false}"
HERMES_PROFILE="${HERMES_PROFILE:-}"
VAULT_PATH="${VAULT_PATH:-}"
MAX_TASK_AGE_HOURS="${MAX_TASK_AGE_HOURS:-48}"

echo "========================================="
echo "  The Operator Stack — Doctor"
echo "========================================="

echo "--- Required dependencies ---"
for cmd in bash git stat date grep sed find wc; do
    if command -v "$cmd" >/dev/null 2>&1; then pass "$cmd is available"; else fail "$cmd is required but unavailable"; fi
done

echo "--- Repository and scripts ---"
if command -v git >/dev/null 2>&1 && git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    pass "Repository is a valid Git working tree"
    if [ -n "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ]; then
        warn "Repository has uncommitted changes"
    else
        pass "Repository working tree is clean"
    fi
    if git -C "$REPO_ROOT" remote get-url origin >/dev/null 2>&1; then
        pass "origin remote is configured"
    else
        warn "origin remote is not configured (local-only work still functions)"
    fi
else
    fail "Repository is not a valid Git working tree"
fi

for script in doctor.sh verify.sh git-sync-safe.sh; do
    if [ ! -f "$SCRIPTS_DIR/$script" ]; then
        fail "$script is missing"
    elif [ ! -x "$SCRIPTS_DIR/$script" ]; then
        fail "$script exists but is not executable"
    else
        pass "$script is present and executable"
    fi
done

echo "--- Environment configuration ---"
if [ -f "$ENV_FILE" ]; then
    perms=$(stat -c '%a' "$ENV_FILE" 2>/dev/null || stat -f '%Lp' "$ENV_FILE" 2>/dev/null || true)
    case "$perms" in 600|400) pass ".env permissions are restricted ($perms)" ;; *) warn ".env permissions are $perms; use 600 or 400" ;; esac
else
    warn "No .env file yet; this is a fresh/default configuration"
fi

case "$MAX_TASK_AGE_HOURS" in
    ''|*[!0-9]*|0) fail "MAX_TASK_AGE_HOURS must be a positive integer" ;;
    *) pass "MAX_TASK_AGE_HOURS is valid ($MAX_TASK_AGE_HOURS)" ;;
esac

echo "--- Hermes environment ---"
if command -v hermes >/dev/null 2>&1; then
    pass "Hermes CLI is available"
else
    if [ "$HERMES_REQUIRED" = "true" ]; then fail "Hermes CLI is required but unavailable"; else warn "Hermes CLI is optional and unavailable"; fi
fi

if [ -n "$HERMES_PROFILE" ]; then
    case "$HERMES_PROFILE" in
        /*) profile_path="$HERMES_PROFILE" ;;
        *) profile_path="$HOME/.hermes/profiles/$HERMES_PROFILE" ;;
    esac
    if [ -d "$profile_path" ]; then
        pass "Configured Hermes profile exists"
    elif [ "$HERMES_REQUIRED" = "true" ]; then
        fail "Configured Hermes profile does not exist"
    else
        warn "Configured optional Hermes profile does not exist"
    fi
else
    if [ "$HERMES_REQUIRED" = "true" ]; then fail "HERMES_PROFILE is required but unset"; else warn "No Hermes profile selected (optional)"; fi
fi

echo "--- Optional local knowledge path ---"
if [ -z "$VAULT_PATH" ]; then
    warn "VAULT_PATH is not configured (optional)"
else
    case "$VAULT_PATH" in '~/'*) resolved_vault="$HOME/${VAULT_PATH#~/}" ;; *) resolved_vault="$VAULT_PATH" ;; esac
    if [ -d "$resolved_vault" ]; then pass "Configured knowledge path exists"; else warn "Configured optional knowledge path does not exist"; fi
fi

echo "--- Git identity ---"
if command -v git >/dev/null 2>&1; then
    git_name=$(git -C "$REPO_ROOT" config user.name 2>/dev/null || true)
    git_email=$(git -C "$REPO_ROOT" config user.email 2>/dev/null || true)
    if [ -n "$git_name" ] && [ -n "$git_email" ]; then pass "Git commit identity is configured"; else warn "Git commit identity is incomplete"; fi
fi

echo "========================================="
echo "  Results: $PASS_COUNT passed, $WARN_COUNT warnings, $FAIL_COUNT failures"
echo "========================================="
if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "Required checks failed." >&2
    exit 1
fi
echo "Required checks passed; warnings are non-blocking."
exit 0
