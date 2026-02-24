---
name: mega-coder
description: Orchestrate OpenClaw-driven software delivery with run-scoped state and isolated git worktrees, where OpenClaw ingests ticket/chat context, Codex CLI performs architecture and planning, Claude Code CLI implements tasks, and OpenClaw sends updates back to the originating thread, wakes the main agent on run events, and opens feature/bugfix PRs. Use when users ask for MegaCoder, Codex-plan + Claude-implement workflows, multi-channel thread-safe execution, wake-on-complete behavior, or parallel ticket execution.
---

# Mega Coder

Use this skill to run a strict OpenClaw orchestration loop:
1) OpenClaw creates a run folder and isolated worktree.
2) OpenClaw passes full context to Codex for architecture + planning.
3) OpenClaw passes planning outputs to Claude for implementation.
4) OpenClaw routes blocker questions back to the originating thread.
5) OpenClaw wakes the main agent on plan/blocker/implementation/PR events.
6) OpenClaw opens the PR when implementation is complete.

## Run-Scoped Artifacts

For each run id `<run_id>`, store artifacts in:
- `.megacoder/runs/<run_id>/INTAKE.md`
- `.megacoder/runs/<run_id>/CONTEXT.md`
- `.megacoder/runs/<run_id>/DECISIONS.md`
- `.megacoder/runs/<run_id>/CODEX_FINDINGS.md`
- `.megacoder/runs/<run_id>/PLAN.md`
- `.megacoder/runs/<run_id>/TASKS.md`
- `.megacoder/runs/<run_id>/QUESTIONS.md`
- `.megacoder/runs/<run_id>/IMPLEMENTATION_SUMMARY.md`
- `.megacoder/runs/<run_id>/TEST_RESULTS.md`
- `.megacoder/runs/<run_id>/ROUTE.env`

Use isolated git worktrees per run:
- `.megacoder/worktrees/<run_id>/`

This layout supports parallel tickets without state collisions.

## Workflow

1. Bootstrap run + worktree:
```bash
bash /path/to/mega-coder/scripts/bootstrap-run.sh /path/to/project [run_id]
```

2. Plan with Codex:
```bash
bash /path/to/mega-coder/scripts/run-codex-plan.sh /path/to/project <run_id>
```

3. `run-codex-plan.sh` dispatches the event to the originating thread and wakes the main agent. If `QUESTIONS.md` is not `NONE`, OpenClaw asks the user and appends answers to `DECISIONS.md`, then re-runs planning.

4. Implement with Claude:
```bash
bash /path/to/mega-coder/scripts/run-claude-implement.sh /path/to/project <run_id>
```

5. OpenClaw creates PR:
```bash
bash /path/to/mega-coder/scripts/create-openclaw-pr.sh /path/to/project <run_id>
```

6. Configure heartbeat safety-net to catch missed wake events:
```bash
bash /path/to/mega-coder/scripts/heartbeat-check.sh /path/to/project
```

## Guardrails

- Never run Claude when `QUESTIONS.md` contains unresolved blockers.
- Keep all human answers in `DECISIONS.md` with timestamp and rationale.
- Keep routing metadata in `ROUTE.env` so notifications go back to the originating thread/channel.
- Set `MC_ORIGIN_AGENT_ID` on bootstrap so run events can re-invoke the correct OpenClaw agent.
- Keep planning and implementation artifacts in run-scoped files only.
- OpenClaw owns all messaging, orchestration, and PR creation.

## Permission Modes

Default safe modes:
- Codex: `--ask-for-approval never --sandbox workspace-write`
- Claude: `--permission-mode acceptEdits`

Optional high-autonomy modes:
- Codex: set `MEGACODER_CODEX_MODE=yolo`
- Claude: set `MEGACODER_CLAUDE_MODE=dangerous` (uses `--permission-mode bypassPermissions --dangerously-skip-permissions`)

Use high-autonomy modes only in isolated runner environments.

## References

- `references/workflow.md` — operating loop, parallelism, and monitoring behavior.
- `references/prompt-templates.md` — context-rich prompt contracts for Codex and Claude.
- `references/heartbeat.md` — heartbeat file template to recover missed notifications/wakes.
