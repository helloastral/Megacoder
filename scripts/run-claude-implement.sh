#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: run-claude-implement.sh [project_dir] [run_id]

Run Claude implementation for a MegaCoder run.
If run_id is omitted, .megacoder/latest-run is used.

Optional environment variables:
  MEGACODER_CLAUDE_MODE=dangerous|safe (default: dangerous)
  MEGACODER_CLAUDE_PERMISSION_MODE=bypassPermissions|acceptEdits|plan|default (used only in safe mode; default: bypassPermissions)
  MEGACODER_CLAUDE_MODEL=<model>
  MEGACODER_RUN_AS_USER=<username> (optional when running as root; used only if useradd/runuser are available)
USAGE
}

PROJECT_DIR="${1:-$(pwd)}"
RUN_ID="${2:-}"
CLAUDE_MODE="${MEGACODER_CLAUDE_MODE:-dangerous}"
PERMISSION_MODE="${MEGACODER_CLAUDE_PERMISSION_MODE:-bypassPermissions}"

if [[ "$PROJECT_DIR" == "-h" || "$PROJECT_DIR" == "--help" ]]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

if [[ -z "$RUN_ID" ]]; then
  if [[ -f .megacoder/latest-run ]]; then
    RUN_ID="$(cat .megacoder/latest-run)"
  else
    echo "Missing run_id and .megacoder/latest-run not found"
    exit 1
  fi
fi

RUN_DIR=".megacoder/runs/$RUN_ID"
WT_DIR=".megacoder/worktrees/$RUN_ID"

if [[ ! -d "$RUN_DIR" ]]; then
  echo "Run directory not found: $RUN_DIR"
  exit 1
fi
if [[ ! -d "$WT_DIR" ]]; then
  echo "Worktree not found: $WT_DIR"
  exit 1
fi

ABS_RUN_DIR="$(cd "$RUN_DIR" && pwd)"
ABS_WT_DIR="$(cd "$WT_DIR" && pwd)"

for f in PLAN.md TASKS.md DECISIONS.md INTAKE.md CONTEXT.md CODEX_FINDINGS.md; do
  if [[ ! -f "$ABS_RUN_DIR/$f" ]]; then
    echo "Missing required file: $ABS_RUN_DIR/$f"
    exit 1
  fi
done

if [[ -f "$ABS_RUN_DIR/QUESTIONS.md" ]]; then
  q_trimmed="$(tr -d '[:space:]' < "$ABS_RUN_DIR/QUESTIONS.md")"
  if [[ "$q_trimmed" != "NONE" ]]; then
    echo "$ABS_RUN_DIR/QUESTIONS.md still has unresolved items. Resolve blockers first."
    exit 1
  fi
fi

IMPLEMENT_CONTEXT="$ABS_RUN_DIR/IMPLEMENTATION_CONTEXT.md"
{
  echo "# Implementation Context Packet"
  echo
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Run ID: $RUN_ID"
  echo "Worktree: $ABS_WT_DIR"
  for f in INTAKE.md CONTEXT.md DECISIONS.md CODEX_FINDINGS.md PLAN.md TASKS.md; do
    echo
    echo "## $f"
    echo
    cat "$ABS_RUN_DIR/$f"
  done
} > "$IMPLEMENT_CONTEXT"

PROMPT=$(cat <<EOF2
You are the implementation agent for MegaCoder run '$RUN_ID'.

Repository root (apply code changes here):
$ABS_WT_DIR

Run state directory:
$ABS_RUN_DIR

Read first:
- $ABS_RUN_DIR/IMPLEMENTATION_CONTEXT.md
- relevant repository code in $ABS_WT_DIR

Implementation requirements:
- Implement TASKS.md in order with minimal scope drift.
- Preserve explicit decisions in DECISIONS.md.
- Keep changes reviewable and well scoped.
- Run relevant tests/lint/build commands.

Write/overwrite these run artifacts:
1. $ABS_RUN_DIR/QUESTIONS.md
   - exactly NONE if no blockers remain
   - otherwise blocker questions requiring human input
2. $ABS_RUN_DIR/IMPLEMENTATION_SUMMARY.md
   - completed tasks, changed files, rationale, known risks
3. $ABS_RUN_DIR/TEST_RESULTS.md
   - exact commands executed and results

If blocked by missing information:
- stop further implementation
- write blocker questions to QUESTIONS.md
- summarize partial progress in IMPLEMENTATION_SUMMARY.md
EOF2
)

