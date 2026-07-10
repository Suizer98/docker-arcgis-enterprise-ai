#!/usr/bin/env bash
# Verify Portal can complete the Keycloak OIDC backchannel (token + userinfo).
# Run from repo root: sh keycloak/verify-oidc.sh
set -e
cd "$(dirname "$0")/.."

echo "=== OIDC discovery (from Portal container) ==="
docker compose exec -T portal curl -sk \
  https://keycloak:8443/realms/arcgis/.well-known/openid-configuration \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
for k in ('issuer', 'authorization_endpoint', 'token_endpoint', 'userinfo_endpoint', 'jwks_uri'):
    print(f'{k}: {d.get(k)}')
"

echo ""
echo "=== Portal JVM truststore (keycloak-local cert) ==="
docker compose exec -T portal bash -lc '
JAVA_HOME=/home/arcgis/portal/framework/runtime/jre
if keytool -list -alias keycloak-local -keystore "$JAVA_HOME/lib/security/cacerts" -storepass changeit >/dev/null 2>&1; then
  echo "OK: keycloak-local alias present"
else
  echo "MISSING: run keytool import (see sample.env)"
fi
'

echo ""
echo "=== Token + userinfo (password grant smoke test) ==="
docker compose exec -T portal bash -lc '
set -e
TOKEN_JSON=$(curl -sk -X POST https://keycloak:8443/realms/arcgis/protocol/openid-connect/token \
  -d grant_type=password \
  -d client_id=arcgis-portal \
  -d client_secret=arcgis-portal-secret \
  -d username=portaluser \
  -d password=portaluser \
  -d scope="openid profile email")
echo "$TOKEN_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(\"token_error:\", d.get(\"error\", \"none\")); print(\"has_access_token:\", \"access_token\" in d); print(\"has_id_token:\", \"id_token\" in d)"
ACCESS=$(echo "$TOKEN_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get(\"access_token\",\"\"))")
ID=$(echo "$TOKEN_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get(\"id_token\",\"\"))")
if [ -n "$ACCESS" ]; then
  echo "userinfo:"
  curl -sk -H "Authorization: Bearer $ACCESS" \
    https://keycloak:8443/realms/arcgis/protocol/openid-connect/userinfo
  echo ""
fi
if [ -n "$ID" ]; then
  echo "id_token claims (payload):"
  echo "$ID" | python3 -c "
import sys, json, base64
t = sys.stdin.read().strip().split(\".\")[1]
t += \"=\" * (-len(t) % 4)
print(json.dumps(json.loads(base64.urlsafe_b64decode(t)), indent=2))
"
fi
'
