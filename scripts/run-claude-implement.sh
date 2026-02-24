#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
cd "$PROJECT_DIR"

for f in PLAN.md TASKS.md DECISIONS.md; do
  [[ -f "$f" ]] || { echo "Missing required file: $f"; exit 1; }
done

if [[ -f QUESTIONS.md ]]; then
  if [[ "$(tr -d '[:space:]' < QUESTIONS.md)" != "NONE" ]]; then
    echo "QUESTIONS.md still has unresolved items. Resolve blockers before implementation."
    exit 1
  fi
fi

PROMPT=$(cat <<'EOF'
You are the implementation engineer.

Read PLAN.md, TASKS.md, and DECISIONS.md.
Implement TASKS.md in order with minimal scope drift.

Rules:
- If blocked, STOP and write blocker(s) into QUESTIONS.md, then exit.
- Keep changes small and reviewable.
- Run relevant tests/lint/build.
- At the end, output a concise summary of completed tasks and test results.
EOF
)

claude -p --permission-mode bypassPermissions "$PROMPT"

echo "Claude implementation run finished. Review git diff and test output."
