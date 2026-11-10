#!/usr/bin/env python3
"""Turn the Mac U2D2 bridge into /dev/ttyDXL inside the container."""
import os
import pty
import select
import socket
import termios
import time
import tty

HOST = "host.docker.internal"
PORT = 8765
LINK = "/dev/ttyDXL"


def write_all(fd, data):
    view = memoryview(data)
    while view:
        n = os.write(fd, view)
        view = view[n:]


def serve(conn):
    master, slave = pty.openpty()
    tty.setraw(slave, termios.TCSANOW)
    os.set_blocking(master, False)
    slave_name = os.ttyname(slave)
    try:
        os.remove(LINK)
    except FileNotFoundError:
        pass
    os.symlink(slave_name, LINK)
    print(f"{LINK} -> {slave_name}", flush=True)
    try:
        while True:
            readable, _, _ = select.select([master, conn], [], [], 1.0)
            for ready in readable:
                if ready == master:
                    try:
                        data = os.read(master, 4096)
                    except BlockingIOError:
                        continue
                    if not data:
                        return
                    conn.sendall(data)
                else:
                    data = conn.recv(4096)
                    if not data:
                        return
                    write_all(master, data)
    finally:
        try:
            os.remove(LINK)
        except FileNotFoundError:
            pass
        os.close(master)
        os.close(slave)


def main():
    while True:
        try:
            conn = socket.create_connection((HOST, PORT), timeout=5)
        except OSError:
            time.sleep(1)
            continue
        conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        conn.setblocking(False)
        print(f"connected to {HOST}:{PORT}", flush=True)
        try:
            serve(conn)
        finally:
            conn.close()
            print("bridge closed, retrying", flush=True)


if __name__ == "__main__":
    main()
