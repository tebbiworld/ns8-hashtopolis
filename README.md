# ns8-hashtopolis

A [NethServer 8](https://github.com/NethServer/ns8-core) module that packages
[Hashtopolis](https://github.com/hashtopolis/server) — a distributed wrapper for
hashcat used for authorized password recovery and security testing.

The module runs three rootless containers:

- **hashtopolis-backend** — the official `hashtopolis/backend` image (PHP API
  server and agent endpoints)
- **hashtopolis-frontend** — the official `hashtopolis/frontend` image (Angular
  web UI)
- **hashtopolis-db** — a dedicated `mysql:8.0` database, data kept in the
  `hashtopolis-db` named volume

All three containers share one pod, so they reach each other over the pod's
localhost.

## Routing

The module publishes **one** port and creates **one** Traefik route: a plain
host rule with the usual Let's Encrypt and HTTP→HTTPS options. Splitting the
request paths is done inside the module by the frontend's nginx, which is
configured by `imageroot/nginx/default.conf`:

- `/` → the Angular single page application (nginx, port 8080 in the pod)
- `/api/` (v1 `api/server.php` and v2 `api/v2`), `/static/` (7zr and uftpd agent
  binaries), `/binaries/`, `/agents.php`, `/getFile.php`, `/getFound.php`,
  `/getHashlist.php` → Apache in the backend container on port 80 in the pod

Hashtopolis has to hand out absolute URLs (agent binary downloads, v2 pagination
links). Because the backend only ever sees plain http behind the reverse proxy,
the module writes the public base URL into the Hashtopolis `baseHost` setting,
which overrides the auto-detection. The base URL is derived from the host name
and the Traefik settings, or taken from the optional **Public URL** field —
use that field when the instance is published through a gateway node which
terminates TLS while this node serves plain http.

Agents are registered with `<base URL>/api/server.php`, the web interface uses
`<base URL>/api/v2`.

## Install

From the NethServer 8 cluster leader:

```bash
add-module ghcr.io/tebbiworld/hashtopolis:latest 1
```

Configure it (replace the host name):

```bash
api-cli run module/hashtopolis1/configure-module --data '{
  "host": "hashtopolis.example.org",
  "lets_encrypt": true,
  "http2https": true
}'
```

Read back the configuration, including the generated initial admin password and
the agent URL:

```bash
api-cli run module/hashtopolis1/get-configuration --data '{}'
```

Log in at `https://hashtopolis.example.org` with user `admin` and the returned
password, then change it immediately.

## Build

```bash
bash build-images.sh
buildah push ghcr.io/tebbiworld/hashtopolis:latest
```

## Uninstall

```bash
remove-module --no-preserve hashtopolis1
```

## License

GPL-3.0-or-later
