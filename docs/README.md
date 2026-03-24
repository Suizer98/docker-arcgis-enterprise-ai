# docker-arcgis-enterprise

> **Fork Notice**: This is a fork of the original [docker-arcgis-enterprise](https://github.com/Wildsong/docker-arcgis-enterprise) repository by Wildsong.

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
On Windows WSL2, we use direct hostname resolution through `/etc/hosts` entries. Add the same lines to Windows hosts (`C:\Windows\System32\drivers\etc\hosts`) if you need the browser or other apps on the host to resolve these names (for example `nginx.local` for static Experience Builder widgets):

```
127.0.0.1 portal portal.local
127.0.0.1 server server.local
127.0.0.1 datastore datastore.local
127.0.0.1 nginx nginx.local
```

You need administrative rights to edit `/etc/hosts` in WSL and the hosts file on Windows.
You may also explore to use Nginx reverse proxy.

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

**Problem**: "Bad login user[ ]" error when validating relational data store.

**Solution**: Add PostgreSQL access permissions for the actual database user:

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

**Problem**: `st_geometry.so` downloaded from MyESRI is not compatible with ArcGIS Server version.

```
ERROR: Setup st_geometry library ArcGIS version does not match the expected version in use [Success] st_geometry library release expected: 1.30.4.10, found: 1.30.5.10
Connected RDBMS instance is not setup for Esri spatial type configuration.
ERROR 003425: Setup st_geometry library ArcGIS version does not match the expected version in use.
Failed to execute (CreateEnterpriseGeodatabase)
```

**Solution**: Use POSTGIS instead of ST_GEOMETRY due to version mismatch:
- Expected: 1.30.4.10
- Found: 1.30.5.10

In [`create_enterprise_gdb.py`](postgres/create_enterprise_gdb.py), replace value below to use:
```python
spatial_type="POSTGIS"  # Instead of "ST_GEOMETRY"
```

### Portal `allowedProxyHosts` (custom Experience Builder widgets)

If you host widget files on another host (for example `nginx.local` via this repo’s `nginx` service), Portal may need that hostname in `allowedProxyHosts` so server-side requests to your widget URL are allowed. Adjust hostnames, ports, and credentials to match your environment; use a Portal administrator account.

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

Use a comma-separated list if you need several hostnames. To clear `allowedProxyHosts`, POST an updated config with that key removed (`jq 'del(.allowedProxyHosts)'` on the current JSON).

## Offline authorisation using `.ecp` file

You may refer to this [website](https://enterprise.arcgis.com/en/server/10.9.1/install/linux/silently-install-arcgis-server.htm) to convert your `.prvc` into `.ecp` file for arcgis server, if this is required for air-gapped or internet isolated environment.
