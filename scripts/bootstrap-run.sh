#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: bootstrap-run.sh [project_dir] [run_id]

Creates a run-scoped .megacoder/runs/<run_id> state folder and
.megacoder/worktrees/<run_id> isolated git worktree from origin/main.

Optional environment variables:
  MEGACODER_BASE_BRANCH=origin/main
  MEGACODER_BRANCH_PREFIX=codex
  MC_ORIGIN_AGENT_ID=<openclaw agent id that should be re-invoked>
  MC_TASK_ID=ABC-123
  MC_TASK_TITLE="Short task title"
  MC_TASK_SOURCE="slack|telegram|jira|linear|..."
  MC_TASK_TEXT="full inbound text"
  MC_TASK_TEXT_FILE=/path/to/full_context.txt
  MC_ROUTE_CHANNEL=slack|telegram|...
  MC_ROUTE_TARGET=channel:<id>|user:<id>|chat id
  MC_ROUTE_THREAD_ID=<thread/topic id>
  MC_ROUTE_REPLY_TO=<message id>
  MC_ROUTE_ACCOUNT=<account id>
USAGE
}

slugify() {
  local raw="${1:-}"
  local out
  out="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  if [[ -z "$out" ]]; then
    out="task"
  fi
  printf '%s' "$out"
}

quote_for_env() {
  printf "%s" "$1" | sed "s/'/'\"'\"'/g"
}

PROJECT_DIR="${1:-$(pwd)}"
RUN_ID="${2:-}"
BASE_BRANCH="${MEGACODER_BASE_BRANCH:-origin/main}"
BRANCH_PREFIX="${MEGACODER_BRANCH_PREFIX:-codex}"

if [[ "${PROJECT_DIR}" == "-h" || "${PROJECT_DIR}" == "--help" ]]; then
  usage
  exit 0
fi

cd "$PROJECT_DIR"

if [[ ! -d .git ]]; then
  echo "Not a git repository: $PROJECT_DIR"
  exit 1
fi

if [[ -z "$RUN_ID" ]]; then
  seed="${MC_TASK_ID:-${MC_TASK_TITLE:-task}}"
  RUN_ID="$(slugify "$seed")-$(date -u +%Y%m%d%H%M%S)"
fi

RUN_ROOT=".megacoder"
RUNS_DIR="$RUN_ROOT/runs"
WTS_DIR="$RUN_ROOT/worktrees"
RUN_DIR="$RUNS_DIR/$RUN_ID"
WT_DIR="$WTS_DIR/$RUN_ID"
BRANCH_NAME="$BRANCH_PREFIX/$RUN_ID"

mkdir -p "$RUNS_DIR" "$WTS_DIR"

if [[ ! -f .gitignore ]]; then
  touch .gitignore
fi
if ! grep -qxF ".megacoder/" .gitignore; then
  echo ".megacoder/" >> .gitignore
fi

git fetch origin --prune
if ! git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
  echo "Unable to resolve base branch '$BASE_BRANCH'. Set MEGACODER_BASE_BRANCH."
  exit 1
fi

mkdir -p "$RUN_DIR"

if [[ -e "$WT_DIR" ]]; then
  echo "Worktree already exists: $WT_DIR"
else
  git worktree add -B "$BRANCH_NAME" "$WT_DIR" "$BASE_BRANCH"
fi

