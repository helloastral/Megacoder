# HEARTBEAT.md Template

Use this content in your OpenClaw agent workspace `HEARTBEAT.md`.

```markdown
# Heartbeat

## MegaCoder safety-net monitor

Run:

bash /path/to/mega-coder/scripts/heartbeat-check.sh /path/to/project

Expected outcomes:
- `HEARTBEAT_OK: no pending MegaCoder events`
- `HEARTBEAT_ACTION: dispatched pending MegaCoder events`

If questions are pending for any run:
1. Ask the user in the originating thread.
2. Append answers to `.megacoder/runs/<run_id>/DECISIONS.md`.
3. Re-run `run-codex-plan.sh` for that run.
```
