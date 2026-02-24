#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: wake-main-agent.sh [project_dir] [run_id] [event]

Wake the orchestrating OpenClaw agent after a run event.
Event options: planned | questions | implemented | pr

Wake order:
1) targeted wake via openclaw agent --agent <MC_ORIGIN_AGENT_ID>
2) fallback global wake via openclaw system event --mode now
USAGE
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
    MSG="MegaCoder run $RUN_ID planned. Review plan and decide whether to proceed to implementation."
    ;;
  questions)
    MSG="MegaCoder run $RUN_ID has blocker questions. Ask the user in the originating thread, append answers to DECISIONS.md, then continue."
    ;;
  implemented)
    MSG="MegaCoder run $RUN_ID implementation finished. Review summary/tests and create PR if acceptable."
    ;;
  pr)
    MSG="MegaCoder run $RUN_ID PR was created. Share the PR link and next review steps."
    ;;
  *)
    echo "Unsupported event: $EVENT"
    exit 1
    ;;
esac

wake_targeted() {
  if [[ -z "${MC_ORIGIN_AGENT_ID:-}" ]]; then
    return 1
  fi
  openclaw agent --agent "$MC_ORIGIN_AGENT_ID" --message "$MSG" >/dev/null
}

wake_global() {
  openclaw system event --text "$MSG" --mode now >/dev/null
}

if wake_targeted; then
  echo "Woke origin agent '$MC_ORIGIN_AGENT_ID' for run_id=$RUN_ID event=$EVENT"
  exit 0
fi

if wake_global; then
  echo "Triggered global system wake for run_id=$RUN_ID event=$EVENT"
  exit 0
fi

echo "Failed to wake main agent for run_id=$RUN_ID event=$EVENT"
exit 1
