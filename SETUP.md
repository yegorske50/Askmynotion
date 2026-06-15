# Full autonomous warren setup — master runbook

This scaffold replicates the developer's full self-improving loop for a
*new* project. Warren itself stays generic and untouched; everything here
goes into YOUR target project repo and YOUR warren deployment env.

Mental model: warren (the orchestrator) is already running. The os-eco
tools (seeds, mulch, plot, canopy) live in your project repo and "light
up" when their directories are present. The patrol agents + cron triggers
+ auto-merge form a closed loop: patrols file plans -> warren auto-dispatches
plan-runs -> agents implement -> PRs auto-merge on green CI -> mulch
accumulates -> the weekly digest synthesizes.

Do the phases IN ORDER. Each builds on the last.

--------------------------------------------------------------------------
## Phase 0 — Warren host config (the autonomy switches)

These live in your warren deployment's `.env` (compose) or `fly secrets`.
Set them, then restart warren.

Required for the loop to push + open + merge PRs:

  GITHUB_TOKEN              PAT with contents:write + pull-requests:write.
                           Used for clones, branch pushes, auto-open PR,
                           AND the plan-run PR-merge poller. Without
                           pull-requests scope, plan-runs stall waiting for
                           merges that they cannot detect.
  ANTHROPIC_API_KEY        Forwarded to the agent runtimes.
                           (+ OPENAI_API_KEY / GEMINI_API_KEY / etc. only
                            if you use pi multi-provider.)

