#!/bin/bash
# Start the Mac U2D2 bridge and the px100 driver. Exits when both are up.
# Pose commands are published from a shell inside the container after this.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
COMPOSE=(docker compose -f docker-compose.yml -f docker-compose.mac.yml)
BRIDGE_LOG="${TMPDIR:-/tmp}/px100-bridge.log"
DEVICE="${1:-}"

say() { printf '%s\n' "$*"; }

bridge_running() {
  pgrep -f "scripts/mac_u2d2_bridge.py" >/dev/null 2>&1
}

start_bridge() {
  if bridge_running; then
    say "U2D2 bridge is already running."
    return
  fi
  say "Starting U2D2 bridge."
  : >"$BRIDGE_LOG"
  # New session, so the bridge keeps the U2D2 after this script exits.
  BRIDGE_LOG="$BRIDGE_LOG" python3 - "$DEVICE" << 'PY'
import os
import sys
device = sys.argv[1]
log = os.environ["BRIDGE_LOG"]
if os.fork() > 0:
    raise SystemExit(0)
os.setsid()
if os.fork() > 0:
    raise SystemExit(0)
fd = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
os.dup2(fd, 1)
os.dup2(fd, 2)
argv = ["python3", "scripts/mac_u2d2_bridge.py"]
if device:
    argv.append(device)
os.execvp("python3", argv)
PY
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if grep -q "waiting on 127.0.0.1:8765" "$BRIDGE_LOG" 2>/dev/null; then
      say "Bridge is listening. Log: $BRIDGE_LOG"
      return
    fi
    if ! bridge_running; then
      say "Bridge exited. Log:"
      cat "$BRIDGE_LOG" >&2
      exit 1
    fi
    sleep 0.3
  done
  say "Bridge did not start listening. Log:"
  cat "$BRIDGE_LOG" >&2
  exit 1
}

driver_running() {
  "${COMPOSE[@]}" exec -T px100 bash -lc 'ps -eo cmd' | grep -q '/interbotix_xs_sdk/xs_sdk ' || return 1
}

launch_running() {
  "${COMPOSE[@]}" exec -T px100 bash -lc 'ps -eo cmd' | grep -q 'xsarm_control.launch.py' || return 1
}

stop_launch() {
  if ! launch_running; then
    return
  fi
  say "Stopping the previous driver launch."
  "${COMPOSE[@]}" exec -T px100 bash -s << 'EOS'
ps -eo pid,cmd | awk '/xsarm_control.launch.py/ && !/awk/ {print $1}' | while read -r pid; do
  kill -INT "$pid" 2>/dev/null || true
done
EOS
  local i
  for i in $(seq 1 20); do
    if ! launch_running && ! driver_running; then
      return
    fi
    sleep 0.3
  done
  say "The previous driver launch did not exit."
  exit 1
}

wait_for_tty() {
  local i
  for i in $(seq 1 20); do
    if "${COMPOSE[@]}" exec -T px100 bash -lc 'test -L /dev/ttyDXL'; then
      return 0
    fi
    sleep 0.5
  done
  say "The container never linked /dev/ttyDXL. Is the bridge still running?"
  return 1
}

# 0 = driver up, 2 = waist hardware error, 1 = anything else
wait_for_driver() {
  local i
  for i in $(seq 1 45); do
    if "${COMPOSE[@]}" exec -T px100 bash -lc 'grep -qs "Interbotix X-Series Driver is up" /tmp/xsarm.log'; then
      return 0
    fi
    if "${COMPOSE[@]}" exec -T px100 bash -lc 'grep -qs "Failed to find all motors" /tmp/xsarm.log'; then
      if "${COMPOSE[@]}" exec -T px100 bash -lc 'grep -qs "Hardware error occurred" /tmp/xsarm.log && grep -qs "Joint Name: '"'"'waist'"'"'" /tmp/xsarm.log'; then
        return 2
      fi
      return 1
    fi
    sleep 1
  done
  return 1
}

