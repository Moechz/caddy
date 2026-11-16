# caddy-for-tos

> TerraMaster TOS 7 App Center — **Docker application** package for
> [Caddy Web Server](https://github.com/caddyserver/caddy).

## What this is

A four-file TOS Docker application archive (`caddydocker.tar.gz`) that installs
Caddy Web Server on TOS 7 through the App Center:

- `config.ini` — TOS application metadata (`application_type: docker`, id `caddydocker`)
- `caddydocker.lang` — 23-language superset (TOS requires 14)
- `caddydocker.svg` — application icon (2475 bytes, 2 SVG elements)
- `docker-compose.yml` — one service, image `caddy:2.11.4-alpine`

## How it works

| | |
|---|---|
| Container image | `caddy:2.11.4-alpine` (Docker Hub, used unmodified) |
| Open | `http://<NAS-IP>:8002/` (container port 8080) |
| Runs as | non-root, `user: "1000:1000"` |
| Persistent data | `/config` → `/Volume1/DockerAppData/caddydocker/config`, `/data` → `/Volume1/DockerAppData/caddydocker/data`, `/www` → `/Volume1/DockerAppData/caddydocker/www` |
| Logs | `docker logs caddydocker` (stdout/stderr) |

All state lives in the application data folder: `config/Caddyfile` is the configuration you edit, `www/` holds the files that are served, `data/` holds certificates and Caddy's runtime state, and `config/caddy/autosave.json` is Caddy's own copy of the running configuration.

## Privacy

This application runs entirely on your NAS. **The developer does not collect, receive or
have access to any data processed by the application.** There is no telemetry, no analytics
and no account.

| Topic | Detail |
|---|---|
| Data processed | The application's configuration, database, caches and logs, plus any files you create with it. |
| Where it is stored | The application data folder (`/Volume1/DockerAppData/caddydocker/`) on your NAS. Nothing is uploaded to the developer. |
| Retention period | Until **you** delete it. Logs are rotated or size-limited by the application; uninstalling keeps the data unless you tick “delete data”. |
| Your rights | **Access / export**: copy the data folder. **Correct**: change the values in the web UI. **Delete**: uninstall with “delete data”, or remove the folder after stopping the container. |
| Deletion channel | Delete the folder yourself, or email **moechz@163.com** (answered within 30 days). |
| Security measures | Container runs as uid 1000 (never root), no `privileged`, no host network, no `cap_add`, no Docker socket, one published port; image tag pinned and refreshed on upstream fixes. |
| Children | Not directed at children. |

**Full privacy policy:** [PRIVACY.md](PRIVACY.md) —
<https://github.com/Moechz/caddy/blob/main/PRIVACY.md> — and the website version at
<https://www.moechz.com/privacy.html>.

## Third-party services (API disclosure)

The developer operates no server in this path. The application contacts only the services
**you configure**, plus (optionally) an update check and the image registry.

| Service | Endpoint | Data sent | Destination / region |
|---|---|---|---|
| Services you configure in the app | the address you enter | only the data that feature needs | normally your own LAN or the provider you chose |
| Update check (if enabled) | the upstream project's release feed | current version string | GitHub, US |
| Image pull | `registry-1.docker.io` or your registry mirror | anonymous pull | Docker Hub, US / your mirror |

See `PRIVACY.md` §6 for the full table. Disable any integration in the app's settings if you
do not want it.

## Licence and attributions

| Component | Licence | Notes |
|---|---|---|
| Caddy Web Server | Apache-2.0 | upstream application, used unmodified inside the image |
| Container image `caddy:2.11.4-alpine` | see the image's own metadata | pulled from Docker Hub at install time |
| This packaging | GPL-3.0 (see `LICENSE`) | compose file, metadata, translations, icon |

“Caddy Web Server”, “TerraMaster” and “TOS” are trademarks of their respective owners. This is an
independent community package by Moechz and is not affiliated with the upstream project or
TerraMaster. Full details: [NOTICE.md](NOTICE.md).

## Design highlights

- **Non-root.** `user: "1000:1000"`; verified on real hardware (the container reports uid 1000).
- **Entrypoint wrapper**: the upstream image starts as root and reads its config from root-owned `/etc/caddy`, so the compose file replaces the entrypoint with `src/entrypoint.sh`. It seeds a working Caddyfile into the `config` volume on the first start, checks before starting that the file is parseable and really listens on container port 8080 (the one published port), and falls back to a built-in default when it is not, so a typo cannot take the application down or make it unreachable.
- **Fixed image tag, never `:latest`**, Docker Hub only, no `privileged`, no `network_mode: host`, no Docker socket, no `cap_add`.
- **Health check** probing the service on container port 8080.
- **Deterministic build**: GNU tar with uid/gid 0 and zeroed timestamps, gzip without a timestamp, plus the review-standards self-check above.
- **Editable configuration in the data volume.** The upstream image keeps its Caddyfile in `/etc/caddy` and starts as root; the wrapper seeds it into `config/Caddyfile` instead, so it is editable from the NAS and survives application updates.
- **An unusable Caddyfile cannot take the application down.** Before starting, the wrapper adapts the Caddyfile and requires a listener on container port 8080 (the only published port); on failure it starts with a built-in default. A typo therefore leaves the app reachable instead of causing a restart loop.
- **No privileged port needed.** The container listens on 8080 and runs as uid 1000, so the app does not rely on the `cap_net_bind_service` file capability of the upstream image and needs no `cap_add`.
- **Fixed image tag, never `:latest`**, Docker Hub only, no `privileged`, no `network_mode: host`, no Docker socket.
- **Health check** probing the service on container port 8080.

## Runtime file manifest

Everything the application writes on the NAS lives inside its own data
directory; the container-internal `/tmp` is discarded with the container. The
table lists what is created and how it behaves. Nothing else is written.

| Path | Purpose | Created when | Growth bound | Lifecycle |
|---|---|---|---|---|
| `config/Caddyfile` | main configuration (sites, reverse proxies, TLS); seeded on the first start | first start | static | never overwritten; user owned |
| `config/README.txt` | how-to for the NAS administrator | first start | static | never overwritten; safe to delete |
| `config/caddy/autosave.json` | Caddy's own copy of the running configuration (used by --resume) | first start | small | managed by Caddy; do not edit |
| `data/caddy` | certificates, private keys, instance id and storage locks | first start / on demand | grows with the number of certificates | managed by Caddy; back it up to keep your certificates |
| `www/index.html` | placeholder welcome page | first start | static | never overwritten; replace it with your own site |
| `/Volume1/DockerAppData/caddydocker/config` | Caddy Web Server application data (everything the container writes outside /tmp) | on first start / on demand | bounded by your own data | persistent; kept on uninstall unless you ask to delete it |
| `/Volume1/DockerAppData/caddydocker/data` | Caddy Web Server application data (everything the container writes outside /tmp) | on first start / on demand | bounded by your own data | persistent; kept on uninstall unless you ask to delete it |
| `/Volume1/DockerAppData/caddydocker/www` | Caddy Web Server application data (everything the container writes outside /tmp) | on first start / on demand | bounded by your own data | persistent; kept on uninstall unless you ask to delete it |

## Build

```bash
scripts/build.sh                  # -> out/caddydocker.tar.gz + .sha256
scripts/build.sh 2.11.4-2   # packaging iteration bump
scripts/build.sh 2.11.4-1 aarch64
```

The build stages the four files, substitutes the version/platform placeholders,
embeds `src/entrypoint.sh` into the compose file (escaping every `$` as `$$`), removes CRLF/BOM/AppleDouble, then runs
`tools/verify.py`, a review-standards self-check (archive layout, JSON validity,
required fields, 14+ language coverage, version consistency, Docker-Hub-only
images, fixed tag, reserved/recommended host ports, non-root user, per-service
healthcheck/TZ/restart, data path below the application data root, never the
`/Volume*` wildcard, comment-free sequence blocks, `x-app-meta` position, no
literal secrets and the SVG size/element limits).

## Local verification

```bash
./TOSAppSelfTestingTool -c out/caddydocker.tar.gz   # official spec check
bash test/install-and-verify.sh                  # on-device E2E (needs root)
```

> Docker applications cannot be side-loaded through the App Center's manual
> install page (it accepts `.deb` only); the official self-testing tool's `-i`
> mode or `docker compose` are the only ways to install one for testing.

## Store submission checklist

1. Public GitHub repo (code + README only).
2. Release **tag `v2.11.4-1`**, assets `caddydocker.tar.gz` +
   `caddydocker.tar.gz.sha256` (Docker asset naming: `<app_id>.tar.gz`, **no
   platform suffix**).
3. Developer platform → Add Application: ID `caddydocker`, package type Docker,
   repository URL, architecture `x86_64`.
4. Version Management → Add Version `2.11.4-1` → automated validation → review.


## Limitations

Only one host port is published (8002). Automatic HTTPS for a public domain needs ports 80 and 443 and is therefore not available; use `tls internal` or your own certificate for TLS.
Sites have to listen on container port 8080 to be reachable. A Caddyfile that does not listen on 8080 is ignored and replaced by the built-in default site.
If you switch the published site to TLS on port 8080, the TOS health check (plain HTTP) may report the app as unhealthy even while it still serves HTTPS.
The default site is served over plain HTTP on the LAN. Do not expose the published port to the internet without TLS.

---

Packaged for TOS 7 by Moechz. Upstream image used unmodified from Docker Hub.

## Support

- Issues and questions: <https://github.com/Moechz/caddy/issues>
- Email: moechz@163.com
- Privacy: [PRIVACY.md](PRIVACY.md) · Licence: [NOTICE.md](NOTICE.md)
