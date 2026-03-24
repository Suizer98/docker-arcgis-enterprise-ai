#!/usr/bin/env sh
# Generate a self-signed cert for local dev (nginx.local / nginx / localhost).
# Run from repo root: sh nginx/generate-ssl.sh
set -e
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SSL_DIR="$SCRIPT_DIR/ssl"
mkdir -p "$SSL_DIR"
if [ -f "$SSL_DIR/server.key" ] && [ -f "$SSL_DIR/server.crt" ]; then
  echo "nginx/ssl/server.key and server.crt already exist; remove them to regenerate."
  exit 0
fi
openssl req -x509 -nodes -days 825 -newkey rsa:2048 \
  -keyout "$SSL_DIR/server.key" \
  -out "$SSL_DIR/server.crt" \
  -subj "/CN=nginx.local" \
  -addext "subjectAltName=DNS:nginx.local,DNS:nginx,DNS:localhost,IP:127.0.0.1"
chmod 600 "$SSL_DIR/server.key"
echo "Wrote $SSL_DIR/server.crt and server.key"
