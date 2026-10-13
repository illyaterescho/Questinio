#!/bin/zsh
set -eu

# One local signing identity keeps Questionio's designated requirement stable
# across development builds. The private key stays in a user-only keychain,
# outside the project and its backups or source-control copies.
SIGNING_DIR="$HOME/Library/Application Support/Questionio/Signing"
KEYCHAIN="$SIGNING_DIR/Questionio.keychain-db"
PASSWORD_FILE="$SIGNING_DIR/keychain-password"
if [[ -f "$KEYCHAIN" && -f "$PASSWORD_FILE" ]]; then
    if security find-identity -p codesigning "$KEYCHAIN" | grep -Eq '^[[:space:]]*[0-9]+\) [0-9A-Fa-f]{40} '; then
        echo "Questionio local signing identity already exists."
        exit 0
    fi
fi
if [[ -e "$KEYCHAIN" && ! -f "$PASSWORD_FILE" ]] || [[ -e "$PASSWORD_FILE" && ! -f "$KEYCHAIN" ]]; then
    echo "Incomplete Questionio signing setup; inspect $SIGNING_DIR before retrying." >&2
    exit 1
fi

umask 077
mkdir -p "$SIGNING_DIR"
chmod 700 "$SIGNING_DIR"
TEMP_CERT_DIR="$(mktemp -d /private/tmp/questionio-signing.XXXXXX)"
trap 'rm -f "$TEMP_CERT_DIR/key.pem" "$TEMP_CERT_DIR/cert.pem" "$TEMP_CERT_DIR/identity.p12"; rmdir "$TEMP_CERT_DIR"' EXIT
if [[ ! -f "$PASSWORD_FILE" ]]; then /opt/homebrew/bin/openssl rand -hex 32 > "$PASSWORD_FILE"; fi
chmod 600 "$PASSWORD_FILE"
KEYCHAIN_PASSWORD="$(cat "$PASSWORD_FILE")"
/opt/homebrew/bin/openssl req -x509 -newkey rsa:3072 -nodes -days 3650 \
    -subj '/CN=Questionio Local Signing/O=Questionio' \
    -addext 'basicConstraints=critical,CA:FALSE' \
    -addext 'keyUsage=critical,digitalSignature' \
    -addext 'extendedKeyUsage=codeSigning' \
    -keyout "$TEMP_CERT_DIR/key.pem" -out "$TEMP_CERT_DIR/cert.pem" >/dev/null 2>&1
/opt/homebrew/bin/openssl pkcs12 -export -legacy \
    -inkey "$TEMP_CERT_DIR/key.pem" -in "$TEMP_CERT_DIR/cert.pem" \
    -out "$TEMP_CERT_DIR/identity.p12" -passout "pass:$KEYCHAIN_PASSWORD" >/dev/null 2>&1
if [[ ! -f "$KEYCHAIN" ]]; then security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"; fi
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$TEMP_CERT_DIR/identity.p12" -k "$KEYCHAIN" -P "$KEYCHAIN_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
chmod 600 "$KEYCHAIN" "$PASSWORD_FILE"
security find-identity -p codesigning "$KEYCHAIN"
