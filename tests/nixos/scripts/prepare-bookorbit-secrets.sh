# shellcheck shell=bash
set -eu
install -d -m 0700 /run/bookorbit-fixture
printf '%s' 'public-native-fixture-jwt-signing-key-0123456789' >/run/bookorbit-fixture/jwt-secret
printf '%s' 'public-native-fixture-setup-token-0123456789' >/run/bookorbit-fixture/setup-token
printf '%s' '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' >/run/bookorbit-fixture/request-key
printf '%s' 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789' >/run/bookorbit-fixture/podcast-key
printf '%s' 'fixture-admin' >/run/bookorbit-fixture/admin-username
printf '%s' 'fixture@example.invalid' >/run/bookorbit-fixture/admin-email
printf '%s' 'PublicFixturePassword123!' >/run/bookorbit-fixture/admin-password
printf '%s' 'public-unused-prowlarr-key' >/run/bookorbit-fixture/prowlarr-api-key
printf '%s' 'public-unused-proxy-password' >/run/bookorbit-fixture/proxy-password
chmod 0400 /run/bookorbit-fixture/*
