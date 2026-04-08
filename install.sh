#!/bin/bash

# ============================================================
#  VPN Manager - Automated Installer
#  Usage: sudo bash <(curl -s https://raw.githubusercontent.com/x-cinema-pro/autoinstaller/main/install.sh)
# ============================================================

# --- COLORS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

REPO_RAW="https://raw.githubusercontent.com/x-cinema-pro/autoinstaller/main"
WEB_DIR="/var/www/html"
OUTLINE_ACCESS_FILE="/opt/outline/access.txt"
OUTLINE_INSTALL_SCRIPT="https://raw.githubusercontent.com/Jigsaw-Code/outline-server/master/src/server_manager/install_scripts/install_server.sh"

print_banner() {
    echo ""
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║       VPN Manager — Auto Installer       ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() { echo ""; echo -e "${YELLOW}${BOLD}▶ $1${NC}"; }
print_ok()   { echo -e "  ${GREEN}✔ $1${NC}"; }
print_err()  { echo -e "  ${RED}✖ $1${NC}"; }

# ============================================================
# STEP 0: Root check
# ============================================================
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Please run as root: sudo bash install.sh${NC}"
    exit 1
fi

print_banner

# ============================================================
# STEP 1: Detect or Install Outline Server
# ============================================================
print_step "Checking for Outline Server..."

parse_outline_url() {
    if [[ -f "$OUTLINE_ACCESS_FILE" ]]; then
        grep -oP '"apiUrl"\s*:\s*"\K[^"]+' "$OUTLINE_ACCESS_FILE" 2>/dev/null
    fi
}

OUTLINE_ALREADY_INSTALLED=false
OUTLINE_API_URL_INPUT=""

# Check 1: access.txt exists and has apiUrl
if [[ -f "$OUTLINE_ACCESS_FILE" ]]; then
    DETECTED_URL=$(parse_outline_url)
    if [[ -n "$DETECTED_URL" ]]; then
        OUTLINE_ALREADY_INSTALLED=true
        print_ok "Outline Server detected!"
        echo -e "  API URL found: ${CYAN}$DETECTED_URL${NC}"
        OUTLINE_API_URL_INPUT="$DETECTED_URL"
    fi
fi

# Check 2: Docker container fallback
if [[ "$OUTLINE_ALREADY_INSTALLED" == false ]]; then
    if command -v docker &>/dev/null && docker ps 2>/dev/null | grep -q "outline"; then
        OUTLINE_ALREADY_INSTALLED=true
        echo -e "  ${YELLOW}⚠ Outline Docker container running but access.txt missing.${NC}"
        echo -e "  ${YELLOW}  Will ask for URL manually.${NC}"
    fi
fi

# If NOT installed → offer to install
if [[ "$OUTLINE_ALREADY_INSTALLED" == false ]]; then
    echo -e "  ${YELLOW}Outline Server not found on this VPS.${NC}"
    echo ""
    echo -e "${BOLD}  Install Outline Server now? [Y/n]${NC}"
    read -r -p "  > " INSTALL_OUTLINE_CHOICE
    INSTALL_OUTLINE_CHOICE="${INSTALL_OUTLINE_CHOICE:-Y}"

    if [[ "$INSTALL_OUTLINE_CHOICE" =~ ^[Yy]$ ]]; then
        print_step "Installing Outline Server (this may take a few minutes)..."

        # Install Docker if missing
        if ! command -v docker &>/dev/null; then
            echo -e "  Installing Docker first..."
            curl -fsSL https://get.docker.com | sh
            if ! command -v docker &>/dev/null; then
                print_err "Docker install failed. Cannot install Outline."
                exit 1
            fi
            print_ok "Docker installed."
        fi

        # Get public IP before Outline install
        PUBLIC_IP_PRE=$(curl -s --max-time 5 https://api.ipify.org | tr -d '[:space:]')

        # Run Outline install
        bash -c "$(wget -qO- $OUTLINE_INSTALL_SCRIPT)" --hostname "$PUBLIC_IP_PRE"

        sleep 3

        if [[ -f "$OUTLINE_ACCESS_FILE" ]]; then
            DETECTED_URL=$(parse_outline_url)
            if [[ -n "$DETECTED_URL" ]]; then
                print_ok "Outline Server installed successfully!"
                echo -e "  API URL: ${CYAN}$DETECTED_URL${NC}"
                OUTLINE_API_URL_INPUT="$DETECTED_URL"
                OUTLINE_ALREADY_INSTALLED=true
            else
                print_err "Outline installed but could not read API URL from access.txt."
            fi
        else
            print_err "Outline install finished but access.txt not found at $OUTLINE_ACCESS_FILE"
        fi
    else
        echo -e "  ${YELLOW}Skipping Outline install.${NC}"
    fi
fi

# Manual fallback if still no URL
if [[ -z "$OUTLINE_API_URL_INPUT" ]]; then
    echo ""
    echo -e "${BOLD}Enter your Outline Server API URL manually:${NC}"
    echo -e "  (e.g. https://203.0.113.5:25336/AbCdEfGhIjKlMn)"
    read -r -p "  > " OUTLINE_API_URL_INPUT

    if [[ -z "$OUTLINE_API_URL_INPUT" ]]; then
        print_err "No URL entered. Exiting."
        exit 1
    fi

    if [[ ! "$OUTLINE_API_URL_INPUT" =~ ^https?:// ]]; then
        print_err "URL must start with https:// — got: $OUTLINE_API_URL_INPUT"
        exit 1
    fi
fi

# ============================================================
# STEP 2: Extract IP & compare with public IP → localhost swap
# ============================================================
print_step "Checking IP address..."

URL_HOST=$(echo "$OUTLINE_API_URL_INPUT" | sed -E 's|https?://([^/:]+).*|\1|')
echo -e "  URL host detected: ${CYAN}${URL_HOST}${NC}"

PUBLIC_IP=""
for PROVIDER in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com"; do
    PUBLIC_IP=$(curl -s --max-time 5 "$PROVIDER" 2>/dev/null | tr -d '[:space:]')
    if [[ -n "$PUBLIC_IP" ]]; then break; fi
done

if [[ -z "$PUBLIC_IP" ]]; then
    echo -e "  ${YELLOW}⚠ Could not detect public IP. Using URL as-is.${NC}"
    FINAL_OUTLINE_URL="$OUTLINE_API_URL_INPUT"
else
    echo -e "  VPS public IP: ${CYAN}${PUBLIC_IP}${NC}"
    if [[ "$URL_HOST" == "$PUBLIC_IP" ]]; then
        FINAL_OUTLINE_URL=$(echo "$OUTLINE_API_URL_INPUT" | sed "s|$PUBLIC_IP|127.0.0.1|g")
        echo -e "  ${GREEN}✔ Match! Switching to localhost:${NC}"
        echo -e "    ${CYAN}$FINAL_OUTLINE_URL${NC}"
    else
        FINAL_OUTLINE_URL="$OUTLINE_API_URL_INPUT"
        echo -e "  ${YELLOW}No IP match — using URL as-is.${NC}"
        echo -e "    ${CYAN}$FINAL_OUTLINE_URL${NC}"
    fi
fi

# ============================================================
# STEP 3: Install Apache + PHP
# ============================================================
print_step "Installing Apache2 and PHP..."

apt update -qq
apt install -y apache2 php libapache2-mod-php php-curl php-json -qq

if systemctl is-active --quiet apache2; then
    print_ok "Apache2 installed and running."
else
    print_err "Apache2 failed to start. Check: journalctl -xe"
    exit 1
fi

# ============================================================
# STEP 4: Clean default web directory
# ============================================================
print_step "Cleaning default web directory..."

[[ -f "$WEB_DIR/index.html" ]] && rm -f "$WEB_DIR/index.html" && print_ok "Removed default Apache index.html"

# ============================================================
# STEP 5: Download app files from GitHub
# ============================================================
print_step "Downloading application files..."

curl -fsSL "$REPO_RAW/index.html" -o "$WEB_DIR/index.html" \
    && print_ok "index.html downloaded." \
    || { print_err "Failed to download index.html"; exit 1; }

curl -fsSL "$REPO_RAW/api.php" -o "$WEB_DIR/api.php" \
    && print_ok "api.php downloaded." \
    || { print_err "Failed to download api.php"; exit 1; }

# ============================================================
# STEP 6: Inject Outline API URL into api.php
# ============================================================
print_step "Configuring Outline API URL in api.php..."

ESCAPED_URL=$(printf '%s\n' "$FINAL_OUTLINE_URL" | sed 's/[\/&]/\\&/g')
sed -i "s|\(\$OUTLINE_API_URL = \)\"[^\"]*\"|\1\"$ESCAPED_URL\"|" "$WEB_DIR/api.php"

if grep -q "$FINAL_OUTLINE_URL" "$WEB_DIR/api.php"; then
    print_ok "Outline API URL injected successfully."
else
    print_err "Could not auto-inject URL. Edit $WEB_DIR/api.php manually:"
    echo -e "  ${YELLOW}\$OUTLINE_API_URL = \"$FINAL_OUTLINE_URL\";${NC}"
fi

# ============================================================
# STEP 7: Create data.json and fix permissions
# ============================================================
print_step "Setting up data.json and permissions..."

cd "$WEB_DIR" || exit 1

echo '{"users":[{"id":1,"username":"owner","password":"$2y$10$GKszpF4beZRykmH\/k8bDoOmv.brxYrL6j\/KXbFn8sElcCuv82Cu.m","role":"owner","expires_at":null,"data_limit":0}]}' > data.json
print_ok "data.json created with default owner account."

chown -R www-data:www-data "$WEB_DIR"
chmod -R 755 "$WEB_DIR"
chmod 664 "$WEB_DIR/data.json"
print_ok "Permissions set."

# ============================================================
# STEP 8: Restart Apache
# ============================================================
print_step "Restarting Apache2..."

systemctl restart apache2 \
    && print_ok "Apache2 restarted." \
    || { print_err "Apache2 failed to restart."; exit 1; }

# ============================================================
# DONE
# ============================================================
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║         Installation Complete! ✔         ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Access your VPN Manager:${NC}  ${CYAN}http://$PUBLIC_IP/${NC}"
echo -e "  ${BOLD}Username:${NC}                 ${CYAN}owner${NC}"
echo -e "  ${BOLD}Password:${NC}                 ${CYAN}password${NC}"
echo ""
echo -e "  ${YELLOW}⚠  Change your password after first login!${NC}"
echo ""
echo -e "  ${BOLD}Outline API URL:${NC} ${CYAN}$FINAL_OUTLINE_URL${NC}"
echo ""