Autonomy + attribution (the developer's deploy sets these):

  WARREN_AUTO_OPEN_PR=true        After a successful run, warren opens a PR
                                  for the pushed branch. Default on; set
                                  explicitly.
  WARREN_BASE_URL=https://<your-warren-host>
                                  Embedded in PR bodies so reviewers can
                                  jump back to the run.
  WARREN_GIT_AUTHOR_NAME=Warren
  WARREN_GIT_AUTHOR_EMAIL=<id>+warren@users.noreply.github.com
                                  Agent commit identity. Use a github.com
                                  noreply so the contribution graph
                                  reflects agent work. (Find your numeric
                                  id at https://api.github.com/users/<login>.)
  WARREN_RUN_BRANCH_PREFIX=warren Friendlier branch names (warren/run_...).
  WARREN_MERGE_POLLER_ENABLED=1   Enables the send-off -> planner chain
                                  used by the warden layer (Phase 6). Safe
                                  to set now even if you skip the warden.

Already set from your initial install (verify): WARREN_API_TOKEN,
BURROW_API_TOKEN == WARREN_BURROW_TOKEN.

Optional — per-run preview environments:
  Path mode is the default and needs NO wildcard DNS/cert; previews serve
  at https://<warren-host>/p/<run-id>/. Just ship `.warren/preview.yaml`
  (Phase 3). For subdomain mode at org scale, set WARREN_PREVIEW_HOST +
  a wildcard CNAME + DNS-01 wildcard cert (see warren's README).
  Lifecycle knobs (all have defaults): WARREN_PREVIEW_IDLE_TTL=30m,
  WARREN_PREVIEW_MAX_LIFETIME=8h, WARREN_PREVIEW_MAX_LIVE=20,
  WARREN_PREVIEW_PORT_RANGE=30000-31000.

Scheduler/plan-run cadence (defaults are fine):
  WARREN_SCHEDULER_TICK_MS=60000   (cron tick)
  WARREN_PLAN_RUN_TICK_MS=10000    (plan-run coordinator tick)

After editing: `docker compose up -d` (or `fly deploy`). Then
`warren doctor` against the instance to catch placeholder tokens etc.

--------------------------------------------------------------------------
## Phase 1 — Install the os-eco CLIs locally

You need these to scaffold the repo and run the sync protocol by hand.
(The agent inside the sandbox already has them — they're baked into the
warren image — so this is for YOUR machine only.)

  bun install -g @os-eco/seeds-cli @os-eco/mulch-cli @os-eco/canopy-cli
  # add @os-eco/plot-cli only if you adopt plot (advanced).

Confirm the init/onboard command names before running them:
  sd --help ; ml --help ; cn --help
(The exact subcommand may be `init` or `onboard` — verify, then use it.)

--------------------------------------------------------------------------
## Phase 2 — Drop this scaffold into your project repo

Copy the contents of this template into the root of your project:

  .github/workflows/auto-merge.yml   (Article-IX-guarded auto-merge)
  .github/workflows/ci.yml           (TODO: wire to your real gate)
  .warren/config.yaml                (TODO: project, model, qualityGate)
  .warren/triggers.yaml              (patrol schedule)
  .warren/preview.yaml               (optional preview env)
  .warren/pr-template.md             (optional PR-body override)
  .canopy/config.yaml                (makes the repo a canopy library)
  agents/*.md                        (the patrol population)
  docs/CONSTITUTION.md               (the auditors' standard — edit it)
  CLAUDE.md                          (agent operating manual — fill TODOs)
  bootstrap.sh                       (GitHub repo config helper)

Then fill EVERY `TODO:` marker. The two that matter most:
  - .warren/config.yaml `qualityGate` and .github/workflows/ci.yml MUST
    run the same command (CI parity). If they disagree, agents think
    they're green while CI is red.
  - docs/CONSTITUTION.md Article II must reference YOUR actual ratchet
    files (or ratchetwatch will report "no ratchets configured").

--------------------------------------------------------------------------
## Phase 3 — Activate the data-plane tooling (seeds + mulch)

Run the tools' own onboarding IN your project repo so the directory AND
the CLAUDE.md block get created together (this is what makes the project
"know" it has the tool):

  cd your-project
  sd init        # creates .seeds/, inserts the <!-- seeds:start --> block
  ml init        # creates .mulch/, inserts the <!-- mulch:start --> block

(Use whatever the exact subcommand is from Phase 1's `--help`.) These
replace the placeholder comment blocks in the scaffold's CLAUDE.md.

Plot (OPTIONAL, advanced): only if you want a multi-actor coordination
substrate and plan-run/plot composition. `plot init` creates `.plot/`.
Dispatching a run with a `plot_id` then threads PLOT_ID/PLOT_ACTOR into
the sandbox. Skip this until the basic loop is solid.

--------------------------------------------------------------------------
## Phase 4 — Configure GitHub for auto-merge

  chmod +x bootstrap.sh
  ./bootstrap.sh your-org/your-project

This enables auto-merge, branch auto-delete, removes the required-review
gate (the workflow scopes auto-merge to the repo owner only), and sets the
AUTO_MERGE_PAT secret. Then set a required status check named after your
CI job so PRs must pass CI before merging (the script prints the command).

Seed at least one task so there's work to do, commit, push:

  sd create --title "First task" --type task --priority 2
  git add -A && git commit -m "chore: scaffold warren autonomous tooling"
  git push

--------------------------------------------------------------------------
## Phase 5 — Register project + agents with warren

If your canopy agents live IN the project repo (the .canopy/ + agents/ in
this scaffold), warren picks them up as the per-project tier:

  warren add-project https://github.com/your-org/your-project.git
  # refresh so warren discovers the agents/ prompts:
  #   POST /agents/refresh   (UI: Agents -> Refresh, or via the API)

If you keep agents in a SEPARATE library repo instead, set
CANOPY_REPO_URL=<that repo> in warren's env and refresh.

Verify the patrol agents are registered:
  GET /agents   -> you should see nightwatch, gatewatch, ratchetwatch,
                   tastewatch (+ the built-ins claude-code, pi, sapling).

The cron triggers in .warren/triggers.yaml now fire on schedule. To test
WITHOUT waiting for cron, use Run Now:
  POST /projects/:id/triggers/nightwatch-patrol/run

--------------------------------------------------------------------------
## Phase 6 — The warden layer (OPTIONAL synthesis on top)

The "Audit Warden" is a standing overseer conversation that consolidates
the week's auditor findings into one digest and proposes plans via the
send-off -> planner chain. It needs: WARREN_MERGE_POLLER_ENABLED=1 (Phase
0), a long-lived `mode: conversation` run titled exactly "Audit Warden"
bound to a meta-Plot, and the overseer (Leveret) agent.

HONEST GAP: the bootstrap procedure for that standing conversation lives
in your warren deployment's LEVERET.md, which is not part of this
template. Until you have it:
  - Leave the `warden-digest` trigger commented out in triggers.yaml.
  - The auditors (gatewatch/ratchetwatch/tastewatch) degrade gracefully —
    they detect no "Audit Warden" conversation, note `warden: undeliverable`,
    and just file their findings as seeds directly. You lose the weekly
    synthesis, NOT the autonomous loop.

When you obtain LEVERET.md: bootstrap the standing conversation per its
instructions, confirm `GET /conversations?status=active` shows a row
titled "Audit Warden", then uncomment the warden-digest trigger and the
delivery sections already present in the auditor prompts.

--------------------------------------------------------------------------
## Phase 7 — Verify full capacity

Walk the loop end to end:

1. Manual run works:
   warren run pi your-project -p "Read sd ready, implement the top task,
   run the quality gate until green, commit. Warren handles the push."
   -> run reaches `succeeded`, branch pushed, PR opened, CI runs,
      auto-merge fires on green, branch deleted.

2. Memory round-trips: after a run, check the project's .mulch/ has new
   records (reap merges them back, last-write-wins by ts).

3. Patrol -> plan -> auto-dispatch: Run Now on nightwatch. It should file
   a plan (parent seed + child seeds). Because nightwatch has
   `auto_plan_run: true`, warren auto-dispatches a plan-run that walks the
   children one at a time, gating each on the previous PR merging.

4. Audit -> seed: Run Now on gatewatch/ratchetwatch. They file
   evidence-bearing seeds (with SHAs) against the constitution.

5. Preview (if enabled): a successful run's PR carries a preview link;
   open https://<warren-host>/p/<run-id>/.

6. Weekly digest (if warden set up): the Sunday triggers produce the
   tastewatch digest seed and the warden synthesis.

If any step fails, `warren doctor`, then `fly logs` / `docker logs warren`
filtered by the run's X-Request-ID.

--------------------------------------------------------------------------
## Two things I could not fully verify (check these yourself)

1. Exact `sd` / `ml` / `cn` init subcommand spelling — confirm with
   `--help`. The CLAUDE.md onboarding markers prove the commands exist;
   the spelling is the only unknown.
2. The Audit Warden / Leveret bootstrap (Phase 6) — needs LEVERET.md from
   your warren deployment. The rest of the loop runs fully without it.