if ! command -v claude >/dev/null 2>&1; then
  echo "claude CLI not found in PATH"
  exit 1
fi

CMD=(claude -p --add-dir "$ABS_RUN_DIR" --output-format json)
if [[ -n "${MEGACODER_CLAUDE_MODEL:-}" ]]; then
  CMD+=(--model "$MEGACODER_CLAUDE_MODEL")
fi

case "$CLAUDE_MODE" in
  dangerous)
    CMD+=(--permission-mode bypassPermissions)
    ;;
  safe)
    CMD+=(--permission-mode "$PERMISSION_MODE")
    ;;
  *)
    echo "Invalid MEGACODER_CLAUDE_MODE: $CLAUDE_MODE (expected dangerous|safe)"
    exit 1
    ;;
esac

RUN_USER="${MEGACODER_RUN_AS_USER:-openclaw}"

if [[ "$(id -u)" -eq 0 ]]; then
  # Claude refuses --permission-mode bypassPermissions under root.
  # Try to drop privileges when system tools are available; otherwise fallback to root.
  if command -v useradd >/dev/null 2>&1 && command -v runuser >/dev/null 2>&1; then
    if ! id "$RUN_USER" &>/dev/null; then
      echo "User '$RUN_USER' does not exist. Creating..."
      useradd -r -m -s /bin/bash "$RUN_USER"
    fi
    chown -R "$RUN_USER" "$ABS_RUN_DIR" "$ABS_WT_DIR"
    (
      cd "$ABS_WT_DIR"
      runuser -u "$RUN_USER" -- "${CMD[@]}" "$PROMPT"
    ) > "$ABS_RUN_DIR/CLAUDE_OUTPUT.json"
  else
    echo "useradd/runuser not available; running claude as current user (root)."
    (
      cd "$ABS_WT_DIR"
      "${CMD[@]}" "$PROMPT"
    ) > "$ABS_RUN_DIR/CLAUDE_OUTPUT.json"
  fi
else
  (
    cd "$ABS_WT_DIR"
    "${CMD[@]}" "$PROMPT"
  ) > "$ABS_RUN_DIR/CLAUDE_OUTPUT.json"
fi

if [[ ! -f "$ABS_RUN_DIR/QUESTIONS.md" ]]; then
  echo "Claude did not produce QUESTIONS.md"
  exit 1
fi
if [[ ! -f "$ABS_RUN_DIR/IMPLEMENTATION_SUMMARY.md" ]]; then
  echo "Claude did not produce IMPLEMENTATION_SUMMARY.md"
  exit 1
fi
if [[ ! -f "$ABS_RUN_DIR/TEST_RESULTS.md" ]]; then
  echo "Claude did not produce TEST_RESULTS.md"
  exit 1
fi

q_trimmed="$(tr -d '[:space:]' < "$ABS_RUN_DIR/QUESTIONS.md")"
if [[ "$q_trimmed" == "NONE" ]]; then
  phase="implemented"
else
  phase="blocked"
fi

cat > "$ABS_RUN_DIR/STATUS.md" <<STATUS
phase: $phase
updated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
STATUS

if [[ -x "$SCRIPT_DIR/dispatch-event.sh" ]]; then
  if [[ "$q_trimmed" == "NONE" ]]; then
    "$SCRIPT_DIR/dispatch-event.sh" "$PROJECT_DIR" "$RUN_ID" implemented
  else
    "$SCRIPT_DIR/dispatch-event.sh" "$PROJECT_DIR" "$RUN_ID" questions
  fi
fi

echo "Claude implementation run finished for run_id=$RUN_ID"
if [[ "$q_trimmed" == "NONE" ]]; then
  echo "No blockers remain. OpenClaw can now create the PR."
else
  echo "Blockers were raised in $ABS_RUN_DIR/QUESTIONS.md"
fi
