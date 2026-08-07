# HANDOFF — Woow_ha_vpn_headscale_package（as-built 現狀 → 本機 Claude Code 接手）

> 版本：v3（as-built，2026-08-07）。取代先前 v2 建置規格（仍在 git 歷史）。
> 來源：Cowork session（已用 multi-agent workflow 產出、審查、推 GitHub、並在辦公室 HA 實機 build + 啟動測試通過）。
> 接手者：本機 Claude Code。
> 回收：本機完成「推送/確認 + 乾淨重裝」後，回 Cowork 由 Claude 執行 §5 全面測試。
> 語言：文件 zh-TW + English 技術詞；commit message 英文。

---

## 0. TL;DR

- 倉庫 `WOOWTECH/Woow_ha_vpn_headscale_package` main 已是**完整、審查過、實機跑通**的 add-on。HEAD = `cfaa8d0`。
- 辦公室 HA 上 `5ad331fe_woow-headscale` **已本地 build 成功並 `started`**：headscale v0.29.3 health 200、Headplane 0.7.0 連上、nginx ingress shim 服務中、ngrok 選配正確停用、default user + API key 自動建立。
- **本機你要做的**：clone → 確認與 remote 一致（Cowork 是用 GitHub MCP 推的，本機請正常 `git push` 驗證能力）→（選）打 tag / 補 CI → 對辦公室 HA 做一次乾淨重裝 → 跑 §4 啟動驗收 → 回報。
- **不要動的東西**在 §6，尤其 apparmor capability 區塊與 nginx `allow 172.30.32.2; deny all;`——動了會壞。

---

## 1. 倉庫現狀

Commit（新→舊，全部經 GitHub MCP 推送；Cowork 的 git proxy 不給本倉庫注憑證，故 `git push` 在 Cowork 端不通，本機端應可正常 push）：

```
cfaa8d0  fix(apparmor): grant nginx capabilities (chown/setuid/setgid)   ← HEAD
0ab3000  fix(nginx): run ingress shim workers as root (no CAP_CHOWN)
bae5368  docs: ingress+ngrok-aware README, DOCS, CHANGELOG (zh-TW)
728b865  feat: nginx HA Ingress shim template (source-IP locked)
aef69bc  feat: ingress+ngrok add-on runtime & manifest (reviewed, hardened)
59773915 docs: HANDOFF v2（建置規格，已被本文件取代）
```

檔案樹：

```
Woow_ha_vpn_headscale_package/
├── repository.yaml
├── README.md                 # 商店首頁 + my.home-assistant.io badge
├── LICENSE                   # MIT（保留自初始 scaffold）
├── HANDOFF.md                # 本文件
└── headscale/
    ├── config.yaml           # add-on manifest（as-built，見 §2）
    ├── build.yaml            # amd64/aarch64 → ghcr.io/hassio-addons/debian-base:9.3.0
    ├── Dockerfile            # multi-stage：headplane 0.7.0 COPY + headscale 0.29.3 .deb + yq + ngrok v3 + sed patch(含 grep guard)
    ├── apparmor.txt          # ⚠️ 含 capability 區塊（§3、§6）——關鍵，勿刪
    ├── addon_info.yaml       # 版本追蹤 metadata（renovate 風格）
    ├── DOCS.md               # zh-TW 完整使用說明（架構/port/曝露/註冊/備份/troubleshoot）
    ├── CHANGELOG.md          # 0.1.0
    ├── README.md
    ├── translations/{en.yaml, zh-Hant.yaml}
    └── rootfs/
        ├── etc/nginx/ingress.conf.tpl            # HA Ingress shim 模板（§3、§6，版本綁定）
        ├── etc/cont-init.d/headscale.sh          # options→tempio render + 驗證 + cookie secret + ingress entry 代入
        └── etc/services.d/{headscale,headplane,nginx,ngrok}/{run,type}   # s6 legacy longrun
        └── usr/share/tempio/{headscale.config.gtpl, headplane.config.gtpl}
```

---

## 2. As-built 規格（不要偏離，除非測試發現需要）

| 項目 | 值 |
|------|-----|
| slug | `woow-headscale`（HA 上完整 slug：`5ad331fe_woow-headscale`） |
| version | `0.1.0` |
| arch | `aarch64`, `amd64`；`init: false`；`startup: services` |
| ingress | `true`，`ingress_port: 3000`，`panel_title: "Headscale VPN"`，`panel_icon: mdi:vpn`；GUI **無 host port** |
| ports | `8080/tcp:28080`（control plane，唯一曝露）、`9090/tcp:null`（metrics）、`50443/tcp:null`（gRPC）。**3000 不進 ports** |
| map | `addon_config→/etc/headscale`（rw）、`data→/var/lib/headscale`；`backup: cold`；`backup_exclude: ["*/logs"]` |
| 元件版本 | Headscale **v0.29.3**（官方 .deb）、Headplane **0.7.0**（`ghcr.io/tale/headplane:0.7.0` COPY `/app`+`/nodejs`）、base `ghcr.io/hassio-addons/debian-base:9.3.0` |
| options | `server_url`(url) / `log_level` / `ipv4_prefix` / `ipv6_prefix` / `magic_dns_base_domain` / `create_default_user`(bool) / `ngrok_enabled`(bool) / `ngrok_authtoken`(password?) / `ngrok_mode`(http\|tcp) / `ngrok_domain`(str?) |

