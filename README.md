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

Backend and database share one pod; the frontend runs as a separate container
because it also listens on port 80.

## Routing

Traefik publishes everything on a single host name:

- `https://<host>/` → Angular frontend
- `https://<host>/api` → backend API and agent communication (higher priority)

The frontend talks to the backend from the browser via `HASHTOPOLIS_BACKEND_URL`
(`https://<host>/api/v2`); Hashtopolis agents use the same `/api` URL.

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
