#!/usr/bin/env python3
"""Open the U2D2 on macOS and serve its bytes on 127.0.0.1:8765.

Docker Desktop cannot pass USB into a container. The container connects to this
process and exposes the stream as /dev/ttyDXL. The arm talks at 1 Mbaud.
"""
import fcntl
import glob
import os
import select
import socket
import struct
import subprocess
import sys
import termios
import tty

# _IOW('T', 2, speed_t) with a 4-byte speed, as used by pyserial on Darwin
IOSSIOSPEED = 0x80045402
# _IOW('T', 0, unsigned long) receive latency in microseconds
IOSSDATALAT = 0x80085400
BAUD = 1000000
LISTEN = ("127.0.0.1", 8765)


def serial_device(argv):
    if len(argv) > 1:
        return argv[1]
    found = sorted(glob.glob("/dev/cu.usbserial-*"))
    if len(found) == 1:
        return found[0]
    if not found:
        sys.exit("No /dev/cu.usbserial-* device. Plug in the U2D2, or pass the path.")
    sys.exit("More than one U2D2-style device:\n  " + "\n  ".join(found) + "\nPass the path to use.")


def already_open(path):
    listed = subprocess.run(["lsof", "-t", path], capture_output=True, text=True)
    pids = []
    for line in listed.stdout.split():
        try:
            pid = int(line)
        except ValueError:
            continue
        if pid != os.getpid():
            pids.append(pid)
    return pids


def open_serial(path):
    holders = already_open(path)
    if holders:
        sys.exit(
            f"{path} is already open by pid {', '.join(str(pid) for pid in holders)}.\n"
            "That bridge is the one to keep. Do not start a second copy."
        )
    fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        sys.exit(f"{path} is already open. Do not start a second copy.")
    tty.setraw(fd, termios.TCSANOW)
    fcntl.ioctl(fd, IOSSIOSPEED, struct.pack("I", BAUD))
    for request, packed in (
        (IOSSDATALAT, struct.pack("Q", 1000)),
        (0x80045400, struct.pack("I", 1000)),
    ):
        try:
            fcntl.ioctl(fd, request, packed)
            print(f"USB latency set to 1 ms with ioctl {request:#x}", flush=True)
            break
        except OSError as exc:
            print(f"latency ioctl {request:#x} failed: {exc}", flush=True)
    return fd


def write_all(fd, data):
    view = memoryview(data)
    while view:
        n = os.write(fd, view)
        view = view[n:]


def relay(serial_fd, conn):
    conn.setblocking(False)
    while True:
        readable, _, _ = select.select([serial_fd, conn], [], [], 1.0)
        for ready in readable:
            if ready == serial_fd:
                try:
                    data = os.read(serial_fd, 4096)
                except BlockingIOError:
                    continue
                if not data:
                    return
                conn.sendall(data)
            else:
                data = conn.recv(4096)
                if not data:
                    return
                write_all(serial_fd, data)


def main():
    path = serial_device(sys.argv)
    serial_fd = open_serial(path)
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(LISTEN)
    server.listen(1)
    print(f"U2D2 {path} at {BAUD} baud, waiting on {LISTEN[0]}:{LISTEN[1]}", flush=True)
    while True:
        conn, addr = server.accept()
        conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        print(f"container connected from {addr[0]}:{addr[1]}", flush=True)
        try:
            relay(serial_fd, conn)
        finally:
            conn.close()
            print("container disconnected", flush=True)


if __name__ == "__main__":
    main()
