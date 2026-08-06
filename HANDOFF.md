# HANDOFF — Woow_ha_vpn_headscale_package：Headscale + Headplane HA Add-on 建置交接

> 交接來源：Cowork session（2026-08-06，研究分析已完成）
> 接手者：本機 Claude Code
> 目標倉庫：https://github.com/WOOWTECH/Woow_ha_vpn_headscale_package （已建立，目前僅 README）
> 語言慣例：文件用 zh-TW + English 技術詞；commit message 用英文

---

## 1. 任務目標

把 [WOOWTECH/Woow_vpn_headscale_package](https://github.com/WOOWTECH/Woow_vpn_headscale_package) **podman 分支**的 Headscale + Headplane stack 打包成 **Home Assistant add-on**，讓本倉庫成為可用 URL 加入 HA add-on 商店的來源。裝好後 HA 主機即為自架 VPN 區網的 control plane：所有裝置用**未修改的官方 Tailscale client** 加入 `100.64.0.0/10` tailnet。

倉庫定位遵循 WOOWTECH 重整規範：**repository.yaml 放根目錄 + add-on 子目錄**，版型比照已驗證上線的 [Woow_ha_n8n](https://github.com/WOOWTECH/Woow_ha_n8n)（2026-08-06 已在辦公室 HA 從商店安裝並穩定運行）。

## 2. 核心決策（已定案，不需重新討論）

| 項目 | 決策 |
|------|------|
| 打包形式 | **單一 add-on、單一容器**，s6-overlay 跑兩個 service（headscale + headplane 共享 localhost，Headplane 可 SIGHUP reload Headscale） |
| Headscale 版本 | **v0.29.3**（官方 .deb，2026-07-29 釋出，修 tagged-node 過期卡死與 auth 相關 bug；勿用 repo 內的 0.29.2） |
| Headplane 版本 | **v0.7.0**（multi-stage 從 `ghcr.io/tale/headplane:0.7.0` COPY `/app` 與 `/nodejs`） |
| Base image | `ghcr.io/hassio-addons/debian-base`（與 Headplane distroless 同 libc；arch: `amd64` + `aarch64`） |
| Port 佈局 | container 8080→host **28080**（control plane）、3000→**23000**（Headplane `/admin`）、9090→null（metrics 預設關）。沿用 podman 分支佈局，避開 HA 生態常撞的 8080 |
| 儲存 | `map:` `addon_config`→`/etc/headscale`（rw）、`data`→`/var/lib/headscale`（noise key + sqlite，自動進 HA backup） |
| Image 發佈 | 第一版 **不設 `image:` 欄位** → Supervisor 本地 build（辦公室 HA amd64、16GB，Odoo/n8n add-on 已驗證本地 build 可行）。GHCR CI 之後再補 |
| 架構參考 | **直接移植** [AlessioBazzanella/homeassistant-headscale-addon](https://github.com/AlessioBazzanella/homeassistant-headscale-addon)（打包的正是 Headscale 0.29.2 + Headplane 0.7.0，架構已跑通；MIT LICENSE，保留出處註記） |

## 3. 必讀來源材料

1. `Woow_vpn_headscale_package` **podman 分支**：`podman-compose.yml`（port/volume 佈局）、`deploy.sh`（7 步自動化＝add-on init 腳本的規格）、`config/headscale/config.yaml`（Headscale 設定基準）、`config/headplane/config.yaml`（注意檔頭註解的 v0.7.0 坑）。
2. `Woow_vpn_headscale_package` **main 分支 docs/**：`EXTERNAL-ACCESS.md`（曝露相容性矩陣）、`HAOS-ADDON-SETUP.md`（client 端接入 + 官方 add-on 陷阱）、`DEPLOYMENT-REPORT.md`（踩坑總表）→ 重點併入本 add-on 的 `DOCS.md`。
3. `AlessioBazzanella/homeassistant-headscale-addon` 的 `headscale/` 目錄全部：`config.yaml`（options/schema 設計）、`Dockerfile`（multi-stage 做法）、`build.yaml`、`rootfs/etc/cont-init.d/headscale.sh`（tempio render + Headplane override 保留機制）、`rootfs/etc/services.d/{headscale,headplane}/run`、`DOCS.md`、`apparmor.txt`、`translations/`。
4. `Woow_ha_n8n` 的目錄版型：`repository.yaml`、`n8n/{config.yaml,build.yaml,Dockerfile,addon_info.yaml,DOCS.md,CHANGELOG.md,rootfs,translations,test}`。

## 4. 要建的檔案結構

```
Woow_ha_vpn_headscale_package/
├── repository.yaml              # name: "WoowTech Home Assistant Add-ons — Headscale VPN"
├── README.md                    # 商店首頁說明 + 安裝 URL badge
└── headscale/
    ├── config.yaml              # add-on manifest（見 §5）
    ├── build.yaml               # amd64/aarch64 → ghcr.io/hassio-addons/debian-base
    ├── Dockerfile               # multi-stage：headplane image → debian-base + headscale .deb + yq + tempio template
    ├── DOCS.md                  # zh-TW 為主：設定說明、註冊流程、曝露方案、坑
    ├── CHANGELOG.md             # 0.1.0 起
    ├── README.md / addon_info.yaml / icon.png / logo.png
    ├── translations/en.yaml     # options 說明（可加 zh-Hant.yaml）
    └── rootfs/etc/
        ├── cont-init.d/headscale.sh          # options→tempio render、cookie secret、驗證
        └── services.d/
            ├── headscale/run                 # exec headscale serve
            └── headplane/run                 # 等 /health → 自動 apikey → node build/server/index.js
```

## 5. Add-on manifest 規格（headscale/config.yaml）

```yaml
name: "Woow Headscale VPN"
version: "0.1.0"
slug: "woow-headscale"
description: "Self-hosted Tailscale control plane (Headscale + Headplane) by WoowTech"
url: "https://github.com/WOOWTECH/Woow_ha_vpn_headscale_package"
webui: "http://[HOST]:[PORT:3000]/admin"
init: false
arch: [aarch64, amd64]
ports:
  8080/tcp: 28080
  3000/tcp: 23000
  9090/tcp: null
ports_description:
  8080/tcp: "Headscale control plane（client 註冊入口）"
  3000/tcp: "Headplane 管理介面 /admin"
  9090/tcp: "Metrics（預設關閉）"
map:
  - {type: addon_config, path: /etc/headscale, read_only: false}
  - {type: data, path: /var/lib/headscale}
options:
  server_url: "http://homeassistant.local:28080"
  log_level: "info"
  ipv4_prefix: "100.64.0.0/10"
  ipv6_prefix: "fd7a:115c:a1e0::/48"
  magic_dns_base_domain: "ts.local"
  headplane_enabled: true
  create_default_user: true
schema:
  server_url: url
  log_level: list(trace|debug|info|warn|error)
  ipv4_prefix: str
  ipv6_prefix: str
  magic_dns_base_domain: str
  headplane_enabled: bool
  create_default_user: bool
```

Headscale config template 以 podman 分支的 `config/headscale/config.yaml` 為基準（DERP 用公共 `controlplane.tailscale.com/derpmap/default`、sqlite、policy file mode、`unix_socket: /var/run/headscale/headscale.sock`），把 `server_url`/prefix/base_domain/log_level 換成 options 注入。

## 6. 啟動自動化（deploy.sh → add-on 的映射）

| deploy.sh 步驟 | add-on 實作位置 |
|----------------|----------------|
| load .env SERVER_URL + sed patch | `cont-init.d`：tempio 從 options render config |
| 產 cookie-secret（32 chars） | `cont-init.d`：不存在才生成，存 `/var/lib/headscale/.headplane_cookie_secret` |
| 起 headscale + 等 `/health` | `services.d/headscale/run`；headplane `run` 內 curl 輪詢 `/health`（60 次 × 1s） |
| `headscale users create default` | headscale service 起來後（`create_default_user: true` 時）idempotent 執行 |
| `apikeys create` → 寫給 Headplane | headplane `run`：key 檔不存在才 `headscale apikeys create --expiration 3650d`，`yq` 注入 config |
| 起 headplane | `exec /opt/nodejs/bin/node build/server/index.js` |
| 產測試 preauthkey | 不自動產；DOCS.md 教兩條路：Headplane UI 或 add-on terminal `headscale preauthkeys create --user 1 --reusable --expiration 72h` |

另外：`/var/run/headscale` 是 tmpfs，**每次啟動要 mkdir**（cont-init）；Dockerfile 加 `HEALTHCHECK curl -f http://127.0.0.1:8080/health`，config 開 `watchdog` 可後續評估。

## 7. 已知坑（必須寫進程式邏輯或 DOCS.md）

1. **`server_url` 網域 ≠ `dns.base_domain`**，否則 Headscale 拒啟動 → cont-init 驗證，兩者相同時 `bashio::exit.nok` 給中文錯誤訊息。
2. **Headplane v0.7.0 config 不能出現 `integration:` 區段**（`enabled: false` 也會驗證 `pod_name`）→ template 完全不產生該區段。
3. **Control plane 不能走 HA Ingress、也不能放 Cloudflare Tunnel 後面**（TS2021 noise 協議的非標準 `Upgrade: tailscale-control-protocol` header 會被剝掉，cloudflared#883/#990）。可行曝露：router port-forward + Nginx/Caddy/Traefik 反代（config 要 `proxy_http_version 1.1` + Upgrade passthrough、關 buffering）、ngrok http。Headplane 管理面倒是可以走 CF Tunnel。
4. **官方 Tailscale add-on（client 端）曾登入過其他 server 會 crash-loop**（`can't change --login-server without --force-reauth`）→ 解法：解除安裝→重裝清 `/data`，DOCS.md 要寫。
5. Alessio 版的 `cont-init.d/headscale.sh` 有一套「Headplane 改過的 DNS/OIDC 設定在重啟後保留」的 override diff 機制——**第一版可以整段簡化**（我們 options 少），但 `dns_records.json`（`dns.extra_records_path`，Headplane 熱更新用）要保留。
6. OIDC 相關 options 第一版**全部不做**（辦公室未來才接 OpenClaw 登入），保持 schema 精簡；Alessio 版留著當日後參考。

## 8. 驗收標準（辦公室 HA，amd64 HAOS/Supervised，16GB）

依 Woow_ha_odoo/n8n 的既有驗證流程，可用 woowtech ha mcp 操作（`ha_manage_addon` add repository/install/start、`ha_get_logs` 看 log、`ha_get_addon` 查狀態）：

1. Settings → Add-on Store → Repositories 加 `https://github.com/WOOWTECH/Woow_ha_vpn_headscale_package` → add-on 出現、本地 build 安裝成功。
2. Start 後：`curl http://<HA_IP>:28080/health` 回 200 `{"status":"pass"}`；`http://<HA_IP>:23000/admin` 回 302/200。
3. Add-on terminal：`headscale users list` 看到 `default`；`headscale preauthkeys create --user 1 --reusable --expiration 72h` 成功。
4. Headplane 用 log 裡輸出的 API key 登入成功。
5. 手機官方 Tailscale app：`login-server` 指 `http://<HA_IP>:28080`（先區網內測）→ 節點註冊成功、`headscale nodes list` 看得到、手機 ping 通 tailnet IP。
6. 重啟 add-on：資料保留（user/node 不丟）；HA backup 包含 `/var/lib/headscale`。
7. （第二階段，非本次 blocking）另一台 HAOS 用官方 Tailscale add-on 接入；外部曝露走 router port-forward 或反代 + HTTPS。

## 9. Git 執行注意

直接在本倉庫 `main` 開發（全新內容，無舊 branch 歷史要保留）。commit 拆小步：scaffold → Dockerfile/build → rootfs scripts → docs/translations → 驗收修正。完成後 README.md 補「加入商店」安裝說明與 my.home-assistant.io badge，並在 `Woow_vpn_headscale_package` main README 的分支導覽表加一列指向本倉庫（HA add-on 版）。

## 10. 建議起手 prompt（給 Claude Code）

> 讀本倉庫 HANDOFF.md 後開始執行。先 clone 參考庫：`AlessioBazzanella/homeassistant-headscale-addon`（架構移植來源）、`WOOWTECH/Woow_vpn_headscale_package` 的 podman 分支（設定基準）、`WOOWTECH/Woow_ha_n8n`（版型基準）。依 HANDOFF §4–§7 建出 add-on，Headscale 用 v0.29.3。完成後照 §8 驗收清單逐項驗證（可透過 woowtech ha mcp 操作辦公室 HA），任何偏離 §2 決策的地方先回報再改。
