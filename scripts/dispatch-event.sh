#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: dispatch-event.sh [project_dir] [run_id] [event]

Dispatch a MegaCoder event by:
1) notifying the origin channel/thread (if route metadata exists)
2) waking the orchestrating OpenClaw agent

Event options: initialized | planned | questions | implemented | pr
USAGE
}

PROJECT_DIR="${1:-$(pwd)}"
RUN_ID="${2:-}"
EVENT="${3:-}"

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
ROUTE_FILE="$RUN_DIR/ROUTE.env"

if [[ ! -d "$RUN_DIR" ]]; then
  echo "Run directory not found: $RUN_DIR"
  exit 1
fi

# Route metadata may be missing in local/manual runs; keep this path non-fatal.
has_channel_route=0
if [[ -f "$ROUTE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ROUTE_FILE"
  if [[ -n "${MC_ROUTE_CHANNEL:-}" && -n "${MC_ROUTE_TARGET:-}" ]]; then
    has_channel_route=1
  fi
fi

notify_ok=0
wake_ok=0

if [[ $has_channel_route -eq 1 ]]; then
  if "$SCRIPT_DIR/notify-origin.sh" "$PROJECT_DIR" "$RUN_ID" "$EVENT"; then
    notify_ok=1
  else
    echo "notify-origin failed for run_id=$RUN_ID event=$EVENT" >&2
  fi
else
  echo "No channel route metadata for run_id=$RUN_ID; skipping notify-origin" >&2
  notify_ok=1
fi

if "$SCRIPT_DIR/wake-main-agent.sh" "$PROJECT_DIR" "$RUN_ID" "$EVENT"; then
  wake_ok=1
else
  echo "wake-main-agent failed for run_id=$RUN_ID event=$EVENT" >&2
fi

if [[ $notify_ok -eq 1 && $wake_ok -eq 1 ]]; then
  exit 0
fi

# If this run is route-less local execution and wake failed, do not hard-fail.
if [[ $has_channel_route -eq 0 && $wake_ok -eq 0 ]]; then
  echo "Local run without routing metadata; continuing without external dispatch" >&2
  exit 0
fi

exit 1
