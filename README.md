# ns8-hashtopolis

A [NethServer 8](https://github.com/NethServer/ns8-core) module that packages
[Hashtopolis](https://github.com/hashtopolis/server) — a distributed wrapper for
hashcat used for authorized password recovery and security testing.

The module runs three rootless containers:

- **hashtopolis-backend** — the Hashtopolis backend (PHP API server and agent
  endpoints), built by this repository from the upstream Dockerfile of the
  pinned Hashtopolis release on a pinned PHP release, see [Backend image](#backend-image)
- **hashtopolis-frontend** — the official `hashtopolis/frontend` image (Angular
  web UI)
- **hashtopolis-db** — a dedicated `mysql:8.4` (LTS) database, data kept in the
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

### Empty lists with "Invalid pagination cursor"

The web UI stores the table position in the browser (localStorage key
`ui-config`). A position saved by an older UI version is sent as
`page[after]=0`. The backend rejects that with HTTP 400 "Invalid pagination
cursor, cursor has to be base64 encoded", and Agents, Tasks, Hashlists and
Binaries look empty although the data is there. The module's nginx drops this
invalid cursor, so the first page is shown. With an older module version,
delete `ui-config` for the Hashtopolis host in the browser's developer tools
(Storage → Local Storage), or open the page in a private window.

## Authorized use only

Hashtopolis recovers passwords from hashes. Use it only on hashes you are
authorized to test - your own systems, or a written order of their owner - and
keep hash lists and results confidential: they end up in the module backup
(database dump and the `hashtopolis-data` volume). The Software Center shows
this section before the installation.

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

Read back the configuration (including the agent URL) and, once, the generated
initial admin password:

```bash
api-cli run module/hashtopolis1/get-configuration --data '{}'
api-cli run module/hashtopolis1/get-admin-password --data '{}'
```

Log in at `https://hashtopolis.example.org` with user `admin` and that
password, then change it immediately. The settings page shows the password only
on request; `get-configuration` never returns it.

### Restricting access

`ip_allowlist` (CIDR list, empty = everybody) limits the route of this node's
Traefik, e.g. to the LAN and the cluster VPN:

```bash
api-cli run module/hashtopolis1/configure-module --data '{"host": "hashtopolis.example.org", "ip_allowlist": ["192.168.1.0/24", "10.5.4.0/24"]}'
```

If another node publishes the host name - for example the node that receives
the Internet traffic forwards it to this node over the cluster VPN - every
request arrives here from that node's VPN address, so restrict the route on
that node as well.

## Agents

The agents (hashcat workers) run on machines with a GPU, outside NS8:

1. In the web UI create a voucher (*Agents → New agent*).
2. On the agent machine get the Python agent from the server
   (*Agents → New agent → Download agent*, `hashtopolis.zip`) and register it:
   `python3 hashtopolis.zip --url <agent URL> --voucher <voucher>`. The agent
   URL is shown on the settings page (`https://<host>/api/server.php`); with
   `public_url` set it is built from that address.
3. The agent needs to trust the certificate of the host name (Let's Encrypt,
   or the CA of an internal certificate) and to reach it on port 443. After the
   registration it appears under *Agents*; assign it to tasks there.
4. The agent downloads hashcat and the task files from the server and runs
   them: treat the Hashtopolis admin account as access to every agent machine.

## Mail

Hashtopolis sends e-mail notifications and password-reset mails with PHP
`mail()`. The module points the image's `ssmtp` at the cluster smarthost
(`state/ssmtp/ssmtp.conf`, written before every start and after a change of
the smarthost). Without a smarthost Hashtopolis cannot send mail. ssmtp cannot
read a relay password that contains `#`.

## Database

MySQL 8.4 LTS (since 1.3.0; 8.0 reached its end of life in April 2026). The
update from an earlier release upgrades the 8.0 data directory in place on the
first start, which can take a minute. The accounts keep `mysql_native_password`
(`--mysql-native-password=ON`, `--authentication-policy`); MySQL 9 will remove
it. The automatic release follows 8.4 patch releases only.

## Backend image

The published `hashtopolis/backend` images are only rebuilt for a Hashtopolis
release, so their PHP falls behind: v1.0.1 runs PHP 8.5.10, which is affected
by CVE-2026-109618 and CVE-2026-109619 (remote code execution, fixed in PHP
8.5.12). `build-images.sh` therefore builds the backend itself:

- source: the upstream repository at the tag of the pinned frontend image
  (`frontend_image`), so frontend and backend are always the same release
- base: the pinned `php_image` instead of the floating `php:8.5-apache` of the
  upstream Dockerfile; the build stops when upstream has moved to another PHP
  minor release, and when the built image does not run the pinned PHP version
- image: `ghcr.io/tebbiworld/hashtopolis-backend:<release>-php<version>`, e.g.
  `1.0.1-php8.5.12`. A published tag is never rebuilt; a new PHP or Hashtopolis
  release gives a new tag. The node exposes it as `${HASHTOPOLIS_BACKEND_IMAGE}`.

The automatic release follows Hashtopolis release tags (`vX.Y.Z`) and PHP 8.5
patch releases. In addition, `imageroot/php/zz-ns8-hardening.ini` turns off
`session.upload_progress.enabled` and `fatal_error_backtraces`, which
Hashtopolis does not use (configuration mitigation named by the CVE-2026-109619
advisory).

## Build

```bash
bash build-images.sh
# the backend image is only built when its tag is not published yet;
# the script prints the push commands
buildah push ghcr.io/tebbiworld/hashtopolis-backend:1.0.1-php8.5.12
buildah push ghcr.io/tebbiworld/hashtopolis:latest
```

`BUILD_BACKEND=1` forces the backend build. `PHP_IMAGE=<image>` replaces the
base for a local test only (the PHP version check still applies).

## Uninstall

```bash
remove-module --no-preserve hashtopolis1
```

## License

GPL-3.0-or-later
