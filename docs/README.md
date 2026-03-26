# docker-arcgis-enterprise

> Fork Notice: This is a fork of the original [docker-arcgis-enterprise](https://github.com/Wildsong/docker-arcgis-enterprise) repository by Wildsong.

Tech stacks:

![Tech stacks](https://skillicons.dev/icons?i=docker,windows,ubuntu,bash)

## Changes in fork

Enabling ESRI ArcGIS Enterprise to be run in Docker containers on Window WSL2 or MacOS (primarily OrbStack). This fork focuses on improving the undone job by resolving Datastore issue and setting up your own enterprise geodatabases using the PostgreSQL.

## Building appropriate image as a start

### Docker image in AMD64

When building the base ubuntu-server image on MacOS, you must specify the platform:

```bash
docker buildx build --platform linux/amd64 -t ubuntu-server ubuntu-server
```

## Port forwarding between each containers

### Current Approach
`/etc/hosts` in WSL; mirror in Windows (`C:\Windows\System32\drivers\etc\hosts`) if the browser/host apps must resolve names (e.g. `nginx.local` for widgets):

```
127.0.0.1 portal portal.local
127.0.0.1 server server.local
127.0.0.1 datastore datastore.local
127.0.0.1 nginx nginx.local
```

Admin rights required. Optional: Nginx reverse proxy.

### Web Adaptor: register with FQDN, then point the public URL at `localhost`

The Web Adaptor wizard asks for Portal and Server machine names as FQDNs (for example `portal.local` and `server.local`), not `localhost`. Those names must resolve from the Web Adaptor container (Compose DNS) and, when you use the browser to Portal/Server directly, from Windows via the same `hosts` lines as above (`127.0.0.1 portal.local`, `127.0.0.1 server.local`, matching your `.env` `PORTAL` / `GISSERVER` casing if you use uppercase in Docker).

After registration, Portal often records the Web Adaptor URL using the machine name Esri sees from the Web Adaptor host (often Docker’s default hostname, e.g. a short id like `787D93599E29`) instead of the URL you use in the browser. That breaks OAuth redirects and “invalid redirect_uri” until the stored URL matches how you browse.

Important: Updating the Web adaptor URL in Portal (and `WebContextURL` in step 4) to `https://localhost/arcgis` is what fixes the mismatch when you sign in at `https://localhost/arcgis/home`. Without that, OAuth redirects and callback URLs can point at the wrong host (the container id or another name), which shows up as invalid redirect URI errors, failed login loops, or 404s on redirect/callback paths after you submit credentials.

To compare with Machine name in Portal, see what hostname the Web Adaptor container reports:

```bash
docker exec web-adaptor hostname
```

Fix the Web Adaptor URL in Portal (direct HTTPS to Portal, bypassing the Web Adaptor for admin):

1. Open Portal Administrator Directory (signed in as a Portal admin), for example:  
   `https://portal.local:7443/arcgis/portaladmin/`  
   (requires `portal.local` in Windows `hosts`, or use `--resolve` / real DNS.)

2. Go to Home → System → Web Adaptors, open the Web Adaptor that lists your machine (for example Web Adaptor: `787D93599E29`), then edit.  
   Direct link pattern (your GUID will differ):  
   `https://portal.local:7443/arcgis/portaladmin/system/webadaptors/<web-adaptor-id>`  
   Append `/edit` to open the edit form directly:  
   `https://portal.local:7443/arcgis/portaladmin/system/webadaptors/<web-adaptor-id>/edit`

3. Set Web adaptor URL to what clients actually use through the adaptor, for example:  
   `https://localhost/arcgis`  
   with HTTP port `80` and HTTPS port `443` (host ports mapped in `compose.yaml` to the Web Adaptor container).

4. Save (Portal may restart). Optionally align System → Properties → WebContextURL with `https://localhost/arcgis` so Portal-generated links and OAuth match.

Summary: Register using `portal.local` / `server.local` (and `hosts` on Windows for direct Portal admin). Then edit the Web Adaptor entry so URL is `https://localhost/arcgis`, not the auto-detected Docker hostname—so that logging in through `https://localhost/arcgis/home` uses consistent redirect URIs and OAuth stops failing with 404 or invalid redirect on the callback.

## Setup enterprise geodatabases connection

### Setup connection between pgadmin and postgresql

Go to [http://localhost:8080/browser/](http://localhost:8080/browser/), in pgadmin use these settings:
```
Host name/address: postgres # docker container service name as defined in compose.yaml
Port: 5432
Username: {$POSTGRES_USER}
Password: {$POSTGRES_PASSWORD}
Save password?: On
```

### Preparing sde file

Test databases are already created with the `init.sh` script, so just grab those variables and go to ArcGIS Pro and create a `.sde` file first.

Go to your ArcGIS Pro, create a sde file using WSL2-IP, you can also use `localhost` or `127.0.0.1` for testing. But the caveat is when importing the sde to ArcGIS Server, it cannot recognise `localhost` which postgres port supposed to be exposed from outside, and also container name like `postgres`.
```
Platform: PostgreSQL
Instance: WSL2-IP,5432 # Must be comma, not semicolon
Username: {$POSTGRES_USER}
Password: {$POSTGRES_PASSWORD}
Database: arcgis_enterprise
```
After connected, right click the created sde and `enable enterprise geodatabase`. If you don't how to get the Authorisation file to be used on ArcGIS Pro interface, I highly recommend you to check step below.

### Creating Enterprise Geodatabase with ArcPy

1. First, locate the keygen inside the ArcGIS Server container:

```bash
# From WSL2, locate the keygen
docker exec docker-arcgis-enterprise-server-1 find /home/arcgis -name "keygen" -type f
```

2. Since the keycodes file is inside the ArcGIS Server container, you need to copy it to a Windows-accessible location:

```bash
# From WSL2, copy keycodes to Windows Desktop
docker cp docker-arcgis-enterprise-server-1:/home/arcgis/server/framework/runtime/.wine/drive_c/Program\ Files/ESRI/License11.4/sysgen/keycodes /mnt/c/Users/YOUR_USERNAME/Desktop/keycodes
```
3. Run script [`create_enterprise_gdb.py`](postgres/create_enterprise_gdb.py), you can rename the database name as you wish inside the script, I didn't implement variable pass in.

4. After successful creation, create new database connection in ArcGIS Pro to generate the sde file.

## Troubleshooting

### DataStore Validation Issues

Problem: "Bad login user[ ]" error when validating relational data store.

Solution: Add PostgreSQL access permissions for the actual database user:

1. Find the username from the validation payload in Server Manager:
   - Go to `Site` > `Data Stores` in Server Manager
   - Click `"Validate"` on the relational data store
   - Look at the error message for the connection string
   - Extract the username from `"USER=username"` in the connectionString

   ![Example Validation Error](docs/readme.png)

2. Add Server access using the `allowconnection.sh` tool, from the screenshot we know that user trying to connect is `hsu_jr2ht`:
```bash
docker exec docker-arcgis-enterprise-datastore-1 /home/arcgis/datastore/tools/allowconnection.sh "SERVER.LOCAL" "hsu_jr2ht"
```

Reference: [ESRI Community discussion](https://community.esri.com/t5/arcgis-enterprise-questions/data-store-not-validating/td-p/1071516)

Note: DataStore spins up its own PostgreSQL instance, this is different from the PostGIS issue below.

### Onboarding self hosted PostgreSQL as an enterprise GDB

Problem: `st_geometry.so` downloaded from MyESRI is not compatible with ArcGIS Server version.

```
ERROR: Setup st_geometry library ArcGIS version does not match the expected version in use [Success] st_geometry library release expected: 1.30.4.10, found: 1.30.5.10
Connected RDBMS instance is not setup for Esri spatial type configuration.
ERROR 003425: Setup st_geometry library ArcGIS version does not match the expected version in use.
Failed to execute (CreateEnterpriseGeodatabase)
```

Solution: Use POSTGIS instead of ST_GEOMETRY due to version mismatch:
- Expected: 1.30.4.10
- Found: 1.30.5.10

In [`create_enterprise_gdb.py`](postgres/create_enterprise_gdb.py), replace value below to use:
```python
spatial_type="POSTGIS"  # Instead of "ST_GEOMETRY"
```

### Hosting custom widget on Nginx

Follow Esri’s workflow: compile the widget in Experience Builder developer edition, copy the built folder to a web server, then register the manifest URL in Portal. Details (HTTPS, CORS, `application/json` for `.json`, and deploying `chunks` or `shared-code` when your widget uses them) are in [Add custom widgets](https://doc.arcgis.com/en/experience-builder/latest/configure-widgets/add-custom-widgets.htm).

In this repository, the `nginx` Compose service serves static files from `nginx/html` (HTTP and HTTPS ports are mapped in `compose.yaml`). Point your manifest at something like `https://nginx.local:<tls-port>/<widget>/manifest.json` once TLS and hosts entries are in place.

Portal may still block server-side access to that host until you allow it. Add the widget hostname (for example `nginx.local`) to Portal’s `allowedProxyHosts` security setting. The example below uses a referer-based token and `Referer: https://portal.local:7443/`; replace `portal.local`, ports, username, and password to match your site. You need a Portal administrator account.

```bash
TOKEN=$(curl -sk --resolve portal.local:7443:127.0.0.1 \
  "https://portal.local:7443/arcgis/sharing/rest/generateToken" \
  -d "username=YOUR_PORTAL_ADMIN" \
  -d "password=YOUR_PASSWORD" \
  -d "client=referer" \
  -d "referer=https://portal.local:7443/" \
  -d "f=json" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')

curl -sk --resolve portal.local:7443:127.0.0.1 \
  -H "Referer: https://portal.local:7443/" \
  "https://portal.local:7443/arcgis/portaladmin/security/config?f=json&token=${TOKEN}" \
  | jq '. + {"allowedProxyHosts": "nginx.local"}' \
  > /tmp/portal-security-config-with-proxy.json

curl -sk --resolve portal.local:7443:127.0.0.1 \
  -H "Referer: https://portal.local:7443/" \
  -X POST \
  "https://portal.local:7443/arcgis/portaladmin/security/config/update?f=json&token=${TOKEN}" \
  --data-urlencode "securityConfig@/tmp/portal-security-config-with-proxy.json"
```

Use a comma-separated list in `allowedProxyHosts` if you need more than one hostname. To undo the change, fetch the current security config JSON, run `jq 'del(.allowedProxyHosts)'`, and POST the result with the same `update` endpoint and a fresh token.

### Custom Experience Builder widgets — `jimu-core/emotion.js` 404

We built a widget with Experience Builder developer edition 1.19 (`npm run build:prod` in the developer `client` tree) and registered it on ArcGIS Enterprise 11.4 Portal. The widget showed in the builder but failed at runtime: the browser requested `.../cdn/<n>/jimu-core/emotion.js`, got a 404, then MIME-type and SystemJS errors because the error page was HTML. The same `cdn/<n>/jimu-core` path could serve `index.js` with HTTP 200, but there was no `emotion.js` file on the Portal host under `jimu-core`.

The stock developer `client/tsconfig.json` turns on the automatic JSX runtime via `"jsxImportSource": "@emotion/react"` (often with `"jsx": "react-jsx"`), so the bundle imports `jimu-core/emotion` (resolved to `emotion.js`). The Experience Builder embedded in Enterprise 11.4 does not publish that file separately; Emotion is folded into other bundles. Switching to classic JSX avoids emitting that import.

In the developer edition, edit `client/tsconfig.json` under `compilerOptions`. Remove the stock JSX lines and align with something like the following (merge with your existing options—do not duplicate keys):

Before (remove):

```json
"jsx": "react-jsx",
"jsxImportSource": "@emotion/react",
```

After:

```json
"lib": [
  "dom",
  "es6",
  "scripthost",
  "es2015",
  "es2020.Promise"
],
"jsx": "react",
```

With `"jsx": "react"`, ensure each `.tsx` file has React in scope (for example `import { React } from 'jimu-core'` if that matches your project). Run `npm run build:prod` again, deploy the output under `dist-prod/widgets/<widget-name>/` to your static host, and hard-refresh the browser. Grep the built `.js` files: there should be no remaining `jimu-core/emotion` or `emotion.js` URL references.

## Offline authorisation using `.ecp` file

You may refer to this [website](https://enterprise.arcgis.com/en/server/10.9.1/install/linux/silently-install-arcgis-server.htm) to convert your `.prvc` into `.ecp` file for arcgis server, if this is required for air-gapped or internet isolated environment.
