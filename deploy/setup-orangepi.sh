#!/usr/bin/env bash
# =============================================================================
# INTERCEPT — Orange Pi 5 Plus System-Level Setup
# =============================================================================
# Automates the system configuration steps documented in ORANGEPI5PLUS.md:
#   - Security hardening (sysctl BPF, DVB kernel module blacklist)
#   - Sudoers config for passwordless systemctl/pkill
#   - flask-sock WebSocket dependency
#   - systemd service installation and activation
#
# Usage: sudo bash deploy/setup-orangepi.sh
#        Run from the root of the intercept repo directory.
# =============================================================================

RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"
CYAN="\033[0;36m"; BOLD="\033[1m"; NC="\033[0m"

info()    { echo -e "${CYAN}[*]${NC} $*"; }
ok()      { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
fail()    { echo -e "${RED}[x]${NC} $*"; exit 1; }
section() { echo -e "\n${BOLD}── $* ──${NC}"; }

# Must run as root
if [ "$(id -u)" -ne 0 ]; then
    fail "This script must be run as root: sudo bash deploy/setup-orangepi.sh"
fi

# Resolve real user (the one who invoked sudo)
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo orangepi)}"
REAL_HOME=$(eval echo "~$REAL_USER")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BOLD}"
echo "  ██╗███╗   ██╗████████╗███████╗██████╗  ██████╗███████╗██████╗ ████████╗"
echo "  ██║████╗  ██║╚══██╔══╝██╔════╝██╔══██╗██╔════╝██╔════╝██╔══██╗╚══██╔══╝"
echo "  ██║██╔██╗ ██║   ██║   █████╗  ██████╔╝██║     █████╗  ██████╔╝   ██║   "
echo "  ██║██║╚██╗██║   ██║   ██╔══╝  ██╔══██╗██║     ██╔══╝  ██╔═══╝    ██║   "
echo "  ██║██║ ╚████║   ██║   ███████╗██║  ██║╚██████╗███████╗██║        ██║   "
echo "  ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚═╝  ╚═╝ ╚═════╝╚══════╝╚═╝        ╚═╝   "
echo -e "${NC}"
echo -e "  ${BOLD}Orange Pi 5 Plus — System Setup${NC}"
echo -e "  Repo: $REPO_DIR"
echo -e "  User: $REAL_USER ($REAL_HOME)"
echo ""

# =============================================================================
section "1. Security — Disable unprivileged BPF (Spectre v2 mitigation)"
# =============================================================================
BPF_CONF="/etc/sysctl.d/99-disable-unprivileged-bpf.conf"
if [ ! -f "$BPF_CONF" ]; then
    echo "kernel.unprivileged_bpf_disabled=1" > "$BPF_CONF"
    sysctl --system 2>/dev/null | grep -q "unprivileged_bpf" && ok "BPF restriction applied" || warn "BPF sysctl written (takes effect on next boot)"
else
    ok "BPF restriction already configured"
fi

# =============================================================================
section "2. Security — Blacklist DVB kernel driver"
# =============================================================================
DVB_CONF="/etc/modprobe.d/blacklist-rtl-dvb.conf"
if [ ! -f "$DVB_CONF" ]; then
    echo "blacklist dvb_usb_rtl28xxu" > "$DVB_CONF"
    update-initramfs -u 2>&1 | tail -1
    ok "dvb_usb_rtl28xxu blacklisted"
else
    ok "DVB blacklist already configured"
fi
# Unload if currently loaded
if lsmod | grep -q dvb_usb_rtl28xxu; then
    rmmod dvb_usb_rtl28xxu 2>/dev/null && ok "Unloaded dvb_usb_rtl28xxu" || warn "Could not unload dvb_usb_rtl28xxu (may be in use)"
fi

# =============================================================================
section "3. Sudoers — Passwordless systemctl and pkill for $REAL_USER"
# =============================================================================
SUDOERS_FILE="/etc/sudoers.d/orangepi-systemctl"
SUDOERS_LINE="${REAL_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/bin/pkill"
if [ ! -f "$SUDOERS_FILE" ] || ! grep -qF "$REAL_USER" "$SUDOERS_FILE"; then
    echo "$SUDOERS_LINE" > "$SUDOERS_FILE"
    chmod 440 "$SUDOERS_FILE"
    # Validate with visudo
    if visudo -c -f "$SUDOERS_FILE" >/dev/null 2>&1; then
        ok "Sudoers rule installed for $REAL_USER"
    else
        rm -f "$SUDOERS_FILE"
        fail "Sudoers syntax check failed — file removed"
    fi
