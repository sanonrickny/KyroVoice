#!/bin/bash
# setup_deps.sh — one-time setup: creates a persistent code-signing identity
# so macOS TCC permissions (Accessibility, Input Monitoring) survive rebuilds.
set -euo pipefail

CERT_NAME="KyroVoice Dev"
KC_NAME="kyro-build"
KC_PATH="$HOME/Library/Keychains/$KC_NAME.keychain-db"
KC_PASS="kyro-build-pass"

# Already set up?
if [ -f "$KC_PATH" ]; then
    security unlock-keychain -p "$KC_PASS" "$KC_PATH" 2>/dev/null || true
    if security find-identity -v -p codesigning "$KC_PATH" 2>/dev/null | grep -q "$CERT_NAME"; then
        echo "Already set up — certificate is valid. Run ./run.sh."
        exit 0
    fi
fi

echo "==> Creating keychain: $KC_NAME"
security create-keychain -p "$KC_PASS" "$KC_PATH" 2>/dev/null || true
security unlock-keychain -p "$KC_PASS" "$KC_PATH"
security set-keychain-settings -lut 21600 "$KC_PATH" 2>/dev/null || true

# Keep existing keychains in the search list
EXISTING=$(security list-keychains -d user 2>/dev/null | tr -d '"' | tr '\n' ' ')
security list-keychains -d user -s "$KC_PATH" $EXISTING 2>/dev/null || true

TMPDIR_CERT=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR_CERT"; }
trap cleanup EXIT

KEY="$TMPDIR_CERT/key.pem"
CERT="$TMPDIR_CERT/cert.pem"
P12="$TMPDIR_CERT/identity.p12"
CONF="$TMPDIR_CERT/cert.conf"

echo "==> Generating code-signing certificate (valid 10 years)…"

# Certificate config with Code Signing EKU — this is what the manual
# Keychain Access flow often gets wrong.
cat > "$CONF" << 'EOF'
[req]
default_bits       = 2048
prompt             = no
default_md         = sha256
distinguished_name = dn
x509_extensions    = v3_req

[dn]
CN = KyroVoice Dev

[v3_req]
keyUsage             = critical, digitalSignature
extendedKeyUsage     = critical, codeSigning
basicConstraints     = critical, CA:false
subjectKeyIdentifier = hash
EOF

openssl genrsa -out "$KEY" 2048 2>/dev/null
openssl req -new -x509 -key "$KEY" -out "$CERT" -days 3650 -config "$CONF" 2>/dev/null

echo "==> Importing identity into keychain…"
openssl pkcs12 -export \
    -out "$P12" \
    -inkey "$KEY" \
    -in "$CERT" \
    -passout pass:"$KC_PASS" \
    -name "$CERT_NAME" \
    -legacy 2>/dev/null

security import "$P12" \
    -k "$KC_PATH" \
    -P "$KC_PASS" \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    2>/dev/null || true

echo "==> Trusting certificate for code signing…"
security add-trusted-cert -r trustRoot -k "$KC_PATH" "$CERT" 2>/dev/null || true

echo "==> Allowing codesign to access the key without prompts…"
security set-key-partition-list \
    -S apple-tool:,apple: \
    -s -k "$KC_PASS" \
    "$KC_PATH" 2>/dev/null || true

# Verify
echo ""
if security find-identity -v -p codesigning "$KC_PATH" 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "✓ Done. Certificate is ready."
    echo "  Run ./run.sh — permissions will now survive every rebuild."
else
    echo "WARNING: Certificate imported but not visible as a code-signing identity yet."
    echo "Try opening Keychain Access, find 'KyroVoice Dev' in the kyro-build keychain,"
    echo "double-click it → Trust → Code Signing → Always Trust, then re-run ./run.sh."
fi
