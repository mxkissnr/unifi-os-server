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

# 2. Download-URL
ARG UOS_BINARY_URL="https://fw-download.ubnt.com/data/unifi-os-server/f5e2-linux-x64-5.1.21-a400c9c6-8328-4634-b223-ebfcf742720a.21-x64"

# 3. Binary herunterladen
RUN curl -L -o /usr/local/bin/unifi-os-server "${UOS_BINARY_URL}" && \
    chmod +x /usr/local/bin/unifi-os-server

# 4. Dein Entrypoint-Skript einbinden
COPY uos-entrypoint.sh /uos-entrypoint.sh
RUN chmod +x /uos-entrypoint.sh

STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/uos-entrypoint.sh"]
