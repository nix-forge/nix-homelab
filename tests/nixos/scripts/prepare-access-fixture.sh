# shellcheck shell=bash
mkdir -p /run/access-fixture
@pkgs_openssl@/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -keyout /run/access-fixture/key -out /run/access-fixture/certificate \
  -subj '/CN=auth.homelab.home.arpa' -addext 'subjectAltName=DNS:auth.homelab.home.arpa,DNS:dashboard.homelab.home.arpa' >/dev/null 2>&1
for name in jwt session storage; do printf '%s' disposable-fixture-secret-with-at-least-32-bytes >/run/access-fixture/"$name"; done
@pkgs_python3_withPackages_ps_ps_argon2_cffi@/bin/python3 @pythonCheck1@
