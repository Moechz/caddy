#!/bin/sh
# ===========================================================================
# Caddy web server for TOS 7 - container entrypoint
# ===========================================================================
# The upstream image (caddy:2.11.4-alpine) starts as root and keeps its
# configuration in root-owned /etc/caddy. TOS requires every container to run
# as a non-root user, and everything the user may change has to live in the
# bind-mounted application data directory. This wrapper therefore
#
#   1. keeps the user-editable Caddyfile in the bind-mounted /config directory
#      and seeds a working default the first time the application starts,
#   2. validates the Caddyfile before starting - both its syntax and that it
#      really listens on the one published container port - and falls back to a
#      built-in default when the user's file is unusable, because a bad edit
#      must never turn the application into a restart loop or make it
#      unreachable,
#   3. starts Caddy in the foreground.
#
# Everything the user can change lives in the bind mounts (/config, /www);
# certificates and Caddy's own state are kept in /data.
#
# MAINTAINERS: this file is embedded verbatim into docker-compose.yml by
# scripts/build.sh, which indents it and escapes every dollar sign (docker
# compose interpolates ${VAR} / $VAR in compose files). Edit THIS file only,
# never the generated block in docker-compose.yml.
# ===========================================================================
set -u

log() { printf '[caddy-app] %s\n' "$*"; }

CONF_DIR=/config
DATA_DIR=/data
WWW_DIR=/www

# ------------------------------------------------------------ writable mounts
# The bind-mount sources are created by Docker (owned by root) the first time
# the container starts. The TOS installer chowns them to the application user;
# if that has not happened, fall back to a container-local copy so that the
# application still starts instead of entering a restart loop.
if ! { mkdir -p "$CONF_DIR" 2>/dev/null && : > "$CONF_DIR/.write-test" 2>/dev/null; }; then
    log "WARNING: $CONF_DIR is not writable - using an ephemeral configuration in /tmp"
    log "WARNING: configuration changes will be lost when the container is recreated"
    CONF_DIR=/tmp/caddy-app/config
    mkdir -p "$CONF_DIR"
fi
rm -f "$CONF_DIR/.write-test" 2>/dev/null || true

if ! { mkdir -p "$DATA_DIR" 2>/dev/null && : > "$DATA_DIR/.write-test" 2>/dev/null; }; then
    log "WARNING: $DATA_DIR is not writable - certificates and Caddy state will be lost on restart"
    DATA_DIR=/tmp/caddy-app/data
    mkdir -p "$DATA_DIR"
fi
rm -f "$DATA_DIR/.write-test" 2>/dev/null || true

if ! { mkdir -p "$WWW_DIR" 2>/dev/null && : > "$WWW_DIR/.write-test" 2>/dev/null; }; then
    log "WARNING: $WWW_DIR is not writable - serving a fallback web root from /tmp"
    WWW_DIR=/tmp/caddy-app/www
    mkdir -p "$WWW_DIR"
fi
rm -f "$WWW_DIR/.write-test" 2>/dev/null || true

# Caddy keeps its certificates and the autosaved configuration below
# XDG_DATA_HOME / XDG_CONFIG_HOME. The image sets both to /config and /data;
# point them at the directories really in use so the fallback above still works.
XDG_CONFIG_HOME="$CONF_DIR"
XDG_DATA_HOME="$DATA_DIR"
export XDG_CONFIG_HOME XDG_DATA_HOME

CADDYFILE="$CONF_DIR/Caddyfile"

# --------------------------------------------------------------- file seeding
# seed <target> <mode> <www-dir>   (template on stdin)
# Writes the template only when the target does not exist yet, so a file the
# user has changed is never overwritten. @WWW_DIR@ is replaced with the web
# root actually in use (it can differ from /www when the fallback kicked in).
seed() {
    if [ -e "$1" ]; then
        cat > /dev/null
        return 0
    fi
    sed -e "s|@WWW_DIR@|$3|g" > "$1"
    chmod "$2" "$1" 2>/dev/null || true
    log "created $1"
}