容器內服務佈局（s6-overlay 單容器多 longrun）：

```
headscale   0.0.0.0:8080  ── 映射 host 28080（control plane）＋ metrics 9090
headplane   127.0.0.1:3001（無 host port）
nginx shim  0.0.0.0:3000  ←── HA Ingress（僅 allow 172.30.32.2）→ proxy 127.0.0.1:3001
ngrok       選配（ngrok_enabled=false 時 s6-svc -O 自停）
```

關鍵路徑：API key `/var/lib/headscale/.headplane_api_key`（nginx `/_ha_key` 供自動登入）、cookie secret `/var/lib/headscale/.headplane_cookie_secret`、DNS 熱更新 `/etc/headscale/dns_records.json`、unix socket `/var/run/headscale/headscale.sock`（tmpfs，cont-init 每次 mkdir）。

---

## 3. 兩個「部署期實機修正」的根因（務必理解，別回退）

實機 build 成功但頭兩次啟動 nginx crash-loop，根因診斷如下——**這兩個修正是這個 add-on 能跑的關鍵，勿刪勿改**：

**(A) apparmor 少 capability（commit `cfaa8d0`）**
HA add-on 只要 `apparmor.txt` 存在就會 enforce；enforced profile **未列出的 capability 一律 deny**。原 profile 一條 capability 都沒有 → nginx（root 起、要切 worker 身分 + chown temp 目錄）直接 EPERM crash。headscale/headplane 不需 cap 所以沒事。
修法：`apparmor.txt` 補
```
capability chown,
capability setuid,
capability setgid,
capability dac_override,
capability net_bind_service,
```

**(B) nginx worker 以 root 執行（commit `0ab3000`）**
`ingress.conf.tpl` 頂部 `user root;`。HA 容器無多餘特權，internal shim 只 proxy 127.0.0.1、只經 ingress 進來，root worker 可接受；搭配 (A) 的 caps 才不會 EPERM。

診斷軌跡（給你對照，別再踩）：
```
無 (A)：[emerg] chown("/var/lib/nginx/body", 65534) failed (1: Operation not permitted)
加 user root 但無 (A)：[emerg] initgroups(root, 0) failed (1: Operation not permitted)
(A)+(B) 齊：nginx 正常啟動，無 emerg
```

---

## 4. 本機 Claude Code 任務

### 4.1 取得與確認
```bash
git clone https://github.com/WOOWTECH/Woow_ha_vpn_headscale_package.git
cd Woow_ha_vpn_headscale_package
git log --oneline -6        # 確認 HEAD = cfaa8d0（本 HANDOFF v3 commit 會在其上），與 §1 一致
```
- 若你在本機做任何修改，正常 `git push origin main`（本機憑證應可推；Cowork 端不行才走 MCP）。
- 建議（選）：打 release tag `v0.1.0`；未來要 GHCR 預建 image 再補 `.github/workflows` 與 config.yaml 的 `image:` 欄位（第一版刻意用本地 build，勿急）。

### 4.2 對辦公室 HA 乾淨重裝
辦公室 HA：amd64 HAOS 18.1、Supervisor 2026.07.5、Core 2026.4.2。目前已裝著跑通版本；若你有推新 commit，用「移除倉庫→重加→重裝」強制 Supervisor 重新 clone（`rebuild` 會用到 stale store 快取，別只 rebuild）：
```
1) 停 + 解除安裝 add-on：slug 5ad331fe_woow-headscale
2) 移除 store repository：5ad331fe
3) 重新加入 repository：https://github.com/WOOWTECH/Woow_ha_vpn_headscale_package
4) install（本地 build 約 3–5 分鐘）
5) start
```
（用 HA UI 或 Woowtech HA MCP 的 `ha_manage_addon` 均可。）

