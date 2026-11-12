"""Validate generated artifacts in an isolated build or VM fixture."""

import socket

with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
    sock.bind(("10.71.216.232", 19000))
    while True:
        data, peer = sock.recvfrom(4096)
        sock.sendto(data, peer)
