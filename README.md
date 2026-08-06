# Woow Headscale VPN — Home Assistant Add-on

自架 [Tailscale](https://tailscale.com/) control plane（[Headscale](https://headscale.net/) + [Headplane](https://github.com/tale/headplane) 管理介面）以 Home Assistant add-on 形式打包，讓 HA 主機同時擔任 VPN 區網的中控伺服器。所有裝置用**未修改的官方 Tailscale client** 加入你自己的 `100.64.0.0/10` tailnet，資料流不經任何第三方服務。

## 加入商店（HAOS / HA Supervised）

**Settings → Add-ons → Add-on Store → ⋮ → Repositories** 貼上：

```
https://github.com/WOOWTECH/Woow_ha_vpn_headscale_package
```

或直接按：

[![Open your Home Assistant instance and show the add add-on repository dialog with a specific repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository=https%3A%2F%2Fgithub.com%2FWOOWTECH%2FWoow_ha_vpn_headscale_package)

商店會出現 **Woow Headscale VPN**，點 Install 由 Supervisor 本地 build（首次約 3–5 分鐘）。

## 內含 add-on

| Slug | 名稱 | 說明 |
|------|------|------|
| [`woow-headscale`](./headscale) | Woow Headscale VPN | Headscale v0.29.3 control plane + Headplane v0.7.0 管理介面（單容器、s6-overlay 監督） |

## 對照文件

- Add-on 使用說明：[`headscale/DOCS.md`](./headscale/DOCS.md)（zh-TW）
- Podman 版原始部署：[`WOOWTECH/Woow_vpn_headscale_package`](https://github.com/WOOWTECH/Woow_vpn_headscale_package)（podman 分支）
- 打包架構致謝：本 add-on 的檔案佈局、cont-init 與 tempio template 機制參考自 [`AlessioBazzanella/homeassistant-headscale-addon`](https://github.com/AlessioBazzanella/homeassistant-headscale-addon)（MIT License）

## 已知限制（第一版）

- **Control plane（port 28080）不能走 HA Ingress、也不能放 Cloudflare Tunnel 後面** — Tailscale noise 協議的非標準 `Upgrade: tailscale-control-protocol` header 會被剝掉。可行曝露方案：router port-forward、Nginx/Caddy/Traefik 反代（需正確 upgrade passthrough）、或 ngrok。詳見 DOCS.md。
- **Headplane 管理介面（port 23000）可以走 CF Tunnel / Ingress** — 純 HTTP，沒有特殊 header。
- 第一版沒有 OIDC 選項（辦公室未來才接 OpenClaw 登入）。

## Licence

Add-on package: MIT — see `LICENSE`.
Headscale: BSD-3-Clause (juanfont/headscale). Headplane: BSD-3-Clause (tale/headplane).
