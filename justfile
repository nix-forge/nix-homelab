# Use the host-provided workload runner when available.
task := if os() == "linux" { `if command -v workstation-task >/dev/null 2>&1; then printf workstation-task; fi` } else { "" }

default:
    @just --list

format:
    {{ task }} nix fmt

check:
    {{ task }} bash scripts/checks.sh evaluate
    {{ task }} nix develop --command prek run --all-files

lint:
    {{ task }} nix develop --command prek run --all-files

hooks:
    {{ task }} nix develop --command true

test:
    {{ task }} bash scripts/checks.sh build

vm:
    {{ task }} nix run .#nixosConfigurations.vm-test-vpn.config.system.build.vm