ROUTE_FILE="$RUN_DIR/ROUTE.env"
{
  printf "MC_ROUTE_CHANNEL='%s'\n" "$(quote_for_env "${MC_ROUTE_CHANNEL:-}")"
  printf "MC_ROUTE_TARGET='%s'\n" "$(quote_for_env "${MC_ROUTE_TARGET:-}")"
  printf "MC_ROUTE_THREAD_ID='%s'\n" "$(quote_for_env "${MC_ROUTE_THREAD_ID:-}")"
  printf "MC_ROUTE_REPLY_TO='%s'\n" "$(quote_for_env "${MC_ROUTE_REPLY_TO:-}")"
  printf "MC_ROUTE_ACCOUNT='%s'\n" "$(quote_for_env "${MC_ROUTE_ACCOUNT:-}")"
  printf "MC_ORIGIN_AGENT_ID='%s'\n" "$(quote_for_env "${MC_ORIGIN_AGENT_ID:-}")"
  printf "MC_TASK_ID='%s'\n" "$(quote_for_env "${MC_TASK_ID:-}")"
  printf "MC_TASK_TITLE='%s'\n" "$(quote_for_env "${MC_TASK_TITLE:-}")"
  printf "MC_TASK_SOURCE='%s'\n" "$(quote_for_env "${MC_TASK_SOURCE:-unknown}")"
} > "$ROUTE_FILE"

TASK_TEXT=""
if [[ -n "${MC_TASK_TEXT_FILE:-}" && -f "${MC_TASK_TEXT_FILE:-}" ]]; then
  TASK_TEXT="$(cat "$MC_TASK_TEXT_FILE")"
elif [[ -n "${MC_TASK_TEXT:-}" ]]; then
  TASK_TEXT="${MC_TASK_TEXT}"
fi

if [[ ! -f "$RUN_DIR/INTAKE.md" ]]; then
  {
    echo "# Intake"
    echo
    echo "- run_id: $RUN_ID"
    echo "- source: ${MC_TASK_SOURCE:-unknown}"
    echo "- task_id: ${MC_TASK_ID:-unknown}"
    echo "- task_title: ${MC_TASK_TITLE:-untitled}"
    echo "- branch: $BRANCH_NAME"
    echo
    echo "## Requested Outcome"
    echo
    if [[ -n "$TASK_TEXT" ]]; then
      printf '%s\n' "$TASK_TEXT"
    else
      echo "Paste full ticket/thread text here."
    fi
    echo
    echo "## Route Metadata"
    echo
    echo "- channel: ${MC_ROUTE_CHANNEL:-}"
    echo "- target: ${MC_ROUTE_TARGET:-}"
    echo "- thread_id: ${MC_ROUTE_THREAD_ID:-}"
    echo "- reply_to: ${MC_ROUTE_REPLY_TO:-}"
    echo "- account: ${MC_ROUTE_ACCOUNT:-}"
    echo "- origin_agent_id: ${MC_ORIGIN_AGENT_ID:-}"
  } > "$RUN_DIR/INTAKE.md"
fi

if [[ ! -f "$RUN_DIR/CONTEXT.md" ]]; then
  cat > "$RUN_DIR/CONTEXT.md" <<'CONTEXT'
# Context

Add supporting context gathered by OpenClaw before planning:
- PM ticket details (Jira/Linear/etc)
- Linked docs/specs
- Existing production issues/incidents
- Repo constraints or team conventions
CONTEXT
fi

if [[ ! -f "$RUN_DIR/DECISIONS.md" ]]; then
  cat > "$RUN_DIR/DECISIONS.md" <<'DECISIONS'
# Decisions

Record explicit human decisions here.
Use UTC timestamps and rationale.

Example:
- 2026-02-24T18:33:00Z: Use Postgres instead of SQLite for production reliability.
DECISIONS
fi

if [[ ! -f "$RUN_DIR/QUESTIONS.md" ]]; then
  cat > "$RUN_DIR/QUESTIONS.md" <<'QUESTIONS'
PENDING
QUESTIONS
fi

if [[ ! -f "$RUN_DIR/STATUS.md" ]]; then
  cat > "$RUN_DIR/STATUS.md" <<STATUS
phase: initialized
updated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
STATUS
fi

echo "$RUN_ID" > "$RUN_ROOT/latest-run"

echo "Initialized MegaCoder run"
echo "run_id=$RUN_ID"
echo "run_dir=$RUN_DIR"
echo "worktree=$WT_DIR"
echo "branch=$BRANCH_NAME"
