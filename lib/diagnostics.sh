#!/bin/bash

generate_diagnostics_bundle() {
    local ts outdir outfile
    ts="$(date +%Y%m%d-%H%M%S)"
    outdir="/tmp/openwb-trixie-diagnose-$ts"
    outfile="/tmp/openwb-trixie-diagnose-$ts.tar.gz"
    mkdir -p "$outdir"

    {
        echo "timestamp=$ts"
        echo "installer_version=$INSTALLER_VERSION"
        echo "build_id=$BUILD_ID"
        echo "mode=${MODE:-menu}"
    } > "$outdir/meta.txt"

    show_status > "$outdir/status.txt" 2>&1 || true
    systemctl --no-pager --full status openwb2 > "$outdir/systemctl-openwb2.txt" 2>&1 || true
    systemctl --no-pager --full status openwb-simpleAPI > "$outdir/systemctl-openwb-simpleAPI.txt" 2>&1 || true
    journalctl -u openwb2 -n 200 --no-pager > "$outdir/journal-openwb2.txt" 2>&1 || true
    journalctl -u openwb-simpleAPI -n 200 --no-pager > "$outdir/journal-openwb-simpleAPI.txt" 2>&1 || true
    [ -f "$PATCH_CONF" ] && cp "$PATCH_CONF" "$outdir/enabled-patches.conf" || true
    [ -f "$TOOL_CONF" ] && cp "$TOOL_CONF" "$outdir/enabled-tools.conf" || true

    tar -czf "$outfile" -C /tmp "$(basename "$outdir")"
    log_success "Diagnose-Archiv erstellt: $outfile"
    printf '%s\n' "$outfile"
}

anonymize_diagnostics_bundle() {
    local bundle="$1"
    local tmpd anon_out host ip
    tmpd="$(mktemp -d)"
    tar -xzf "$bundle" -C "$tmpd"
    host="$(hostname 2>/dev/null || echo unknown-host)"
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    find "$tmpd" -type f \( -name '*.txt' -o -name '*.conf' -o -name '*.log' \) | while IFS= read -r f; do
        [ -n "$host" ] && sed -i "s/${host}/host-redacted/g" "$f" 2>/dev/null || true
        [ -n "$ip" ] && sed -i "s/${ip}/ip-redacted/g" "$f" 2>/dev/null || true
        sed -Ei 's/([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}/mac-redacted/g' "$f" 2>/dev/null || true
        sed -Ei 's/(token|apikey|api_key|password)[[:space:]]*[:=][[:space:]]*[^[:space:]]+/\1=redacted/Ig' "$f" 2>/dev/null || true
    done
    anon_out="${bundle%.tar.gz}-anonymized.tar.gz"
    tar -czf "$anon_out" -C "$tmpd" .
    rm -rf "$tmpd"
    log_success "Anonymisiertes Archiv erstellt: $anon_out"
    printf '%s\n' "$anon_out"
}

extract_upload_link() {
    local headers="$1" body="$2"
    local link
    link="$(printf '%s\n' "$headers" | awk 'tolower($1)=="location:" {print $2}' | tr -d '\r' | head -n1)"
    if [ -n "$link" ] && [[ "$link" =~ ^/ ]]; then
        link="${PASTE_UPLOAD_URL%/}$link"
    fi
    [ -n "$link" ] || link="$(printf '%s\n' "$body" | grep -Eo 'https?://[^"[:space:]]+' | head -n1 || true)"
    if [ -z "$link" ]; then
        return 0
    fi
    printf '%s\n' "$link"
}

upload_diagnostics_bundle() {
    local bundle="$1"
    local resp_file hdr_file body link
    local link_file="/tmp/openwb-trixie-last-diagnose-link.txt"
    local response_log="/tmp/openwb-upload-response.txt"
    local upload_url="${PASTE_UPLOAD_URL}"
    local backup_url="${PASTE_UPLOAD_URL_BACKUP:-}"
    local attempt
    resp_file="$(mktemp)"
    hdr_file="$(mktemp)"

    if [ "${NONINTERACTIVE:-0}" -eq 1 ] && [ "${DIAG_UPLOAD_CONSENT:-0}" != "1" ]; then
        log_error "Non-Interactive Upload benötigt DIAG_UPLOAD_CONSENT=1"
        rm -f "$resp_file" "$hdr_file"
        return 1
    fi

    if [ "${NONINTERACTIVE:-0}" -ne 1 ]; then
        echo ""
        log_warning "Datenschutzhinweis: Es wird ein Diagnose-Archiv an ${PASTE_UPLOAD_URL} gesendet."
        log_warning "Archiv enthält Systemstatus/Logs. Vor Upload wird anonymisiert."
        read -p "Upload jetzt durchführen? (j/N): " -n 1 -r < /dev/tty
        echo ""
        if [[ ! "$REPLY" =~ ^[JjYy]$ ]]; then
            log "Upload abgebrochen."
            rm -f "$resp_file" "$hdr_file"
            return 0
        fi
    fi

    : > "$response_log"
    for attempt in 1 2 3; do
        curl -m 20 -fsSL -D "$hdr_file" -o "$resp_file" -F "c=@${bundle}" "${upload_url}" 2>>"$response_log" && break
        sleep $((attempt * 2))
    done
    if [ ! -s "$resp_file" ] && [ -n "$backup_url" ]; then
        log_warning "Primärer Upload fehlgeschlagen, nutze Backup-Endpoint."
        for attempt in 1 2 3; do
            curl -m 20 -fsSL -D "$hdr_file" -o "$resp_file" -F "c=@${bundle}" "${backup_url}" 2>>"$response_log" && break
            sleep $((attempt * 2))
        done
    fi
    body="$(cat "$resp_file" 2>/dev/null || true)"
    link="$(extract_upload_link "$(cat "$hdr_file" 2>/dev/null || true)" "$body")"
    rm -f "$resp_file" "$hdr_file"

    if [ -n "$link" ]; then
        log_success "Upload erfolgreich. Link: $link"
        printf '%s\n' "$link" | tee "$link_file" >/dev/null
        log "Link gespeichert in: $link_file"
        log "Upload-Response Log: $response_log"
        log "Bitte diesen Link an den Maintainer/Git-Author senden."
        return 0
    fi
    log_warning "Upload ohne auswertbaren Link beendet. Endpoint/Response prüfen."
    log_warning "Details siehe: $response_log"
    return 0
}
