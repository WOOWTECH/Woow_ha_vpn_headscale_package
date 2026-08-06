# Changelog

## 0.1.0 — 2026-08-06

Initial release.

- Headscale **v0.29.3** control plane
- Headplane **v0.7.0** management dashboard
- Single container, s6-overlay supervises `headscale` + `headplane` services
- Ports: `8080→28080` (control plane), `3000→23000` (Headplane `/admin`), `9090` metrics disabled
- Add-on options (7): `server_url`, `log_level`, `ipv4_prefix`, `ipv6_prefix`, `magic_dns_base_domain`, `headplane_enabled`, `create_default_user`
- One-shot bootstrap on first start: default user + long-lived Headplane API key auto-provisioned, key printed to log for login
- cont-init guards: refuses to start when `server_url` host equals `magic_dns_base_domain`
- Preserves manual/Headplane edits to `dns.*` keys across restarts via override diff
- HA backup covers `/addon_configs/<slug>/` and `/var/lib/headscale`
- Supervisor local build only (no `image:` field this release) — GHCR CI to follow
