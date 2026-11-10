# syntax=docker/dockerfile:1
# ROS 2 Humble + Interbotix X-Series arm packages (PincherX-100)
# The GUI (RViz, Gazebo, terminals) runs in a desktop you open in your web browser,
# so no X server / XQuartz / WSLg setup is needed: http://localhost:6080
#
# ros:humble-ros-base is an official multi-arch image (amd64 + arm64), so Apple Silicon
# Macs build and run natively instead of under slow x86 emulation.
# The Gazebo Classic ROS wrappers (gazebo_ros_pkgs, gazebo_ros2_control) are published
# for amd64 only. On arm64, Gazebo 11 comes from the Open Robotics PPA and those
# wrappers are built from the Humble source repos.
FROM ros:humble-ros-base

ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-c"]

# ROS desktop (RViz etc.), MoveIt, ros2_control, plus a lightweight XFCE desktop
# served over noVNC so the GUI works from any host OS.
RUN apt-get update && apt-get install -y --no-install-recommends \
      git nano python3-pip python3-colcon-common-extensions python3-rosdep \
      ros-humble-desktop \
      ros-humble-moveit \
      ros-humble-ros2-control ros-humble-ros2-controllers \
      ros-humble-joint-state-publisher-gui \
      xfce4 xfce4-terminal dbus-x11 \
      tigervnc-standalone-server novnc websockify \
      mesa-utils libgl1-mesa-dri \
    && if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
         apt-get install -y --no-install-recommends \
           ros-humble-gazebo-ros-pkgs ros-humble-gazebo-ros2-control ; \
       fi \
    && ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html \
    && rm -rf /var/lib/apt/lists/*

# arm64 has no ros-humble-gazebo-ros-pkgs / ros-humble-gazebo-ros2-control debs.
# This MacBook Air is arm64 with a Docker VM of about 8 GB, so the compile is capped at 2 jobs.
RUN if [ "$(dpkg --print-architecture)" = "arm64" ]; then \
      apt-get update && \
      apt-get install -y --no-install-recommends software-properties-common gnupg && \
      add-apt-repository -y ppa:openrobotics/gazebo11-non-amd64 && \
      apt-get update && \
      apt-get install -y gazebo libgazebo-dev && \
      mkdir -p /opt/gazebo_ws/src && \
      git clone --depth 1 -b ros2 https://github.com/ros-simulation/gazebo_ros_pkgs.git /opt/gazebo_ws/src/gazebo_ros_pkgs && \
      git clone --depth 1 -b humble https://github.com/ros-simulation/gazebo_ros2_control.git /opt/gazebo_ws/src/gazebo_ros2_control && \
      touch /opt/gazebo_ws/src/gazebo_ros2_control/gazebo_ros2_control_demos/COLCON_IGNORE && \
      rosdep update --rosdistro "$ROS_DISTRO" && \
      rosdep install --from-paths /opt/gazebo_ws/src --ignore-src -y --rosdistro "$ROS_DISTRO" && \
      source /opt/ros/humble/setup.bash && \
      cd /opt/gazebo_ws && \
      CMAKE_BUILD_PARALLEL_LEVEL=2 MAKEFLAGS="-j2" \
        colcon build --parallel-workers 1 --cmake-args -DCMAKE_BUILD_TYPE=Release && \
      rm -rf build log src && \
      rm -rf /var/lib/apt/lists/* ; \
    fi

# Python helpers used by the Interbotix Python API (modern_robotics is handy for this course too)
RUN pip3 install --no-cache-dir modern_robotics transforms3d \
    || pip3 install --no-cache-dir --break-system-packages modern_robotics transforms3d

# Interbotix source code (humble branches)
WORKDIR /root/interbotix_ws/src
RUN git clone -b humble https://github.com/Interbotix/interbotix_ros_core.git && \
    git clone -b humble https://github.com/Interbotix/interbotix_ros_manipulators.git && \
    git clone -b humble https://github.com/Interbotix/interbotix_ros_toolboxes.git && \
    cd interbotix_ros_core && git submodule update --init --recursive

# Interbotix ships some folders (including the X-Series driver and messages) with
# COLCON_IGNORE files that their install script normally deletes. Remove them all,
# then re-ignore any leftover ROS 1 (catkin) packages, and skip camera/perception
# and Raspberry Pi packages (not needed for PX100 basics).
RUN find . -name COLCON_IGNORE -delete && \
    for pxml in $(grep -rlE --include=package.xml '<buildtool_depend>\s*catkin' .); do \
      d="$(dirname "$pxml")"; echo "Ignoring ROS 1 package: $d"; touch "$d/COLCON_IGNORE"; \
    done && \
    find . -maxdepth 4 -type d \( -name '*perception*' -o -name '*rpi*' -o -name '*landmark*' \) \
      -exec touch {}/COLCON_IGNORE \; && \
    echo "Core packages found:" && \
    colcon list --names-only | grep -E 'interbotix_xs_msgs|interbotix_xs_sdk'

# Joint-state reads and motor commands share one serial port. This patch puts
# the read timer on its own callback and lets a waiting command take the port
# before the next read, so torque and position goals are not stuck behind it.
COPY patches/xs_sdk_bus_priority.patch /tmp/xs_sdk_bus_priority.patch
RUN git -C /root/interbotix_ws/src/interbotix_ros_core apply /tmp/xs_sdk_bus_priority.patch

# Dependencies + build. On arm64 the Gazebo wrappers are already in /opt/gazebo_ws,
# and apt has no packages for them.
WORKDIR /root/interbotix_ws
RUN apt-get update && rosdep update && \
    if [ "$(dpkg --print-architecture)" = "arm64" ]; then \
      rosdep install --from-paths src --ignore-src -r -y \
        --skip-keys gazebo \
        --skip-keys gazebo_dev \
        --skip-keys gazebo_msgs \
        --skip-keys gazebo_plugins \
        --skip-keys gazebo_ros \
        --skip-keys gazebo_ros_pkgs \
        --skip-keys gazebo_ros2_control ; \
    else \
      rosdep install --from-paths src --ignore-src -r -y ; \
    fi && \
    rm -rf /var/lib/apt/lists/*
# Build the message packages first (some Interbotix packages don't declare
# this dependency, so colcon may otherwise build them in the wrong order)
RUN source /opt/ros/humble/setup.bash && \
    if [ -f /opt/gazebo_ws/install/setup.bash ]; then source /opt/gazebo_ws/install/setup.bash ; fi && \
    if [ "$(dpkg --print-architecture)" = "arm64" ]; then \
      export CMAKE_BUILD_PARALLEL_LEVEL=2 MAKEFLAGS="-j2" ; \
      WORKERS=1 ; \
    else \
      WORKERS="$(nproc)" ; \
    fi && \
    colcon build --symlink-install --parallel-workers "$WORKERS" --packages-up-to interbotix_xs_msgs && \
    source install/setup.bash && \
    colcon build --symlink-install --parallel-workers "$WORKERS"

# Source everything automatically in every shell
RUN echo "source /opt/ros/humble/setup.bash" >> /root/.bashrc && \
    echo "[ -f /opt/gazebo_ws/install/setup.bash ] && source /opt/gazebo_ws/install/setup.bash" >> /root/.bashrc && \
    echo "source /root/interbotix_ws/install/setup.bash" >> /root/.bashrc && \
    echo "[ -f /root/me5250_ws/install/setup.bash ] && source /root/me5250_ws/install/setup.bash" >> /root/.bashrc && \
    echo "export ROS_DOMAIN_ID=\${ROS_DOMAIN_ID:-42}" >> /root/.bashrc

# Software OpenGL: works identically on every host (no GPU passthrough on Mac/Windows)
ENV LIBGL_ALWAYS_SOFTWARE=1 \
    DISPLAY=:1 \
    VNC_RESOLUTION=1600x900

# Start script: virtual display -> XFCE desktop -> noVNC on port 6080
COPY <<'EOF' /usr/local/bin/start-desktop.sh
#!/bin/bash
set -e
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
Xtigervnc :1 -geometry "${VNC_RESOLUTION}" -depth 24 \
  -SecurityTypes None -localhost yes -AlwaysShared &
sleep 2
dbus-launch --exit-with-session startxfce4 >/tmp/xfce.log 2>&1 &
echo "=============================================="
echo " Desktop ready: open http://localhost:6080"
echo "=============================================="
exec websockify --web /usr/share/novnc 6080 localhost:5901
EOF
# Strip Windows line endings in case the Dockerfile was saved with CRLF
RUN sed -i 's/\r$//' /usr/local/bin/start-desktop.sh && chmod +x /usr/local/bin/start-desktop.sh

WORKDIR /root/me5250_ws
EXPOSE 6080
CMD ["/usr/local/bin/start-desktop.sh"]
