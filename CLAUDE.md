# <Your Project>

<!-- TODO: one-paragraph description of what this project is and does. -->

## Tech Stack

<!-- TODO: runtime, language, framework, storage, etc. -->

## Build & Test Commands

```bash
# TODO: install
# TODO: run tests
# TODO: the canonical quality gate — MUST match
#       .warren/config.yaml `qualityGate` AND .github/workflows/ci.yml
```

## Quality Gates

Run the quality gate before committing — it is surfaced to you as
`$WARREN_QUALITY_GATE`. You are NOT done until it exits zero. Fix failures
(including lint warnings, which CI treats as errors) until it is green. Do
not declare the task complete, hand off, or end the session with a red
gate. If the gate is genuinely unfixable in this run, say so explicitly
and leave the work open rather than claiming success.

## Conventions

<!-- TODO: naming, file layout, error handling, anything an agent should
     not have to guess. The more specific, the better the agent output. -->

## Constitution

This project is governed by [docs/CONSTITUTION.md](docs/CONSTITUTION.md).
Merges are truthful, ratchets only tighten, tests verify behavior. The
audit population (`agents/`, scheduled in `.warren/triggers.yaml`)
measures merged work against it.

## Operating contract (for agents)

- Edit files in place. Run the quality gate before committing.
- Commit your changes (`git commit`) — staging alone is NOT enough. A run
  that ends with staged-but-uncommitted changes is a failure.
- Do NOT run `git push` — warren reaps the branch and pushes for you.
- Use `sd` for the issue queue and `ml` for memory (see the onboarding
  blocks below).

## Session Completion Protocol

When ending a work session, complete ALL steps:

1. File follow-ups for remaining work: `sd create --title "..."`
2. Run the quality gate (if code changed).
3. Close finished issues: `sd close <id>`
4. Record insights worth preserving: `ml learn` then `ml record ...`
5. Sync: `sd sync && ml sync`  (warren handles the push)

<!-- The two blocks below are INSERTED AUTOMATICALLY by `sd init` and
     `ml init` (or onboard). Do not hand-write them — run the tools so the
     version markers stay accurate. They tell every agent run to prime the
     queue and memory at start and sync at end. -->

<!-- seeds:start -->
<!-- (run `sd init` / `sd onboard` in this repo to populate) -->
<!-- seeds:end -->

<!-- mulch:start -->
<!-- (run `ml init` / `ml onboard` in this repo to populate) -->
<!-- mulch:end -->
