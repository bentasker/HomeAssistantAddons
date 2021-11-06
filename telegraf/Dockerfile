ARG BUILD_FROM=ghcr.io/hassio-addons/base/amd64:10.0.1
# hadolint ignore=DL3006
FROM ${BUILD_FROM}

# Set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Setup base
ARG BUILD_ARCH=amd64
ARG TELEGRAF_VERSION=1.20.3

# Build arguments
ARG BUILD_ARCH
ARG BUILD_DATE
ARG BUILD_DESCRIPTION
ARG BUILD_NAME
ARG BUILD_REF
ARG BUILD_REPOSITORY
ARG BUILD_VERSION


WORKDIR /usr/local/src
# Todo - make this use the build arch (there's no armv7l in the repo)
ADD https://dl.influxdata.com/telegraf/releases/telegraf-${TELEGRAF_VERSION}_linux_armhf.tar.gz ./

COPY rootfs /

RUN tar -xzf telegraf-${TELEGRAF_VERSION}_linux_*.tar.gz \
    && chmod +x telegraf*/usr/bin/telegraf \
    && cp telegraf*/usr/bin/telegraf /usr/local/bin \
    && rm -f telegraf-${TELEGRAF_VERSION}_linux_*.tar.gz

# Labels
LABEL \
    io.hass.name="${BUILD_NAME}" \
    io.hass.description="${BUILD_DESCRIPTION}" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.type="addon" \
    io.hass.version=${BUILD_VERSION} \
    maintainer="B Tasker" \
    org.opencontainers.image.title="${BUILD_NAME}" \
    org.opencontainers.image.description="${BUILD_DESCRIPTION}" \
    org.opencontainers.image.vendor="BTasker Home Assistant Add-ons" \
    org.opencontainers.image.authors="B Tasker" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.url="https://tobeconfirmed" \
    org.opencontainers.image.source="https://github.com/${BUILD_REPOSITORY}" \
    org.opencontainers.image.documentation="https://github.com/${BUILD_REPOSITORY}/blob/main/README.md" \
    org.opencontainers.image.created=${BUILD_DATE} \
    org.opencontainers.image.revision=${BUILD_REF} \
    org.opencontainers.image.version=${BUILD_VERSION}

ENTRYPOINT ["/usr/local/src/entrypoint.sh"]
