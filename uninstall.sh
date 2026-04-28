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
echo -e "  ${BOLD}ServerSwitch AOD${NC} — Always-On Device uninstaller"
echo "  Completely removes ServerSwitch AOD from your system."
echo ""
echo "─────────────────────────────────────────────────────"

if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root: sudo bash uninstall.sh"
    exit 1
fi

echo ""
echo -e "${BOLD}This will completely remove ServerSwitch AOD.${NC}"
echo ""
echo -e "  ${YELLOW}This will:${NC}"
echo -e "  • Stop and disable the systemd service"
echo -e "  • Remove the service file"
echo -e "  • Delete the install directory and all files"
echo ""
read -p "  Continue with uninstall? [y/N]: " CONFIRM
CONFIRM="${CONFIRM:-N}"
if [[ ! "$CONFIRM" =~ ^[Yy] ]]; then echo "Cancelled."; exit 0; fi

# Default install directory (same as install.sh)
INSTALL_DIR="/opt/serverswitch-aod"

if [ -d "$INSTALL_DIR" ]; then
    print_step "Stopping and disabling service"
    systemctl stop serverswitch-aod 2>/dev/null || print_warn "Service not running"
    systemctl disable serverswitch-aod 2>/dev/null || print_warn "Service not enabled"
    print_ok "Service stopped and disabled"

    print_step "Removing systemd service file"
    rm -f /etc/systemd/system/serverswitch-aod.service
    systemctl daemon-reload
    print_ok "Service file removed"

    print_step "Removing install directory"
    rm -rf "$INSTALL_DIR"
    print_ok "Directory $INSTALL_DIR removed"
else
    print_warn "Install directory $INSTALL_DIR not found"
fi

# Check if service file exists separately (in case of custom install)
if [ -f /etc/systemd/system/serverswitch-aod.service ]; then
    print_step "Removing orphaned service file"
    rm -f /etc/systemd/system/serverswitch-aod.service
    systemctl daemon-reload
    print_ok "Orphaned service file removed"
fi

echo ""
echo "─────────────────────────────────────────────────────"
echo -e "  ${GREEN}${BOLD}✓ ServerSwitch AOD uninstalled!${NC}"
echo ""
echo -e "  ${YELLOW}Note: Python packages (flask, gunicorn) were not removed${NC}"
echo -e "  as they may be used by other applications. Remove manually if needed:"
echo -e "  ${BOLD}pip3 uninstall flask gunicorn${NC}"
echo ""