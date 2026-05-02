#!/bin/bash

set -Eeo pipefail

OPENWB_DIR="/var/www/html/openWB"
VENV_DIR="/opt/openwb-venv"

log() { echo "[openwb-trixie-boot] $1"; }

if [ ! -d "$OPENWB_DIR" ]; then
    log "OpenWB nicht installiert, überspringe"
    exit 0
fi

if [ ! -d "$VENV_DIR" ]; then
    log "venv nicht gefunden, überspringe"
    exit 0
fi

log "Reappliziere OpenWB Trixie Patches..."

# pip3-Wrapper sicherstellen
if [ ! -f /usr/local/bin/pip3 ] || ! head -1 /usr/local/bin/pip3 2>/dev/null | grep -q openwb-venv; then
    cat > /usr/local/bin/pip3 <<'WRAPPER'
#!/bin/bash
if [ -x /opt/openwb-venv/bin/pip3 ]; then
    exec /opt/openwb-venv/bin/pip3 "$@"
else
    exec /usr/bin/pip3 "$@"
fi
WRAPPER
    chmod 755 /usr/local/bin/pip3
    log "pip3-Wrapper installiert"
fi

# requirements.txt patchen (alle auf latest außer pymodbus)
req="$OPENWB_DIR/requirements.txt"
if [ -f "$req" ]; then
    sed -i -E '/^pymodbus==/!s/==[0-9][0-9.a-zA-Z+-]*[[:space:]]*$//' "$req"
    log "requirements.txt gepatcht"
fi

# openwb2.service -> venv Python
service="$OPENWB_DIR/data/config/openwb2.service"
if [ -f "$service" ] && ! grep -q "$VENV_DIR/bin/python3" "$service"; then
    sed -i "s#^ExecStart=.*main.py#ExecStart=$VENV_DIR/bin/python3 $OPENWB_DIR/packages/main.py#g" "$service"
    log "openwb2.service -> venv Python"
fi

# simpleAPI.service -> venv Python
simpleapi="$OPENWB_DIR/data/config/openwb-simpleAPI.service"
if [ -f "$simpleapi" ] && ! grep -q "$VENV_DIR/bin/python3" "$simpleapi"; then
    sed -i -E "s@^ExecStart=.*simpleAPI_mqtt\.py\$@ExecStart=$VENV_DIR/bin/python3 $OPENWB_DIR/simpleAPI/simpleAPI_mqtt.py@g" "$simpleapi"
    ln -sfn "$simpleapi" /etc/systemd/system/openwb-simpleAPI.service
    log "simpleAPI.service -> venv Python"
fi

# remoteSupport.service -> venv Python
remote_service="/etc/systemd/system/openwbRemoteSupport.service"
if [ -f "$remote_service" ] && ! grep -q "$VENV_DIR/bin/python3" "$remote_service"; then
    sed -i "s#^ExecStart=.*#ExecStart=$VENV_DIR/bin/python3 $OPENWB_DIR/runs/remoteSupport/remoteSupport.py#g" "$remote_service"
    log "remoteSupport.service -> venv Python"
fi

# atreboot.sh pip3-Aufrufe -> venv pip
atreboot="$OPENWB_DIR/runs/atreboot.sh"
if [ -f "$atreboot" ]; then
    if ! grep -q '/opt/openwb-venv/bin/pip3' "$atreboot"; then
        sed -i -E 's@(^|[^[:alnum:]_/.-])pip3[[:space:]]+install[[:space:]]+-r@\1/opt/openwb-venv/bin/pip3 install -r@g' "$atreboot"
        sed -i -E 's@(^|[^[:alnum:]_/.-])pip3[[:space:]]+install[[:space:]]+--only-binary@\1/opt/openwb-venv/bin/pip3 install --only-binary@g' "$atreboot"
        sed -i 's|pip uninstall urllib3 -y|/opt/openwb-venv/bin/pip3 uninstall urllib3 -y|g' "$atreboot"
        log "atreboot.sh -> venv pip"
    fi
fi

# asyncio.coroutine Kompatibilitaets-Shim
shim_dir=$(ls -d "$VENV_DIR/lib/python3."*/site-packages 2>/dev/null | head -1)
if [ -n "$shim_dir" ] && [ -d "$shim_dir" ] && [ ! -f "$shim_dir/openwb_py313_compat.py" ]; then
    printf 'import asyncio\nimport types\nimport sys\nif sys.version_info >= (3, 11) and not hasattr(asyncio, "coroutine"):\n    def _coroutine_compat(func):\n        return types.coroutine(func)\n    asyncio.coroutine = _coroutine_compat\n' > "$shim_dir/openwb_py313_compat.py"
    echo 'import openwb_py313_compat' > "$shim_dir/openwb_py313_compat.pth"
    log "asyncio.coroutine Shim installiert"
fi

# mosquitto_local native systemd Unit
if [ -f /etc/init.d/mosquitto_local ] && [ ! -f /etc/systemd/system/mosquitto_local.service ]; then
    cat > /etc/systemd/system/mosquitto_local.service <<'EOF'
[Unit]
Description=Mosquitto Local Instance (openWB)
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStart=/usr/sbin/mosquitto -c /etc/mosquitto/mosquitto_local.conf -d
PIDFile=/run/mosquitto_local.pid
TimeoutSec=60
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable mosquitto_local >/dev/null 2>&1 || true
    systemctl mask mosquitto_local-sysv 2>/dev/null || true
    log "mosquitto_local systemd Unit erstellt"
fi

# Home-Dir Ownership
if [ -d /home/openwb ]; then
    chown -R openwb:openwb /home/openwb 2>/dev/null || true
fi

systemctl daemon-reload

log "Patches reappligiert"
