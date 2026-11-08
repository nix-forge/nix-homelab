"""Run isolated VM socket probes with parameters supplied by the test driver."""

from __future__ import annotations

import argparse
import errno
import json
import socket
import sys
import time


def send_leak_probes(label: str, destinations: str) -> None:
    payload = f"vpn-leak-{label}".encode()
    for address, port in json.loads(destinations):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            try:
                sock.sendto(payload, (address, port))
            except OSError as error:
                if error.errno not in {errno.EPERM, errno.EACCES}:
                    raise


def send_udp(address: str, port: int, payload: str) -> None:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.sendto(payload.encode(), (address, port))


def bind_tcp(address: str, port: int) -> None:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind((address, port))


def connect_unix(path: str, timeout: float | None) -> None:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(timeout)
        sock.connect(path)


def receive_udp_ack(sock: socket.socket, payload: bytes) -> bool:
    sock.settimeout(0.2)
    sock.send(payload)
    deadline = time.monotonic() + 0.2
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return False
        # Receiving blocks. Preserve the total response deadline when discarding
        # a delayed response to an older sequence number.
        sock.settimeout(remaining)
        if sock.recv(4096) == payload:
            return True


def maintain_udp_flow(address: str, port: int) -> None:
    # Keep this one connected socket and its source port across route changes.
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.connect((address, port))
        sequence = 0
        while True:
            sequence += 1
            payload = str(sequence).encode()
            try:
                received = receive_udp_ack(sock, payload)
            except OSError:
                # Provider/route failures are the condition under test. Continue
                # sending from the established flow so recovery can be observed.
                received = False
            if received:
                sys.stdout.write(f"{sequence}\n")
                sys.stdout.flush()
            time.sleep(0.1)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    leak = commands.add_parser("udp-leaks")
    leak.add_argument("label")
    leak.add_argument("destinations", help="JSON array of [IPv4 address, port]")
    for command in ("udp-send", "tcp-bind", "udp-flow"):
        probe = commands.add_parser(command)
        probe.add_argument("address")
        probe.add_argument("port", type=int)
        if command == "udp-send":
            probe.add_argument("payload")
    unix = commands.add_parser("unix-connect")
    unix.add_argument("path")
    unix.add_argument("--timeout", type=float, default=None)
    args = parser.parse_args()
    if args.command == "udp-leaks":
        send_leak_probes(args.label, args.destinations)
    elif args.command == "udp-send":
        send_udp(args.address, args.port, args.payload)
    elif args.command == "tcp-bind":
        bind_tcp(args.address, args.port)
    elif args.command == "unix-connect":
        connect_unix(args.path, args.timeout)
    elif args.command == "udp-flow":
        maintain_udp_flow(args.address, args.port)


if __name__ == "__main__":
    main()
