# shellcheck shell=bash
set -eu
umask 077
mkdir -p /run/wg-test
printf '%s\n' 'qE43SrN52JGV9FYU5i7jp5zCq+8osxyXORZfS5faf3s=' >/run/wg-test/client.key
printf '%s\n' 'wOXXEHK/pVYgJSj/mU05R2kCz+bhawfV0TttYud+zk8=' >/run/wg-test/peer.key
ip link add wg-test-peer type wireguard
ip address add 10.71.216.232/32 dev wg-test-peer
ip address add 10.71.216.233/32 dev wg-test-peer
wg set wg-test-peer private-key /run/wg-test/peer.key listen-port 51821 \
  peer "$(wg pubkey </run/wg-test/client.key)" allowed-ips 10.71.216.231/32
ip link set wg-test-peer up
ip route add 10.71.216.231/32 dev wg-test-peer
