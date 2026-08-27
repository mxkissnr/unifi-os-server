# syntax=docker/dockerfile:1
# Self-contained build: downloads the installer, extracts the embedded OCI
# image with binwalk, flattens its layers into a rootfs, and layers the
# entrypoint on top. No pre-built base image required.

# ---------------------------------------------------------------------------
# Stage 1 – extract the UniFi OS Server rootfs from the installer binary
# ---------------------------------------------------------------------------
FROM ubuntu:22.04 AS extractor

ARG TARGETARCH
ARG INSTALLER_URL_AMD64="https://fw-download.ubnt.com/data/unifi-os-server/9aee-linux-x64-5.1.37-a88d909c-2ac0-43f8-bb22-2bff3b673cbb.37-x64"
ARG INSTALLER_URL_ARM64="https://fw-download.ubnt.com/data/unifi-os-server/e060-linux-arm64-5.1.37-eafe439e-ca8f-4aeb-bd82-85d2edf345ff.37-arm64"
# sha256_checksum from https://fw-update.ubnt.com/api/firmware-latest — kept
# in lockstep with the URLs above by scripts/check-update.sh.
ARG INSTALLER_SHA256_AMD64="4a5b1f7f29f25733cfc5f7497a63e3dbd4f4a616b352cbbd817a89eb1fa66b61"
ARG INSTALLER_SHA256_ARM64="6a3d5069e6412fcb7d15e0a97bd013eea130a62565276d4b5e53b314de2a3e4d"

RUN apt-get update && apt-get install -y --no-install-recommends \
    binwalk jq p7zip-full curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN if [ "$TARGETARCH" = "arm64" ]; then \
      URL="$INSTALLER_URL_ARM64"; SHA256="$INSTALLER_SHA256_ARM64"; \
    else \
      URL="$INSTALLER_URL_AMD64"; SHA256="$INSTALLER_SHA256_AMD64"; \
    fi && \
    [ -n "$URL" ] || { echo "No installer URL for $TARGETARCH"; exit 1; } && \
    curl -fL --retry 5 --retry-delay 2 -o installer.bin "$URL" && \
    echo "${SHA256}  installer.bin" | sha256sum -c -

RUN binwalk --run-as=root -e installer.bin

RUN /bin/bash <<'EXTRACT'
set -eo pipefail
IMAGE_TAR=$(find /build -type f -name 'image.tar' -print -quit)
[ -n "$IMAGE_TAR" ] || { echo "image.tar not found after extraction"; exit 1; }
mkdir oci
tar xf "$IMAGE_TAR" -C oci/
MANIFEST=$(jq -r '.manifests[0].digest' oci/index.json | cut -d: -f2)
mkdir /rootfs
jq -r '.layers[].digest' "oci/blobs/sha256/$MANIFEST" | cut -d: -f2 | \
while read -r layer; do
  echo "Extracting layer $layer"
  tar xf "oci/blobs/sha256/$layer" -C /rootfs
  find /rootfs -name '.wh.*' 2>/dev/null | while read -r wh; do
    base=$(basename "$wh"); dir=$(dirname "$wh")
    if [ "$base" = ".wh..wh..opq" ]; then
      find "$dir" -mindepth 1 -maxdepth 1 ! -name '.wh..wh..opq' -exec rm -rf {} +
    else
      rm -rf "$dir/${base#.wh.}"
    fi
    rm -f "$wh"
  done
done
EXTRACT

COPY uos-entrypoint.sh /rootfs/root/uos-entrypoint.sh
RUN chmod +x /rootfs/root/uos-entrypoint.sh

# ---------------------------------------------------------------------------
# Stage 2 – final image from the extracted rootfs
# ---------------------------------------------------------------------------
FROM scratch
COPY --from=extractor /rootfs /

ARG UOS_SERVER_VERSION="5.1.37"
ENV UOS_SERVER_VERSION="${UOS_SERVER_VERSION}" \
    APP_VERSION="${UOS_SERVER_VERSION}" \
    APP_MODEL="UOSSERVER" \
    PRODUCT_NAME="UniFi OS Server"

# The packaging (this Dockerfile/repo) is AGPL-3.0; the UniFi OS Server
# binary extracted into this image remains Ubiquiti's proprietary software,
# unmodified and unaffiliated with this project.
LABEL org.opencontainers.image.title="UniFi OS Server" \
      org.opencontainers.image.description="Unofficial Docker/Kubernetes packaging of the self-hosted UniFi OS Server" \
      org.opencontainers.image.source="https://github.com/mxkissnr/unifi-os-server" \
      org.opencontainers.image.version="${UOS_SERVER_VERSION}" \
      org.opencontainers.image.licenses="AGPL-3.0-only"

STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/root/uos-entrypoint.sh"]
