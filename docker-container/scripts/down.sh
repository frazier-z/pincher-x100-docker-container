#!/bin/bash
# Stop the px100 container, then the Mac U2D2 bridge.
# The container is kept, so /opt/dxl_ws and /tmp/px100_slow.yaml stay.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
COMPOSE=(docker compose -f docker-compose.yml -f docker-compose.mac.yml)

say() { printf '%s\n' "$*"; }

bridge_pids() {
  pgrep -f "[s]cripts/mac_u2d2_bridge.py" || true
}

say "Stopping the container."
"${COMPOSE[@]}" stop

pids="$(bridge_pids)"
if [[ -z "$pids" ]]; then
  say "U2D2 bridge is not running."
else
  say "Stopping the U2D2 bridge."
  # shellcheck disable=SC2086
  kill $pids
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 0.2
    pids="$(bridge_pids)"
    [[ -z "$pids" ]] && break
  done
  if [[ -n "$(bridge_pids)" ]]; then
    say "Bridge did not exit. Still running:"
    pgrep -fl "[s]cripts/mac_u2d2_bridge.py" >&2 || true
    exit 1
  fi
fi

say "Stopped. The container is still on disk. Start again with ./scripts/up.sh"
