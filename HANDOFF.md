# HANDOFF — Woow_ha_vpn_headscale_package：Headscale + Headplane HA Add-on 建置交接

> 交接來源：Cowork session（2026-08-06 研究、2026-08-07 曝露架構定案，v2）
> 接手者：本機 Claude Code
> 目標倉庫：https://github.com/WOOWTECH/Woow_ha_vpn_headscale_package （已建立，目前僅 README + 本文件）
> 語言慣例：文件用 zh-TW + English 技術詞；commit message 用英文

---

## 1. 任務目標

把 [WOOWTECH/Woow_vpn_headscale_package](https://github.com/WOOWTECH/Woow_vpn_headscale_package) **podman 分支**的 Headscale + Headplane stack 打包成 **Home Assistant add-on**，讓本倉庫成為可用 URL 加入 HA add-on 商店的來源。裝好後 HA 主機即為自架 VPN 區網的 control plane：所有裝置用**未修改的官方 Tailscale client** 加入 `100.64.0.0/10` tailnet。

倉庫定位遵循 WOOWTECH 重整規範：**repository.yaml 放根目錄 + add-on 子目錄**，版型比照已驗證上線的 [Woow_ha_n8n](https://github.com/WOOWTECH/Woow_ha_n8n)（2026-08-06 已在辦公室 HA 從商店安裝並穩定運行）。

## 2. 核心決策（已定案，不需重新討論）

| 項目 | 決策 |
|------|------|
| 打包形式 | **單一 add-on、單一容器**，s6-overlay 跑多個 service：headscale、headplane、nginx（ingress shim）、ngrok（選配） |
| Headscale 版本 | **v0.29.3**（官方 .deb，2026-07-29 釋出；勿用 repo 內的 0.29.2） |
| Headplane 版本 | **v0.7.0**（multi-stage 從 `ghcr.io/tale/headplane:0.7.0` COPY `/app` 與 `/nodejs`）。⚠️ 不可退回 0.6.x——headscale 0.29 需要 headplane 0.7.0（0.7.0 release notes 明載支援 0.29 的 registration keys / capability detection） |
| Base image | `ghcr.io/hassio-addons/debian-base`（與 Headplane distroless 同 libc；arch: `amd64` + `aarch64`） |
| **GUI 入口** | **HA Ingress 為唯一入口**，採 [yuriy1337/headscale-ha](https://github.com/yuriy1337/headscale-ha) 的 shim 方案**移植到 Headplane 0.7.0**（詳 §6A）。GUI **不開 host port**（ingress-only 安全模型：管理面被 HA 帳號體系保護，且經 HA 遠端存取管道即可在外網開 GUI） |
| **Control plane 曝露** | 兩條並存：**基本路徑**＝直開 host port **28080**（container 8080），使用者自行反代（Woow_ha_nginxpm + router 443，或其他）；**選配路徑**＝**內建 ngrok service**（`ngrok_authtoken` 欄位），啟用時自動建立對外 tunnel 並把 public URL 注入 `server_url`（詳 §6B） |
| Port 佈局 | 8080→host 28080（control plane）、9090→null（metrics 預設關）、50443→null（gRPC remote CLI 選配）。**3000 不進 ports**（ingress-only） |
| 儲存 | `map:` `addon_config`→`/etc/headscale`（rw）、`data`→`/var/lib/headscale`（noise key + sqlite + api_key + cookie secret 全收在此 → backup 還原＝整組 VPN 復活，比照 yuriy 的 state 集中模型） |
| Image 發佈 | 第一版 **不設 `image:` 欄位** → Supervisor 本地 build（辦公室 HA amd64、16GB，Odoo/n8n 已驗證）。GHCR CI 之後再補 |
| 架構參考 | 服務組裝參考 [AlessioBazzanella/homeassistant-headscale-addon](https://github.com/AlessioBazzanella/homeassistant-headscale-addon)（headscale 0.29.2 + headplane 0.7.0 同版本組合）；**ingress shim 與自動登入參考 yuriy1337/headscale-ha**（headscale 0.28 + headplane 0.6.2-beta，pattern 需移植驗證）；兩者皆註明出處 |

## 3. 必讀來源材料

1. `Woow_vpn_headscale_package` **podman 分支**：`podman-compose.yml`（port/volume 佈局）、`deploy.sh`（7 步自動化＝init 腳本規格）、`config/headscale/config.yaml`、`config/headplane/config.yaml`（注意檔頭註解的 v0.7.0 坑）。
2. `Woow_vpn_headscale_package` **main 分支 docs/**：`EXTERNAL-ACCESS.md`（曝露相容性矩陣：ngrok http ✅、ngrok tcp ✅(http only)、CF Tunnel ❌）、`HAOS-ADDON-SETUP.md`、`DEPLOYMENT-REPORT.md` → 重點併入本 add-on 的 `DOCS.md`。
3. `AlessioBazzanella/homeassistant-headscale-addon` 的 `headscale/`：`config.yaml`（options/schema）、`Dockerfile`（multi-stage）、`rootfs/etc/cont-init.d/headscale.sh`（tempio render）、`rootfs/etc/services.d/{headscale,headplane}/run`、`rootfs/usr/share/tempio/*.gtpl`、`DOCS.md`。
4. **`yuriy1337/headscale-ha` 的 `headscale/`（ingress 方案本體）**：`Dockerfile`（對 headplane build 產物的 sed basename patch）、`rootfs/etc/nginx/nginx.conf`（`%%INGRESS_ENTRY%%` shim 全文：sub_filter 規則、fetch interceptor、`/_ha_key` 自動登入）、`rootfs/etc/s6-overlay/s6-rc.d/`（init 順序與 ingress entry 代入）、`config.yaml`（ingress 欄位 + ports 只開 8080 的安全模型）。
5. `Woow_ha_n8n`：倉庫版型基準。

## 4. 要建的檔案結構

```
Woow_ha_vpn_headscale_package/
├── repository.yaml
├── README.md                    # 商店首頁說明 + 安裝 URL badge
├── HANDOFF.md                   # 本文件
└── headscale/
    ├── config.yaml              # add-on manifest（§5）
    ├── build.yaml               # amd64/aarch64 → ghcr.io/hassio-addons/debian-base
    ├── Dockerfile               # multi-stage + sed basename patch + nginx + ngrok binary
    ├── DOCS.md / CHANGELOG.md / README.md / addon_info.yaml / icon.png / logo.png
    ├── translations/en.yaml     #（可加 zh-Hant.yaml）
    └── rootfs/
        ├── etc/nginx/nginx.conf              # ingress shim（自 yuriy 版移植，§6A）
        └── etc/
            ├── cont-init.d/headscale.sh      # options→tempio render、cookie secret、%%INGRESS_ENTRY%% 代入、驗證
            └── services.d/
                ├── headscale/run             # （ngrok 啟用時先等 URL）exec headscale serve
                ├── headplane/run             # 等 /health → 自動 apikey → node（listen 127.0.0.1:3001）
                ├── nginx/run                 # ingress shim（listen :3000 = ingress_port）
                └── ngrok/run                 # 選配（§6B）
```

## 5. Add-on manifest 規格（headscale/config.yaml）

```yaml
name: "Woow Headscale VPN"
version: "0.1.0"
slug: "woow-headscale"
description: "Self-hosted Tailscale control plane (Headscale + Headplane) by WoowTech"
url: "https://github.com/WOOWTECH/Woow_ha_vpn_headscale_package"
init: false
startup: services
arch: [aarch64, amd64]
ingress: true
ingress_port: 3000            # nginx shim；Headplane 實際跑 127.0.0.1:3001
panel_title: "Headscale VPN"
panel_icon: mdi:vpn
ports:
  8080/tcp: 28080             # control plane —— 使用者反代指到這裡
  9090/tcp: null
  50443/tcp: null
ports_description:
  8080/tcp: "Headscale control plane（tailscale login-server／反代目標）"
  9090/tcp: "Metrics（預設關閉）"
  50443/tcp: "gRPC remote CLI（需有效 TLS，預設關閉）"
map:
  - {type: addon_config, path: /etc/headscale, read_only: false}
  - {type: data, path: /var/lib/headscale}
options:
  server_url: "http://homeassistant.local:28080"
  log_level: "info"
  ipv4_prefix: "100.64.0.0/10"
  ipv6_prefix: "fd7a:115c:a1e0::/48"
  magic_dns_base_domain: "ts.local"
  create_default_user: true
  ngrok_enabled: false
  ngrok_authtoken: ""
  ngrok_mode: "http"
  ngrok_domain: ""
schema:
  server_url: url
  log_level: list(trace|debug|info|warn|error)
  ipv4_prefix: str
  ipv6_prefix: str
  magic_dns_base_domain: str
  create_default_user: bool
  ngrok_enabled: bool
  ngrok_authtoken: password?
  ngrok_mode: list(http|tcp)
  ngrok_domain: str?
```

（headplane_enabled 選項移除——GUI 是本 add-on 核心體驗，恆開；Headscale config template 以 podman 分支為基準：公共 DERP、sqlite、policy file mode、unix_socket。）

## 6. 兩大移植工程

### 6A. GUI Ingress（yuriy shim → Headplane 0.7.0）

機制三層，逐一移植並重驗（yuriy 驗證基準是 headplane **0.6.2-beta.5**，0.7.0 重構過 build/auth，sed 與 sub_filter 規則**必須逐條對照新產物調整**）：

1. **Dockerfile sed patch**：掃 `/opt/headplane/build` 的 `*.js`/`*.html`，`s|/admin/|/|g; s|"/admin"|"/"|g` 把 basename 拔到根路徑。對 0.7.0 需先 dump build 產物確認 pattern 是否仍長這樣（特別注意 Ghostty WASM 資產與新 auth 路由）。
2. **nginx shim**（listen :3000＝ingress_port，proxy → 127.0.0.1:3001）：整份照抄 yuriy 的 `nginx.conf` 再調整——`absolute_redirect off`；`proxy_redirect / %%INGRESS_ENTRY%%/`；`proxy_set_header Accept-Encoding ""`（sub_filter 前提）；sub_filter 重寫 `href/src/action/url()/"​/assets/"/"basename":"/"` → `%%INGRESS_ENTRY%%/`；`<head>` 注入 fetch interceptor（處理 React Router `__manifest` 的 paths 參數防 double-prefix）；`proxy_hide_header X-Frame-Options` + `SAMEORIGIN`（iframe 內嵌）。`%%INGRESS_ENTRY%%` 由 cont-init 以 `bashio::addon.ingress_entry` 代入。
3. **`/_ha_key` 自動登入**：Headplane 的 API key 落檔（`/var/lib/headscale/`），nginx `location = /_ha_key` alias 提供（`Cache-Control no-store`）；注入 script 在 login 頁自動抓 key POST 登入 → 從 HA sidebar 點開即進站。因 GUI 無 host port，`/_ha_key` 天然只能經 ingress（HA 已驗證身分）到達。

**風險備案**：0.7.0 移植若卡關，fallback＝把 GUI 暫時加回 host port（`3000/tcp: 23000` + `webui:`）出貨 v0.1，ingress 掛 v0.1.x 跟進——不要讓 shim 阻塞整個 add-on 上線。

### 6B. 內建 ngrok（選配 token 欄位）

- Dockerfile 裝 ngrok v3 static binary（amd64/aarch64）。
- `services.d/ngrok/run`：`ngrok_enabled` 才啟動；`ngrok_mode: http` → `ngrok http 8080`（`ngrok_domain` 有值加 `--domain`，paid reserved domain＝URL 固定）；`ngrok_mode: tcp` → `ngrok tcp 8080`（raw passthrough，隨機 `N.tcp.ngrok.io:port`，無有效 TLS → login-server 用 `http://`，**測試用途**；podman 分支已實測可通）。
- **啟動順序（關鍵耦合）**：ngrok service 先起 → `services.d/headscale/run` 輪詢 `127.0.0.1:4040/api/tunnels` 拿 `public_url` →（http 模式取 `https://…`；tcp 模式把 `tcp://host:port` 轉 `http://host:port`）→ 覆寫 render 出的 `server_url` → 才 `exec headscale serve`；Headplane 的 `headscale.public_url` 同步注入。`ngrok_enabled: false` 時直接用 options 的 `server_url`。
- 啟動完成後把最終 login-server URL 用 `bashio::log.info` 大字輸出（使用者複製給 `tailscale up` 用）。
- DOCS.md 營運警告：**free tier URL 重啟即變＝所有已註冊裝置 login-server 失聯、需逐台重新註冊**——正式環境用 paid reserved domain（http 模式）或改走基本反代路徑。

## 7. 已知坑（必須寫進程式邏輯或 DOCS.md）

1. **`server_url` 網域 ≠ `dns.base_domain`**，否則 Headscale 拒啟動 → cont-init 驗證（注意 ngrok 動態 URL 也要跟 base_domain 比對）。
2. **Headplane v0.7.0 config 不能出現 `integration:` 的 kubernetes 區段**；本設計用 `integration.proc.enabled: true`（同容器 SIGHUP reload，Alessio 版同款）。
3. **Control plane 不能走 HA Ingress、不能放 Cloudflare Tunnel 後面**（TS2021 noise 的非標準 Upgrade header 會被剝，cloudflared#883/#990、2026-07 實測 ❌）。可行：直開 port + 反代（`proxy_http_version 1.1` + Upgrade passthrough + buffering off）、ngrok http/tcp。
4. **官方 Tailscale add-on（client 端）曾登入過其他 server 會 crash-loop** → 解除安裝→重裝清 `/data`。
5. `/var/run/headscale` 是 tmpfs，每次啟動 mkdir；Dockerfile `HEALTHCHECK curl -f http://127.0.0.1:8080/health`。
6. **sub_filter/sed 規則版本敏感**：升級 Headplane 版本時 ingress shim 要整組回歸測試——CHANGELOG 註明此依賴，headplane 版本 bump 一律附 ingress 驗收（§8-2）。
7. OIDC 第一版全部不做（未來接 OpenClaw 再加），schema 保持精簡。

## 8. 驗收標準（辦公室 HA，amd64 HAOS/Supervised，16GB）

可用 woowtech ha mcp 操作（`ha_manage_addon`、`ha_get_logs`、`ha_get_addon`）：

1. 加 repository URL → add-on 出現、本地 build 安裝成功、start 後 `curl http://<HA_IP>:28080/health` 回 200。
2. **Ingress 驗收**：HA sidebar 點「Headscale VPN」→ 自動登入 Headplane（免手動貼 API key）→ 逐頁點 Machines / Users / DNS / ACL / Settings，client-side 換頁不逃出 ingress 路徑、assets 無 404、無 double-prefix。
3. **安全模型驗收**：`<HA_IP>:3000` 與 `:23000` 連不上（GUI 無 host port）；`/_ha_key` 從外部不可達。
4. Add-on terminal：`headscale users list` 有 `default`；`preauthkeys create` 成功。
5. 手機官方 Tailscale app 經 `http://<HA_IP>:28080` 區網內註冊成功、互 ping 通。
6. **ngrok 驗收**：填 authtoken + `ngrok_enabled: true` → log 輸出外網 URL → 手機走 4G 經該 URL 註冊成功（http 模式）；`ngrok_mode: tcp` 亦跑一輪（http:// login-server）。
7. 重啟 add-on 資料保留；HA backup 含 `/var/lib/headscale`，還原後節點全在。
8. （第二階段）Woow_ha_nginxpm 反代 + router 443 的正式曝露路徑實測。

## 9. Git 執行注意

直接在本倉庫 `main` 開發。commit 拆小步：scaffold → Dockerfile/build → headscale/headplane services → ingress shim → ngrok service → docs/translations → 驗收修正。完成後 README 補安裝說明與 badge，並在 `Woow_vpn_headscale_package` main README 分支導覽表加一列指向本倉庫。

## 10. 網路架構總覽

```
                        Internet
                           |
          +----------------+------------------+
          |（基本）router 443 → Woow_ha_nginxpm |（選配）ngrok tunnel
          |  反代 → HA:28080                   |  http: https://xxx.ngrok.app
          |                                    |  tcp:  tcp://N.tcp.ngrok.io:P
          +----------------+------------------+
                           |
  [Woow Headscale VPN add-on 容器]（s6-overlay）
    headscale   127.0.0.1:8080 ── host 28080
    headplane   127.0.0.1:3001（無 host port）
    nginx shim  :3000 ←── HA Ingress（sidebar，自動登入）
    ngrok       選配，只出站，URL 自動注入 server_url
                           |
   手機/筆電：官方 Tailscale app ── tailscale up --login-server=<URL>
   其他 HAOS：官方 Tailscale add-on（login_server 指過來）
                           |
   資料面：WireGuard P2P（UDP 41641 裝置間）＋公共 DERP fallback
           —— 不經過 add-on，HA 端不需開任何 UDP port
```

## 11. 建議起手 prompt（給 Claude Code）

> 讀本倉庫 HANDOFF.md 後開始執行。先 clone 參考庫：`yuriy1337/headscale-ha`（ingress shim 本體）、`AlessioBazzanella/homeassistant-headscale-addon`（服務組裝）、`WOOWTECH/Woow_vpn_headscale_package` podman 分支（設定基準）、`WOOWTECH/Woow_ha_n8n`（版型）。依 §4–§7 建置：Headscale v0.29.3、Headplane 0.7.0、ingress shim 依 §6A 移植（先 dump headplane 0.7.0 build 產物驗 sed/sub_filter pattern）、ngrok 依 §6B。完成後照 §8 逐項驗收（可透過 woowtech ha mcp 操作辦公室 HA）。§6A 移植卡關就走 fallback（GUI 暫回 host port）先出 v0.1，不要阻塞上線。任何偏離 §2 決策先回報再改。
