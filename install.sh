#!/bin/bash

# ============================================================
#  VPN Manager - Automated Installer
#  Usage: bash <(curl -s https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/install.sh)
# ============================================================

# --- COLORS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- GITHUB RAW BASE URL ---
# UPDATE THIS to point to your own repo before pushing!
REPO_RAW="https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main"

WEB_DIR="/var/www/html"

print_banner() {
    echo ""
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║       VPN Manager — Auto Installer       ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo ""
    echo -e "${YELLOW}${BOLD}▶ $1${NC}"
}

print_ok() {
    echo -e "  ${GREEN}✔ $1${NC}"
}

print_err() {
    echo -e "  ${RED}✖ $1${NC}"
}

# ---- STEP 0: Root check ----
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Please run as root (sudo bash install.sh)${NC}"
    exit 1
fi

print_banner

# ---- STEP 1: Ask for Outline API URL ----
echo -e "${BOLD}Enter your Outline Server API URL${NC}"
echo -e "  (e.g. https://203.0.113.5:25336/AbCdEfGhIjKlMn)"
echo -n "  > "
read -r OUTLINE_API_URL_INPUT

if [[ -z "$OUTLINE_API_URL_INPUT" ]]; then
    print_err "No URL entered. Exiting."
    exit 1
fi

# Validate it looks like a URL
if [[ ! "$OUTLINE_API_URL_INPUT" =~ ^https?:// ]]; then
    print_err "URL must start with https:// — got: $OUTLINE_API_URL_INPUT"
    exit 1
fi

# ---- STEP 2: Extract IP from the URL & compare with public IP ----
print_step "Checking IP address..."

# Extract the host (IP or domain) from the URL
URL_HOST=$(echo "$OUTLINE_API_URL_INPUT" | sed -E 's|https?://([^/:]+).*|\1|')

echo -e "  URL host detected: ${CYAN}${URL_HOST}${NC}"

# Get the VPS public IP (try multiple providers for reliability)
PUBLIC_IP=""
for PROVIDER in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com"; do
    PUBLIC_IP=$(curl -s --max-time 5 "$PROVIDER" 2>/dev/null | tr -d '[:space:]')
    if [[ -n "$PUBLIC_IP" ]]; then
        break
    fi
done

if [[ -z "$PUBLIC_IP" ]]; then
    echo -e "  ${YELLOW}⚠ Could not auto-detect public IP. Skipping localhost substitution.${NC}"
    FINAL_OUTLINE_URL="$OUTLINE_API_URL_INPUT"
else
    echo -e "  VPS public IP detected: ${CYAN}${PUBLIC_IP}${NC}"

    if [[ "$URL_HOST" == "$PUBLIC_IP" ]]; then
        # Replace the public IP with 127.0.0.1 for local loopback
        FINAL_OUTLINE_URL=$(echo "$OUTLINE_API_URL_INPUT" | sed "s|$PUBLIC_IP|127.0.0.1|g")
        echo -e "  ${GREEN}✔ Match found! Using localhost in config:${NC}"
        echo -e "    ${CYAN}$FINAL_OUTLINE_URL${NC}"
    else
        FINAL_OUTLINE_URL="$OUTLINE_API_URL_INPUT"
        echo -e "  ${YELLOW}IP does not match public IP — using URL as-is.${NC}"
        echo -e "    ${CYAN}$FINAL_OUTLINE_URL${NC}"
    fi
fi

# ---- STEP 3: Install Apache + PHP ----
print_step "Installing Apache2 and PHP..."

apt update -qq
apt install -y apache2 php libapache2-mod-php php-curl php-json -qq

if systemctl is-active --quiet apache2; then
    print_ok "Apache2 installed and running."
else
    print_err "Apache2 failed to start. Check logs: journalctl -xe"
    exit 1
fi

# ---- STEP 4: Clean default web directory ----
print_step "Cleaning default web directory..."

if [[ -f "$WEB_DIR/index.html" ]]; then
    rm -f "$WEB_DIR/index.html"
    print_ok "Removed default Apache index.html"
fi

# ---- STEP 5: Download application files from GitHub ----
print_step "Downloading application files..."

# Download index.html
curl -fsSL "$REPO_RAW/index.html" -o "$WEB_DIR/index.html"
if [[ $? -eq 0 ]]; then
    print_ok "index.html downloaded."
else
    print_err "Failed to download index.html from: $REPO_RAW/index.html"
    print_err "Make sure REPO_RAW in this script points to your GitHub repo."
    exit 1
fi

# Download api.php
curl -fsSL "$REPO_RAW/api.php" -o "$WEB_DIR/api.php"
if [[ $? -eq 0 ]]; then
    print_ok "api.php downloaded."
else
    print_err "Failed to download api.php from: $REPO_RAW/api.php"
    exit 1
fi

# ---- STEP 6: Inject the correct Outline API URL into api.php ----
print_step "Configuring Outline API URL in api.php..."

# Escape special characters in the URL for sed (forward slashes, dots, etc.)
ESCAPED_URL=$(printf '%s\n' "$FINAL_OUTLINE_URL" | sed 's/[\/&]/\\&/g')

# Replace the placeholder URL in api.php
# The downloaded api.php should have the placeholder: OUTLINE_API_URL_PLACEHOLDER
# OR we do a pattern replace on the $OUTLINE_API_URL line directly
sed -i "s|\(\$OUTLINE_API_URL = \)\"[^\"]*\"|\1\"$ESCAPED_URL\"|" "$WEB_DIR/api.php"

if grep -q "$FINAL_OUTLINE_URL" "$WEB_DIR/api.php"; then
    print_ok "Outline API URL set successfully."
else
    print_err "Could not auto-inject URL. Please edit $WEB_DIR/api.php manually."
    echo -e "  ${YELLOW}Set: \$OUTLINE_API_URL = \"$FINAL_OUTLINE_URL\";${NC}"
fi

# ---- STEP 7: Create data.json and fix permissions ----
print_step "Setting up data.json and permissions..."

cd "$WEB_DIR" || exit 1

touch data.json
print_ok "data.json created."

chown -R www-data:www-data "$WEB_DIR"
chmod -R 755 "$WEB_DIR"
chmod 664 "$WEB_DIR/data.json"
print_ok "Permissions set (www-data ownership, 755/664)."

# ---- STEP 8: Restart Apache ----
print_step "Restarting Apache2..."

systemctl restart apache2

if systemctl is-active --quiet apache2; then
    print_ok "Apache2 restarted successfully."
else
    print_err "Apache2 failed to restart."
    exit 1
fi

# ---- DONE ----
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║         Installation Complete! ✔         ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Access your VPN Manager at:${NC}"
echo -e "  ${CYAN}http://$PUBLIC_IP/${NC}"
echo ""
echo -e "  ${BOLD}Default login:${NC}"
echo -e "  Username: ${CYAN}owner${NC}"
echo -e "  Password: ${CYAN}password${NC}"
echo ""
echo -e "  ${YELLOW}⚠  Change your password after first login!${NC}"
echo ""
echo -e "  ${BOLD}Important checks:${NC}"
echo -e "  1. Ensure Outline API port is open in your firewall."
echo -e "  2. Outline API URL in use: ${CYAN}$FINAL_OUTLINE_URL${NC}"
echo ""
