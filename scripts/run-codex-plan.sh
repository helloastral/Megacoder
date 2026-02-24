#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: run-codex-plan.sh [project_dir] [run_id]

Run Codex planning for a MegaCoder run.
If run_id is omitted, .megacoder/latest-run is used.

Optional environment variables:
  MEGACODER_CODEX_MODE=safe|yolo (default: safe)
  MEGACODER_CODEX_MODEL=<model>
  MEGACODER_CODEX_SEARCH=1
USAGE
}

PROJECT_DIR="${1:-$(pwd)}"
RUN_ID="${2:-}"
CODEX_MODE="${MEGACODER_CODEX_MODE:-safe}"

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

for f in INTAKE.md CONTEXT.md DECISIONS.md; do
  if [[ ! -f "$ABS_RUN_DIR/$f" ]]; then
    echo "Missing required file: $ABS_RUN_DIR/$f"
    exit 1
  fi
done

CONTEXT_PACKET="$ABS_RUN_DIR/PLANNING_CONTEXT.md"
{
  echo "# Planning Context Packet"
  echo
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Run ID: $RUN_ID"
  echo "Worktree: $ABS_WT_DIR"
  for f in INTAKE.md CONTEXT.md DECISIONS.md PLAN.md TASKS.md QUESTIONS.md CODEX_FINDINGS.md; do
    if [[ -f "$ABS_RUN_DIR/$f" ]]; then
      echo
      echo "## $f"
      echo
      cat "$ABS_RUN_DIR/$f"
    fi
  done
} > "$CONTEXT_PACKET"

PROMPT=$(cat <<EOF2
You are the architecture and planning agent for MegaCoder run '$RUN_ID'.

Repository root:
$ABS_WT_DIR

Run state directory:
$ABS_RUN_DIR

Read first:
- $ABS_RUN_DIR/PLANNING_CONTEXT.md
- repository code under $ABS_WT_DIR

Then write/overwrite these files in the run state directory:
1. $ABS_RUN_DIR/CODEX_FINDINGS.md
2. $ABS_RUN_DIR/PLAN.md
3. $ABS_RUN_DIR/TASKS.md
4. $ABS_RUN_DIR/QUESTIONS.md

Required output quality:
- Capture what the user actually wants, constraints, and acceptance criteria.
- Include what you discovered from the codebase in CODEX_FINDINGS.md.
- PLAN.md must include architecture decisions, risks, and milestones.
- TASKS.md must be execution-ready, ordered, and include validation steps.
- QUESTIONS.md must be exactly: NONE  (when no blockers remain)

Rules:
- Do not implement code changes.
- Keep assumptions explicit.
- Use DECISIONS.md as the source of truth for approved decisions.
- Ask only high-impact blocker questions.
EOF2
)

if ! command -v codex >/dev/null 2>&1; then
  echo "codex CLI not found in PATH"
  exit 1
fi

CMD=(codex exec --cd "$ABS_WT_DIR" --add-dir "$ABS_RUN_DIR" --output-last-message "$ABS_RUN_DIR/CODEX_LAST_MESSAGE.md" --json)
if [[ -n "${MEGACODER_CODEX_MODEL:-}" ]]; then
  CMD+=(--model "$MEGACODER_CODEX_MODEL")
fi
if [[ "${MEGACODER_CODEX_SEARCH:-0}" == "1" ]]; then
  CMD+=(--search)
fi

case "$CODEX_MODE" in
  safe)
    CMD+=(--ask-for-approval never --sandbox workspace-write)
    ;;
  yolo)
    CMD+=(--yolo)
    ;;
  *)
    echo "Invalid MEGACODER_CODEX_MODE: $CODEX_MODE (expected safe|yolo)"
    exit 1
    ;;
esac

"${CMD[@]}" "$PROMPT" > "$ABS_RUN_DIR/CODEX_EVENTS.jsonl"

for f in CODEX_FINDINGS.md PLAN.md TASKS.md QUESTIONS.md; do
  if [[ ! -s "$ABS_RUN_DIR/$f" ]]; then
    echo "Codex did not produce expected file: $ABS_RUN_DIR/$f"
    exit 1
  fi
done

cat > "$ABS_RUN_DIR/STATUS.md" <<STATUS
phase: planned
updated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
STATUS

if [[ -x "$SCRIPT_DIR/notify-origin.sh" ]]; then
  q_trimmed="$(tr -d '[:space:]' < "$ABS_RUN_DIR/QUESTIONS.md")"
  if [[ "$q_trimmed" == "NONE" ]]; then
    "$SCRIPT_DIR/notify-origin.sh" "$PROJECT_DIR" "$RUN_ID" planned || true
  else
    "$SCRIPT_DIR/notify-origin.sh" "$PROJECT_DIR" "$RUN_ID" questions || true
  fi
fi

echo "Codex planning run complete for run_id=$RUN_ID"
echo "Review: $ABS_RUN_DIR/PLAN.md, $ABS_RUN_DIR/TASKS.md, $ABS_RUN_DIR/QUESTIONS.md"
