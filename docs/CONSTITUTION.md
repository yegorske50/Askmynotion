# The Project Constitution

Taste, compiled. This document is the standard the audit population
(`nightwatch`, `gatewatch`, `ratchetwatch`, `tastewatch` — see
`.warren/triggers.yaml`) measures merged work against. Auditors cite
articles by number when filing findings. CI gates enforce what they can;
these articles cover what executable gates cannot — and every article
aspires to become a gate.

> Adapt the articles to your project. The structure below is reusable;
> the specifics (coverage thresholds, budget file names, identities)
> should reflect your stack.

## Article I — Merges are truthful

A PR's title and description describe its diff. A feature-titled PR
contains the feature. A merge is never rationalized past a red gate
("this failure is unrelated" is a finding, not a waiver — fix the gate
or fix the change). If work is blocked, the PR says so and carries no
feature title.

## Article II — Ratchets only tighten

Quality floors (coverage, file size, bundle size, debt markers) rise to
track actuals; meaningful slack is debt. Budget and grandfather
exceptions carry a tracker reference in the diff that adds them. Nothing
is grandfathered at birth: a new file written over a limit is fixed
before merge, not exempted at write time. Automated budget raises stay
within caps and are reviewed in aggregate.

## Article III — Releases mean something

A published release contains at least one consumer-observable change.
Internal hygiene (comment fixes, doc drift, test tightening) batches into
the next real release rather than minting its own.

## Article IV — Tests verify behavior

Coverage gains come from meaningful assertions, not test theater.
Aggregation, parsing, and decision logic ships with adversarial cases —
malformed input, boundary values, the case that broke last time — not
happy-path only. A test that asserts a mock was called is documentation,
not verification.

## Article V — Comments state constraints

A comment exists to state a constraint the code cannot show.
Institutional memory belongs in mulch records, not in long comment
essays. Narration of the obvious is noise and gets removed.

## Article VI — Refactors prove runtime paths

Any file move or rename verifies references that tests do not import:
Dockerfile entrypoints, CI/workflow YAML, config strings, docs. The check
is a repo-wide search for the old path, including non-source files.
"All gates green" is not "deploy works."

## Article VII — Identity is consistent

Agent-authored commits use one canonical identity. One agent, one
spelling. An identity that appears once and never again is a finding.

## Article VIII — Evidence or it didn't happen

Findings cite commit SHAs, file paths, and line ranges. A seed filed
without evidence gets closed without action. Auditors that cannot show
their work do not file.

## Article IX — The constitution outranks the population

Changes to this file, to auditor prompts (`agents/` and `.canopy/`), or
to `.warren/triggers.yaml` audit entries require explicit human review —
they must not ride an auto-merged PR. The `auto-merge.yml` workflow's
"Article IX check" step withholds auto-merge on any PR touching these
files. Any auditor that observes a merged change to these files without
human approval files a priority-1 finding citing this article. The
population does not rewrite its own mandate.

## Amendments

Amend by PR touching this file, flagged for human merge (Article IX).
`tastewatch`'s weekly digest may *propose* amendments; it may not apply
them. When an article becomes enforceable as an executable gate, note the
gate here and retire the manual check.
