#!/bin/bash
log() { echo "[uos-entrypoint][$(date -Iseconds)] $*"; }

set_unifi_property() {
  local key="$1" value="$2"
  local escaped_value="${value//\\/\\\\}"
  escaped_value="${escaped_value//&/\\&}"
  if grep -q "^${key}=" "$UNIFI_SYSTEM_PROPERTIES" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${escaped_value}|" "$UNIFI_SYSTEM_PROPERTIES"
  else
    echo "${key}=${value}" >> "$UNIFI_SYSTEM_PROPERTIES"
  fi
}

ensure_dir() {
  local dir="$1" owner="$2"
  if [ ! -d "$dir" ]; then
    log "Initializing $dir"
    mkdir -p "$dir"
    chown "$owner" "$dir"
    chmod 755 "$dir"
  fi
}

# --- UUID ---
if [ ! -f /data/uos_uuid ]; then
  if [ -n "${UOS_UUID+1}" ]; then
    echo "$UOS_UUID" > /data/uos_uuid
  else
    UUID=$(cat /proc/sys/kernel/random/uuid)
    UOS_UUID=$(echo $UUID | sed s/./5/15)
    log "Setting UUID to $UOS_UUID"
    echo "$UOS_UUID" > /data/uos_uuid
  fi
fi

# --- Version / platform metadata ---
log "Setting UOS_SERVER_VERSION to $UOS_SERVER_VERSION"
echo "UOSSERVER.0000000.$UOS_SERVER_VERSION.0000000.000000.0000" > /usr/lib/version
FIRMWARE_PLATFORM="${FIRMWARE_PLATFORM:-linux-x64}"
echo "$FIRMWARE_PLATFORM" > /usr/lib/platform
echo "${PRODUCT_NAME:-UniFi OS Server}" > /usr/lib/product_name
echo "${APP_MODEL:-UOSSERVER}" > /usr/lib/app_model

# --- Service dirs ---
ensure_dir "/var/log/nginx" "nginx:nginx"
ensure_dir "/var/log/mongodb" "mongodb:mongodb"
ensure_dir "/var/log/rabbitmq" "rabbitmq:rabbitmq"
log "Ensuring mongodb ownership for /var/lib/mongodb"
chown -R mongodb:mongodb /var/lib/mongodb 2>/dev/null || true

# --- UOS_SYSTEM_IP (Pflicht) ---
if [ -z "${UOS_SYSTEM_IP}" ]; then
  log "ERROR: UOS_SYSTEM_IP is required but not set"
  exit 1
fi
UNIFI_SYSTEM_PROPERTIES="/var/lib/unifi/system.properties"
set_unifi_property "system_ip" "$UOS_SYSTEM_IP"

# --- MongoDB: intern (Default, wie bisher bei dir - single container) ---
MONGO_INTERNAL="${MONGO_INTERNAL:-true}"
if [ "$MONGO_INTERNAL" = "true" ]; then
  log "Using internal MongoDB"
  set_unifi_property "db.mongo.local" "true"
else
  MONGO_HOST="${MONGO_HOST:-unifi-os-server-mongodb}"
  MONGO_PORT="${MONGO_PORT:-27017}"
  MONGO_URI="mongodb\\://${MONGO_HOST}\\:${MONGO_PORT}"
  log "External MongoDB: ${MONGO_HOST}:${MONGO_PORT}"
  set_unifi_property "db.mongo.local" "false"
  set_unifi_property "db.mongo.uri" "${MONGO_URI}/ace?tls\\=false"
  set_unifi_property "statdb.mongo.uri" "${MONGO_URI}/ace_stat?tls\\=false"
fi

# --- Journal ins Docker-Log weiterleiten ---
exec 3>&1
(
  while journalctl -n 0 2>&1 | grep -q "No journal files were found"; do sleep 1; done
  exec journalctl -f --no-hostname -o short >&3 2>&3
) &

log "Starting systemd init"
exec /sbin/init
