#!/usr/bin/env bash
#
# install.sh — EVLBOX Core base layer installer
#
# Called by each stack's provision.sh at deploy time.
# Installs: Docker, Docker Compose, UFW, fail2ban, Diun,
#           unattended-upgrades, Gum (TUI), evlbox CLI, branded MOTD.
#
# NOTE: Caddy runs in Docker as part of each stack's compose.yml.
# It is NOT installed at the system level by this script.
#
# Usage (from a stack's provision.sh):
#   curl -fsSL https://raw.githubusercontent.com/evlbox/evlbox-core/main/install.sh | bash
#
# Or from a cloned repo:
#   sudo bash install.sh

set -euo pipefail

EVLBOX_CORE_VERSION="0.1.0"
LOG_FILE="/var/log/evlbox-install.log"

# --- Colors ---
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[evlbox]${NC} $*"; }
ok()    { echo -e "${GREEN}[evlbox]${NC} $*"; }
warn()  { echo -e "${YELLOW}[evlbox]${NC} $*"; }
err()   { echo -e "${RED}[evlbox]${NC} $*" >&2; }

# --- Logging: mirror all output to log file ---
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

# --- Error trap ---
trap 'err "Installation failed at line ${LINENO}. Check ${LOG_FILE} for details."' ERR

# --- Pre-flight checks ---

if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root."
    exit 1
fi

if [[ ! -f /etc/debian_version ]]; then
    err "This installer requires Debian or Ubuntu."
    exit 1
fi

if ! curl -fsSL --connect-timeout 5 https://get.docker.com > /dev/null 2>&1; then
    err "Cannot reach the internet. Check your network connection."
    exit 1
fi

info "Installing EVLBOX Core v${EVLBOX_CORE_VERSION}..."
info "Log file: ${LOG_FILE}"
echo ""

# --- System updates ---

info "Updating package lists..."
apt-get update -qq

info "Installing base packages..."
apt-get install -y -qq \
    curl \
    git \
    ca-certificates \
    gnupg \
    lsb-release \
    ufw \
    fail2ban \
    unattended-upgrades \
    apt-listchanges \
    whiptail \
    jq \
    > /dev/null

# --- Docker ---

info "Installing Docker..."
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
else
    info "Docker already installed, skipping."
fi

if ! docker compose version &>/dev/null; then
    err "Docker Compose plugin not found. Docker install may have failed."
    exit 1
fi
ok "Docker $(docker --version | awk '{print $3}' | tr -d ',') ready."

# --- Gum (TUI toolkit from Charm) ---

info "Installing Gum..."
if ! command -v gum &>/dev/null; then
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
        > /etc/apt/sources.list.d/charm.list
    apt-get update -qq
    apt-get install -y -qq gum > /dev/null
else
    info "Gum already installed, skipping."
fi

# --- UFW ---

info "Configuring firewall..."
ufw default deny incoming > /dev/null
ufw default allow outgoing > /dev/null
ufw allow 22/tcp  > /dev/null    # SSH
ufw allow 80/tcp  > /dev/null    # HTTP
ufw allow 443/tcp > /dev/null    # HTTPS
ufw limit 22/tcp  > /dev/null    # Rate-limit SSH
ufw --force enable > /dev/null
ok "Firewall active (SSH, HTTP, HTTPS allowed)."

# --- fail2ban ---

info "Configuring fail2ban..."
cat > /etc/fail2ban/jail.local << 'JAIL'
[sshd]
enabled = true
port = ssh
maxretry = 5
bantime = 3600
findtime = 600
JAIL
systemctl enable --now fail2ban > /dev/null 2>&1
systemctl restart fail2ban
ok "fail2ban active (SSH: 5 retries, 1hr ban)."

# --- Unattended upgrades ---

info "Enabling unattended security upgrades..."
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'AUTOUPGRADE'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
AUTOUPGRADE

# --- Diun (container update notifications) ---

info "Setting up Diun..."
mkdir -p /opt/evlbox/diun
cat > /opt/evlbox/diun/compose.yml << 'DIUN'
services:
  diun:
    image: crazymax/diun:latest
    container_name: diun
    restart: unless-stopped
    command: serve
    volumes:
      - diun-data:/data
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      - TZ=UTC
      - DIUN_WATCH_SCHEDULE=0 6 * * *
      - DIUN_PROVIDERS_DOCKER=true
      - DIUN_PROVIDERS_DOCKER_WATCHBYDEFAULT=true

volumes:
  diun-data:
DIUN
docker compose -f /opt/evlbox/diun/compose.yml up -d
ok "Diun active (daily image update checks)."

# --- evlbox CLI ---

info "Installing evlbox CLI..."
mkdir -p /opt/evlbox/backups
mkdir -p /opt/evlbox/stack

# Detect if running from cloned repo or piped via curl
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" != "/dev/stdin" && -f "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || true
fi

if [[ -n "$SCRIPT_DIR" && -f "${SCRIPT_DIR}/cli/evlbox" ]]; then
    cp "${SCRIPT_DIR}/cli/evlbox" /usr/local/bin/evlbox
    info "Installed CLI from local repo."
else
    curl -fsSL "https://raw.githubusercontent.com/evlbox/evlbox-core/v${EVLBOX_CORE_VERSION}/cli/evlbox" \
        -o /usr/local/bin/evlbox
    info "Downloaded CLI from GitHub."
fi
chmod +x /usr/local/bin/evlbox

# --- Branded MOTD ---

info "Setting up login message..."

# Clear static MOTD (we use profile.d for colored version)
> /etc/motd

# Disable default dynamic MOTD scripts if they exist
chmod -x /etc/update-motd.d/* 2>/dev/null || true

# Colored MOTD via profile.d (shown on interactive login)
cat > /etc/profile.d/evlbox.sh << 'PROFILE'
# EVLBOX branded login message
if [ -t 1 ] && [ -z "${EVLBOX_MOTD_SHOWN:-}" ]; then
    export EVLBOX_MOTD_SHOWN=1
    C='\033[0;36m'
    B='\033[1m'
    D='\033[2m'
    N='\033[0m'
    echo ""
    echo -e "${C}${B}  ╔══════════════════════════════════════════╗${N}"
    echo -e "${C}${B}  ║            Welcome to EVLBOX             ║${N}"
    echo -e "${C}${B}  ╚══════════════════════════════════════════╝${N}"
    echo ""
    echo -e "  ${D}Get started:${N}   evlbox setup"
    echo -e "  ${D}Check status:${N}  evlbox status"
    echo -e "  ${D}View help:${N}     evlbox help"
    echo ""
    echo -e "  ${D}Docs:${N} https://evlbox.com/docs"
    echo ""
fi
PROFILE

# --- Maintenance cron jobs ---

info "Setting up maintenance cron jobs..."
cat > /etc/cron.d/evlbox-maintenance << 'CRON'
# Weekly Docker cleanup (Sunday 3 AM)
0 3 * * 0 root docker system prune -f > /dev/null 2>&1

# Disk usage alert (daily 6 AM)
0 6 * * * root df -h / | awk 'NR==2 {gsub(/%/,"",$5); if ($5 > 80) print "EVLBOX WARNING: Disk usage at "$5"%%"}' | logger -t evlbox
CRON

# --- Done ---

echo ""
ok "════════════════════════════════════════"
ok " EVLBOX Core v${EVLBOX_CORE_VERSION} installed"
ok "════════════════════════════════════════"
echo ""
info "Stack directory:  /opt/evlbox/stack/"
info "Backup directory: /opt/evlbox/backups/"
info "Log file:         ${LOG_FILE}"
echo ""
