#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: heartbeat-check.sh [project_dir]

Safety-net monitor to re-dispatch missed events for MegaCoder runs.
Intended for OpenClaw HEARTBEAT.md or periodic hooks.

It checks each run and dispatches events only when content changed:
- blocker questions (QUESTIONS.md != NONE)
- implementation complete
- PR created
USAGE
}

trim_ws() {
  tr -d '[:space:]' < "$1"
}

sha_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

PROJECT_DIR="${1:-$(pwd)}"

if [[ "$PROJECT_DIR" == "-h" || "$PROJECT_DIR" == "--help" ]]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

RUNS_DIR=".megacoder/runs"
if [[ ! -d "$RUNS_DIR" ]]; then
  echo "HEARTBEAT_OK: no .megacoder/runs directory"
  exit 0
fi

sent_any=0

while IFS= read -r run_dir; do
  run_id="$(basename "$run_dir")"
  marker_dir="$run_dir/.dispatch"
  mkdir -p "$marker_dir"

  questions_file="$run_dir/QUESTIONS.md"
  summary_file="$run_dir/IMPLEMENTATION_SUMMARY.md"
  pr_file="$run_dir/PR_URL.txt"

  if [[ -f "$questions_file" ]]; then
    q_trimmed="$(trim_ws "$questions_file")"
    if [[ "$q_trimmed" != "NONE" && "$q_trimmed" != "PENDING" ]]; then
      q_hash="$(sha_file "$questions_file")"
      q_marker="$marker_dir/questions.sha256"
      q_prev=""
      if [[ -f "$q_marker" ]]; then
        q_prev="$(cat "$q_marker")"
      fi
      if [[ "$q_hash" != "$q_prev" ]]; then
        "$SCRIPT_DIR/dispatch-event.sh" "$PROJECT_DIR" "$run_id" questions
        printf '%s\n' "$q_hash" > "$q_marker"
        sent_any=1
      fi
      # If questions are open, skip lower-priority notifications for this run.
      continue
    fi
  fi

  if [[ -f "$summary_file" ]]; then
    s_hash="$(sha_file "$summary_file")"
    s_marker="$marker_dir/implemented.sha256"
    s_prev=""
    if [[ -f "$s_marker" ]]; then
      s_prev="$(cat "$s_marker")"
    fi
    if [[ "$s_hash" != "$s_prev" ]]; then
      "$SCRIPT_DIR/dispatch-event.sh" "$PROJECT_DIR" "$run_id" implemented
      printf '%s\n' "$s_hash" > "$s_marker"
      sent_any=1
    fi
  fi

  if [[ -f "$pr_file" ]]; then
    p_hash="$(sha_file "$pr_file")"
    p_marker="$marker_dir/pr.sha256"
    p_prev=""
    if [[ -f "$p_marker" ]]; then
      p_prev="$(cat "$p_marker")"
    fi
    if [[ "$p_hash" != "$p_prev" ]]; then
      "$SCRIPT_DIR/dispatch-event.sh" "$PROJECT_DIR" "$run_id" pr
      printf '%s\n' "$p_hash" > "$p_marker"
      sent_any=1
    fi
  fi

done < <(find "$RUNS_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

if [[ "$sent_any" -eq 1 ]]; then
  echo "HEARTBEAT_ACTION: dispatched pending MegaCoder events"
else
  echo "HEARTBEAT_OK: no pending MegaCoder events"
fi
