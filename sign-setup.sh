#!/bin/bash
# Crée une fois pour toutes un certificat de signature local, auto-signé, dans le trousseau de session.
# build-app.sh signe ensuite l'app avec lui : l'accès complet au disque survit aux recompilations.
# Sans compte développeur Apple. macOS demande le mot de passe de session pour approuver le certificat.
set -eu

NAME="core-eraser local signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Certificate '$NAME' already in the login keychain."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)"

# LibreSSL de macOS : format PKCS#12 lisible par « security import »
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -subj "/CN=$NAME" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/identity.p12" -passout "pass:$PASS" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1

security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo "Certificate '$NAME' created. Rebuild with ./build-app.sh, then grant Full Disk Access once more."