else
    ok "Sudoers rule already present"
fi

# =============================================================================
section "4. Python — Install flask-sock WebSocket support"
# =============================================================================
VENV_PIP="$REPO_DIR/venv/bin/pip"
if [ -x "$VENV_PIP" ]; then
    if "$VENV_PIP" show flask-sock >/dev/null 2>&1; then
        ok "flask-sock already installed"
    else
        info "Installing flask-sock..."
        "$VENV_PIP" install flask-sock && ok "flask-sock installed" || warn "flask-sock install failed"
    fi
else
    warn "venv not found at $REPO_DIR/venv — run setup.sh first, then re-run this script"
fi

# =============================================================================
section "5. systemd — Install service files"
# =============================================================================
SYSTEMD_DIR="/etc/systemd/system"
SERVICES_SRC="$SCRIPT_DIR/systemd"

for svc in intercept.service vdl2-autostart.service; do
    SRC="$SERVICES_SRC/$svc"
    DST="$SYSTEMD_DIR/$svc"
    if [ ! -f "$SRC" ]; then
        warn "Service file not found: $SRC — skipping"
        continue
    fi
    cp "$SRC" "$DST"
    ok "Installed $svc"
done

# =============================================================================
section "6. VDL2 autostart script"
# =============================================================================
VDL2_SCRIPT_SRC="$SCRIPT_DIR/intercept-vdl2-start.sh"
VDL2_SCRIPT_DST="$REAL_HOME/intercept-vdl2-start.sh"

if [ -f "$VDL2_SCRIPT_SRC" ]; then
    cp "$VDL2_SCRIPT_SRC" "$VDL2_SCRIPT_DST"
    chown "$REAL_USER:$REAL_USER" "$VDL2_SCRIPT_DST"
    chmod +x "$VDL2_SCRIPT_DST"
    ok "VDL2 autostart script installed to $VDL2_SCRIPT_DST"
else
    warn "intercept-vdl2-start.sh not found in $SCRIPT_DIR"
fi

# =============================================================================
section "7. systemd — Enable and start services"
# =============================================================================
systemctl daemon-reload

for svc in intercept.service vdl2-autostart.service; do
    systemctl enable "$svc" 2>/dev/null && ok "Enabled $svc" || warn "Could not enable $svc"
done

info "Starting intercept.service..."
systemctl restart intercept.service && ok "intercept.service started" || fail "intercept.service failed to start — check: journalctl -u intercept.service"

# =============================================================================
section "8. Verification"
# =============================================================================
sleep 5

echo ""
PASS=0; FAIL=0

check() {
    local label="$1"; local cmd="$2"
    if eval "$cmd" >/dev/null 2>&1; then
        ok "$label"; PASS=$((PASS+1))
    else
        warn "FAIL: $label"; FAIL=$((FAIL+1))
    fi
}

check "intercept.service active"        "systemctl is-active intercept.service"
check "vdl2-autostart.service enabled"  "systemctl is-enabled vdl2-autostart.service"
check "Port 5050 listening"             "ss -tlnp | grep -q 5050"
check "BPF restriction active"          "sysctl kernel.unprivileged_bpf_disabled | grep -q = 1"
check "DVB driver blacklisted"          "grep -q dvb_usb_rtl28xxu /etc/modprobe.d/blacklist-rtl-dvb.conf"
check "flask-sock installed"            "[ -x \"$VENV_PIP\" ] && $VENV_PIP show flask-sock"

echo ""
echo -e "${BOLD}Results: ${GREEN}${PASS} passed${NC}  ${YELLOW}${FAIL} warnings${NC}"
echo ""
if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}Setup complete!${NC}"
    # Determine LAN IP
    LAN_IP=$(hostname -I 2>/dev/null | awk "{print \$1}")
    echo -e "  INTERCEPT UI → ${BOLD}http://${LAN_IP:-<device-ip>}:5050${NC}"
    echo -e "  Logs         → tail -f /var/log/intercept.log | grep -v GPS"
    echo -e "  VDL2 auto-starts ~15s after intercept is ready"
else
    echo -e "${YELLOW}Setup completed with warnings. Review output above.${NC}"
fi
echo ""
