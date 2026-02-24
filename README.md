# MegaCoder Skill

MegaCoder is an OpenClaw skill for parallel, thread-safe software delivery:

1. OpenClaw ingests ticket/chat context and creates a run id
2. Codex CLI performs architecture + planning
3. Claude Code CLI implements from the approved plan
4. OpenClaw sends updates/questions to the originating thread and wakes the main agent
5. Heartbeat safety-net re-dispatches missed events
6. OpenClaw creates feature/bugfix PRs

## Repository Contents

- `SKILL.md` - skill definition and orchestration behavior
- `references/workflow.md` - detailed run lifecycle and guardrails
- `references/prompt-templates.md` - Codex/Claude prompt contracts
- `scripts/bootstrap-run.sh` - creates run folder + isolated worktree
- `scripts/run-codex-plan.sh` - planning pass (Codex)
- `scripts/run-claude-implement.sh` - implementation pass (Claude)
- `scripts/notify-origin.sh` - posts updates to originating channel/thread
- `scripts/wake-main-agent.sh` - re-invokes the OpenClaw main agent on run events
- `scripts/dispatch-event.sh` - unified notify + wake dispatcher
- `scripts/heartbeat-check.sh` - heartbeat safety-net to catch missed notifications
- `scripts/create-openclaw-pr.sh` - pushes branch and opens PR (OpenClaw step)

## Prerequisites

On the runner machine:

- `git`
- `codex` CLI (authenticated)
- `claude` CLI (authenticated)
- `openclaw` CLI (for outbound thread updates)
- `gh` CLI (for PR creation)

Quick checks:

```bash
which git
which codex
which claude
which openclaw
which gh
```

## Run Layout

Each run gets isolated state and code:

- State: `.megacoder/runs/<run_id>/...`
- Code worktree: `.megacoder/worktrees/<run_id>/...`

This enables multiple tickets in parallel with no shared-file collisions.

## Typical OpenClaw-Orchestrated Flow

1. Prepare route + task context (from Slack/Telegram/etc):

```bash
export MC_ROUTE_CHANNEL="slack"
export MC_ROUTE_TARGET="C123456"
export MC_ROUTE_THREAD_ID="1730412217.008"
export MC_ROUTE_REPLY_TO="1730412217.008"
export MC_ORIGIN_AGENT_ID="main-agent"
export MC_TASK_SOURCE="linear"
export MC_TASK_ID="ABC-123"
export MC_TASK_TITLE="Improve checkout retries"
export MC_TASK_TEXT_FILE="/tmp/inbound-context.txt"
```

2. Bootstrap run + worktree:

```bash
bash scripts/bootstrap-run.sh /path/to/project
```

Bootstrap now dispatches an `initialized` event by default (`MEGACODER_BOOTSTRAP_DISPATCH=1`), which wakes the orchestrator to start planning. Set `MEGACODER_BOOTSTRAP_DISPATCH=0` to disable.

3. Run Codex planning:

```bash
bash scripts/run-codex-plan.sh /path/to/project <run_id>
```

4. If blockers exist, OpenClaw relays `QUESTIONS.md` in the same origin thread and appends answers to `DECISIONS.md`, then reruns step 3.

5. Run Claude implementation:

```bash
bash scripts/run-claude-implement.sh /path/to/project <run_id>
```

6. Open PR via OpenClaw-owned step:

```bash
export MEGACODER_PR_KIND=feature # or bugfix
bash scripts/create-openclaw-pr.sh /path/to/project <run_id>
```

7. Add heartbeat safety-net (OpenClaw HEARTBEAT.md should call this):

```bash
bash scripts/heartbeat-check.sh /path/to/project
```

## Permission Profiles

Non-interactive defaults:

```bash
export MEGACODER_CODEX_MODE=yolo
export MEGACODER_CLAUDE_MODE=dangerous
```

Safer override (may reintroduce permission constraints):
- Codex: `MEGACODER_CODEX_MODE=safe`
- Claude: `MEGACODER_CLAUDE_MODE=safe` (optional `MEGACODER_CLAUDE_PERMISSION_MODE=acceptEdits|plan|default`)

## Notes

- `run-codex-plan.sh` and `run-claude-implement.sh` create context packets so each agent receives full run context.
- `dispatch-event.sh` now runs after bootstrap/plan/implement/PR and does both:
- notify origin thread via `notify-origin.sh`
  - for `planned` events, it posts `PLAN.md` + `TASKS.md` contents directly (code block on Slack/Telegram/WhatsApp)
- wake orchestrator agent via `wake-main-agent.sh`
- `heartbeat-check.sh` is a fallback scanner for missed wake/message events.
- OpenClaw remains the orchestrator and PR owner; Codex/Claude are execution engines.
