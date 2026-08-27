#!/usr/bin/env bash
set -euo pipefail

DOCKERFILE="${1:-Dockerfile}"

fetch() {
  curl -s "https://fw-update.ubnt.com/api/firmware-latest" \
    | jq -r --arg platform "$1" \
      '._embedded.firmware[]
        | select(.product == "unifi-os-server"
                  and .channel == "release"
                  and .platform == $platform)'
}

AMD64=$(fetch "linux-x64")
ARM64=$(fetch "linux-arm64")

NEW_VERSION=$(echo "$AMD64" | jq -r '.version' | sed 's/^v//')
NEW_URL_AMD64=$(echo "$AMD64" | jq -r '._links.data.href')
NEW_URL_ARM64=$(echo "$ARM64" | jq -r '._links.data.href')

CURRENT_VERSION=$(grep -oP 'ARG UOS_SERVER_VERSION="\K[^"]+' "$DOCKERFILE" | tail -n1)

echo "Aktuell im Dockerfile: $CURRENT_VERSION"
echo "Neueste verfügbare:    $NEW_VERSION"

if [ "$NEW_VERSION" != "$CURRENT_VERSION" ]; then
  echo "-> Update verfügbar, aktualisiere $DOCKERFILE"
  sed -i "s|ARG INSTALLER_URL_AMD64=\".*\"|ARG INSTALLER_URL_AMD64=\"$NEW_URL_AMD64\"|" "$DOCKERFILE"
  sed -i "s|ARG INSTALLER_URL_ARM64=\".*\"|ARG INSTALLER_URL_ARM64=\"$NEW_URL_ARM64\"|" "$DOCKERFILE"
  sed -i "0,/ARG UOS_SERVER_VERSION=\".*\"/s||ARG UOS_SERVER_VERSION=\"$NEW_VERSION\"|" "$DOCKERFILE"

  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "updated=true" >> "$GITHUB_OUTPUT"
    echo "new_version=$NEW_VERSION" >> "$GITHUB_OUTPUT"
  fi
else
  echo "-> Keine neue Version, nichts zu tun."
  [ -n "${GITHUB_OUTPUT:-}" ] && echo "updated=false" >> "$GITHUB_OUTPUT"
fi
