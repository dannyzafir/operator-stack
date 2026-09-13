# 08. What breaks

Most documentation tells you how a system is supposed to work. This file tells you how this one actually failed.

Every incident below happened on a live deployment that was running a real business, and every one of them was **silent**. Nothing alerted. Nothing looked wrong. In two cases the system actively reported success while failing.

That is the whole reason this file exists. Automation that fails loudly is a nuisance. Automation that fails silently is a liability, because you keep making decisions on information that stopped being true days ago.

Read this before you build anything. Then read it again when your own system starts feeling reliable, because that is exactly when these bite.

---

## The failure mode behind all of them: silent success

Four incidents, one shared property. In every case the outward signal said the system was healthy.

- A nightly backup reported success every night for three nights while uploading nothing.
- A knowledge curator failed every four hours for an unknown period, on schedule, looking exactly like a job that was running fine.
- A curator that *did* run quietly filed its own prompts as knowledge, degrading its own output while reporting success.
- An alerting job died on a provider rate limit with nothing to retry on, and simply produced no report.

The lesson is not "check your logs". The lesson is that **a scheduled job that fails and a scheduled job that succeeds look identical from the outside**. Both occupy the same slot. Both leave a last-run timestamp. Neither produces an error you will see.

So the design rule this file argues for is not more automation. It is that every automated action needs a separate statement of what a *successful* run looks like, checked against reality rather than against the job's own exit code.

A job reporting its own success is not evidence. It is a claim. You need the corroborating fact.

---

## Incident 1: the backup that lied for three nights

**What we saw.** Nothing. That is the point. The backup service showed a fresh commit every night, a clean timer, and a successful exit status.

**What it looked like.** Healthy. The local repository had a new commit dated each night. `git log` was exactly what you would want to see.

**How we found it.** By comparing the local repository against the remote, for an unrelated reason. The remote had not moved in three days. Three nightly commits existed locally and had never been uploaded.

**Root cause.** The backup ran as a system service. System services start with a deliberately minimal environment, and that environment has **no `HOME`**. Without `HOME`, git does not read the user's global configuration file, which is where the credential helper lived. With no credential helper available, git fell back to prompting for a username. With no terminal to prompt on, it failed with `could not read Username`.

The credentials were never the problem. They were valid and working the entire time. The environment was the problem.

**Why it stayed hidden for three nights.** This is the important part. The backup script staged files, committed them locally, and then pushed. The commit succeeded. The push failed. A failed push leaves the local commit in place, so the evidence of the failure and the evidence of success were the same artifact.

Every surface you would normally check said fine:
- The commit existed.
- The service exited with a status that looked like work had happened.
- The timer was enabled and firing on schedule.

The one fact that mattered, that the remote had not advanced, lived somewhere nobody was looking.
**The fix.** Give the service the environment it needs, in the unit itself:

