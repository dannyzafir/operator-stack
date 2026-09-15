# 01. Architecture

## System overview

The reference architecture runs across two machines sharing GitHub as the single source of truth. No direct sync between machines — all coordination flows through version-controlled repos.

```
Mac (execution node)          GitHub (source of truth)           VPS (orchestrator)
───────────────              ───────────────────────             ────────────
┌──────────────────┐         ┌─────────────────┐               ┌──────────────────┐
│ Obsidian Vault    │         │ github.com/     │   git sync    │ Hermes Agent     │
│ Local repos       │ ◄────►  dannyzafir/      │ ◄───────────► │ Cron schedules   │
│ Computer Use      │         operator-stack    │   (safe pull/ │ Model routing    │
│ Browser automation│         (this repo)       │    push)      │ doctor/verify    │
└──────────────────┘         └─────────────────┘               └──────────────────┘
         ▲                                                             │
         │ Telegram / Discord (remote control surfaces)                │
         └─────────────────────────────────────────────────────────────┘
```

### Why this design?

Three constraints drove it:

1. **Never let one machine directly modify the other.** Direct filesystem access creates hidden state — files changed on the Mac that the VPS knows nothing about, commits pushed from the VPS that corrupt uncommitted local work. Shared origin + safe Git protocols eliminate this entire class of failure.

2. **Profiles isolate routing per project.** Each Hermes profile has its own model assignment, fallback chain, auxiliary model assignments, and credential scope. A failure or rate limit in one profile never affects another. Fallback chains belong to profiles, not jobs.

3. **Verification lives alongside automation, not inside it.** The automation script does its job. A separate verify script (or the `verify.sh` utility in this repo) checks whether the outcome occurred. They are distinct processes because the same failure mode applies everywhere: a job that ran and a job that succeeded produce identical signals if you only look at the job itself.

---

## Profile architecture

Each project gets its own Hermes profile folder under `~/.hermes/profiles/<name>/`. A profile contains:

| File | Purpose |
|------|---------|
| `config.yaml` | Model assignment, fallback providers, auxiliary models, delegation settings |
| `SOUL.md` | Persona and operational rules for this profile's agent instance |
| `state.db` | Conversation history (automatically managed) |

Key principle: **a profile is a self-contained execution context.** It decides which model to use, what fallback chain to apply, and how to delegate subagent work — independently of every other profile.

Example minimal config (`config.yaml`):

```yaml
model:
  default: <routine-model>
  provider: <primary-provider>
fallback_providers:
  - provider: <fallback-provider>
    model: <fallback-model>
delegation:
  model: <premium-model>
  provider: <premium-provider>
auxiliary:
  vision:
    provider: <vision-provider>
    model: <vision-model>
```

Profile routing decisions are independent. When you create a new profile, copy the safety nets (fallback chains, delegation settings) unless you deliberately omit them — because omitted safety nets are silent failures, which are the hardest kind to detect.

See [08-what-breaks.md](08-what-breaks.md) for the incident that taught this lesson.

---

## Safe Git workflow

All Git operations follow a strict protocol to prevent data loss:

### Pre-work (before pulling or editing)

1. Check `git status` — must show clean working tree
2. Run `git fetch` — update remote refs without merging
3. Check divergence — if `HEAD` is behind and ahead of `origin`, stop and alert
4. Abort and alert if anything fails

### During work

1. Commit frequently with descriptive messages
2. Never force push under any circumstance
3. Never reset --hard or discard uncommitted changes
4. Keep a diff available before each push so you can audit what changed

### Post-work (after completing changes)

1. Diff the working tree before committing
2. Stage and commit with clear messages
3. Fetch again to get latest remote state
4. Reconcile — fast-forward merge if clean, otherwise abort and investigate
5. Push with verbose output
6. Verify against the live system, not just the deployment URL

**The golden rule:** If anything in the pre-work check fails, stop. Do not guess. Do not try to "fix it by force pushing." There is always a safer option.

---

## Model routing philosophy

Models serve different tiers of work. The architecture stays stable while the specific providers and models can change:

| Tier | Purpose |
|------|---------|
| Routine default | Use the least expensive model that reliably completes the measured task |
| Provider fallback | Keep unattended work running when the primary provider is unavailable |
| Premium escalation | Reserve higher-cost capability for tasks that fail an explicit complexity or quality threshold |

Model preferences should be treated as versioned configuration, not permanent product claims. Evaluate changes against observed outcomes, record the comparison criteria, and update the routing table independently of the core architecture.

Routing happens at three levels:

1. **Session startup** — configured in `config.yaml` under `model.default`
2. **Delegation** — configured under `delegation.model/provider` in `config.yaml`
3. **Per-session override** — `/model` slash command during an active session

Model routing decisions are profile-level, not job-level. A profile decides which model to use for session startup, delegation, and per-session overrides independently of every other profile.

---

## Cron and scheduled jobs

Scheduled jobs run via Hermes' built-in cron system. Each job declares:

- Its model/provider (always pinned to the appropriate tier)
- Its schedule (cron expression or interval)
- Its deliver target (where results go)
- Its skills/prompt requirements

Jobs run independently. One failing job should never cascade into another. Verification scripts ensure each job produced an actual outcome, not just that it fired on schedule.

---

## Security principles

1. **Secrets never leave their machine.** SSH keys, API tokens, OAuth credentials stay local. Shared repos contain no credentials.
2. **Environment variables > hardcoded values.** Configuration goes in `.env` files that are gitignored. Templates go in `.env.example` with placeholder values.
3. **Least privilege.** Scripts run with the minimum permissions necessary. No sudo unless explicitly required and justified.
4. **Audit trail.** Every significant change produces a git commit. The commit message describes what changed and why.

These principles serve as defaults, and are also written up in [SECURITY.md](../SECURITY.md).
