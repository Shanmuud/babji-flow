#!/bin/zsh
# Creates a local self-signed code-signing identity "Babji Flow Dev" once, so every
# rebuild keeps the same signature and macOS keeps Mic/Accessibility/Screen grants.
set -euo pipefail
NAME="Babji Flow Dev"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then echo "identity exists"; exit 0; fi
TMP=$(mktemp -d)
cat > "$TMP/ext.cnf" <<CNF
[req]
distinguished_name=dn
x509_extensions=v3
prompt=no
[dn]
CN=$NAME
[v3]
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
basicConstraints=critical,CA:false
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/ext.cnf" -keyout "$TMP/k.pem" -out "$TMP/c.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/k.pem" -in "$TMP/c.pem" -name "$NAME" -out "$TMP/id.p12" -passout pass:babji -legacy 2>/dev/null || \
openssl pkcs12 -export -inkey "$TMP/k.pem" -in "$TMP/c.pem" -name "$NAME" -out "$TMP/id.p12" -passout pass:babji
security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db -P babji -T /usr/bin/codesign -T /usr/bin/security >/dev/null
# Trust it for code signing (user trust store; may show one password prompt)
security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db "$TMP/c.pem" 2>/dev/null || true
rm -rf "$TMP"
security find-identity -v -p codesigning | grep "$NAME" && echo "identity created"
