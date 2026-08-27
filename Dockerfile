FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
# 1. System-Abhängigkeiten installieren
RUN apt-get update && apt-get install -y \
    curl \
    systemd \
    systemd-sysv \
    podman \
    slirp4netns \
    iptables \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 2. Version & Download-URLs (werden vom Update-Skript automatisch aktualisiert)
ARG UOS_VERSION="5.1.37"
ARG UOS_BINARY_URL_AMD64="https://fw-download.ubnt.com/data/unifi-os-server/9aee-linux-x64-5.1.37-a88d909c-2ac0-43f8-bb22-2bff3b673cbb.37-x64"
ARG UOS_BINARY_URL_ARM64="https://fw-download.ubnt.com/data/unifi-os-server/e060-linux-arm64-5.1.37-eafe439e-ca8f-4aeb-bd82-85d2edf345ff.37-arm64"

# 3. Binary passend zur Build-Architektur herunterladen
ARG TARGETARCH
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) URL="${UOS_BINARY_URL_AMD64}" ;; \
      arm64) URL="${UOS_BINARY_URL_ARM64}" ;; \
      *) echo "Nicht unterstützte Architektur: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -L -o /usr/local/bin/unifi-os-server "$URL" && \
    chmod +x /usr/local/bin/unifi-os-server

ENV APP_VERSION=${UOS_VERSION}

# 4. Dein Entrypoint-Skript einbinden
COPY uos-entrypoint.sh /uos-entrypoint.sh
RUN chmod +x /uos-entrypoint.sh
STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/uos-entrypoint.sh"]
