---
name: px100-mac-bootstrap
description: >-
  Bootstrap the PincherX-100 ROS 2 Humble Docker environment on a Mac and
  drive the real arm through the U2D2. Use when setting up, rebuilding, or
  starting this px100 stack, when Docker Desktop and python3 are already
  installed, or when the user mentions up.sh, down.sh, the Mac USB bridge,
  /dev/ttyDXL, or Docker - MultiArch.
---

# PincherX-100 Mac bootstrap

Work from `Docker - MultiArch`. ROS 2 is Humble. The real arm is driven by `./scripts/up.sh`, not by a plain `docker compose up`.

Read `Docker - MultiArch/docs/runbook.md` before changing launch steps. Read `Docker - MultiArch/README.md` for the short path. Do not rewrite `scripts/up.sh`, `scripts/down.sh`, or the driver command path. Those already work.

## Which start

- Desktop only, no arm: `docker compose up -d --build`, then http://localhost:6080.
- Real arm on macOS: plug in the U2D2 and the arm power, wait until Docker Desktop is running, then `./scripts/up.sh`.
- Stop the real arm with `./scripts/down.sh`. That keeps the container. `docker compose down` deletes it and drops `/opt/dxl_ws` and `/tmp/px100_slow.yaml`.

`up.sh` starts the Mac serial bridge, the container, and the driver, turns torque on, and opens a container shell when the terminal is interactive. Publish poses from that shell. Do not start a second `mac_u2d2_bridge.py` or a second `xsarm_control` launch.

If more than one `/dev/cu.usbserial-*` device exists, pass that path: `./scripts/up.sh /dev/cu.usbserial-...`.

## First build or a new container

The first `./scripts/up.sh` builds the image (about 15–30 minutes on Apple Silicon) and then exits if these are missing:

- `/opt/dxl_ws` with `LATENCY_TIMER` 200 in both `port_handler_linux.cpp` copies
- `/tmp/px100_slow.yaml` copied from the px100 motor config with `update_rate: 5`

Create them with the commands in the runbook section "If the container was recreated", then run `./scripts/up.sh` again. Source `/opt/dxl_ws/install/setup.bash` last whenever launching the driver by hand. The stock SDK timeout misses replies over the Mac bridge.

A image built from the current Dockerfile already contains `patches/xs_sdk_bus_priority.patch`. Confirm with the runbook `bus_waiters_` grep. Apply and rebuild `interbotix_xs_sdk` only when that grep prints nothing.

## Leave alone

Do not change how joint commands are accepted or rejected. Do not change the waist reboot inside `scripts/up.sh`.
