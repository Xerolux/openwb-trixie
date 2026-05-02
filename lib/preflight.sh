#!/bin/bash

run_preflight_checks() {
    log_step "Preflight-Checks"

    local failures=0
    if is_trixie; then
        log_success "Debian Trixie erkannt"
    else
        log_warning "Debian Trixie nicht sicher erkannt (bitte prüfen)"
    fi

    if command -v curl >/dev/null 2>&1; then
        log_success "curl vorhanden"
    else
        log_error "curl fehlt"
        failures=$((failures + 1))
    fi

    if command -v git >/dev/null 2>&1; then
        log_success "git vorhanden"
    else
        log_warning "git fehlt (wird ggf. nachinstalliert)"
    fi

    ensure_free_space_mb 3000

    if [ "$failures" -gt 0 ]; then
        log_error "Preflight fehlgeschlagen ($failures Fehler)"
        exit 1
    fi
}