```
Environment=HOME=/home/<username>
Environment=GH_CONFIG_DIR=/home/<username>/.config/gh
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

**The rule it produced.** Never accept a commit list as proof a backup arrived. Compare local against remote: the count of commits ahead of the remote must be zero, and the remote's head must have advanced. Two facts, not one.

**How to catch it next time.** A check that runs daily and compares local head against remote head, alerting on divergence rather than on exit status.

---

## Incident 2: the curator that could never start

**What we saw.** A scheduled review job failing every four hours with exit code `126`, reported as `Permission denied`.

**What it looked like.** A missing dependency, or a broken interpreter, or a bad shebang. Exit 126 reads like something is not installed.

**Root cause.** None of the above. The script's shebang was correct and it imported nothing outside the standard library. The file's **permissions** were wrong: mode `600`, owner read and write only. The wrapper invoked it directly, which requires the execute bit. A file that is not executable cannot be executed, regardless of how correct its contents are.

The file had been written by a tool that creates files owner-only by default, and nobody had noticed because the job that used it had never successfully run.

**Why it stayed hidden.** A failing cron job and a working cron job occupy the same schedule slot. The job had failed on every tick since it was created, so there was no successful run to compare against, and no change in behaviour to notice. It was perfectly consistent, and perfectly broken.

**The fix.** Two layers, deliberately:

```
chmod +x /path/to/script.py
```

And in the wrapper, invoke the interpreter explicitly rather than relying on the mode bit:

```bash
exec python3 /path/to/script.py "$@"
```

The second is the more durable fix. The mode bit is a property of the file that any future rewrite can silently reset. Naming the interpreter makes the wrapper immune to it.

**The rule it produced.** When a scheduled job reports exit code 126, check the file mode before anything else. Then stop depending on the mode bit at all.

---

## Incident 3: the curator that curated itself

**What we saw.** A review queue filling with items that were not knowledge. Entries like *"You are analyzing conversation sessions for knowledge curation"* and *"You are generating concise permanent knowledge for an Obsidian vault"*.

**What it looked like.** A working system with a noisy output problem. The queue had items, so the pipeline was clearly running end to end.

**Root cause.** The curator read conversation sessions from a database and judged which contained durable knowledge. To do its work it invoked a model through the CLI, and every one of those invocations **wrote an ordinary session row into the same database**. The curator was a session producer reading a session table.

So on each run it found its own previous analysis calls, judged them, and queued its own prompt text as knowledge. Worse, those self-sessions consumed the entire per-database candidate limit, so the real sessions it existed to find were crowded out. It was not just adding noise, it was starving its own input.

**Why it stayed hidden.** Every individual run succeeded. The queue grew. Nothing errored. From the outside it looked like a busy, functioning system. The only way to see it was to read the items and notice they were the reviewer talking to itself.

There is a detail worth keeping. The model, left to judge, *did* recognise some of these. It skipped two with a reason reading roughly *"self-referential, this session is the curation skill executing again"*. It also queued one. So the model's judgment was partially correct, which is the worst kind of correct: enough to look like it was handling the problem, not enough to actually handle it.

**The fix.** Exclude the agent's own sessions deterministically rather than hoping the model notices. Match on the signature of your own prompts and skip before assessment:

```python
SELF_SESSION_MARKERS = [
    "you are analyzing conversation sessions",
    "you are generating concise permanent knowledge",
    "knowledge curation",
    "return only a text response",
    "do not use any tools",
]
```

**The rule it produced.** Any agent that both writes and reads the same store must exclude its own writes explicitly. Do not delegate that to the model. And when you add a filter, prove it discriminates: list what it excluded and confirm nothing genuine was caught. A filter returning zero results is otherwise indistinguishable from a filter that excludes everything.

---

## Incident 4: the rate limit with nowhere to fall back to

**What we saw.** An alerting job dying with `HTTP 429: This request would exceed your account's rate limit`.

**What it looked like.** The expected cost of running on a cheap shared provider. Rate limits happen. Retry later.

**Root cause.** The fallback configuration was **per profile**, and this profile did not have any. The job was pinned to the correct cheap model, which felt like the protection, but pinning controls which model is *asked for*. It does nothing when the provider itself is saturated. With no chain behind the primary, a single 429 failed the entire run.

The profile that hosted this job had been created independently of the main one, and had inherited the deployment's habits without inheriting its safety nets. Nothing compared the two.

**Why it stayed hidden.** It failed once and then did not run again for a while, because its schedule was weekday-only. A single 429 looks like weather. It only becomes a pattern if you are watching, and nothing was watching a job that produced no output when it failed.

**The fix.** Mirror the fallback chain into every profile that runs unattended work, and verify it loaded rather than assuming the file was read:

```bash
hermes -p <profile> config get fallback_providers
```

**The rule it produced.** Fallback configuration belongs to the profile, not the job. A profile running unattended work without a fallback chain has a single point of failure that its job-level settings cannot see. When you create a new profile by copying habits, copy the safety nets too, or prove you deliberately left them out.

---

## The rules, collected

1. Never treat a job's own exit status as proof of the outcome. Find the corroborating fact.
2. A failed git push leaves a local commit. Compare local against remote, both facts.
3. Scheduled jobs that fail look exactly like scheduled jobs that succeed. Alert on the outcome, not the schedule.
4. Check file modes before debugging a `126`.
5. Do not depend on the execute bit. Name the interpreter.
6. Any agent reading a store it also writes to must exclude its own writes, deterministically.
7. Prove a filter discriminates, not just that it returns results.
8. Fallbacks are per profile. New profiles need the safety nets copied across, not assumed.
9. A single failure on an infrequent schedule is not "weather" until you have checked whether it failed the last time too.
10. Build the check that would have caught the incident, or you have not finished fixing it.

---

## The check that would have caught all four

Every incident above produced a green signal while failing. A monitoring job that reads the same green signals reproduces the same blindness.

What catches them is a daily verification pass that asks questions about **outcomes**, separately from the jobs that produce them:

- Did the remote backup repository advance since yesterday? (catches incident 1)
- Did every scheduled job record a genuine success in the last cycle, and is its last error empty? (catches incident 2)
- Does each agent that reads a store it writes to actually exclude its own writes? (catches incident 3)
- Does every profile running unattended work have a fallback chain configured? (catches incident 4)

The difference is small and it is everything. The job says "I ran". Verification says "here is the evidence that running changed something true".

Build the second thing, or you have built the first one twice.