seed "$CADDYFILE" 0644 "$WWW_DIR" <<'TPL_CADDYFILE'
# ===========================================================================
# Caddy web server for TOS - main configuration (the "Caddyfile")
# ===========================================================================
# This file is created on the first start and kept on your NAS, in the
# application data directory:
#
#     <volume>/DockerAppData/caddydocker/config/Caddyfile
#
# After editing it, apply the change without restarting the application:
#
#     docker exec caddydocker caddy reload --config /config/Caddyfile
#
# (or restart the Caddy application in the TOS App Center).
#
# Caddyfile syntax : https://caddyserver.com/docs/caddyfile
# Directive order  : https://caddyserver.com/docs/caddyfile/directives
#
# Only one port reaches the container: TOS opens http://<NAS-IP>:8002/ and
# Caddy listens on port 8080 inside the container. Automatic HTTPS for a
# public domain needs ports 80 and 443, which this application does not
# publish; use "tls internal" if you want a certificate for local use.
# ===========================================================================

# ------------------------------------------------------------- default site
# Serves the files you put into the "www" folder of the application data
# directory (<volume>/DockerAppData/caddydocker/www).
:8080 {
	root * @WWW_DIR@
	encode gzip
	file_server

	# Health endpoint used by the TOS application health check.
	# Keep it when rewriting this file, otherwise the application may be
	# reported as not running.
	respond /healthz "ok" 200
}

# ------------------------------------------------------------------ examples
# Reverse proxy for a service running elsewhere on your LAN:
#
#     :8080 {
#         handle /app/* {
#             reverse_proxy 192.168.1.10:3000
#         }
#     }
#
# A second site on the same port, selected by the requested host name:
#
#     http://nas.example.lan:8080 {
#         root * @WWW_DIR@
#         file_server
#     }
#
# Serve the same site over TLS with a locally generated certificate:
#
#     https://:8080 {
#         tls internal
#         root * @WWW_DIR@
#         file_server
#     }
TPL_CADDYFILE

seed "$CONF_DIR/README.txt" 0644 "$WWW_DIR" <<'TPL_README'
Caddy web server for TOS - application data
===========================================

Everything in this directory is kept on your NAS (it is the "config" volume of
the Caddy application) and survives restarts, re-installs and upgrades.

  Caddyfile   Main configuration. Created on the first start.
  README.txt  This file.
  caddy/      Caddy's own state (the autosaved configuration).

The files that are served live in the "www" directory next to this one, and
certificates plus other runtime state are kept in the "data" directory:

  <volume>/DockerAppData/caddydocker/config/Caddyfile
  <volume>/DockerAppData/caddydocker/www/
  <volume>/DockerAppData/caddydocker/data/

How to use it
-------------
1. Put your website into the www directory (an index.html is created for you
   on the first start).
2. Edit Caddyfile to add sites, reverse proxies or TLS. Examples are included
   at the end of the file.
3. Apply the change:

       docker exec caddydocker caddy validate --config /config/Caddyfile
       docker exec caddydocker caddy reload   --config /config/Caddyfile

   (or restart the Caddy application in the TOS App Center).

   If the Caddyfile is invalid, the container refuses to use it and keeps
   serving the built-in default instead, so the application stays reachable
   and you can fix the file.

Ports
-----
Only one port is published: the TOS application opens
http://<NAS-IP>:8002/ and Caddy listens on port 8080 inside the container.
Sites that listen on any other port are not reachable from outside.

Non-root
--------
The container runs as a non-root user (uid 1000) and can only write inside its
own data directory. Do not point "root" at system directories such as /etc.

Logs
----
Caddy writes its log to the container log:

       docker logs caddydocker
TPL_README

if [ ! -e "$WWW_DIR/index.html" ]; then
    seed "$WWW_DIR/index.html" 0644 "$WWW_DIR" <<'TPL_INDEX'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Caddy Web Server</title>
