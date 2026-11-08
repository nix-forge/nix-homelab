# shellcheck shell=bash
@lib_optionalString_cfg_native_export_PATH_run_wrappers_bin_P@
# BookOrbit 3.2.0 enables four providers when no provider row exists.
# Seed only the initial policy; later admin choices remain authoritative.
# Native startup follows migration completion. Container migrations publish
# committed DDL notifications, installed before the application starts.
@waitForSchema@
cat @metadataSql@ | @metadataPsqlInput@
touch /run/bookorbit-metadata/ready
