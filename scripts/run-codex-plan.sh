#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
cd "$PROJECT_DIR"

STATE_DIR=".megacoder"
mkdir -p "$STATE_DIR"

for f in "$STATE_DIR/ROUGH_DRAFT.md"; do
  [[ -f "$f" ]] || { echo "Missing required file: $f"; exit 1; }
done

[[ -f "$STATE_DIR/DECISIONS.md" ]] || touch "$STATE_DIR/DECISIONS.md"

PROMPT=$(cat <<'EOF'
You are the planning architect for this project.

All project-state files are in .megacoder/.
Read:
- .megacoder/ROUGH_DRAFT.md
- .megacoder/DECISIONS.md

Then write/overwrite:
1) .megacoder/PLAN.md - architecture, milestones, assumptions, risks
2) .megacoder/TASKS.md - ordered implementation checklist
3) .megacoder/QUESTIONS.md - only unresolved blockers requiring human input

Rules:
- Do NOT implement code.
- Keep questions concise and high impact.
- If there are no blockers, set .megacoder/QUESTIONS.md to exactly: NONE
EOF
)

codex exec --full-auto --sandbox workspace-write "$PROMPT"

echo "Codex planning run complete. Review .megacoder/PLAN.md, .megacoder/TASKS.md, .megacoder/QUESTIONS.md"
