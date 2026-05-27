# VPN Manager — Automated Installer

One-command Outline VPN server deployment with a built-in web dashboard for key management.

```bash
sudo bash <(curl -s https://raw.githubusercontent.com/x-cinema-pro/autoinstaller/main/install.sh)
```

## What it does

Run one command on a fresh Debian/Ubuntu VPS and get:

- **Outline VPN Server** — auto-installed with Docker if not already present
- **Web Dashboard** — Apache + PHP admin panel for managing VPN keys and users
- **Role-based Access** — owner account with full control out of the box
- **Smart IP Detection** — automatically swaps public IP to localhost for local API calls

The installer handles everything: Docker setup, Outline Server deployment, Apache/PHP installation, file downloads, API URL injection, and permission configuration.

## Requirements

- Fresh **Debian 10+** or **Ubuntu 20.04+** VPS
- Root access (`sudo`)
- Ports **80** (web dashboard) and Outline's default port open

## Installation

SSH into your VPS and run:

```bash
sudo bash <(curl -s https://raw.githubusercontent.com/x-cinema-pro/autoinstaller/main/install.sh)
```

The installer will:

1. Check for an existing Outline Server (or install one automatically)
2. Detect and configure the Outline API URL
3. Install Apache2 + PHP with required modules
4. Download the web dashboard files
5. Configure API connectivity and file permissions
6. Start the dashboard

## Post-install

Once complete, the installer outputs:

```
Access your VPN Manager:  http://<your-vps-ip>/
Username:                 owner
Password:                 password
```

**Change the default password immediately after first login.**

## Architecture

```
install.sh
├── Detects or installs Outline Server (Docker)
├── Captures Outline API URL from access.txt or install output
├── Installs Apache2 + PHP + required modules
├── Downloads index.html (dashboard UI) + api.php (backend)
├── Injects Outline API URL into api.php
├── Creates data.json with default owner credentials
└── Sets www-data permissions and restarts Apache
```

## Tech Stack

- **Outline VPN** — Shadowsocks-based VPN server by Jigsaw (Google)
- **Docker** — container runtime for Outline
- **Apache2 + PHP** — web dashboard backend
- **Bash** — installer automation

## Troubleshooting

| Issue | Fix |
|---|---|
| Installer can't detect public IP | Enter Outline API URL manually when prompted |
| Apache won't start | Check port 80 isn't in use: `sudo lsof -i :80` |
| Dashboard loads but API fails | Verify URL in `/var/www/html/api.php` matches your Outline server |
| Docker install fails | Run `curl -fsSL https://get.docker.com | sh` manually first |

## License

MIT
