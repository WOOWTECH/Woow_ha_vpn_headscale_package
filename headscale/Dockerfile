ARG BUILD_FROM=ghcr.io/hassio-addons/debian-base:9.3.0
ARG HEADPLANE_VERSION="0.7.0"

###############################################################################
# Official Headplane image, used as a source for the app and the Node runtime.
# Its final stage is distroless/nodejs24-debian13 — same libc as our base.
###############################################################################
# hadolint ignore=DL3006
FROM ghcr.io/tale/headplane:${HEADPLANE_VERSION} AS headplane

###############################################################################
# Add-on image.
###############################################################################
# hadolint ignore=DL3006
FROM ${BUILD_FROM}

ARG BUILD_ARCH="amd64"
# Pinned per WoowTech HANDOFF §2 — v0.29.3 fixes tagged-node expiry hangs
# and several auth bugs regressed in v0.29.2. Do NOT downgrade.
ARG HEADSCALE_VERSION="v0.29.3"
ARG YQ_VERSION="v4.53.3"

# hadolint ignore=SC2181,SC3009,DL3008
RUN \
    apt-get update \
    && if [ "${BUILD_ARCH}" = "aarch64" ]; then ARCH="arm64"; fi \
    && if [ "${BUILD_ARCH}" = "amd64" ]; then ARCH="amd64"; fi \
    && curl -J -L -o /tmp/headscale.deb \
        "https://github.com/juanfont/headscale/releases/download/${HEADSCALE_VERSION}/headscale_${HEADSCALE_VERSION#v}_linux_${ARCH}.deb" \
    && dpkg -i --force-confdef --force-confold /tmp/headscale.deb \
    && curl -J -L -o /usr/bin/yq \
        "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${ARCH}" \
    && chmod +x /usr/bin/yq \
    && rm -fr \
        /root/.cache \
        /tmp/* \
        /var/cache/* \
        /var/log/* \
        /var/lib/apt/lists/*

# Headplane dashboard: Node.js runtime + the self-contained app build
COPY --from=headplane /nodejs /opt/nodejs
COPY --from=headplane /app /opt/headplane

# Copy root filesystem (s6 service dirs, cont-init scripts, tempio templates)
COPY rootfs /

HEALTHCHECK \
   CMD curl --fail http://127.0.0.1:8080/health || exit 1

# Build arguments propagated by Supervisor
ARG BUILD_DATE
ARG BUILD_DESCRIPTION
ARG BUILD_NAME
ARG BUILD_REF
ARG BUILD_REPOSITORY
ARG BUILD_VERSION

LABEL \
    io.hass.name="${BUILD_NAME}" \
    io.hass.description="${BUILD_DESCRIPTION}" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.type="addon" \
    io.hass.version=${BUILD_VERSION} \
    maintainer="WoowTech" \
    org.opencontainers.image.title="${BUILD_NAME}" \
    org.opencontainers.image.description="${BUILD_DESCRIPTION}" \
    org.opencontainers.image.authors="WoowTech" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.url="https://github.com/${BUILD_REPOSITORY}" \
    org.opencontainers.image.source="https://github.com/${BUILD_REPOSITORY}" \
    org.opencontainers.image.documentation="https://github.com/${BUILD_REPOSITORY}/blob/main/headscale/DOCS.md" \
    org.opencontainers.image.created=${BUILD_DATE} \
    org.opencontainers.image.revision=${BUILD_REF} \
    org.opencontainers.image.version=${BUILD_VERSION}
