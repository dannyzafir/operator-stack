# The Operator Stack

## Background Growth, installed.

Automation is easy to schedule. The difficult part is knowing it actually worked.

The Operator Stack is a collection of scripts, patterns, and verification loops built from real systems that failed quietly—and the lessons those failures taught me about keeping the operator out of the shot.

## Foreground Tax and Background Growth

**Foreground Growth:** the operator has to remain present for the process to produce an outcome. Every enquiry, follow-up, report, and approval needs someone in the shot.

**Background Growth:** the system continues producing the outcome without requiring the operator to stay in the shot.

The Stack addresses the infrastructure underneath that transition. Its core insight is simple:

> Automation without verification can create invisible Foreground Tax.

A silent failure pulls the operator back into the shot because decisions continue resting on information that stopped being true.

> Businesses are not behind on AI because they picked the wrong tool. They are behind because the bottleneck is the operator's attention, and their identity is built on how they currently spend it.

## The four layers

Most systems stop at automation. A complete unattended system has four layers:

1. **Automation — make the work happen.** Scheduled jobs, API calls, data pipelines, and agent runs produce the output.
2. **Guardrails — prevent destructive behaviour.** Safe sync, isolated credentials, and fallback rules stop bad outcomes before they happen.
3. **Observability — show what happened.** Logs, alerts, and timestamps expose the process state.
4. **Verification — prove the outcome occurred.** A separate check corroborates the result against reality, not the job's own claim.

Observability says the process ran. Verification proves running changed something true.

## The four incidents

Four live failures shaped this project:

- **The backup that lied for three nights:** local commits succeeded while every remote push failed.
- **The curator that could never start:** a scheduled script had the wrong file mode and failed on every run.
- **The curator that curated itself:** an agent read its own generated sessions back as source knowledge.
- **The rate limit with nowhere to fall back to:** an unattended profile had no provider fallback.

Each looked healthy from the outside. Each produced a concrete verification rule. Read the full evidence in [docs/08-what-breaks.md](docs/08-what-breaks.md).

## What is included

| Component | Purpose |
|---|---|
| `scripts/doctor.sh` | Check whether required prerequisites and selected optional components are ready |
| `scripts/verify.sh` | Verify that an expected outcome actually occurred |
| `scripts/git-sync-safe.sh` | Synchronize clean Git histories without force or silent overwrite |
| `docs/01-architecture.md` | Explain the reference architecture and its safety boundaries |
| `docs/08-what-breaks.md` | Record the four incidents and the rules they produced |
| `docs/09-verification.md` | Show reusable verification patterns |
| `.env.example` | Document the small set of configuration values the scripts consume |

## Architecture overview

This is one reference configuration, not a prescribed stack:

```text
Mac (execution)  <->  GitHub (source of truth)  <->  VPS (orchestration)
local files           versioned repositories         schedules and agents
```

The machines do not directly sync files. GitHub carries reviewed history between them. Each Hermes project profile can isolate routing and credentials, while outcome checks remain separate from the jobs they verify.

See [docs/01-architecture.md](docs/01-architecture.md) for the full model.

## Quick start

1. Clone the repository:

   ```bash
   git clone https://github.com/dannyzafir/operator-stack.git
   cd operator-stack
   ```

2. Copy the optional configuration template:

   ```bash
   cp .env.example .env
   chmod 600 .env
   ```

3. Check prerequisites and configuration:

   ```bash
   bash scripts/doctor.sh
   ```

4. Verify an outcome:

   ```bash
   bash scripts/verify.sh --check file-recent /path/to/output.md 24
   ```

5. Synchronize a clean repository safely:

   ```bash
   bash scripts/git-sync-safe.sh /path/to/repo https://github.com/<your-username>/your-repo.git
   ```

## doctor vs verify

`doctor.sh` asks whether the environment is installed and configured. It reports required breakage as **FAIL** and optional or unfinished setup as **WARN**.

`verify.sh` asks whether an intended outcome is present. It can check Git divergence, file freshness, backup arrival, and scheduled output. A healthy environment can still produce a failed outcome; that is why the checks remain separate.

```bash
bash scripts/verify.sh --help
bash scripts/verify.sh --check git-divergence /path/to/repo
bash scripts/verify.sh --check backup-arrival /source/repo /backup/repo
bash scripts/verify.sh --check schedule-fired /path/to/output 24
```

## Safe Git behaviour

The sync guardrail requires a clean working tree, fetches before deciding, and compares both directions:

- Local behind remote: permit a fast-forward-only update.
- Local ahead of remote: push the intended commits.
- Diverged histories: stop for human intervention.
- Dirty working tree: stop before any remote operation.

It never force-pushes or recommends discarding work.

## Who this is for

When I say **operator**, I mean the person in the business who keeps everything moving—the founder, partner, growth lead, second-generation owner, or person everyone calls when something breaks. Not an IT operations engineer: the person whose attention is the operating constraint.

This is for people building unattended systems: agent workflows, scheduled integrations, CI/CD pipelines, backup routines, or anything that runs while nobody watches.

The goal is a shift from **Executor → Architect**: from personally carrying every process to designing systems whose outcomes can be trusted.

## What it is not

This is not:

- an AI agent framework or platform;
- a course, no-code tutorial, or subscription;
- DevOps or SRE documentation for enterprise teams;
- generic AI consulting advice; or
- a claim that one technical architecture fits everyone.

It is an open-source reference for operators who have learned that what runs and what works are not the same thing.

## Technical reference implementation

The examples use Hermes, AI agents, GitHub, a VPS, a local computer, shell scripts, and optional model providers. Those tools are implementation details, not the category. The principles—safe change, independent evidence, explicit failure, and recoverable operation—apply regardless of the stack.

## The Operator's Edge

For more Background Growth systems, incidents, and builds, subscribe to [The Operator's Edge](https://danny-zafirovic.beehiiv.com/).

The newsletter is the primary next step for readers who want to keep moving from executor to architect.

## Foreground Tax diagnostic

If your business is carrying Foreground Tax—if growth still depends on you staying personally involved in every step—take the [Foreground Tax diagnostic](https://www.dannyzafir.com/a) to map where the tax lives.

## License

MIT. Use it, adapt it, and keep the safety checks honest.