<style>
  :root { color-scheme: light dark; }
  body { font-family: system-ui,-apple-system,"Segoe UI",Roboto,"Helvetica Neue",Arial,"Noto Sans CJK SC",sans-serif;
         max-width: 46rem; margin: 0 auto; padding: 3rem 1.25rem 4rem; line-height: 1.7; }
  h1 { font-size: 1.6rem; margin-bottom: .2rem; }
  h2 { font-size: 1.1rem; margin-top: 2rem; }
  code, pre { font-family: ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; font-size: .92em; }
  code { background: rgba(127,127,127,.15); padding: .1em .35em; border-radius: .3em; }
  pre { background: rgba(127,127,127,.12); padding: .8rem 1rem; border-radius: .5rem; overflow-x: auto; }
  .ok { color: #0a7d33; font-weight: 600; }
  footer { margin-top: 3rem; font-size: .85rem; opacity: .7; }
</style>
</head>
<body>
<h1>Caddy Web Server</h1>
<p class="ok">Caddy is running on your NAS.</p>

<p>This is the placeholder page created on the first start. Replace
<code>index.html</code> in the <code>www</code> folder of the application data
(<code>&lt;volume&gt;/DockerAppData/caddydocker/www</code>) and reload the page
to publish your own site.</p>

<h2>Configuration</h2>
<p>Everything is configured with a single <code>Caddyfile</code> in the
<code>config</code> folder next to <code>www</code>:</p>
<pre>config/Caddyfile   sites, reverse proxies and TLS (created on first start)
config/README.txt  how-to and examples
www/               the files that are served
data/              certificates and Caddy state</pre>
<p>A reverse proxy is a few lines, for example:</p>
<pre>:8080 {
    handle /app/* {
        reverse_proxy 192.168.1.10:3000
    }
}</pre>

<h2>Apply a change</h2>
<pre>docker exec caddydocker caddy validate --config /config/Caddyfile
docker exec caddydocker caddy reload   --config /config/Caddyfile</pre>
<p>Logs: <code>docker logs caddydocker</code> (or the TOS Container Manager).</p>

<hr>
<p><b>中文：</b>Caddy 已在你的 NAS 上运行。上面的绿色提示说明服务正常。
把 <code>index.html</code> 换成自己的网页即可发布网站（位置：应用数据目录
<code>DockerAppData/caddydocker/www</code>）。站点、反向代理与 TLS 全部写在同级的
<code>config/Caddyfile</code> 里（首次启动自动生成，文件末尾有示例）。
改完用
<code>docker exec caddydocker caddy reload --config /config/Caddyfile</code>
热加载；配置写错时应用会继续用内置默认配置运行，不会中断服务。
访问日志用 <code>docker logs caddydocker</code> 查看。</p>

<footer>Caddy 2.11.4 (Docker Hub official image, unmodified) &middot; packaged for
TOS 7 by Moechz. Caddy is a trademark of Stack Holdings GmbH.</footer>
</body>
</html>
TPL_INDEX
fi

# ------------------------------------------------------------------- validate
# Never start with a broken configuration: Caddy would exit immediately and the
# container would restart in a loop, which TOS reports as a faulty application.
#
# "caddy validate" alone is not enough here: a Caddyfile is valid for much more
# than a web server on the published port. A stray line such as "this is not
# valid config" is accepted as a list of host names (Caddy then tries to obtain
# certificates for them on port 443 and nothing is served on 8080). The adapted
# configuration therefore has to contain a listener on port 8080; otherwise the
# application would be reachable at the TOS URL but silently serve nothing.
#
# check_config <file> -> 0 usable, 1 not parseable, 2 does not listen on 8080,
#                        3 syntax ok but Caddy refuses it
check_config() {
    caddy adapt --config "$1" --adapter caddyfile \
        > /tmp/caddy-adapt.json 2>/tmp/caddy-check.log || return 1
    grep -q '":8080"' /tmp/caddy-adapt.json || return 2
    caddy validate --config "$1" --adapter caddyfile \
        >> /tmp/caddy-check.log 2>&1 || return 3
    return 0
}

start_file="$CADDYFILE"
check_config "$CADDYFILE"
rc=$?
if [ "$rc" = 0 ]; then
    cat /tmp/caddy-check.log
else
    log "ERROR: the Caddyfile $CADDYFILE cannot be used:"
    if [ "$rc" = 2 ]; then
        log "ERROR: it does not listen on port 8080, the only port this application publishes"
    fi
    sed 's/^/  /' /tmp/caddy-check.log
    if [ "$CADDYFILE" = "/config/Caddyfile" ]; then
        log "ERROR: falling back to the built-in default configuration"
        log "ERROR: fix the file above, then restart the application"
        start_file=/tmp/caddy-app/fallback/Caddyfile
        mkdir -p /tmp/caddy-app/fallback
        seed "$start_file" 0644 "$WWW_DIR" <<'TPL_FALLBACK'
{
	admin off
}
:8080 {
	root * @WWW_DIR@
	file_server
	respond /healthz "ok" 200
}
TPL_FALLBACK
        check_config "$start_file" || {
            log "ERROR: the built-in configuration cannot be used either - giving up"
            cat /tmp/caddy-check.log
            exit 1
        }
    else
        exit 1
    fi
fi

log "starting caddy with $start_file (uid=$(id -u))"
exec caddy run --config "$start_file" --adapter caddyfile
