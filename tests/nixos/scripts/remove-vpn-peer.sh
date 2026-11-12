# shellcheck shell=bash
@pkgs_iproute2@/bin/ip link del wg-test-peer 2>/dev/null || true
