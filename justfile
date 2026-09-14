default:
    @just --list

format:
    nix fmt

check:
    bash scripts/checks.sh evaluate
    nix develop --command prek run --all-files

lint:
    nix develop --command prek run --all-files

hooks:
    nix develop --command true

test:
    bash scripts/checks.sh build

vm:
    nix run .#nixosConfigurations.vm-test-vpn.config.system.build.vm
