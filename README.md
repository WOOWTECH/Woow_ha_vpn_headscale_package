# Woow Headscale VPN — Home Assistant Add-on Repository

[![Add repository to Home Assistant](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2FWOOWTECH%2FWoow_ha_vpn_headscale_package)

自架 [Tailscale](https://tailscale.com/) control plane（[Headscale](https://headscale.net/) + [Headplane](https://github.com/tale/headplane) 管理介面）以 Home Assistant add-on 形式打包，讓 HA 主機同時擔任 VPN 區網的中控伺服器。所有裝置用**未修改的官方 Tailscale client** 加入你自己的 `100.64.0.0/10` tailnet；資料面走 WireGuard P2P（公共 DERP 為 fallback），不經任何第三方服務、也不經 HA 主機。

## 加入商店（HAOS / HA Supervised）

1. 按上方 badge，或到 **Settings → Add-ons → Add-on Store → ⋮ → Repositories** 貼上：

   ```
   https://github.com/WOOWTECH/Woow_ha_vpn_headscale_package
   ```

2. 商店會出現 **Woow Headscale VPN**，點 **INSTALL**。第一版不提供預建 image，由 Supervisor 在本地 build（首次約 3–5 分鐘）。
3. 安裝後先看 **Configuration** 分頁設定 `server_url`，再 **START**。完整使用說明見 [`headscale/DOCS.md`](./headscale/DOCS.md)。

## 內含 add-on

| Slug | 名稱 | 說明 |
|------|------|------|
| [`woow-headscale`](./headscale) | Woow Headscale VPN | Headscale v0.29.3 control plane + Headplane v0.7.0 管理介面（單容器、s6-overlay 監督；GUI 走 HA Ingress、選配內建 ngrok tunnel） |

支援架構：`amd64`、`aarch64`。

## 架構重點

- **管理 GUI（Headplane）＝HA Ingress 唯一入口**：不開任何 host port，從 HA sidebar「Headscale VPN」點開即自動登入。管理面被 HA 帳號體系保護；要在外網用 GUI，走你既有的 HA 遠端存取管道（Nabu Casa Cloud、自家反代 HA 等）即可。
- **Control plane（host port 28080）是唯一需要對外曝露的 port**：區網內裝置直接連 `http://<HA_IP>:28080`；對外曝露走 (A) [Woow_ha_nginxpm](https://github.com/WOOWTECH/Woow_ha_nginxpm) 反代 + router 443，或 (B) 內建 ngrok tunnel（填 authtoken 即用）。教學見 [`headscale/DOCS.md`](./headscale/DOCS.md)。
- **備份即還原**：所有 VPN state（noise key、SQLite、API key、cookie secret）集中在 add-on data 目錄，HA backup 還原後整組 VPN 復活。

## 已知限制（第一版）

- **Control plane（port 28080）不能走 HA Ingress、也不能放 Cloudflare Tunnel 後面** — Tailscale control 協議（TS2021）的非標準 `Upgrade: tailscale-control-protocol` header 會被剥掉（[cloudflared#883](https://github.com/cloudflare/cloudflared/issues/883)、[#990](https://github.com/cloudflare/cloudflared/issues/990)）。可行曝露方案：router port-forward、Nginx/Caddy/Traefik 反代（需正確 Upgrade passthrough）、或 ngrok。詳見 DOCS.md。
- 第一版沒有 OIDC 選項（未來接 OpenClaw 登入再加）。
- Ingress shim 的重寫規則對 Headplane 版本敏感，請勿自行改裝其他 Headplane 版本。

## 對照文件與出處

- Add-on 使用說明：[`headscale/DOCS.md`](./headscale/DOCS.md)（zh-TW）
- 原始部署倉庫：[`WOOWTECH/Woow_vpn_headscale_package`](https://github.com/WOOWTECH/Woow_vpn_headscale_package) — K3s/Podman 版部署與研究文件（`docs/EXTERNAL-ACCESS.md` 曝露相容性實測、`docs/HAOS-ADDON-SETUP.md` 官方 Tailscale add-on 接入指南）；本 add-on 的 Headscale/Headplane 設定基準來自其 **podman 分支**
- 打包架構致謝：
  - [`AlessioBazzanella/homeassistant-headscale-addon`](https://github.com/AlessioBazzanella/homeassistant-headscale-addon)（MIT）— 檔案佈局、cont-init/tempio template 與 s6 服務組裝
  - [`yuriy1337/headscale-ha`](https://github.com/yuriy1337/headscale-ha) — HA Ingress nginx shim 與自動登入機制

## Licence

Add-on package: MIT — see `LICENSE`.
Headscale: BSD-3-Clause (juanfont/headscale). Headplane: BSD-3-Clause (tale/headplane).
