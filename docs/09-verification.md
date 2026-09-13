# 09. Verification

## The core distinction

Automation asks: **did the process run?**
Verification asks: **did running change something true?**

A scheduled job that failed and a scheduled job that succeeded occupy the same slot. Both have a last-run timestamp. Neither tells you the outcome. Only verification distinguishes them — by asking a question external to the job itself, and checking reality rather than the job's own exit code.

A job reporting its own success is a claim. You need the corroborating fact.

---

## Four verification patterns

### Pattern 1: Compare local vs remote (for backups, deployments, syncs)

Check two facts independently:
1. Count of commits ahead of remote must be zero
2. Remote head must have advanced since last check

One fact alone is insufficient. A local commit proves nothing about delivery. An empty remote proves nothing about intent.

**What to check:** `git log origin/main..HEAD --oneline | wc -l` should return 0 after push completes. Also check `git ls-remote origin main` to confirm the remote pointer moved.

### Pattern 2: Check file/output existence (for generated content, exports, reports)

Verify the expected artifact actually landed:
1. File exists at expected path
2. File has non-zero size (optional but recommended)
3. File timestamp is within expected window

**What to check:** use the repository's portable check, which verifies existence, non-zero size, and age without relying on a platform-specific pipeline:

```bash
bash scripts/verify.sh --check file-recent /path/to/output.md 24
```

### Pattern 3: Check downstream effect (for integrations, API calls, notifications)

If a system sends a notification, makes an API call, or updates a database, verify the downstream result:
1. Expected state change in target system
2. Confirmation message returned from target (if applicable)
3. Timestamp matches expected execution window

**What to check:** For API calls, verify the response body/status code indicates success. For database updates, query the affected row. For notifications, check the receiving channel for the message.

### Pattern 4: Idempotency check (for repeated operations)

Run the verification twice in succession. The second run should produce no changes:
1. First check: records baseline
2. Second check: confirms nothing changed between checks
3. If second check shows new changes, the operation may not be idempotent

This catches systems that "succeed" but also trigger additional side effects on re-execution.

---

## Verification in practice

Here is how verification appears in each layer of the four-layer framework:

### Automation → verified by outcome check
A backup script commits locally. Verification checks that those commits reached the remote. The script exits 0 (success). Verification may still fail if the push did not reach the destination.

### Guardrails → verified by rule compliance
A Git sync script refuses to overwrite uncommitted changes. Verification checks the working tree is clean afterward (no accidental modifications happened despite the guardrail firing).

### Observability → verified by signal correlation
Cron logs show a job ran. Verification checks whether the job produced the expected downstream result, not just whether it started and stopped.

### Verification → verified by cross-source confirmation
Two independent sources agree on the outcome. One says the task completed. Another says the result appeared where expected. If they disagree, investigate before declaring success.

---

## Building the check that would have caught it

Every incident taught a rule. Every rule produced a check. The complete checklist:

From [Incident 1: The backup that lied](08-what-breaks.md):
- Daily check: compare local commit count against remote commit count
- Alert when divergence exceeds zero for more than one cycle

From [Incident 2: The curator that could never start](08-what-breaks.md):
- Check file mode before execution attempt
- Use explicit interpreter invocation instead of depending on execute bit
- After each deployment, run the script once manually to confirm it executes

From [Incident 3: The curator that curated itself](08-what-breaks.md):
- Agents reading a store they also write to must exclude their own writes deterministically
- Prove the filter discriminates by listing what it excluded and confirming nothing genuine was caught
- A filter returning zero results is indistinguishable from a filter that excludes everything

From [Incident 4: The 429 with nowhere to fall back to](08-what-breaks.md):
- Every profile running unattended work must have a fallback chain configured
- Verify fallback loaded: read the profile config directly (the CLI flag varies by version)
- When creating a new profile, copy the safety nets from existing profiles or prove deliberate omission

---

## Verification is the differentiator

Most people build automations and consider their job done when the cron fires. The difference between amateur and professional is that amateurs trust their own tooling. Professionals verify outcomes independently of their own tooling.

Automate to reduce Friction.
Verify to eliminate Blindness.

Without verification, you are building Foreground Tax in disguise — a system that looks fine while requiring your attention. With verification, you build Background Growth — systems that produce outcomes without keeping the operator in the shot.

Build the second thing, or you have built the first one twice.
