# Woow Headscale VPN

Self-hosted Tailscale control plane for Home Assistant — bundles [Headscale](https://headscale.net/) v0.29.3 (server) and [Headplane](https://github.com/tale/headplane) v0.7.0 (dashboard) in a single add-on.

Turn your HA host into the coordinator of a private VPN mesh. All devices use the **unmodified official Tailscale client** and join a tailnet at `100.64.0.0/10` that never touches Tailscale Inc's servers.

See [DOCS.md](./DOCS.md) for setup, options, expose strategies and known pitfalls (zh-TW).
