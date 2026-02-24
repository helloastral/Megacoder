# MegaCoder Workflow Reference

## Artifact contract

Create and maintain these files per project under `.megacoder/`:
- `.megacoder/ROUGH_DRAFT.md`: raw user intent
- `.megacoder/PLAN.md`: architecture + phased approach
- `.megacoder/QUESTIONS.md`: unresolved questions/blockers
- `.megacoder/DECISIONS.md`: user-approved decisions
- `.megacoder/TASKS.md`: executable checklist for implementation

Add `.megacoder/` to the project `.gitignore`.

## Phase A — Plan (Codex CLI)

1. Read `ROUGH_DRAFT.md` and `DECISIONS.md` if present.
2. Produce/refresh:
   - `PLAN.md` (architecture, constraints, milestones)
   - `TASKS.md` (ordered, implementation-ready tasks)
   - `QUESTIONS.md` (only remaining questions)
3. Stop and wait if questions remain.

## Phase B — Clarify (Human)

1. Relay `QUESTIONS.md` to the user.
2. Record answers in `DECISIONS.md` with date/time and rationale.
3. Re-run Phase A until no blocking questions remain.

## Phase C — Implement (Claude Code CLI)

1. Require explicit approval to implement.
2. Execute `TASKS.md` in order.
3. Run tests/lint/build.
4. Report:
   - completed tasks
   - changed files
   - test results
   - remaining risks

## Operational rules

- Never bypass unresolved blockers in `QUESTIONS.md`.
- Keep answers in files, not only chat.
- Prefer small incremental commits.
- If scope changes, return to Phase A.
