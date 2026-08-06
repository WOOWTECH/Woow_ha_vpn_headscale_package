# Woow Headscale VPN — 使用說明

自架 Tailscale 中控伺服器（Headscale + Headplane 管理介面），封裝成 HA add-on。裝完之後 HA 主機就是你的 VPN control plane，所有裝置用**官方原版 Tailscale client** 加入你自己的 tailnet。

## 快速上手（5 分鐘）

1. **裝好、啟動** — Settings → Add-ons → Woow Headscale VPN → Install → Start。
2. **看 log 抓 API key** — 頁面切到 Log tab，找到形如：
   ```
   Headplane API key (use to log in at /admin):
     abc1234...
   ```
3. **登入 Headplane** — 瀏覽器打開 `http://<HA_IP>:23000/admin`，貼上 API key。
4. **產第一支 preauthkey** — Add-on Terminal（或 Headplane UI → Machines → New）執行：
   ```bash
   headscale preauthkeys create --user 1 --reusable --expiration 72h
   ```
5. **手機/電腦裝官方 Tailscale**，登入時把 `Login server` 指到 `http://<HA_IP>:28080`，貼 preauthkey。
6. `headscale nodes list` 或 Headplane UI 就會看到節點，tailnet IP 互 ping 得通。

## Options

| Option | 預設 | 說明 |
|--------|------|------|
| `server_url` | `http://homeassistant.local:28080` | client 連的 URL。**LAN 內測**放 HA 的 IP+28080；**外部曝露**改成 `https://<你的網域>`。這個網域必須跟 `magic_dns_base_domain` **不同**（Headscale 拒啟動）。|
| `log_level` | `info` | `trace / debug / info / warn / error` |
| `ipv4_prefix` | `100.64.0.0/10` | tailnet IPv4 範圍，改動前請確認沒撞到現有 subnet |
| `ipv6_prefix` | `fd7a:115c:a1e0::/48` | tailnet IPv6 範圍 |
| `magic_dns_base_domain` | `ts.local` | MagicDNS 尾綴（例如 `phone.ts.local`）。**不能等於 `server_url` 的網域** |
| `headplane_enabled` | `true` | 是否啟用 `/admin` 管理介面（關掉可省 ~150MB RAM，全靠 CLI 管理） |
| `create_default_user` | `true` | 首次啟動自動建 `default` user（idempotent，之後改為 false 也不會刪） |

## Port 配置

| Container | Host | 用途 | 對外曝露可行？ |
|-----------|------|------|----------------|
| `8080` | `28080` | Headscale control plane（client 註冊入口） | ✅ router port-forward / 反代（要 upgrade passthrough）／ngrok — ❌ **CF Tunnel、HA Ingress**（見下方坑 3） |
| `3000` | `23000` | Headplane `/admin` 管理介面 | ✅ 任意 HTTPS 前端都行（CF Tunnel / Ingress / 反代）|
| `9090` | — | Metrics（預設關閉） | 需要時把 `null` 改成 port 號 |

## 對外曝露（Expose to the internet）

**Control plane（28080）能過的方案：**

1. **Router port-forward + DDNS + TLS** — 最傳統，最穩。前面接個 Nginx/Caddy/Traefik 補 HTTPS，反代設定要有：
   ```nginx
   proxy_http_version 1.1;
   proxy_set_header Upgrade $http_upgrade;
   proxy_set_header Connection $http_upgrade;
   proxy_buffering off;
   proxy_request_buffering off;
   ```
2. **ngrok http 28080** — 一行指令、有 HTTPS、免申請憑證，缺點是免費版重啟換 URL。
3. **Tailscale Funnel** — 反諷但可行，如果本機已經有另一台已加入 tailnet 的機器可以做 relay。

**Headplane（23000）** 沒特殊限制，Cloudflare Tunnel、HA Ingress、任何反代都可以。

## 已知坑（**必讀**）

