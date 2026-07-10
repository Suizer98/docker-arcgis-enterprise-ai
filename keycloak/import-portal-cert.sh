#!/usr/bin/env bash
# Import Keycloak TLS cert into Portal JVM and restart Portal.
# Run from repo root: sh keycloak/import-portal-cert.sh
set -e
cd "$(dirname "$0")/.."

docker compose exec -T portal bash -lc '
JAVA_HOME=/home/arcgis/portal/framework/runtime/jre
if [ ! -f /app/keycloak-ca.crt ]; then
  echo "ERROR: /app/keycloak-ca.crt not mounted. Recreate portal: docker compose up portal -d --force-recreate"
  exit 1
fi
if ! keytool -list -alias keycloak-local -keystore "$JAVA_HOME/lib/security/cacerts" -storepass changeit >/dev/null 2>&1; then
  keytool -importcert -noprompt -alias keycloak-local \
    -file /app/keycloak-ca.crt \
    -keystore "$JAVA_HOME/lib/security/cacerts" -storepass changeit
  echo "Imported keycloak-local cert"
else
  echo "keycloak-local cert already present"
fi
/home/arcgis/portal/framework/etc/agsportal.sh restart
echo "Portal restarted"
'
