# MegaCoder Workflow Reference

## Objective

Use OpenClaw as the orchestrator that manages context ingestion, routing, monitoring, and PR creation while delegating:
- architecture/planning to Codex CLI
- implementation to Claude Code CLI

## Per-Run Contract

For each run id `<run_id>`:

- State directory: `.megacoder/runs/<run_id>/`
- Worktree directory: `.megacoder/worktrees/<run_id>/`
- Branch name: `codex/<run_id>`

Required state artifacts:
- `INTAKE.md` - full inbound request text and explicit requested outcome
- `CONTEXT.md` - supplemental context (ticket details, docs, incidents, constraints)
- `DECISIONS.md` - approved human decisions only
- `CODEX_FINDINGS.md` - repo/architecture findings from Codex
- `PLAN.md` - architecture + milestones
- `TASKS.md` - execution-ready implementation checklist
- `QUESTIONS.md` - unresolved blockers (`NONE` when clear)
- `IMPLEMENTATION_SUMMARY.md` - Claude implementation summary
- `TEST_RESULTS.md` - command-by-command validation results
- `ROUTE.env` - origin routing metadata (channel/target/thread/reply/origin agent)

## Phase 1 - Bootstrap (OpenClaw)

1. Gather inbound context from PM/chat integrations.
2. Pick run id and call `scripts/bootstrap-run.sh`.
3. Ensure full request text exists in `INTAKE.md`.
4. Add extra context into `CONTEXT.md`.

## Phase 2 - Plan (Codex via OpenClaw)

1. Call `scripts/run-codex-plan.sh` for the run.
2. Codex reads code + run context and writes:
   - `CODEX_FINDINGS.md`
   - `PLAN.md`
   - `TASKS.md`
   - `QUESTIONS.md`
3. Script dispatches event via `scripts/dispatch-event.sh`.
4. If `QUESTIONS.md != NONE`, OpenClaw sends questions back to the originating thread and pauses.

## Phase 3 - Clarify (Human + OpenClaw)

1. Human responds in same originating thread/channel.
2. OpenClaw writes responses into `DECISIONS.md`.
3. Re-run Phase 2 until `QUESTIONS.md == NONE`.

## Phase 4 - Implement (Claude via OpenClaw)

1. Call `scripts/run-claude-implement.sh`.
2. Claude reads full run context (including Codex findings) and implements in run worktree.
3. Claude writes:
   - `QUESTIONS.md`
   - `IMPLEMENTATION_SUMMARY.md`
   - `TEST_RESULTS.md`
4. Script dispatches event via `scripts/dispatch-event.sh`.
5. If blockers appear, OpenClaw sends them to origin thread and returns to Phase 3.

## Phase 5 - PR (OpenClaw)

1. Call `scripts/create-openclaw-pr.sh`.
2. OpenClaw pushes the run branch and opens/updates PR.
3. Script dispatches event via `scripts/dispatch-event.sh`.
4. OpenClaw posts PR URL back to the originating thread.

## Routing and Parallelism

- Always store route metadata in `ROUTE.env`.
- Always set `MC_ORIGIN_AGENT_ID` so completion/questions can wake the correct orchestrator agent.
- Always reply to that same route metadata.
- Never share state files between runs.
- Each run has its own branch + worktree.
- Multiple runs can execute concurrently without conflicts.

## Monitoring Expectations

OpenClaw should monitor run status by watching:
- `STATUS.md`
- `QUESTIONS.md`
- `IMPLEMENTATION_SUMMARY.md`
- `PR_URL.txt`

On each phase transition, run `scripts/dispatch-event.sh` with the relevant event (`planned`, `questions`, `implemented`, `pr`).

Heartbeat fallback:
- OpenClaw heartbeat should call `scripts/heartbeat-check.sh`.
- This scanner re-dispatches missed `questions`, `implemented`, and `pr` events only when file content changed.
