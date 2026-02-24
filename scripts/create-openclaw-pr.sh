#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: create-openclaw-pr.sh [project_dir] [run_id]

Creates/publishes a PR from the run worktree branch.
OpenClaw should run this after successful implementation.

Optional environment variables:
  MEGACODER_PR_BASE_BRANCH=main
  MEGACODER_PR_KIND=feature|bugfix (default: feature)
  MEGACODER_PR_TITLE="custom title"
  MEGACODER_AUTO_COMMIT=1 (default: 1)
  MEGACODER_COMMIT_MESSAGE="custom commit message"
USAGE
}

title_from_intake() {
  local file="$1"
  local from_meta
  if [[ ! -f "$file" ]]; then
    return 0
  fi
  from_meta="$(sed -n 's/^- task_title: //p' "$file" | head -n 1)"
  if [[ -n "$from_meta" && "$from_meta" != "untitled" ]]; then
    printf '%s' "$from_meta"
    return 0
  fi
  awk 'NF && $0 !~ /^#/ && $0 !~ /^- / {print; exit}' "$file"
}

PROJECT_DIR="${1:-$(pwd)}"
RUN_ID="${2:-}"
PR_BASE_BRANCH="${MEGACODER_PR_BASE_BRANCH:-main}"
PR_KIND="${MEGACODER_PR_KIND:-feature}"
AUTO_COMMIT="${MEGACODER_AUTO_COMMIT:-1}"

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
if [[ ! -f "$RUN_DIR/IMPLEMENTATION_SUMMARY.md" ]]; then
  echo "Implementation summary not found: $RUN_DIR/IMPLEMENTATION_SUMMARY.md"
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not found in PATH"
  exit 1
fi

q_trimmed="NONE"
if [[ -f "$RUN_DIR/QUESTIONS.md" ]]; then
  q_trimmed="$(tr -d '[:space:]' < "$RUN_DIR/QUESTIONS.md")"
fi
if [[ "$q_trimmed" != "NONE" ]]; then
  echo "Run still has blockers in $RUN_DIR/QUESTIONS.md"
  exit 1
fi

BRANCH_NAME="$(git -C "$WT_DIR" branch --show-current)"
if [[ -z "$BRANCH_NAME" ]]; then
  echo "Unable to detect branch for worktree $WT_DIR"
  exit 1
fi

if [[ "$AUTO_COMMIT" == "1" ]]; then
  if [[ -n "$(git -C "$WT_DIR" status --porcelain)" ]]; then
    git -C "$WT_DIR" add -A
    if [[ -n "$(git -C "$WT_DIR" diff --cached --name-only)" ]]; then
      COMMIT_MSG="${MEGACODER_COMMIT_MESSAGE:-Implement MegaCoder run $RUN_ID}"
      git -C "$WT_DIR" commit -m "$COMMIT_MSG"
    fi
  fi
fi

git -C "$WT_DIR" push -u origin "$BRANCH_NAME"

TITLE="${MEGACODER_PR_TITLE:-}"
if [[ -z "$TITLE" ]]; then
  TASK_TITLE=""
  if [[ -f "$RUN_DIR/ROUTE.env" ]]; then
    # shellcheck disable=SC1090
    source "$RUN_DIR/ROUTE.env"
    TASK_TITLE="${MC_TASK_TITLE:-}"
  fi
  if [[ -z "$TASK_TITLE" ]]; then
    TASK_TITLE="$(title_from_intake "$RUN_DIR/INTAKE.md")"
  fi
  if [[ -z "$TASK_TITLE" ]]; then
    TASK_TITLE="MegaCoder run $RUN_ID"
  fi
  case "$PR_KIND" in
    feature)
      TITLE="feat: ${TASK_TITLE#\# }"
      ;;
    bugfix)
      TITLE="fix: ${TASK_TITLE#\# }"
      ;;
    *)
      TITLE="chore: ${TASK_TITLE#\# }"
      ;;
  esac
fi

BODY_FILE="$RUN_DIR/PR_BODY.md"
{
  echo "## Summary"
  echo
  cat "$RUN_DIR/IMPLEMENTATION_SUMMARY.md"
  echo
  if [[ -f "$RUN_DIR/TEST_RESULTS.md" ]]; then
    echo "## Test Results"
    echo
    cat "$RUN_DIR/TEST_RESULTS.md"
    echo
  fi
  if [[ -f "$RUN_DIR/CODEX_FINDINGS.md" ]]; then
    echo "## Architecture / Planning Findings"
    echo
    cat "$RUN_DIR/CODEX_FINDINGS.md"
    echo
  fi
  echo "## Run Metadata"
  echo
  echo "- run_id: $RUN_ID"
  echo "- branch: $BRANCH_NAME"
  echo "- generated_by: OpenClaw MegaCoder"
} > "$BODY_FILE"

PR_URL=""
if PR_URL=$(cd "$WT_DIR" && gh pr view --head "$BRANCH_NAME" --json url -q .url 2>/dev/null); then
  :
else
  PR_URL="$(cd "$WT_DIR" && gh pr create --base "$PR_BASE_BRANCH" --head "$BRANCH_NAME" --title "$TITLE" --body-file "$BODY_FILE")"
fi

printf '%s\n' "$PR_URL" > "$RUN_DIR/PR_URL.txt"

cat > "$RUN_DIR/STATUS.md" <<STATUS
phase: pr_opened
updated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
pr_url: $PR_URL
STATUS

if [[ -x "$SCRIPT_DIR/dispatch-event.sh" ]]; then
  "$SCRIPT_DIR/dispatch-event.sh" "$PROJECT_DIR" "$RUN_ID" pr
fi

echo "PR ready: $PR_URL"