1. **`server_url` 網域 ≠ `magic_dns_base_domain`**  
   Headscale 遇到相同會拒啟動。cont-init 會在啟動前擋下並印中文錯誤，不會浪費你 debug 時間。

2. **不要把 control plane 放 Cloudflare Tunnel 後面**  
   Tailscale noise 協議（TS2021）用了非標準 header `Upgrade: tailscale-control-protocol`，cloudflared 會剝掉這個 header（cloudflared issue #883/#990），client 連線一定失敗。**Headplane 走 CF Tunnel 沒事**（純 HTTP）。

3. **官方 Tailscale add-on（client 端）曾登入過其他 server 會 crash-loop**  
   訊息像 `can't change --login-server without --force-reauth`。解法：**Uninstall → 重裝**（清 `/data` 才乾淨），然後改用新的 `login-server`。

4. **Headplane v0.7.0 config 不能出現 `integration.kubernetes:` 區段**  
   本 add-on 產生的 template 只用 `integration.proc`（同容器 SIGHUP reload headscale），已排掉 kubernetes。如果你手動改了 `/addon_configs/xxx_woow-headscale/config.yaml` 加入 kubernetes 區段，Headplane 會 crash。

5. **DNS 記錄由 Headplane 熱更新**  
   `/etc/headscale/dns_records.json` 由 Headplane 寫入，headscale 熱 reload，不需要重啟 add-on。config 裡 `dns.*` 的改動會被 cont-init 保留在 override 檔（`/var/lib/headscale/.headplane_overrides.yaml`），下次改 options 重啟也不會被蓋掉。

6. **本版尚未支援 OIDC 登入**  
   辦公室未來接 OpenClaw SSO 才會加。目前 Headplane 一律用 API key 登入。

## 資料 & 備份

| 路徑 | 內容 | 進 HA backup？ |
|------|------|----------------|
| `/etc/headscale/` (= `/addon_configs/<slug>/`) | `config.yaml`、`policy.json`、`dns_records.json` | ✅ 自動 |
| `/var/lib/headscale/` | sqlite DB、noise private key、cookie secret、api key、override diff | ✅ 自動（HA add-on `data` map） |
| `/var/lib/headscale/*/logs` | 執行 log | ❌ 被 `backup_exclude` 排除 |

**noise_private.key 換過就等於重建 tailnet**：所有節點要重登。所以備份很重要，別亂刪 `data` volume。

## CLI 快查表（Add-on Terminal）

```bash
# 使用者
headscale users list
headscale users create alice

# preauthkey（讓裝置註冊用）
headscale preauthkeys create --user 1 --reusable --expiration 72h
headscale preauthkeys list --user 1

# 節點
headscale nodes list
headscale nodes expire  --identifier 5
headscale nodes delete  --identifier 5
headscale nodes rename  --identifier 5 --new-name laptop

# 手動再開一支 Headplane API key（假設要換）
headscale apikeys create --expiration 3650d
```

## 疑難排解

**Log 有 `server_url domain equals base_domain`** → 見坑 1。改 options 其中一個。

**Client 連 `28080` 一直 timeout** → 防火牆 / port-forward 沒開；或走了 CF Tunnel（見坑 2）。

**Headplane `/admin` 打不開** → 檢查 log；先確認 headscale `/health` 有回 200，Headplane 一定會晚 5–20s 才起（等 /health + 建 api-key）。

**手機裝過其他 Headscale/Tailscale server 現在裝這個會 crash** → 見坑 3。

## 相依 upstream 版本

- Headscale: **v0.29.3**（2026-07-29，修 tagged-node expiry 卡死）
- Headplane: **v0.7.0**
- Base image: `ghcr.io/hassio-addons/debian-base:9.3.0`

## 授權與致謝

MIT。架構移植自 [`AlessioBazzanella/homeassistant-headscale-addon`](https://github.com/AlessioBazzanella/homeassistant-headscale-addon)（MIT），podman 部署參考自 [`WOOWTECH/Woow_vpn_headscale_package`](https://github.com/WOOWTECH/Woow_vpn_headscale_package)。
