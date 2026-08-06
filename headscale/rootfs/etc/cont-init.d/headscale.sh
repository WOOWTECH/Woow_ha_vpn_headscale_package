#!/command/with-contenv bashio
# shellcheck shell=bash
# ==============================================================================
# Woow Headscale VPN — cont-init
# Generates /etc/headscale/config.yaml and /etc/headplane/config.yaml from
# add-on options on every start. Manual edits to DNS keys are preserved.
# ==============================================================================

readonly DATA='/var/lib/headscale'
readonly CONFIG='/etc/headscale/config.yaml'
readonly RENDER='/tmp/headscale-config.rendered.yaml'
readonly BASELINE="${DATA}/.last_rendered_config.yaml"
readonly OVERRIDES="${DATA}/.headplane_overrides.yaml"
readonly OPTIONS='/tmp/options.json'

# Recent Supervisors no longer materialise /data/options.json when the map
# uses a custom path; fetch options through the Supervisor API instead.
bashio::addon.config > "${OPTIONS}"

# Headscale's CLI talks to the server over a unix socket in /var/run,
# which is a tmpfs and must be re-created on every container start.
mkdir -p /var/run/headscale

# ------------------------------------------------------------------------------
# HANDOFF §7 #1: server_url host MUST differ from dns.base_domain, otherwise
# Headscale refuses to start with a confusing error. Fail fast with a clear
# message so users can fix the options before hitting an unhealthy container.
# ------------------------------------------------------------------------------
server_url=$(bashio::config 'server_url')
base_domain=$(bashio::config 'magic_dns_base_domain')
# Strip scheme + optional port to get the bare host.
server_host="${server_url#*://}"
server_host="${server_host%%:*}"
server_host="${server_host%%/*}"
if [[ "${server_host}" == "${base_domain}" ]]; then
    bashio::exit.nok \
        "設定衝突：server_url 的網域 (${server_host}) 不能等於 magic_dns_base_domain (${base_domain})。" \
        "請把 magic_dns_base_domain 改成一個不同的名字（例如 ts.local）。"
fi

# ------------------------------------------------------------------------------
# Bootstrap files inside /etc/headscale (which is the addon_config mount, so
# nothing baked into the image lives here — we seed defaults on first start).
#
# - dns_records.json:  Headplane hot-reloads this (extra_records_path)
# - policy.json:       Headscale ACL policy, accept-all + auto-approve LAN
#                      routes for the default user. Users can edit it via
#                      the add-on config folder to tighten access.
# ------------------------------------------------------------------------------
if ! bashio::fs.file_exists '/etc/headscale/dns_records.json'; then
    echo '[]' > /etc/headscale/dns_records.json
fi
if ! bashio::fs.file_exists '/etc/headscale/policy.json'; then
    cat > /etc/headscale/policy.json <<'POLICY_EOF'
{
  "acls": [
    {"action": "accept", "src": ["*"], "dst": ["*:*"]}
  ],
  "autoApprovers": {
    "routes": {
      "10.0.0.0/8": ["default@"],
      "192.168.0.0/16": ["default@"]
    },
    "exitNode": ["default@"]
  }
}
POLICY_EOF
fi

bashio::log.info "Generating Headscale configuration: ${CONFIG}"
tempio \
    -conf "${OPTIONS}" \
    -template /usr/share/tempio/headscale.config.gtpl \
    -out "${RENDER}"

# Keys owned by Headplane / manual edits — kept across restarts.
managed_paths=(
    '.dns.magic_dns'
    '.dns.override_local_dns'
    '.dns.nameservers.global'
    '.dns.nameservers.split'
    '.dns.search_domains'
)

if ! bashio::fs.file_exists "${OVERRIDES}"; then
    echo '{}' > "${OVERRIDES}"
fi

if bashio::fs.file_exists "${BASELINE}" && bashio::fs.file_exists "${CONFIG}"; then
    for path in "${managed_paths[@]}"; do
        live=$(yq -o=json "${path}" "${CONFIG}")
        old=$(yq -o=json "${path}" "${BASELINE}")
        if [[ "${live}" == "${old}" || "${live}" == "null" ]]; then
            yq -i "del(${path})" "${OVERRIDES}"
        else
            bashio::log.info "Preserving external change: ${path}"
            yq -i "${path} = ${live}" "${OVERRIDES}"
        fi
    done
fi

# Merge fresh render + preserved overrides (deep merge, arrays replaced).
# shellcheck disable=SC2016
yq eval-all '. as $item ireduce ({}; . * $item)' \
    "${RENDER}" "${OVERRIDES}" > "${CONFIG}"
cp "${RENDER}" "${BASELINE}"

# ------------------------------------------------------------------------------
# Headplane dashboard config (rendered only when enabled)
# ------------------------------------------------------------------------------
if bashio::config.true 'headplane_enabled'; then
    bashio::log.info 'Generating Headplane configuration: /etc/headplane/config.yaml'
    mkdir -p /etc/headplane "${DATA}/headplane"

    # 32-char cookie secret for signing sessions; generated once, persisted.
    if ! bashio::fs.file_exists "${DATA}/.headplane_cookie_secret"; then
        head -c 100 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' \
            | head -c 32 > "${DATA}/.headplane_cookie_secret"
    fi

    tempio \
        -conf "${OPTIONS}" \
        -template /usr/share/tempio/headplane.config.gtpl \
        -out /etc/headplane/config.yaml

    cookie_secret=$(< "${DATA}/.headplane_cookie_secret")
    cookie_secure=false
    if [[ "${server_url}" == https://* ]]; then
        cookie_secure=true
    fi
    yq -i ".server.cookie_secret = \"${cookie_secret}\"
         | .server.cookie_secure = ${cookie_secure}" /etc/headplane/config.yaml
fi
