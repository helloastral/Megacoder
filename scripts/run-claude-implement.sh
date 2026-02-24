#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
cd "$PROJECT_DIR"

STATE_DIR=".megacoder"
mkdir -p "$STATE_DIR"

for f in "$STATE_DIR/PLAN.md" "$STATE_DIR/TASKS.md" "$STATE_DIR/DECISIONS.md"; do
  [[ -f "$f" ]] || { echo "Missing required file: $f"; exit 1; }
done

if [[ -f "$STATE_DIR/QUESTIONS.md" ]]; then
  if [[ "$(tr -d '[:space:]' < "$STATE_DIR/QUESTIONS.md")" != "NONE" ]]; then
    echo ".megacoder/QUESTIONS.md still has unresolved items. Resolve blockers before implementation."
    exit 1
  fi
fi

PROMPT=$(cat <<'EOF'
You are the implementation engineer.

All project-state files are in .megacoder/.
Read .megacoder/PLAN.md, .megacoder/TASKS.md, and .megacoder/DECISIONS.md.
Implement .megacoder/TASKS.md in order with minimal scope drift.

Rules:
- If blocked, STOP and write blocker(s) into .megacoder/QUESTIONS.md, then exit.
- Keep changes small and reviewable.
- Run relevant tests/lint/build.
- At the end, output a concise summary of completed tasks and test results.
EOF
)

claude -p --permission-mode bypassPermissions "$PROMPT"

echo "Claude implementation run finished. Review git diff and test output."