### 4.3 啟動驗收 checklist（log 應長這樣才算過）
看 add-on Log（Supervisor source），逐項確認：
- [ ] cont-init：`Rendering Headscale/Headplane configuration` + `Rendering nginx ingress shim (ingress entry: /api/hassio_ingress/…)` + `Configuration generation complete`，`exited 0`
- [ ] headscale：`starting headscale … version=v0.29.3` → `listening and serving HTTP on: 0.0.0.0:8080` → `/health … status=200`
- [ ] 自動化：`建立預設 user 'default'` → `User created` → `簽發 Headplane 用的 Headscale API key`
- [ ] headplane：`Connected to Headscale 0.29.3` + `Using Proc integration` + `Listening on http://127.0.0.1:3001`
- [ ] nginx：只出現一次 `Starting nginx ingress shim (0.0.0.0:3000 -> 127.0.0.1:3001)`，**且無任何 `[emerg]` / `Operation not permitted`**
- [ ] ngrok：`ngrok 未啟用（'ngrok_enabled: false'），停用 ngrok service`
- [ ] add-on `state: started`
- [ ] 從 HA sidebar 點「Headscale VPN」→ 直接進 Headplane（自動登入、免貼 key），逐頁 Machines/Users/DNS/ACL/Settings 換頁不逃出 ingress 路徑、assets 無 404

### 4.4 回報
把 4.3 每項打勾/不過，附上 add-on 啟動 log（尤其 nginx 那段）與 sidebar 是否成功進站的截圖或描述，回 Cowork。有任何偏離 §2 as-built 的改動先講。

---

## 5. 全面測試計畫（回 Cowork 後由 Claude 執行，可透過 Woowtech HA MCP）

分六面，逐項驗：

1. **啟動 / 服務健康**：§4.3 全綠；`restart` 一次資料保留、無 emerg。
2. **Ingress 安全模型**：`<HA_IP>:3000` / `:23000` 從 LAN 連不上（GUI 無 host port）；非 172.30.32.2 來源打 shim 得 403（門禁生效）；sidebar（172.30.32.2）可進站。
3. **Headplane 功能**：建 user、建 pre-auth key（`--user` 用數字 ID）、看 Machines/DNS/ACL 頁；DNS 改動經 proc SIGHUP 熱生效。
4. **裝置註冊（實機）**：一支手機官方 Tailscale app（區網 `http://<HA_IP>:28080`）註冊成功、拿到 100.64.x.x、`headscale nodes list` 看得到、ping 通；（選）另一台 HAOS 官方 Tailscale add-on 接入。
5. **ngrok 選配**：填 authtoken + `ngrok_enabled: true` → log 大字輸出外網 URL、`server_url` 被覆寫 → 手機走 4G 經該 URL 註冊；`tcp` 模式各跑一輪。⚠️ free tier URL 重啟會變、TCP 需綁卡（DOCS §8B）。
6. **備份 / 還原**：HA backup 含 `/var/lib/headscale` → 還原後 user/node 全在、`server_url` 不變則 client 無感。

> 給本機的提醒：**測試前把 add-on 保持在乾淨預設**（`ngrok_enabled: false`、`server_url` 用預設或 `http://<HA_IP>:28080`），別先接大量真實裝置，讓 Cowork 這邊從已知狀態開跑。

---

## 6. 不要動 / 已知坑

- **apparmor.txt 的 capability 區塊**（§3A）：刪掉 = nginx 立刻 crash-loop。
- **ingress.conf.tpl 的 `user root;`（§3B）與 `allow 172.30.32.2; deny all;`**：前者刪掉 nginx 炸；後者放寬 = `/_ha_key` 管理 key 被同網段其他 add-on 讀走（審查抓到的原始漏洞）。要放寬只能加確切的 ingress proxy IP，**絕不可 `allow all` 或整個 172.30.32.0/23**。
- **ingress shim 的 sed / sub_filter 規則與 Headplane 0.7.0 build 產物版本綁定**：升級 Headplane 版本必須連 ingress 介面整組回歸（逐頁換頁 + assets + 無 double-prefix）。Dockerfile 的 `sed 's|"mode": "lazy"|"mode": "initial"|'` 有 grep guard，pattern 消失會讓 build 失敗（刻意的）。
- **`server_url` 網域 ≠ `magic_dns_base_domain`（含子網域）**：相同 Headscale 拒啟動，cont-init 已 fail-fast + 中文提示。
- **Control plane 不能走 HA Ingress / Cloudflare Tunnel**：TS2021 的非標準 `Upgrade` header 會被剝（DOCS §8C）。曝露只走反代（Upgrade passthrough）或 ngrok。
- **改 add-on 原始碼後要讓 HA 生效**：走「移除→重加 repository→install」重新 clone，別只 `rebuild`（會用 stale store 快取）。

---

## 7. 出處與環境事實

- 服務組裝版型：AlessioBazzanella/homeassistant-headscale-addon（MIT）
- HA Ingress nginx shim + 自動登入：yuriy1337/headscale-ha
- 設定基準 / 曝露實測：WOOWTECH/Woow_vpn_headscale_package（podman 分支 + docs/EXTERNAL-ACCESS.md、HAOS-ADDON-SETUP.md）
- 上游：juanfont/headscale v0.29.3（BSD-3-Clause）、tale/headplane 0.7.0（BSD-3-Clause）
- 辦公室 HA：amd64 HAOS 18.1、Supervisor 2026.07.5、HA Core 2026.4.2、16GB RAM、本地 build 可行
