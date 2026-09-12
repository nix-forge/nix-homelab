# User-provided secrets

This project ships no deployable credentials. The consuming system owns its
nix-seal administrator catalog, target identity, encrypted files and
provisioning. See [the nix-seal integration](../examples/nix-seal.nix) and
[setup guide](../docs/setup.md). Never place plaintext keys in a flake or the
Nix store. Runtime VM tests use public disposable fixture keys.
