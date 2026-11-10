# PincherX-100 on this Mac

This is the ROS 2 Humble setup for the PincherX-100 on the Apple M3 MacBook Air. The arm is the real robot, reached through the U2D2. Gazebo Classic is installed for simulation later. The desktop (RViz included) is a browser page on this machine.

The working directory is `docker-container`, next to this `docs` folder.

## What was built

The Mac is arm64. The usual `osrf/ros:humble-desktop` image is amd64 only, and it does not fit the disk. The image `px100-humble` starts from `ros:humble-ros-base`, which has an arm64 build, and installs the desktop pieces, MoveIt, and ros2_control on top.

Gazebo Classic’s ROS packages (`ros-humble-gazebo-ros-pkgs`, `ros-humble-gazebo-ros2-control`) are published for amd64 only. On this Mac, Gazebo 11 comes from `ppa:openrobotics/gazebo11-non-amd64`, and `gazebo_ros_pkgs` (branch `ros2`) plus `gazebo_ros2_control` (branch `humble`) are built from source into `/opt/gazebo_ws`. Interbotix Humble (`interbotix_ros_core`, `interbotix_ros_manipulators`, `interbotix_ros_toolboxes`) is built into `/root/interbotix_ws`. The Interbotix simulation package is `interbotix_xsarm_sim`.

Docker Desktop on macOS cannot pass a USB device into a container. Two scripts make up the substitute:

- `scripts/mac_u2d2_bridge.py` runs on the Mac. It opens `/dev/cu.usbserial-FT9BTII6` at 1 Mbaud and serves the raw bytes on `127.0.0.1:8765`.
- `scripts/container_ttydxl.py` runs inside the container, connects to `host.docker.internal:8765`, and exposes that stream as `/dev/ttyDXL`.

`docker-compose.mac.yml` is the overlay that starts the container side of that bridge and adds `host.docker.internal`. `ROS_DOMAIN_ID` is 42. The browser desktop is http://127.0.0.1:6080.

The Dynamixel SDK’s default USB latency (16 ms) times out before replies come back across this bridge, so the driver cannot see the motors. Inside the running container, DynamixelSDK `humble` is built at `/opt/dxl_ws` with `LATENCY_TIMER` set to 200 in the ROS copy of `port_handler_linux.cpp`. The driver is launched with that overlay sourced last, so it loads that library.

Joint reads and motor commands share one serial port. At the stock 100 Hz read rate, one five-motor read takes longer than the timer period, the next read starts immediately, and torque or position commands never get a turn. Two changes keep reads on without blocking commands:

- The motor config copy `/tmp/px100_slow.yaml` sets `update_rate` to 5.
- `patches/xs_sdk_bus_priority.patch` puts the joint-state timer on its own callback. A waiting command takes the serial port, and the next read waits until that command finishes. The patch is applied in the Dockerfile. It is also already compiled into the container that is running now. The image on disk does not include it until the next `docker compose build`.

With that driver up, torque returns in about two seconds while joint states are still publishing. Shoulder, elbow, and wrist follow `JointGroupCommand`. The waist has been reporting a position near -0.33 radians and has not turned to the commanded angle. A large waist swing also left a latched hardware error once; rebooting that servo cleared it. Recovery is at the bottom.

## What survives overnight

`docker compose stop` and `docker compose start` keep the same container. These stay:

- `/opt/dxl_ws` (the longer Dynamixel timeout)
- the rebuilt `interbotix_xs_sdk` (the command-priority patch)
- `/tmp/px100_slow.yaml`

`docker compose down`, `docker rm`, or `up --build` creates a new container and deletes all three. The image rebuild also takes a long time and the disk on this Mac is tight. Do that only when you mean to.

The driver does not start with the container. After every start you launch it yourself. The Mac bridge is a normal process, not part of Compose, so a reboot of the Mac stops it.

## Tomorrow, if this container is still the one named `px100`

Plug in the U2D2 and the arm power supply. From `docker-container`:

```bash
./scripts/up.sh
```

That starts the Mac bridge in the background, starts the container, and launches the driver. It does not start a second bridge or a second driver if one is already running. If more than one `cu.usbserial-*` device is present, pass the U2D2 path: `./scripts/up.sh /dev/cu.usbserial-FT9BTII6`. This adapter is `/dev/cu.usbserial-FT9BTII6`.

The script turns torque on, then opens a shell inside the container. Open http://127.0.0.1:6080 and click Connect. RViz is on that desktop.

From that shell, publish a pose. The four numbers are waist, shoulder, elbow, and wrist, in radians.

```bash
ros2 topic pub --once /px100/commands/joint_group interbotix_xs_msgs/msg/JointGroupCommand "{name: arm, cmd: [0.0, -1.5, 1.4, 0.5]}"
ros2 topic echo --once /px100/joint_states
```

Poses that have actually been sent:

| Command                    | What it does                                                                           |
| -------------------------- | -------------------------------------------------------------------------------------- |
| `[0.0, 0.0, 0.0, 0.0]`     | Home. A large swing from a tucked pose. This is the move that latched the waist error. |
| `[0.0, -1.5, 1.4, 0.5]`    | Short lift from the tucked pose.                                                       |
| `[0.6, -1.15, 1.05, 0.15]` | Higher, elbow more open.                                                               |
| `[0.0, -1.75, 1.5, 0.8]`   | Lower, near the sleep pose. Sleep in the config is `[0, -1.88, 1.5, 0.8]`.             |

Do not launch `xsarm_control` a second time while the first driver is still running. Both would open `/dev/ttyDXL`.

## If the container was recreated

`docker compose down` or deleting the `px100` container drops three things `up.sh` expects:

