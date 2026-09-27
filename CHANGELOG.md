# Changelog

All notable user-visible changes to the Caddy Web Server TOS application package.

## 2.11.4-1 — 2026-09-27

### Added
- First release. Caddy Web Server (`caddy:2.11.4-alpine`, Docker Hub official image, unmodified)
  packaged as a TOS 7 Docker application, published on port 8002 and running
  as a non-root user (1000:1000).
- Persistent data is kept under `/Volume1/DockerAppData/caddydocker/`.
