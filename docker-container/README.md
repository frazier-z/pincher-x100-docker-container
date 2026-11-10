# PincherX-100 ROS 2 environment

Works on Windows, macOS (both Intel and Apple Silicon) and Linux.

An agent setting this up on a Mac should follow the project skill
`.cursor/skills/px100-mac-bootstrap/SKILL.md` (one folder above this README)
and `docs/runbook.md`.

## 1. Install Docker
- **Windows 10/11:** Docker Desktop (use the WSL 2 backend). For best speed, clone this
  folder inside your WSL home (e.g. `\\wsl$\Ubuntu\home\<you>`), not under `C:\`.
- **macOS:** Docker Desktop. In Settings -> Resources give it at least 8 GB of memory.
- **Linux:** Docker Engine + the Compose plugin.

## 2. Build and start (first build takes ~15–30 min)
From this folder, for the desktop without the real arm:
```
docker compose up -d --build
```
On a Mac, driving the real arm is `./scripts/up.sh` in the next section. The first
run builds this same image, then stops until two in-container files exist. See
`docs/runbook.md`.

## 3. Open the desktop
Go to **http://localhost:6080** in your browser and click *Connect*.
Open a terminal from the desktop and try:
```
ros2 launch interbotix_xsarm_descriptions xsarm_description.launch.py robot_model:=px100 use_joint_pub_gui:=true
```

Your code goes in the `me5250_ws` folder next to this README. It appears in the
container at `/root/me5250_ws` and stays on your computer.

## Everyday use
- Desktop only: `docker compose stop`, then `docker compose start`
- Terminal without the browser: `docker compose exec px100 bash`
- Real arm on a Mac: `./scripts/up.sh` to start, `./scripts/down.sh` to stop.
  Closing the container shell does not stop the arm.

## Connecting the real robot (U2D2 USB)
- **Linux:** uncomment the `devices:` lines in `docker-compose.yml`, then `docker compose up -d`.
- **Windows:** install usbipd-win, then in an admin PowerShell:
  `usbipd list`, `usbipd bind --busid <id>`, `usbipd attach --wsl --busid <id>`.
  Uncomment the `devices:` lines and restart the container.
- **macOS:** Docker cannot mount the USB device. `scripts/mac_u2d2_bridge.py` runs
  on the Mac, and the container presents that stream as `/dev/ttyDXL` (1 Mbaud).
  Plug in the arm and the U2D2, start Docker Desktop, then from this folder:
  ```
  ./scripts/up.sh
  ```
  That starts the bridge, the container, and the driver, turns torque on, and opens
  a shell in the container. Publish joint commands from that shell. RViz is on the
  desktop at http://localhost:6080. Stop with `./scripts/down.sh`.

  The first time, or after `docker compose down`, the container is missing the longer
  Dynamixel timeout (`/opt/dxl_ws`) and the 5 Hz motor config (`/tmp/px100_slow.yaml`).
  `up.sh` exits and names those files. Create them with the commands in
  `docs/runbook.md` under "If the container was recreated," then run `./scripts/up.sh`
  again. If more than one `/dev/cu.usbserial-*` device is present, pass the U2D2
  path: `./scripts/up.sh /dev/cu.usbserial-...`.
