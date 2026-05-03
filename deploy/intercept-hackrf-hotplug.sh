#!/bin/bash
# INTERCEPT HackRF Hotplug Handler
# Called by udev when HackRF is connected or disconnected.

ACTION="${1:-add}"
LOG="/var/log/intercept-hackrf-hotplug.log"
BASE="http://localhost:5050"

log() { echo "[$(date "+%H:%M:%S")] [hackrf-hotplug] $*" | tee -a "$LOG"; }

log "HackRF $ACTION event"

# Give USB subsystem a moment to settle
sleep 2

if [ "$ACTION" = "add" ]; then
    # Verify HackRF is recognised
    if hackrf_info >/dev/null 2>&1; then
        log "HackRF detected: $(hackrf_info 2>&1 | grep -m1 "Serial")"
    fi

    if SoapySDRUtil --find 2>&1 | grep -qi hackrf; then
        log "SoapySDR: HackRF found"
    else
        log "WARNING: SoapySDR did not detect HackRF yet"
    fi

    # Notify INTERCEPT to re-probe devices (if running)
    if curl -s -o /dev/null -w "%{http_code}" "$BASE/health" 2>/dev/null | grep -q "200"; then
        RESP=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/devices/probe" 2>/dev/null)
        log "INTERCEPT device probe: HTTP $RESP"
    fi

elif [ "$ACTION" = "remove" ]; then
    log "HackRF disconnected — INTERCEPT will release device on next mode stop"
fi

log "Done"
