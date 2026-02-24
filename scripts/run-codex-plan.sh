#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
cd "$PROJECT_DIR"

for f in ROUGH_DRAFT.md; do
  [[ -f "$f" ]] || { echo "Missing required file: $f"; exit 1; }
done

[[ -f DECISIONS.md ]] || touch DECISIONS.md

PROMPT=$(cat <<'EOF'
You are the planning architect for this project.

Read ROUGH_DRAFT.md and DECISIONS.md.
Then write/overwrite:
1) PLAN.md - architecture, milestones, assumptions, risks
2) TASKS.md - ordered implementation checklist
3) QUESTIONS.md - only unresolved blockers requiring human input

Rules:
- Do NOT implement code.
- Keep questions concise and high impact.
- If there are no blockers, set QUESTIONS.md to exactly: NONE
EOF
)

codex exec --full-auto --sandbox workspace-write "$PROMPT"

echo "Codex planning run complete. Review PLAN.md, TASKS.md, QUESTIONS.md"
