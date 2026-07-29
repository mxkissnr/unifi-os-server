#!/bin/bash

# Ordner-Strukturen zwingend zuerst anlegen
mkdir -p /data /var/lib/unifi /var/log/nginx /var/log/mongodb /var/lib/mongodb /var/log/rabbitmq

# Persist UOS_UUID env var
if [ ! -f /data/uos_uuid ]; then
    if [ -n "${UOS_UUID+1}" ]; then
        echo "Setting UOS_UUID to $UOS_UUID"
        echo "$UOS_UUID" > /data/uos_uuid
    else
        echo "No UOS_UUID present, generating..."
        UUID=$(cat /proc/sys/kernel/random/uuid)
        UOS_UUID=$(echo $UUID | sed s/./5/15)
        echo "Setting UOS_UUID to $UOS_UUID"
        echo "$UOS_UUID" > /data/uos_uuid
    fi
fi

ARCH="$(dpkg --print-architecture)"
if [ "$ARCH" == "amd64" ]; then
    FIRMWARE_PLATFORM=linux-x64
elif [ "$ARCH" == "arm64" ]; then
    FIRMWARE_PLATFORM=arm64
else
    echo "FIRMWARE_PLATFORM not found for $ARCH"
    exit 1
fi

echo "Setting APP_MODEL to ${APP_MODEL:-UOS}"
echo "Setting APP_VERSION to ${APP_VERSION:-5.1.21}"
echo "Setting FIRMWARE_PLATFORM to $FIRMWARE_PLATFORM"
echo "Setting PRODUCT_NAME to ${PRODUCT_NAME:-UniFi OS Server}"

echo "${APP_MODEL:-UOS}.0000000.${APP_VERSION:-5.1.21}.0000000.000000.0000" > /usr/lib/version
echo "$FIRMWARE_PLATFORM" > /usr/lib/platform
echo "${PRODUCT_NAME:-UniFi OS Server}" > /usr/lib/product_name

# System-User Rechte setzen (falls User bereits von UOS angelegt wurden)
id -u nginx >/dev/null 2>&1 && chown -R nginx:nginx /var/log/nginx
id -u mongodb >/dev/null 2>&1 && chown -R mongodb:mongodb /var/log/mongodb /var/lib/mongodb
id -u rabbitmq >/dev/null 2>&1 && chown -R rabbitmq:rabbitmq /var/log/rabbitmq

# Systemd Service-Unit anlegen, falls nicht vorhanden
if [ ! -f /etc/systemd/system/unifi-os-server.service ]; then
    echo "==> Erstelle Systemd Unit für UniFi OS Server..."
    cat << 'SERVICE' > /etc/systemd/system/unifi-os-server.service
[Unit]
Description=UniFi OS Server
After=network.target

[Service]
ExecStart=/usr/local/bin/unifi-os-server --non-interactive
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE
    systemctl enable unifi-os-server.service
fi

# Set UOS_SYSTEM_IP
UNIFI_SYSTEM_PROPERTIES="/var/lib/unifi/system.properties"
if [ -n "${UOS_SYSTEM_IP+1}" ]; then
    echo "Setting UOS_SYSTEM_IP to $UOS_SYSTEM_IP"
    if [ ! -f "$UNIFI_SYSTEM_PROPERTIES" ]; then
        echo "system_ip=$UOS_SYSTEM_IP" >> "$UNIFI_SYSTEM_PROPERTIES"
    else
        if grep -q "^system_ip=.*" "$UNIFI_SYSTEM_PROPERTIES"; then
            sed -i 's/^system_ip=.*/system_ip='"$UOS_SYSTEM_IP"'/' "$UNIFI_SYSTEM_PROPERTIES"
        else
            echo "system_ip=$UOS_SYSTEM_IP" >> "$UNIFI_SYSTEM_PROPERTIES"
        fi
    fi
fi

# Start systemd
exec /sbin/init
