# Changelog

## 1.2.1 — 2026-09-25

### Fixed

- **Empty Agents, Tasks, Hashlists and Binaries pages with HTTP 400 "Invalid pagination cursor".** A table position that an older web UI stored in the browser is sent as `page[after]=0`, which the backend rejects. The data was never affected. The module's nginx now drops this cursor (a valid cursor is always base64, so `0` never is), and the first page is shown.

## 1.2.0 — 2026-09-19

Alignment with the NethServer module conventions (NethServer/agents skills).

### Changed

- **Secrets moved out of the module environment.** The MySQL passwords and the initial admin password are now kept in `state/passwords.env` (mode 0600) instead of `state/environment`, which NS8 mirrors to Redis in plain text. Existing installations are migrated on update; the values do not change. The secrets are no longer passed on the podman command line or embedded in the container health check.
- **Module backup now contains the data.** New `etc/state-include.conf`: the backup holds a consistent MySQL dump written by `module-dump-state`, the secrets file and the `hashtopolis-data` volume (files, hashlists, agent binaries). Before, only the module environment was saved.
- **Working restore.** New `restore-module` steps rebuild the database from the dump and re-apply every setting.
- MySQL pinned to `8.0.46` instead of the rolling `8.0` tag.
- Service restarts list every unit of the pod explicitly; update hooks log to stderr.

### Added

- Robot Framework tests (install, update from the previous release, backup and restore) run on real NS8 nodes through `stephdl/ns8-ci-actions`.

### Platform integration

- **Clone and move.** New `clone-module` step (a link to the restore step): a cloned or moved instance gets its route and settings back instead of coming up unconfigured. The settings are read from the source instance, including those a new instance starts with a default for.
- `org.nethserver.volumes`: the bulk-data volume(s) `hashtopolis-data` can be placed on an additional disk when the module is installed.
- Release notes are linked from the software centre (`relnotes_url`).

## 1.1.1 — 2026-09-14

### Changed

- Runtime images pinned by digest to the Hashtopolis `latest` builds of 2026-09-09 (backend `f8ea58f6…`, frontend `5749f8d6…`); upstream does not tag releases any more. Every installation now runs the same build; newer upstream builds arrive as module updates (automatic every ~6 weeks).

All notable changes to this module are documented here. Releases before 1.1.0
are described in the GitHub release notes and the git history.

## 1.1.0

### Changed

- **The module now creates a single Traefik route** (host rule, no path rules).
  Up to 1.0.1 it created seven routes: a frontend catch-all plus one
  higher-priority route per backend path. Dividing the request paths is an
  internal matter of this module and does not belong in the cluster reverse
  proxy. All three containers now share one pod and the frontend's nginx, which
  receives its configuration from the module, serves the Angular application and
  proxies the backend paths to Apache inside the pod.
- Only one TCP port is published per instance (`tcp-ports-demand` 2 → 1).
  Existing instances keep their second, now unused, port until they are removed.

### Fixed

- **Agents could not download 7zr and the hashcat binaries.** The module never
  created a route for `/static/`, which `DownloadBinaryAction` uses for the 7zr
  and uftpd binaries, so the request ended up at the frontend catch-all and the
  single page application answered instead of the file. With the internal proxy
  all backend paths are reachable, `/static/` included.
- **Download URLs were built with http.** `Util::buildServerUrl()` derives the
  scheme from `$_SERVER['HTTPS']`, which is always unset behind a
  TLS-terminating reverse proxy, so agents were sent to `http://…/static/7zr.bin`.
  Setting `HTTPS` via Apache alone does not help: `SERVER_PORT` stays 80 and
  cannot be overridden, which makes the function return `https://:80`. The
  module now writes the public base URL into the supported `baseHost`
  configuration item, which short-circuits the auto-detection. This also fixes
  the absolute links in v2 API answers.

### Added

- Optional **Public URL** setting. Empty means "derive from the host name and
  the Traefik settings of this node"; set it when a gateway node terminates TLS
  for this instance.
- The Settings page shows the v1 agent registration URL
  (`<base URL>/api/server.php`) next to the v2 API URL. Previously it showed the
  v2 URL for both.

### Migration

- On update, obsolete per-path routes (`<instance>-api`, `-binaries`, `-agents`,
  `-getfile`, `-gethashlist`, `-getfound`) are deleted automatically and the
  published port is carried over into the new `HTTP_PORT` variable.
- Routes that were added by hand in the cluster's Traefik user interface (for
  example a `/static` exception on a gateway node) are invisible to the module
  and have to be removed manually.
