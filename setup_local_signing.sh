#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SIGNING="$ROOT/Signing"
KEYCHAIN="$SIGNING/Signing.keychain"
PASSWORD_FILE="$SIGNING/keychain_password"

if [[ -f "$KEYCHAIN" || -f "$KEYCHAIN-db" ]]; then
    exit 0
fi

PASSWORD="$(openssl rand -hex 32)"
printf '%s' "$PASSWORD" > "$PASSWORD_FILE"
chmod 600 "$PASSWORD_FILE"

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$SIGNING/private_key.pem" \
    -out "$SIGNING/certificate.pem" \
    -config "$SIGNING/codesign.cnf" >/dev/null 2>&1
openssl pkcs12 -export \
    -name "MusicTrackRecorder Local Signing" \
    -out "$SIGNING/signing.p12" \
    -inkey "$SIGNING/private_key.pem" \
    -in "$SIGNING/certificate.pem" \
    -passout "pass:$PASSWORD" >/dev/null 2>&1

security create-keychain -p "$PASSWORD" "$KEYCHAIN"
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
security import "$SIGNING/signing.p12" \
    -k "$KEYCHAIN" \
    -P "$PASSWORD" \
    -A
security add-trusted-cert -k "$KEYCHAIN" "$SIGNING/certificate.pem"
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null

rm -f "$SIGNING/private_key.pem" "$SIGNING/signing.p12"
security find-identity -v -p codesigning "$KEYCHAIN"
