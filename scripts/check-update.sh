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

if [ -z "$NEW_VERSION" ] || [ -z "$NEW_URL_AMD64" ] || [ -z "$NEW_URL_ARM64" ]; then
  echo "Konnte keine aktuelle Version ermitteln – Abbruch." >&2
  exit 1
fi

CURRENT_VERSION=$(grep -oP 'ARG UOS_VERSION="\K[^"]+' "$DOCKERFILE")

echo "Aktuell im Dockerfile: $CURRENT_VERSION"
echo "Neueste verfügbare:    $NEW_VERSION"

if [ "$NEW_VERSION" != "$CURRENT_VERSION" ]; then
  echo "-> Update verfügbar, aktualisiere $DOCKERFILE"
  sed -i "s|ARG UOS_VERSION=\".*\"|ARG UOS_VERSION=\"$NEW_VERSION\"|" "$DOCKERFILE"
  sed -i "s|ARG UOS_BINARY_URL_AMD64=\".*\"|ARG UOS_BINARY_URL_AMD64=\"$NEW_URL_AMD64\"|" "$DOCKERFILE"
  sed -i "s|ARG UOS_BINARY_URL_ARM64=\".*\"|ARG UOS_BINARY_URL_ARM64=\"$NEW_URL_ARM64\"|" "$DOCKERFILE"

  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "updated=true" >> "$GITHUB_OUTPUT"
    echo "new_version=$NEW_VERSION" >> "$GITHUB_OUTPUT"
  fi
else
  echo "-> Keine neue Version, nichts zu tun."
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "updated=false" >> "$GITHUB_OUTPUT"
  fi
fi
