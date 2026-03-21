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
DIM='\033[2m'
NC='\033[0m'

# --- Output helpers ---
# These write to both terminal and log file

ok()   { echo -e "  ${GREEN}${BOLD}✓${NC} $*"; echo "[ok] $*" >> "$LOG_FILE"; }
warn() { echo -e "  ${YELLOW}${BOLD}⚠${NC} $*"; echo "[warn] $*" >> "$LOG_FILE"; }
err()  { echo -e "  ${RED}${BOLD}✗${NC} $*" >&2; echo "[err] $*" >> "$LOG_FILE"; }
note() { echo -e "  ${DIM}$*${NC}"; }

# --- Spinner ---
# Runs a command in the background with an animated spinner.
# Shows ✓ on success, ✗ on failure. Command output goes to log only.
spin() {
    local msg="$1"; shift
    local tmplog
    tmplog=$(mktemp)

    # Run command in background
    "$@" > "$tmplog" 2>&1 &
    local pid=$!

    # Braille spinner frames
    local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    # Hide cursor during spinner
    tput civis 2>/dev/null || true

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}%s${NC} %s" "${frames:i%${#frames}:1}" "$msg"
        i=$((i + 1))
        sleep 0.1
    done

    wait "$pid"
    local rc=$?

    # Restore cursor
    tput cnorm 2>/dev/null || true

    # Clear the spinner line
    printf "\r\033[K"

    # Append command output to log file
    {
        echo "--- $msg ---"
        cat "$tmplog"
        echo ""
    } >> "$LOG_FILE" 2>/dev/null
    rm -f "$tmplog"

    # Show result
    if [[ $rc -eq 0 ]]; then
        ok "$msg"
    else
        err "$msg (see ${LOG_FILE})"
        return $rc
    fi
}

# --- Pre-flight checks ---

mkdir -p "$(dirname "$LOG_FILE")"
: > "$LOG_FILE"
echo "[$(date)] EVLBOX Core v${EVLBOX_CORE_VERSION} installer" >> "$LOG_FILE"

# Trap: restore cursor + show error
trap 'tput cnorm 2>/dev/null; err "Install failed at line ${LINENO}. See ${LOG_FILE}"' ERR

if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root."
    exit 1
fi

if [[ ! -f /etc/debian_version ]]; then
    err "This installer requires Debian or Ubuntu."
    exit 1
fi

# Connectivity check using bash built-in (no curl/ping needed on minimal installs)
if ! bash -c 'exec 3<>/dev/tcp/google.com/80' 2>/dev/null; then
    err "Cannot reach the internet. Check your network connection."
    exit 1
fi

# --- Banner ---
echo ""
echo -e "  ${CYAN}${BOLD}╔══════════════════════════════════════╗${NC}"
echo -e "  ${CYAN}${BOLD}║     EVLBOX Core v${EVLBOX_CORE_VERSION} Installer     ║${NC}"
echo -e "  ${CYAN}${BOLD}╚══════════════════════════════════════╝${NC}"
echo ""
note "Log: ${LOG_FILE}"
echo ""

# --- System updates ---

spin "Updating package lists" \
    apt-get update -qq

spin "Installing base packages" \
    apt-get install -y -qq \
    curl git ca-certificates gnupg lsb-release \
    ufw fail2ban unattended-upgrades apt-listchanges \
    whiptail jq

# --- Docker ---

if ! command -v docker &>/dev/null; then
    spin "Installing Docker" \
        bash -c 'curl -fsSL https://get.docker.com | sh && systemctl enable --now docker'
else
    ok "Docker already installed"
fi

if ! docker compose version &>/dev/null; then
    err "Docker Compose plugin not found"
    exit 1
fi

note "Docker $(docker --version | awk '{print $3}' | tr -d ',')"

# --- Gum (TUI toolkit from Charm) ---

if ! command -v gum &>/dev/null; then
    spin "Installing Gum (TUI toolkit)" \
        bash -c 'mkdir -p /etc/apt/keyrings && \
        curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg && \
        echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" > /etc/apt/sources.list.d/charm.list && \
        apt-get update -qq && \
        apt-get install -y -qq gum'
else
    ok "Gum already installed"
fi

# --- UFW ---

spin "Configuring firewall" \
    bash -c 'ufw default deny incoming > /dev/null && \
    ufw default allow outgoing > /dev/null && \
    ufw allow 22/tcp > /dev/null && \
    ufw allow 80/tcp > /dev/null && \
    ufw allow 443/tcp > /dev/null && \
    ufw limit 22/tcp > /dev/null && \
    ufw --force enable > /dev/null'

note "SSH, HTTP, HTTPS allowed — SSH rate-limited"

# --- fail2ban ---

cat > /etc/fail2ban/jail.local << 'JAIL'
[sshd]
enabled = true
port = ssh
maxretry = 5
bantime = 3600
findtime = 600
JAIL

spin "Configuring fail2ban" \
    bash -c 'systemctl enable --now fail2ban > /dev/null 2>&1 && systemctl restart fail2ban'

note "SSH: 5 retries then 1hr ban"

# --- Unattended upgrades ---

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'AUTOUPGRADE'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
AUTOUPGRADE

ok "Unattended security upgrades enabled"

# --- Diun (container update notifications) ---

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

spin "Starting Diun (update watcher)" \
    docker compose -f /opt/evlbox/diun/compose.yml up -d

# --- evlbox CLI ---

mkdir -p /opt/evlbox/backups
mkdir -p /opt/evlbox/stack

# Detect if running from cloned repo or piped via curl
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" != "/dev/stdin" && -f "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || true
fi

if [[ -n "$SCRIPT_DIR" && -f "${SCRIPT_DIR}/cli/evlbox" ]]; then
    cp "${SCRIPT_DIR}/cli/evlbox" /usr/local/bin/evlbox
else
    # Download from main branch (use versioned tag once releases are cut)
    curl -fsSL "https://raw.githubusercontent.com/evlbox/evlbox-core/main/cli/evlbox" \
        -o /usr/local/bin/evlbox
fi
chmod +x /usr/local/bin/evlbox

ok "evlbox CLI installed"

# --- Branded MOTD ---

# Clear static MOTD (we use profile.d for colored version)
> /etc/motd

# Disable default dynamic MOTD scripts
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

ok "Login message configured"

# --- Maintenance cron jobs ---

cat > /etc/cron.d/evlbox-maintenance << 'CRON'
# Weekly Docker cleanup (Sunday 3 AM)
0 3 * * 0 root docker system prune -f > /dev/null 2>&1

# Disk usage alert (daily 6 AM)
0 6 * * * root df -h / | awk 'NR==2 {gsub(/%/,"",$5); if ($5 > 80) print "EVLBOX WARNING: Disk usage at "$5"%%"}' | logger -t evlbox
CRON

ok "Maintenance cron jobs set"

# --- Done ---

echo ""
echo -e "  ${GREEN}${BOLD}══════════════════════════════════════${NC}"
echo -e "  ${GREEN}${BOLD}  EVLBOX Core v${EVLBOX_CORE_VERSION} installed ✓     ${NC}"
echo -e "  ${GREEN}${BOLD}══════════════════════════════════════${NC}"
echo ""
note "Stack dir:  /opt/evlbox/stack/"
note "Backups:    /opt/evlbox/backups/"
note "Log:        ${LOG_FILE}"
echo ""
