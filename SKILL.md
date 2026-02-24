---
name: mega-coder
description: Orchestrate a two-stage coding workflow where Codex CLI performs architecture and task planning from a rough draft, asks clarifying questions, and Claude Code CLI performs implementation only after plan approval. Use when the user asks for “MegaCoder”, wants planning-first execution, or wants Codex-for-plan + Claude-for-code collaboration.
---

# Mega Coder

Use this skill to run a strict planning-then-implementation software workflow:
1) Codex CLI plans and asks questions.
2) Human approves decisions.
3) Claude Code CLI implements.

## Workflow

1. Create project artifacts in `.megacoder/` inside the target project directory:
   - `.megacoder/ROUGH_DRAFT.md`
   - `.megacoder/PLAN.md`
   - `.megacoder/QUESTIONS.md`
   - `.megacoder/DECISIONS.md`
   - `.megacoder/TASKS.md`
   - Add `.megacoder/` to `.gitignore` in app repos.
2. Run Codex planning via `scripts/run-codex-plan.sh`.
3. Read `.megacoder/QUESTIONS.md` and relay questions to the user.
4. Append user answers to `.megacoder/DECISIONS.md`.
5. Re-run Codex planning until `.megacoder/QUESTIONS.md` is `NONE` and `.megacoder/TASKS.md` is implementation-ready.
6. Run Claude implementation via `scripts/run-claude-implement.sh`.
7. Validate with tests/lint/build as appropriate.
8. Summarize changes, risks, and next actions.

## Guardrails

- Do not start implementation until plan approval is explicit.
- Keep all decisions in `DECISIONS.md`; do not rely on implicit memory.
- If a blocker appears, update `QUESTIONS.md` and pause implementation.
- Prefer small, reviewable commits aligned to `TASKS.md`.

## Commands

From the project directory:

```bash
bash /path/to/mega-coder/scripts/run-codex-plan.sh
bash /path/to/mega-coder/scripts/run-claude-implement.sh
```

Use absolute paths if running from another directory.

## References

- `references/workflow.md` — detailed operating loop and escalation pattern.
- `references/prompt-templates.md` — prompt templates for Codex and Claude Code.
