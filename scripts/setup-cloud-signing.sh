#!/usr/bin/env bash
set -euo pipefail

# Generates a long-lived self-signed Code Signing certificate for WenBar and
# uploads it as GitHub Actions secrets so every cloud build keeps the exact
# same Designated Requirement (no repeated TCC Calendar/Reminders prompts across updates).
#
# Usage:
#   bash scripts/setup-cloud-signing.sh [owner/repo]

REPO="${1:-WendelYu/WenBar}"
CERT_CN="WenBar Code Signing"

WORK_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

P12_PASS="$(openssl rand -hex 24)"

cat > "$WORK_DIR/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = codesign_ext
prompt = no

[ dn ]
CN = ${CERT_CN}
O = WenBar

[ codesign_ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

echo "Generating 10-year self-signed Code Signing certificate (${CERT_CN})..."
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK_DIR/key.pem" \
  -out "$WORK_DIR/cert.pem" \
  -config "$WORK_DIR/cert.cnf" >/dev/null 2>&1

openssl pkcs12 -export \
  -legacy \
  -inkey "$WORK_DIR/key.pem" \
  -in "$WORK_DIR/cert.pem" \
  -name "$CERT_CN" \
  -passout "pass:${P12_PASS}" \
  -out "$WORK_DIR/wenbar-signing.p12"

P12_BASE64="$(base64 < "$WORK_DIR/wenbar-signing.p12" | tr -d '\n')"

echo "Uploading signing secrets to GitHub repository ${REPO}..."
printf '%s' "$P12_BASE64" | gh secret set SIGNING_CERT_P12_BASE64 --repo "$REPO"
printf '%s' "$P12_PASS" | gh secret set SIGNING_CERT_PASSWORD --repo "$REPO"
printf '%s' "$CERT_CN" | gh secret set SIGNING_IDENTITY --repo "$REPO"

echo "Done! GitHub Actions cloud builds will now sign with '${CERT_CN}'."