launch_driver() {
  "${COMPOSE[@]}" exec -T px100 rm -f /tmp/xsarm.log
  "${COMPOSE[@]}" exec -d px100 bash -lc 'source /opt/ros/humble/setup.bash && source /opt/gazebo_ws/install/setup.bash && source /root/interbotix_ws/install/setup.bash && source /opt/dxl_ws/install/setup.bash && ros2 launch interbotix_xsarm_control xsarm_control.launch.py robot_model:=px100 motor_configs:=/tmp/px100_slow.yaml > /tmp/xsarm.log 2>&1'
}

reboot_waist() {
  say "Waist servo has a latched hardware error. Rebooting it."
  wait_for_tty
  "${COMPOSE[@]}" exec -T px100 bash -s << 'EOS'
set -eo pipefail
set +u
source /opt/dxl_ws/install/setup.bash
set -u
cat > /tmp/reboot_waist.cpp << 'EOF'
#include <cstdio>
#include <cstdint>
#include <unistd.h>
#include "dynamixel_sdk/dynamixel_sdk.h"
int main() {
  dynamixel::PortHandler * port = dynamixel::PortHandler::getPortHandler("/dev/ttyDXL");
  dynamixel::PacketHandler * pkt = dynamixel::PacketHandler::getPacketHandler(2.0);
  if (!port->openPort() || !port->setBaudRate(1000000)) {
    std::printf("could not open /dev/ttyDXL\n");
    return 1;
  }
  uint8_t err = 0;
  int rc = pkt->reboot(port, 1, &err);
  std::printf("reboot rc=%d err=%u\n", rc, err);
  usleep(800000);
  uint16_t model = 0;
  rc = pkt->ping(port, 1, &model, &err);
  std::printf("ping model=%u rc=%d err=%u\n", model, rc, err);
  port->closePort();
  return model == 1060 ? 0 : 1;
}
EOF
g++ -O2 -o /tmp/reboot_waist /tmp/reboot_waist.cpp \
  -I/opt/dxl_ws/install/dynamixel_sdk/include \
  -L/opt/dxl_ws/install/dynamixel_sdk/lib -ldynamixel_sdk \
  -Wl,-rpath,/opt/dxl_ws/install/dynamixel_sdk/lib
/tmp/reboot_waist
EOS
}

start_driver() {
  if driver_running; then
    say "Driver is already running."
    return
  fi
  if ! "${COMPOSE[@]}" exec -T px100 bash -lc 'test -e /opt/dxl_ws/install/setup.bash && test -f /tmp/px100_slow.yaml'; then
    say "This container is missing /opt/dxl_ws or /tmp/px100_slow.yaml."
    say "Those are rebuilt with the steps in docs/runbook.md under 'If the container was recreated'."
    exit 1
  fi
  stop_launch
  say "Starting the driver. RViz opens on the desktop."
  launch_driver
  local status=0
  wait_for_driver || status=$?
  if [[ "$status" -eq 0 ]]; then
    say "Driver is up."
    return
  fi
  if [[ "$status" -eq 2 ]]; then
    stop_launch
    reboot_waist
    say "Starting the driver again."
    launch_driver
    status=0
    wait_for_driver || status=$?
    if [[ "$status" -eq 0 ]]; then
      say "Driver is up."
      return
    fi
  fi
  say "Driver could not find every motor. Log:"
  "${COMPOSE[@]}" exec -T px100 tail -n 40 /tmp/xsarm.log >&2
  exit 1
}

start_bridge
say "Starting the container."
"${COMPOSE[@]}" up -d

say "Waiting for /dev/ttyDXL."
wait_for_tty

enable_torque() {
  say "Turning torque on."
  "${COMPOSE[@]}" exec -T px100 bash -lc 'source /opt/ros/humble/setup.bash && source /root/interbotix_ws/install/setup.bash && ros2 service call /px100/torque_enable interbotix_xs_msgs/srv/TorqueEnable "{cmd_type: group, name: arm, enable: true}"'
}

start_driver
enable_torque
say ""
say "Desktop: http://127.0.0.1:6080"
say "Torque is on. Publish a pose from the container shell, for example:"
say '  ros2 topic pub --once /px100/commands/joint_group interbotix_xs_msgs/msg/JointGroupCommand "{name: arm, cmd: [0.0, -1.5, 1.4, 0.5]}"'
if [[ -t 0 && -t 1 ]]; then
  say "Opening a shell in the container."
  exec "${COMPOSE[@]}" exec px100 bash
fi
