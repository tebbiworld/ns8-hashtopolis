# Changelog

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
