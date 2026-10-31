#!/usr/bin/env bash
# ==============================================================================
# BombSquad Modded Server - Automated Setup & Installer Script
# Target OS: Ubuntu 26+ (Linux x86_64 / aarch64)
# Python: 3.14
# Branch: main
# ==============================================================================

# Interactivity detection
INTERACTIVE=true
AUTO_YES=false
# If stdin is not a terminal and /dev/tty is not accessible, fallback to non-interactive mode
if [ ! -t 0 ] && [ ! -c /dev/tty ]; then
    INTERACTIVE=false
    AUTO_YES=true
fi

# Exit on critical unhandled errors
set -o pipefail

# ANSI color codes
if [ -t 1 ]; then
    BOLD="\033[1m"
    DIM="\033[2m"
    RED="\033[31m"
    GREEN="\033[32m"
    YELLOW="\033[33m"
    BLUE="\033[34m"
    MAGENTA="\033[35m"
    CYAN="\033[36m"
    RESET="\033[0m"
else
    BOLD=""
    DIM=""
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    MAGENTA=""
    CYAN=""
    RESET=""
fi

# Logging functions
log_info() { echo -e "${CYAN}[i]${RESET} $1"; }
log_success() { echo -e "${GREEN}[✓]${RESET} $1"; }
log_warn() { echo -e "${YELLOW}[!]${RESET} $1"; }
log_error() { echo -e "${RED}[✗] ERROR:${RESET} $1" >&2; }
log_step() { echo -e "\n${BOLD}${BLUE}==>${RESET} ${BOLD}$1${RESET}"; }

