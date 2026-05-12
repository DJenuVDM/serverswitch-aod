#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

print_step()  { echo -e "\n${BLUE}${BOLD}▶ $1${NC}"; }
print_ok()    { echo -e "${GREEN}✓ $1${NC}"; }
print_warn()  { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }

clear
echo -e "${BOLD}"
echo "   _   ___  ___  "
echo "  /_\ / _ \|   \ "
echo " / _ \ (_) | |) |"
echo "/_/ \_\___/|___/ "
echo -e "${NC}"
echo -e "  ${BOLD}ServerSwitch AOD${NC} — Always-On Device updater"
echo "  Updates files without touching your config or token."
echo ""
echo "─────────────────────────────────────────────────────"

if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root: sudo bash update.sh"
    exit 1
fi

# Default install directory (same as install.sh)
INSTALL_DIR="/opt/serverswitch-aod"

# Verify AOD is actually installed
if [ ! -d "$INSTALL_DIR" ]; then
    print_error "ServerSwitch AOD does not appear to be installed at $INSTALL_DIR."
    echo -e "  Run ${BOLD}sudo bash install.sh${NC} first."
    exit 1
fi

if [ ! -f "$INSTALL_DIR/config.env" ]; then
    print_error "config.env not found in $INSTALL_DIR. Installation may be incomplete."
    exit 1
fi

# Load existing config so we can display it
source "$INSTALL_DIR/config.env"

echo ""
echo -e "${BOLD}Current installation:${NC}"
echo ""
echo -e "  Install dir : ${BOLD}$INSTALL_DIR${NC}"
echo -e "  Port        : ${BOLD}$PORT${NC}"
echo -e "  Broadcast   : ${BOLD}$BROADCAST${NC}"
echo -e "  Token       : ${BOLD}$(echo "$AUTH_TOKEN" | sed 's/./*/g')${NC}"
echo ""
echo -e "  ${YELLOW}This will:${NC}"
echo -e "  • Stop the running service"
echo -e "  • Replace aod.py with the new version"
echo -e "  • Update the systemd service template (if changed)"
echo -e "  • Update Python packages (flask, gunicorn)"
echo -e "  • Restart the service"
echo -e "  • ${GREEN}Keep your config, token, and custom scripts untouched${NC}"
echo ""
read -p "  Continue with update? [Y/n]: " CONFIRM
CONFIRM="${CONFIRM:-Y}"
if [[ "$CONFIRM" =~ ^[Nn] ]]; then echo "Cancelled."; exit 0; fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Validate new files exist before we touch anything
if [ ! -f "$SCRIPT_DIR/aod.py" ]; then
    print_error "aod.py not found next to update.sh (looked in $SCRIPT_DIR)."
    echo -e "  Make sure aod.py is in the same directory as this script."
    exit 1
fi

print_step "Stopping service"
if systemctl is-active --quiet serverswitch-aod; then
    systemctl stop serverswitch-aod
    print_ok "Service stopped"
else
    print_warn "Service was not running — continuing anyway"
fi

print_step "Backing up current aod.py"
cp "$INSTALL_DIR/aod.py" "$INSTALL_DIR/aod.py.bak"
print_ok "Backup saved to $INSTALL_DIR/aod.py.bak"

print_step "Copying new aod.py"
cp "$SCRIPT_DIR/aod.py" "$INSTALL_DIR/aod.py"
print_ok "aod.py updated"

# Update the systemd service file if a new template is present
if [ -f "$SCRIPT_DIR/serverswitch-aod.service.template" ]; then
    print_step "Updating systemd service file"
    sed \
        -e "s|INSTALL_DIR|$INSTALL_DIR|g" \
        -e "s|PORT|$PORT|g" \
        "$SCRIPT_DIR/serverswitch-aod.service.template" \
        > /etc/systemd/system/serverswitch-aod.service
    systemctl daemon-reload
    print_ok "Service file updated"
else
    print_warn "No service template found — skipping service file update"
fi

print_step "Updating Python packages"
"$INSTALL_DIR/venv/bin/pip" install --quiet --upgrade flask gunicorn
print_ok "flask, gunicorn updated"

print_step "Starting service"
systemctl start serverswitch-aod
print_ok "Service started"

print_step "Verifying"
sleep 2
if curl -s "http://localhost:$PORT/ping" | grep -q "aod"; then
    print_ok "AOD is responding on port $PORT"
else
    print_warn "AOD may not be up yet — check: systemctl status serverswitch-aod"
    echo ""
    echo -e "  ${YELLOW}To roll back to the previous version:${NC}"
    echo -e "  ${BOLD}cp $INSTALL_DIR/aod.py.bak $INSTALL_DIR/aod.py${NC}"
    echo -e "  ${BOLD}systemctl restart serverswitch-aod${NC}"
fi

echo ""
echo "─────────────────────────────────────────────────────"
echo -e "  ${GREEN}${BOLD}✓ ServerSwitch AOD updated!${NC}"
echo ""
echo -e "  Status  : ${BOLD}systemctl status serverswitch-aod${NC}"
echo -e "  Logs    : ${BOLD}tail -f $INSTALL_DIR/serverswitch-aod.log${NC}"
echo -e "  Rollback: ${BOLD}cp $INSTALL_DIR/aod.py.bak $INSTALL_DIR/aod.py && systemctl restart serverswitch-aod${NC}"
echo "─────────────────────────────────────────────────────"
echo ""
