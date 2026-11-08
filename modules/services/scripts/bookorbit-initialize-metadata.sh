# shellcheck shell=bash
# BookOrbit 3.2.0 enables four providers when no provider row exists.
# Seed only the initial policy; later admin choices remain authoritative.
# The native service follows migration completion before initializing policy.
cat @metadataSql@ | @metadataPsqlInput@
touch /run/bookorbit-metadata/ready