# Banner
print_banner() {
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
 ____                  _     ____                      _ 
| __ )  ___  _ __ ___ | |__ / ___|  __ _ _   _  __ _  __| |
|  _ \ / _ \| '_ ` _ \| '_ \\___ \ / _` | | | |/ _` |/ _` |
| |_) | (_) | | | | | | |_) |___) | (_| | |_| | (_| | (_| |
|____/ \___/|_| |_| |_|_.__/|____/ \__, |\__,_|\__,_|\__,_|
                                      |_|                  
EOF
    echo -e "${RESET}${BOLD} BombSquad Ballistica Modded Server - Automated Setup${RESET}"
    echo -e "${DIM} Target: Ubuntu 26+ | Python 3.14 | Branch: ${REPO_BRANCH}${RESET}\n"
}

# Defaults
TARGET_DIR="Bombsquad-Ballistica-Modded-Server"
REPO_BRANCH="main"
REPO_URL="https://github.com/ainahrm/aina-bombsquad-server.git"
TMUX_SESSION="bombsquad"
SYSTEMD_SERVICE="bombsquad-server"
START_SERVER=true
SKIP_CLONE=false
INSTALL_DIR=""

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes|--non-interactive)
            AUTO_YES=true
            INTERACTIVE=false
            shift
            ;;
        -d|--dir)
            TARGET_DIR="$2"
            shift 2
            ;;
        -b|--branch)
            REPO_BRANCH="$2"
            shift 2
            ;;
        -s|--session)
            TMUX_SESSION="$2"
            shift 2
            ;;
        --no-start)
            START_SERVER=false
            shift
            ;;
        -h|--help)
            echo "Usage: bash setup.sh [options]"
            echo "Options:"
            echo "  -y, --yes              Non-interactive mode (accept defaults)"
            echo "  -d, --dir <path>       Custom directory to install server"
            echo "  -b, --branch <name>    Git branch to clone (default: main)"
            echo "  -s, --session <name>   Tmux session name (default: bombsquad)"
            echo "  --no-start             Do not start server after installation"
            echo "  -h, --help             Show this help message"
            exit 0
            ;;
        *)
            log_warn "Unknown option: $1"
            shift
            ;;
    esac
done

# Prompt helper with default value
ask_prompt() {
    local prompt_text="$1"
    local default_val="$2"
    local var_name="$3"
    if [ "$AUTO_YES" = true ]; then
        eval "$var_name=\"$default_val\""
        return
    fi
    echo -ne "${BOLD}${prompt_text}${RESET} "
    local user_val=""
    if [ -c /dev/tty ] && [ -r /dev/tty ]; then
        read -r user_val < /dev/tty
    else
        read -r user_val
    fi
    if [ -z "$user_val" ]; then
        eval "$var_name=\"$default_val\""
    else
        eval "$var_name=\"$user_val\""
    fi
}

# Yes/No prompt helper
ask_yes_no() {
    local prompt_text="$1"
    local default_val="$2" # "y" or "n"
    if [ "$AUTO_YES" = true ]; then
        [ "$default_val" = "y" ] && return 0 || return 1
    fi
    local suffix="[Y/n]"
    [ "$default_val" = "n" ] && suffix="[y/N]"
    while true; do
        echo -ne "${BOLD}${prompt_text}${RESET} ${DIM}${suffix}${RESET}: "
        local answer=""
        if [ -c /dev/tty ] && [ -r /dev/tty ]; then
            read -r answer < /dev/tty
        else
            read -r answer
        fi
        answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]' | xargs)
        if [ -z "$answer" ]; then
            answer="$default_val"
        fi
        case "$answer" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) echo -e "${YELLOW}Please enter 'y' or 'n'.${RESET}" ;;
        esac
    done
}

# Prompt for a value without echoing it to the terminal. The result is stored
# in the variable named by the second argument.
ask_secret() {
    local prompt_text="$1"
    local var_name="$2"
    local secret_val=""
    echo -ne "${BOLD}${prompt_text}${RESET} "
    if [ -c /dev/tty ] && [ -r /dev/tty ]; then
        read -r -s secret_val < /dev/tty
    else
        read -r -s secret_val
    fi
    echo
    printf -v "$var_name" '%s' "$secret_val"
}

# ==============================================================================
# START OF SCRIPT
# ==============================================================================
print_banner

# Step 1: Privilege Verification
log_step "Checking user privileges..."
if [ "$EUID" -ne 0 ]; then
    log_error "Root privileges are required to run this installer."
    echo -e "\n${YELLOW}${BOLD}Please re-run the installation command with sudo:${RESET}"
    echo -e "  ${CYAN}curl -fsSL https://raw.githubusercontent.com/ainahrm/aina-bombsquad-server/main/setup.sh | sudo bash${RESET}"
    echo -e "  Or: ${CYAN}sudo bash setup.sh${RESET}\n"
    exit 1
fi
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    log_info "Running via sudo on behalf of user: $SUDO_USER"
else
    log_info "Running as root user."
fi
log_success "Privilege check passed."

# Step 2: OS Check (Minimum Ubuntu 26 required)
log_step "Validating operating system..."
if [ "$(uname -s)" != "Linux" ]; then
    log_error "Unsupported operating system: $(uname -s). Linux is required."
    exit 1
fi

IS_UBUNTU=false
UBUNTU_VER=0
OS_NAME="Linux"

if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_NAME="${PRETTY_NAME:-$NAME}"
    if [ "${ID:-}" = "ubuntu" ] || [[ "${ID_LIKE:-}" =~ "ubuntu" ]]; then
        IS_UBUNTU=true
        UBUNTU_VER=$(echo "${VERSION_ID:-0}" | cut -d. -f1 | tr -cd '0-9')
    fi
fi

if [ "$IS_UBUNTU" = true ]; then
    if [ "$UBUNTU_VER" -lt 26 ]; then
        log_warn "Detected: $OS_NAME (Version ${VERSION_ID:-unknown})"
        log_warn "BombSquad Modded Server requires minimum Ubuntu 26."
        log_warn "Pre-compiled native extensions (.cpython-314-*.so) and Python 3.14 require Ubuntu 26+ runtime."
        if ! ask_yes_no "Do you want to continue anyway? (Experimental / Installation may fail)" "n"; then
            log_error "Installation cancelled. Please upgrade to Ubuntu 26 or higher."
            exit 1
        fi
    else
        log_success "Ubuntu version check passed: $OS_NAME (Version $VERSION_ID)"
    fi
else
    log_warn "Non-Ubuntu distribution detected: $OS_NAME"
    log_warn "This server is pre-configured and compiled for Ubuntu 26+ (apt package manager and Python 3.14)."
    if ! ask_yes_no "Do you want to proceed anyway?" "n"; then
        log_error "Installation cancelled."
        exit 1
    fi
fi

# Step 3: Architecture Validation
log_step "Checking processor architecture..."
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        log_success "Architecture supported: x86_64 (amd64)"
        ;;
    aarch64|arm64)
        log_success "Architecture supported: $ARCH (arm64)"
        ;;
    *)
        log_error "Unsupported architecture: $ARCH"
        log_error "BombSquad headless binaries are only provided for x86_64 and aarch64."
        exit 1
        ;;
esac

# Step 4: Memory Check & Swap Creation
log_step "Checking system memory and swap..."
if [ -f /proc/meminfo ]; then
    MEM_TOTAL_KB=$(grep -m1 MemTotal /proc/meminfo | awk '{print $2}')
    MEM_TOTAL_MB=$((MEM_TOTAL_KB / 1024))
    SWAP_TOTAL_KB=$(grep -m1 SwapTotal /proc/meminfo | awk '{print $2}')
    SWAP_TOTAL_MB=$((SWAP_TOTAL_KB / 1024))
    TOTAL_MEM_AVAIL=$((MEM_TOTAL_MB + SWAP_TOTAL_MB))

    log_info "Detected RAM: ${MEM_TOTAL_MB} MB | Swap: ${SWAP_TOTAL_MB} MB"

    if [ "$TOTAL_MEM_AVAIL" -lt 1500 ]; then
        log_warn "Low system memory detected (${MEM_TOTAL_MB} MB RAM, ${SWAP_TOTAL_MB} MB Swap)."
        log_warn "BombSquad recommends at least 1.5 GB - 2 GB of memory to prevent Out-Of-Memory (OOM) crashes."
        if ask_yes_no "Would you like to automatically create and activate a 2 GB swap file (/swapfile)?" "y"; then
            log_info "Creating 2 GB swap file at /swapfile..."
            if fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048 2>/dev/null; then
                chmod 600 /swapfile
                mkswap /swapfile >/dev/null 2>&1
                swapon /swapfile >/dev/null 2>&1
                if ! grep -q "/swapfile" /etc/fstab 2>/dev/null; then
                    echo "/swapfile none swap sw 0 0" | tee -a /etc/fstab >/dev/null
                fi
                log_success "2 GB swap file activated successfully!"
            else
                log_warn "Unable to create swap file. Ensure there is enough free disk space."
            fi
        fi
    else
        log_success "Memory requirements satisfied (${MEM_TOTAL_MB} MB RAM + ${SWAP_TOTAL_MB} MB Swap)."
    fi
fi

# Step 5: Install System Prerequisites
log_step "Updating package repositories & installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y software-properties-common curl git tmux ca-certificates procps lsof net-tools

# Step 6: Install Python 3.14
log_step "Checking Python 3.14..."
if ! command -v python3.14 >/dev/null 2>&1; then
    log_info "Python 3.14 not found. Installing Python 3.14 and development headers..."
    if ! apt-cache show python3.14 >/dev/null 2>&1; then
        log_info "Adding deadsnakes PPA..."
        add-apt-repository -y ppa:deadsnakes/ppa
        apt-get update -y
    fi
    apt-get install -y python3.14 python3.14-dev python3.14-venv python3-pip
fi

if ! command -v python3.14 >/dev/null 2>&1; then
    log_error "Python 3.14 could not be installed automatically."
    log_error "Please install python3.14 manually and re-run this script."
    exit 1
fi
PY_VER=$(python3.14 --version 2>&1)
log_success "Python 3.14 verified: $PY_VER"

# Ubuntu may install pip only for its default Python interpreter. Ensure the
# Python 3.14 interpreter used by the server has its own working pip module.
if ! python3.14 -m pip --version >/dev/null 2>&1; then
    log_info "Installing pip support for Python 3.14..."

    # On Debian/Ubuntu, ensurepip is supplied by the version-specific venv
    # package and can be missing when Python itself was installed previously.
    apt-get install -y python3.14-venv || \
        log_warn "python3.14-venv is unavailable; trying the pip bootstrap installer."

    if ! python3.14 -m ensurepip --upgrade; then
        log_warn "ensurepip is unavailable; downloading the official pip bootstrap installer..."
        GET_PIP_FILE=$(mktemp /tmp/get-pip.XXXXXX.py)
        if ! curl -fsSL https://bootstrap.pypa.io/get-pip.py -o "$GET_PIP_FILE"; then
            rm -f "$GET_PIP_FILE"
            log_error "Unable to download the pip bootstrap installer."
            exit 1
        fi
        if ! python3.14 "$GET_PIP_FILE" --break-system-packages; then
            rm -f "$GET_PIP_FILE"
            log_error "Unable to install pip for Python 3.14."
            exit 1
        fi
        rm -f "$GET_PIP_FILE"
    fi
fi

if ! python3.14 -m pip --version >/dev/null 2>&1; then
    log_error "pip was installed but cannot be loaded by Python 3.14."
    exit 1
fi
log_success "pip for Python 3.14 is available."

# Step 7: Clone Repository (selected branch with depth 1)
log_step "Setting up server repository..."

# Check if current directory is already the server repository
if [ -f "./bombsquad_server" ] && [ -d "./dist/ba_root" ]; then
    log_info "Current working directory appears to be an existing BombSquad server repository."
    if ask_yes_no "Use current directory as the installation directory?" "y"; then
        INSTALL_DIR="$(pwd)"
        SKIP_CLONE=true
    fi
fi

if [ "$SKIP_CLONE" != true ]; then
    if [ -d "$TARGET_DIR" ]; then
        log_warn "Directory '$TARGET_DIR' already exists."
        echo -e "Choose an option:"
        echo -e "  1) Use existing directory (skip cloning)"
        echo -e "  2) Backup existing directory and clone fresh"
        echo -e "  3) Cancel installation"
        ask_prompt "Enter choice [1/2/3, default: 1]:" "1" DIR_CHOICE
        case "$DIR_CHOICE" in
            1)
                INSTALL_DIR="$(cd "$TARGET_DIR" && pwd)"
                SKIP_CLONE=true
                ;;
            2)
                BACKUP_DIR="${TARGET_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
                log_info "Backing up '$TARGET_DIR' -> '$BACKUP_DIR'..."
                mv "$TARGET_DIR" "$BACKUP_DIR"
                ;;
            *)
                log_error "Installation cancelled by user."
                exit 1
                ;;
        esac
    fi
fi

if [ "$SKIP_CLONE" != true ]; then
    log_info "Cloning branch '$REPO_BRANCH' (depth=1) from $REPO_URL..."
    if ! git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$TARGET_DIR"; then
        log_error "Failed to clone repository. Please check your network connection."
        exit 1
    fi
    INSTALL_DIR="$(cd "$TARGET_DIR" && pwd)"
    log_success "Repository successfully cloned to: $INSTALL_DIR"
fi

cd "$INSTALL_DIR" || { log_error "Failed to enter directory: $INSTALL_DIR"; exit 1; }

# Reusing an existing clone must not leave old tracked code in place. Update it
# without overwriting local commits or tracked modifications. Untracked runtime
# data (including playersdata JSON files) is preserved by a fast-forward pull.
if [ "$SKIP_CLONE" = true ]; then
    if [ -d "$INSTALL_DIR/.git" ]; then
        log_info "Updating existing repository from origin/$REPO_BRANCH..."
        if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ] && [ "$EUID" -eq 0 ]; then
            UPDATE_CMD=(sudo -H -u "$SUDO_USER" git -C "$INSTALL_DIR")
        else
            UPDATE_CMD=(git -C "$INSTALL_DIR")
        fi
        if ! "${UPDATE_CMD[@]}" pull --ff-only origin "$REPO_BRANCH"; then
            log_error "Unable to update the existing repository with a fast-forward pull."
            log_error "Commit or stash tracked local changes, then run the installer again."
            exit 1
        fi
        log_success "Existing repository updated successfully."
    else
        log_warn "Existing installation is not a Git checkout; automatic code updates are unavailable."
    fi
fi

# Step 8: Set File Permissions (chmod)
log_step "Setting file permissions..."
chmod 777 bombsquad_server 2>/dev/null || chmod +x bombsquad_server
if [ -f "dist/bombsquad_headless" ]; then
    chmod 777 dist/bombsquad_headless 2>/dev/null || chmod +x dist/bombsquad_headless
fi
if [ -f "dist/bombsquad_headless_aarch64" ]; then
    chmod 777 dist/bombsquad_headless_aarch64 2>/dev/null || chmod +x dist/bombsquad_headless_aarch64
fi
log_success "Executable permissions applied to server binaries."

# If executed via sudo from a non-root SSH user, ensure that user owns the directory
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ] && [ "$EUID" -eq 0 ]; then
    chown -R "$SUDO_USER:$SUDO_USER" "$INSTALL_DIR" 2>/dev/null || true
fi

# Step 9: Pre-install Python Dependencies
log_step "Checking Python site-packages dependencies..."
TARGET_SITE="$INSTALL_DIR/dist/ba_data/python-site-packages"
mkdir -p "$TARGET_SITE"
if ! python3.14 -m pip install --upgrade --target "$TARGET_SITE" \
    --break-system-packages ecdsa flask waitress websockets; then
    log_error "Failed to install Python dependencies (including websockets)."
    exit 1
fi
log_success "Python package dependencies prepared."

# Step 10: Preserve Repository Configuration
log_step "Checking existing server configuration..."
CFG_FILE="$INSTALL_DIR/config.json"
ROLES_FILE="$INSTALL_DIR/dist/ba_root/mods/playersdata/roles.json"
SETTING_FILE="$INSTALL_DIR/dist/ba_root/mods/setting.json"

# Configure the gameplay join password once. Existing non-empty passwords are
# deliberately preserved so rerunning the installer never asks again or
# overwrites an administrator's choice.
PASSWORD_IS_SET=$(python3.14 - "$CFG_FILE" << 'PYEOF'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as input_file:
    config = json.load(input_file)
password = config.get("password")
print("yes" if isinstance(password, str) and password else "no")
PYEOF
) || {
    log_error "Unable to read the gameplay password from $CFG_FILE"
    exit 1
}

if [ "$PASSWORD_IS_SET" = "yes" ]; then
    log_info "A gameplay join password is already configured; keeping it unchanged."
else
    SERVER_PASSWORD="${BOMBSQUAD_SERVER_PASSWORD:-}"
    if [ "$AUTO_YES" != true ]; then
        while true; do
            ask_secret "Set gameplay join password:" SERVER_PASSWORD
            if [ -z "$SERVER_PASSWORD" ]; then
                log_warn "The gameplay password cannot be empty."
                continue
            fi
            ask_secret "Confirm gameplay join password:" SERVER_PASSWORD_CONFIRM
            if [ "$SERVER_PASSWORD" = "$SERVER_PASSWORD_CONFIRM" ]; then
                break
            fi
            log_warn "Passwords do not match; please try again."
        done
    elif [ -z "$SERVER_PASSWORD" ]; then
        log_warn "No gameplay password configured. Set BOMBSQUAD_SERVER_PASSWORD when using --non-interactive."
    fi

    if [ -n "$SERVER_PASSWORD" ]; then
        BOMBSQUAD_PASSWORD_VALUE="$SERVER_PASSWORD" \
            python3.14 - "$CFG_FILE" << 'PYEOF' || {
import json
import os
import sys

config_path = sys.argv[1]
with open(config_path, "r", encoding="utf-8") as input_file:
    config = json.load(input_file)
config["password"] = os.environ["BOMBSQUAD_PASSWORD_VALUE"]
with open(config_path, "w", encoding="utf-8") as output_file:
    json.dump(config, output_file, indent=4)
    output_file.write("\n")
PYEOF
            log_error "Unable to save the gameplay password to $CFG_FILE"
            exit 1
        }
        unset SERVER_PASSWORD SERVER_PASSWORD_CONFIRM BOMBSQUAD_PASSWORD_VALUE
        log_success "Gameplay join password configured."
    fi
fi

# Player data files are intentionally not tracked by Git. On a fresh clone,
# initialize an empty roles object; the server and its management tools can
# populate it later. Never overwrite an existing roles file.
if [ ! -f "$ROLES_FILE" ]; then
    log_warn "roles.json is missing; creating an empty roles configuration."
    mkdir -p "$(dirname "$ROLES_FILE")"
    printf '{}\n' > "$ROLES_FILE" || {
        log_error "Unable to create $ROLES_FILE"
        exit 1
    }
fi

# These files are already configured in the repository. Validate them, but do
# not prompt for or overwrite the party name, port, player limit, game mode,
# admin/owner IDs, roles, host name, or web password.
CFG_PORT=$(python3.14 - "$CFG_FILE" "$ROLES_FILE" "$SETTING_FILE" << 'PYEOF'
import json
import sys

config_path, roles_path, setting_path = sys.argv[1:]
documents = {}
for label, path in (
    ("config.json", config_path),
    ("roles.json", roles_path),
    ("setting.json", setting_path),
):
    try:
        with open(path, "r", encoding="utf-8") as input_file:
            documents[label] = json.load(input_file)
    except (OSError, ValueError) as exc:
        raise SystemExit(f"Invalid or missing {label}: {exc}")

port = documents["config.json"].get("port", 43211)
if not isinstance(port, int) or not 1024 <= port <= 65535:
    raise SystemExit(f"Invalid UDP port in config.json: {port!r}")
print(port)
PYEOF
) || {
    log_error "Existing server configuration validation failed."
    exit 1
}
log_success "config.json, roles.json, and setting.json are valid."
log_info "Using configured UDP port: $CFG_PORT"

# Print installation summary
print_summary() {
    echo -e "\n${GREEN}${BOLD}================================================================${RESET}"
    echo -e "${GREEN}${BOLD}       🎉 BombSquad Modded Server Setup Complete! 🎉            ${RESET}"
    echo -e "${GREEN}${BOLD}================================================================${RESET}"
    echo -e " ${BOLD}Installation Directory:${RESET}  $INSTALL_DIR"
    echo -e " ${BOLD}Systemd Service:${RESET}         $SYSTEMD_SERVICE.service"
    echo -e " ${BOLD}Server Config File:${RESET}      $INSTALL_DIR/config.json"
    echo -e " ${BOLD}Roles Configuration:${RESET}     $INSTALL_DIR/dist/ba_root/mods/playersdata/roles.json"
    echo -e " ${BOLD}Extra Mod Settings:${RESET}      $INSTALL_DIR/dist/ba_root/mods/setting.json"
    echo -e "----------------------------------------------------------------"
    echo -e " ${BOLD}Server Management Cheat Sheet:${RESET}"
    echo -e "   • Live logs:             ${CYAN}sudo journalctl -fu $SYSTEMD_SERVICE${RESET}"
    echo -e "   • Status:                ${CYAN}sudo systemctl status $SYSTEMD_SERVICE${RESET}"
    echo -e "   • Restart:               ${CYAN}sudo systemctl restart $SYSTEMD_SERVICE${RESET}"
    echo -e "   • Stop:                  ${CYAN}sudo systemctl stop $SYSTEMD_SERVICE${RESET}"
    echo -e "----------------------------------------------------------------"
    echo -e " ${BOLD}Firewall Notice:${RESET}"
    echo -e "   Ensure your server's UDP port is open in your cloud/VPS firewall:"
    echo -e "   ${DIM}sudo ufw allow ${CFG_PORT:-43211}/udp${RESET}"
    echo -e "${GREEN}${BOLD}================================================================${RESET}\n"
}

# Step 11: Persistent systemd service
log_step "Installing persistent server service"

SERVICE_USER="root"
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    SERVICE_USER="$SUDO_USER"
fi
SERVICE_GROUP="$(id -gn "$SERVICE_USER")"
SERVICE_FILE="/etc/systemd/system/$SYSTEMD_SERVICE.service"

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=BombSquad Ballistica Dedicated Server
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/bombsquad_server --noninteractive
Restart=always
RestartSec=5
TimeoutStopSec=30
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "$SERVICE_FILE"
systemctl daemon-reload
systemctl enable "$SYSTEMD_SERVICE.service"
log_success "Installed and enabled $SYSTEMD_SERVICE.service for automatic restart and boot startup."

if [ "$START_SERVER" = true ]; then
    # Stop an older installer-created tmux process before systemd takes over
    # so the two processes cannot compete for the same UDP port.
    if sudo -u "$SERVICE_USER" tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        log_info "Stopping legacy tmux session '$TMUX_SESSION'..."
        sudo -u "$SERVICE_USER" tmux kill-session -t "$TMUX_SESSION"
    fi

    systemctl restart "$SYSTEMD_SERVICE.service"
    sleep 3
    if systemctl is-active --quiet "$SYSTEMD_SERVICE.service"; then
        log_success "Server is running under systemd supervision."
    else
        log_error "Server failed to remain active. Recent service logs follow:"
        journalctl -u "$SYSTEMD_SERVICE.service" -n 50 --no-pager >&2
        exit 1
    fi
fi

print_summary
