# Run checks directly with the pinned development environment.
task := ""

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
    nix develop --command nix-unit --flake ".#libTests"
