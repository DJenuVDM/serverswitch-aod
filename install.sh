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
echo -e "  ${BOLD}ServerSwitch AOD${NC} — Always-On Device installer"
echo "  Runs on your Pi, NAS, or any always-on Linux machine."
echo ""
echo "─────────────────────────────────────────────────────"

if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root: sudo bash install.sh"
    exit 1
fi

echo ""
echo -e "${BOLD}Let's configure your AOD install.${NC}"
echo ""

read -p "  Install directory [/opt/serverswitch-aod]: " INSTALL_DIR
INSTALL_DIR="${INSTALL_DIR:-/opt/serverswitch-aod}"

read -p "  Port to listen on [5051]: " PORT
PORT="${PORT:-5051}"

echo ""
echo -e "  ${YELLOW}Choose an auth token for this AOD."
echo -e "  You'll enter this in the Android app when adding the AOD.${NC}"
echo ""
while true; do
    read -s -p "  Auth token: " TOKEN
    echo ""
    read -s -p "  Confirm token: " TOKEN2
    echo ""
    if [ "$TOKEN" = "$TOKEN2" ] && [ -n "$TOKEN" ]; then
        break
    fi
    print_warn "Tokens don't match or empty, try again."
done

# WoL broadcast address
echo ""
echo -e "  ${YELLOW}What is the broadcast address of this network?"
echo -e "  Usually your subnet with .255 at the end."
echo -e "  e.g. if your IP is 192.168.1.x, enter 192.168.1.255${NC}"
read -p "  Broadcast address [255.255.255.255]: " BROADCAST
BROADCAST="${BROADCAST:-255.255.255.255}"

echo ""
echo "─────────────────────────────────────────────────────"
echo -e "  Install dir : ${BOLD}$INSTALL_DIR${NC}"
echo -e "  Port        : ${BOLD}$PORT${NC}"
echo -e "  Broadcast   : ${BOLD}$BROADCAST${NC}"
echo -e "  Token       : ${BOLD}$(echo "$TOKEN" | sed 's/./*/g')${NC}"
echo "─────────────────────────────────────────────────────"
echo ""
read -p "  Install now? [Y/n]: " CONFIRM
CONFIRM="${CONFIRM:-Y}"
if [[ "$CONFIRM" =~ ^[Nn] ]]; then echo "Cancelled."; exit 0; fi

print_step "Creating directories"
mkdir -p "$INSTALL_DIR/scripts"
print_ok "Created $INSTALL_DIR and $INSTALL_DIR/scripts"

print_step "Installing system dependencies"
apt-get update -qq
apt-get install -y -qq python3 python3-venv python3-pip
print_ok "Python installed"

print_step "Creating virtual environment"
python3 -m venv "$INSTALL_DIR/venv"
print_ok "Venv created"

print_step "Installing Python packages"
"$INSTALL_DIR/venv/bin/pip" install --quiet flask gunicorn
print_ok "flask, gunicorn installed"

print_step "Copying files"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SCRIPT_DIR/aod.py" "$INSTALL_DIR/aod.py"
print_ok "aod.py copied"

# Example wake script
cat > "$INSTALL_DIR/scripts/example.sh" << 'SCRIPT'
#!/bin/bash
# Example custom wake script
# Replace this with whatever command wakes your device
# e.g. IPMI, smart plug API call, etc.
echo "Custom wake script ran at $(date)"
SCRIPT
chmod +x "$INSTALL_DIR/scripts/example.sh"
print_ok "Example script created at $INSTALL_DIR/scripts/example.sh"

print_step "Writing config"
cat > "$INSTALL_DIR/config.env" << EOF
# ServerSwitch AOD config
AUTH_TOKEN=$TOKEN
PORT=$PORT
BROADCAST=$BROADCAST
EOF
chmod 600 "$INSTALL_DIR/config.env"
print_ok "config.env written"

print_step "Installing systemd service"
sed \
    -e "s|INSTALL_DIR|$INSTALL_DIR|g" \
    -e "s|PORT|$PORT|g" \
    "$SCRIPT_DIR/serverswitch-aod.service.template" \
    > /etc/systemd/system/serverswitch-aod.service

systemctl daemon-reload
systemctl enable serverswitch-aod
systemctl restart serverswitch-aod
print_ok "Service installed and started"

print_step "Verifying"
sleep 2
if curl -s "http://localhost:$PORT/ping" | grep -q "aod"; then
    print_ok "AOD is responding on port $PORT"
else
    print_warn "AOD may not be up yet — check: systemctl status serverswitch-aod"
fi

echo ""
echo "─────────────────────────────────────────────────────"
echo -e "  ${GREEN}${BOLD}✓ ServerSwitch AOD installed!${NC}"
echo ""
echo -e "  Status  : ${BOLD}systemctl status serverswitch-aod${NC}"
echo -e "  Logs    : ${BOLD}tail -f $INSTALL_DIR/serverswitch-aod.log${NC}"
echo -e "  Scripts : ${BOLD}$INSTALL_DIR/scripts/${NC}"
echo ""
echo -e "  ${YELLOW}Add a custom wake script:${NC}"
echo -e "  ${BOLD}nano $INSTALL_DIR/scripts/mydevice.sh${NC}"
echo -e "  ${BOLD}chmod +x $INSTALL_DIR/scripts/mydevice.sh${NC}"
echo ""
echo -e "  ${YELLOW}Add this AOD to your ServerSwitch Android app:${NC}"
echo -e "  IP    : $(hostname -I | awk '{print $1}')"
echo -e "  Port  : $PORT"
echo -e "  Token : $TOKEN"
echo "─────────────────────────────────────────────────────"
echo ""
