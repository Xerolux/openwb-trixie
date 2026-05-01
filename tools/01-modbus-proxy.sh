#!/bin/bash
# ============================================================================
# Tool: modbus-proxy
# ============================================================================
# Id: modbus-proxy
# Name: Modbus TCP Proxy
# Desc: Proxy fuer Modbus TCP Geraete. Erlaubt mehreren Clients auf ein
#       Geraet zuzugreifen. Installiert als systemd-Service.
# ============================================================================

TOOL_ID="modbus-proxy"
TOOL_NAME="Modbus TCP Proxy"
TOOL_DESC="Modbus TCP Proxy — mehrere Clients auf ein Geraet"
TOOL_VERSION="0.8.0"

TOOL_CONF="/etc/modbus-proxy/config.yaml"
TOOL_SERVICE="/etc/systemd/system/modbus-proxy.service"

tool_meta() {
    echo "id:   $TOOL_ID"
    echo "name: $TOOL_NAME"
    echo "desc: $TOOL_DESC"
    echo "ver:  $TOOL_VERSION"
}

tool_check() {
    if [ -n "$VENV_DIR" ] && [ -x "$VENV_DIR/bin/modbus-proxy" ]; then
        return 0
    fi
    command -v modbus-proxy >/dev/null 2>&1
}

tool_apply() {
    if tool_check; then
        echo "  Bereits installiert: $TOOL_NAME"
        return 0
    fi

    # Installieren
    if [ -n "$VENV_DIR" ] && [ -d "$VENV_DIR" ]; then
        echo "  Installiere $TOOL_NAME im venv..."
        "$VENV_DIR/bin/pip3" install "modbus-proxy==$TOOL_VERSION" 2>&1 | tail -1
        local bin="$VENV_DIR/bin/modbus-proxy"
    else
        echo "  Installiere $TOOL_NAME systemweit..."
        sudo pip3 install "modbus-proxy==$TOOL_VERSION" 2>&1 | tail -1
        local bin="$(command -v modbus-proxy)"
    fi

    if [ -z "$bin" ] || [ ! -x "$bin" ]; then
        echo "  FEHLER: modbus-proxy konnte nicht installiert werden"
        return 1
    fi

    # Beispiel-Config erstellen
    sudo mkdir -p /etc/modbus-proxy
    if [ ! -f "$TOOL_CONF" ]; then
        sudo tee "$TOOL_CONF" > /dev/null << 'EOF'
devices:
  - modbus:
      url: 192.168.178.1:502
      timeout: 10
    listen:
      bind: 0.0.0.0:9000
EOF
    fi

    # systemd Service
    sudo tee "$TOOL_SERVICE" > /dev/null << EOF
[Unit]
Description=Modbus TCP Proxy
After=network.target

[Service]
Type=simple
Restart=on-failure
RestartSec=5
ExecStart=$bin -c $TOOL_CONF

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable modbus-proxy 2>/dev/null || true
    sudo systemctl restart modbus-proxy 2>/dev/null || true

    if tool_check; then
        echo "  OK: $TOOL_NAME v$TOOL_VERSION installiert"
        echo "       Config: $TOOL_CONF"
        echo "       Service: modbus-proxy.service"
        echo "       Status: $(systemctl is-active modbus-proxy 2>/dev/null || echo 'nicht gestartet — Config anpassen!')"
        return 0
    else
        echo "  FEHLER: Installation konnte nicht verifiziert werden"
        return 1
    fi
}

tool_revert() {
    if ! tool_check && [ ! -f "$TOOL_SERVICE" ]; then
        echo "  Nicht installiert: $TOOL_NAME"
        return 0
    fi

    sudo systemctl stop modbus-proxy 2>/dev/null || true
    sudo systemctl disable modbus-proxy 2>/dev/null || true
    sudo rm -f "$TOOL_SERVICE"
    sudo systemctl daemon-reload

    if [ -n "$VENV_DIR" ] && [ -x "$VENV_DIR/bin/modbus-proxy" ]; then
        "$VENV_DIR/bin/pip3" uninstall -y modbus-proxy 2>/dev/null || true
    else
        sudo pip3 uninstall -y modbus-proxy 2>/dev/null || true
    fi

    echo "  Revert OK: $TOOL_NAME entfernt (Config in /etc/modbus-proxy/ behalten)"
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    true
else
    tool_meta
fi
