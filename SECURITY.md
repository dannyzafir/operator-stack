# Security

This repo ships shell scripts (`doctor.sh`, `verify.sh`, `git-sync-safe.sh`) that read local files, run `git`, and never call out to a network endpoint you didn't specify. There is no telemetry, no phone-home, and no bundled credential.

## Principles this repo follows

1. **Secrets never leave their machine.** SSH keys, API tokens, and OAuth credentials stay local. Nothing here transmits or requests them.
2. **Environment variables over hardcoded values.** Configuration lives in `.env` (gitignored). `.env.example` ships placeholder values only.
3. **Least privilege.** Scripts run with the permissions of the invoking user. Nothing requires or requests `sudo`.
4. **No destructive defaults.** `git-sync-safe.sh` never force-pushes, never resets `--hard`, and stops on a dirty working tree or a diverged history rather than guessing.
5. **`.env` is read as data, not executed.** `doctor.sh` parses known `key=value` lines out of `.env` — it does not `source` it, so a malformed or malicious `.env` cannot inject shell code.

## Reporting a problem

If you find a way for these scripts to do something unsafe — force-push under a condition that shouldn't allow it, `.env` handling that executes instead of reads, or a check that reports PASS/verified when the underlying claim is false — please open an issue. That last category (a false PASS) is the one this whole repo exists to prevent, so it gets priority.

## Scope

This file covers the scripts and docs in this repository. It does not cover Hermes itself, your model provider, or any infrastructure you connect this to — those have their own security postures and disclosure channels.