- `/opt/dxl_ws`, the Dynamixel library with `LATENCY_TIMER` 200
- `/tmp/px100_slow.yaml`, the motor config with `update_rate: 5`
- the compiled command-priority patch, unless the image was built after that patch was added to the Dockerfile

Plug in the arm, start Docker Desktop, and from `docker-container` run `./scripts/up.sh` once. It starts the bridge and a new container, then stops because those files are missing.

The longer serial timeout. This needs a network connection for the clone:

```bash
docker compose -f docker-compose.yml -f docker-compose.mac.yml exec px100 bash -lc 'git clone -b humble https://github.com/ROBOTIS-GIT/DynamixelSDK.git c/src/DynamixelSDK && sed -i "s/#define LATENCY_TIMER.*/#define LATENCY_TIMER  200/" /opt/dxl_ws/src/DynamixelSDK/ros/dynamixel_sdk/src/dynamixel_sdk/port_handler_linux.cpp /opt/dxl_ws/src/DynamixelSDK/c++/src/dynamixel_sdk/port_handler_linux.cpp && source /opt/ros/humble/setup.bash && cd /opt/dxl_ws && colcon build --packages-select dynamixel_sdk'
```

The 5 Hz motor config:

```bash
docker compose -f docker-compose.yml -f docker-compose.mac.yml exec px100 bash -lc 'cp /root/interbotix_ws/install/interbotix_xsarm_control/share/interbotix_xsarm_control/config/px100.yaml /tmp/px100_slow.yaml && sed -i "s/update_rate: 100/update_rate: 5/" /tmp/px100_slow.yaml'
```

The command patch. Skip this if `grep` prints a line. A full image rebuild, below, already includes it.

```bash
docker compose -f docker-compose.yml -f docker-compose.mac.yml exec px100 bash -lc 'grep -n bus_waiters_ /root/interbotix_ws/src/interbotix_ros_core/interbotix_ros_xseries/interbotix_xs_sdk/src/xs_sdk_obj.cpp | head'
```

If that prints nothing:

```bash
docker cp patches/xs_sdk_bus_priority.patch px100:/tmp/xs_sdk_bus_priority.patch
docker compose -f docker-compose.yml -f docker-compose.mac.yml exec px100 bash -lc 'git -C /root/interbotix_ws/src/interbotix_ros_core apply /tmp/xs_sdk_bus_priority.patch && source /opt/ros/humble/setup.bash && source /root/interbotix_ws/install/setup.bash && cd /root/interbotix_ws && colcon build --symlink-install --packages-select interbotix_xs_sdk'
```

Then run `./scripts/up.sh` again.

A full `docker compose -f docker-compose.yml -f docker-compose.mac.yml up -d --build` compiles Gazebo and Interbotix again. Expect 15–30 minutes, and check free disk first. After that build the command patch is in the image, and only the two commands above (Dynamixel timeout and `/tmp/px100_slow.yaml`) are still required before `./scripts/up.sh`.

## Stopping

From `docker-container`:

```bash
./scripts/down.sh
```

That stops the container and then the Mac bridge. The container stays on disk, so the Dynamixel timeout and the 5 Hz motor config are still there for the next `./scripts/up.sh`. `docker compose down` removes the container and throws those away.

## When the waist reports a hardware error

`scripts/up.sh` handles this. If the driver log says `Hardware error occurred` for the waist, the script reboots that servo, launches the driver once more, and turns torque back on.

The manual version, with the driver stopped and the bridge still running:

```bash
docker compose exec px100 bash -lc 'source /opt/dxl_ws/install/setup.bash && cat > /tmp/reboot_waist.cpp << "EOF"
#include <cstdio>
#include <cstdint>
#include <unistd.h>
#include "dynamixel_sdk/dynamixel_sdk.h"
int main() {
  dynamixel::PortHandler * port = dynamixel::PortHandler::getPortHandler("/dev/ttyDXL");
  dynamixel::PacketHandler * pkt = dynamixel::PacketHandler::getPacketHandler(2.0);
  if (!port->openPort() || !port->setBaudRate(1000000)) return 1;
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
g++ -O2 -o /tmp/reboot_waist /tmp/reboot_waist.cpp -I/opt/dxl_ws/install/dynamixel_sdk/include -L/opt/dxl_ws/install/dynamixel_sdk/lib -ldynamixel_sdk -Wl,-rpath,/opt/dxl_ws/install/dynamixel_sdk/lib && /tmp/reboot_waist'
```

`ping model=1060` is the XL430-W250. Then launch the driver again. Torque is off after a reboot until the torque service is called.

## Layout

| Piece                   | Where                                                |
| ----------------------- | ---------------------------------------------------- |
| Compose project         | `docker-container`                                 |
| Image / container       | `px100-humble` / `px100`                             |
| Bring-up                | `scripts/up.sh` (bridge, container, driver, torque)  |
| Shutdown                | `scripts/down.sh` (container, then bridge)           |
| Mac serial bridge       | `scripts/mac_u2d2_bridge.py`, port 8765              |
| Container serial end    | `/dev/ttyDXL`                                        |
| Desktop                 | http://127.0.0.1:6080, display `:1`                  |
| Driver launch           | `interbotix_xsarm_control` `xsarm_control.launch.py` |
| Motor config in use     | `/tmp/px100_slow.yaml` (`update_rate: 5`)            |
| Dynamixel overlay       | `/opt/dxl_ws`, `LATENCY_TIMER` 200                   |
| Command-priority patch  | `patches/xs_sdk_bus_priority.patch`                  |
| Course code on the host | `me5250_ws`, mounted at `/root/me5250_ws`            |
