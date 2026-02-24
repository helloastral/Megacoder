#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: notify-origin.sh [project_dir] [run_id] [event]

Sends a run update back to the originating OpenClaw route.
Event options: planned | questions | implemented | pr
USAGE
}

trim_file() {
  local file="$1"
  local max_chars="$2"
  if [[ ! -f "$file" ]]; then
    return 0
  fi
  LC_ALL=C head -c "$max_chars" "$file"
}

PROJECT_DIR="${1:-$(pwd)}"
RUN_ID="${2:-}"
EVENT="${3:-}"

if [[ "$PROJECT_DIR" == "-h" || "$PROJECT_DIR" == "--help" ]]; then
  usage
  exit 0
fi

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
ROUTE_FILE="$RUN_DIR/ROUTE.env"

if [[ ! -d "$RUN_DIR" ]]; then
  echo "Run directory not found: $RUN_DIR"
  exit 1
fi
if [[ ! -f "$ROUTE_FILE" ]]; then
  echo "Route file not found: $ROUTE_FILE"
  exit 1
fi

# shellcheck disable=SC1090
source "$ROUTE_FILE"

if [[ -z "${MC_ROUTE_CHANNEL:-}" || -z "${MC_ROUTE_TARGET:-}" ]]; then
  echo "Missing MC_ROUTE_CHANNEL or MC_ROUTE_TARGET in $ROUTE_FILE"
  exit 1
fi

if ! command -v openclaw >/dev/null 2>&1; then
  echo "openclaw CLI not found in PATH"
  exit 1
fi

if [[ -z "$EVENT" ]]; then
  if [[ -f "$RUN_DIR/PR_URL.txt" ]]; then
    EVENT="pr"
  elif [[ -f "$RUN_DIR/QUESTIONS.md" && "$(tr -d '[:space:]' < "$RUN_DIR/QUESTIONS.md")" != "NONE" ]]; then
    EVENT="questions"
  elif [[ -f "$RUN_DIR/IMPLEMENTATION_SUMMARY.md" ]]; then
    EVENT="implemented"
  else
    EVENT="planned"
  fi
fi

MSG=""
case "$EVENT" in
  planned)
    MSG="MegaCoder run $RUN_ID: planning complete. Review PLAN.md and TASKS.md."
    ;;
  questions)
    QUESTIONS_SNIPPET="$(trim_file "$RUN_DIR/QUESTIONS.md" 3000)"
    MSG=$(cat <<EOFMSG
MegaCoder run $RUN_ID needs input before continuing:

$QUESTIONS_SNIPPET
EOFMSG
)
    ;;
  implemented)
    SUMMARY_SNIPPET="$(trim_file "$RUN_DIR/IMPLEMENTATION_SUMMARY.md" 2500)"
    TEST_SNIPPET="$(trim_file "$RUN_DIR/TEST_RESULTS.md" 1200)"
    MSG=$(cat <<EOFMSG
MegaCoder run $RUN_ID implementation finished.

Summary:
$SUMMARY_SNIPPET

Tests:
$TEST_SNIPPET

OpenClaw can now create the PR.
EOFMSG
)
    ;;
  pr)
    PR_URL=""
    if [[ -f "$RUN_DIR/PR_URL.txt" ]]; then
      PR_URL="$(cat "$RUN_DIR/PR_URL.txt")"
    fi
    MSG="MegaCoder run $RUN_ID PR created: $PR_URL"
    ;;
  *)
    echo "Unsupported event: $EVENT"
    exit 1
    ;;
esac

CMD=(openclaw message send --channel "$MC_ROUTE_CHANNEL" --target "$MC_ROUTE_TARGET" --message "$MSG")
if [[ -n "${MC_ROUTE_ACCOUNT:-}" ]]; then
  CMD+=(--account "$MC_ROUTE_ACCOUNT")
fi
if [[ -n "${MC_ROUTE_THREAD_ID:-}" ]]; then
  CMD+=(--thread-id "$MC_ROUTE_THREAD_ID")
fi
if [[ -n "${MC_ROUTE_REPLY_TO:-}" ]]; then
  CMD+=(--reply-to "$MC_ROUTE_REPLY_TO")
fi

"${CMD[@]}"

echo "Sent '$EVENT' update for run_id=$RUN_ID to channel=$MC_ROUTE_CHANNEL target=$MC_ROUTE_TARGET"
