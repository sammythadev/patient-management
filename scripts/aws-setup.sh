#!/bin/bash
# =============================================================================
# aws-setup.sh — One-time EC2 instance bootstrap
# =============================================================================
# Run this script ONCE on a fresh EC2 instance (Ubuntu 22.04+ recommended):
#   chmod +x aws-setup.sh && sudo ./aws-setup.sh
# =============================================================================

set -euo pipefail

echo "============================================="
echo " Patient Management — EC2 Setup"
echo "============================================="

# ---- 1. Update system ----
echo ">>> Updating system packages..."
apt-get update -y && apt-get upgrade -y

# ---- 2. Install Docker ----
echo ">>> Installing Docker..."
apt-get install -y ca-certificates curl gnupg lsb-release

# Ensure a clean, single Docker apt source to avoid Signed-By conflicts
rm -f /etc/apt/sources.list.d/docker.list
rm -f /etc/apt/keyrings/docker.gpg

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add current user to docker group (so docker runs without sudo)
ACTUAL_USER="${SUDO_USER:-$USER}"
usermod -aG docker "$ACTUAL_USER"

systemctl enable docker
systemctl start docker

echo ">>> Docker installed: $(docker --version)"

# ---- 3. Install Nginx ----
echo ">>> Installing Nginx..."
apt-get install -y nginx

# ---- 4. Configure Nginx ----
echo ">>> Configuring Nginx reverse proxy..."
APP_DIR="/home/$ACTUAL_USER/patient-management"
mkdir -p "$APP_DIR/scripts"

# Copy nginx config if it exists in the app directory, otherwise create it
if [ -f "$APP_DIR/scripts/nginx.conf" ]; then
    cp "$APP_DIR/scripts/nginx.conf" /etc/nginx/sites-available/patient-management
else
    cat > /etc/nginx/sites-available/patient-management << 'NGINX_CONF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:4004;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location /health {
        access_log off;
        return 200 "OK\n";
        add_header Content-Type text/plain;
    }
}
NGINX_CONF
fi

# Enable the site, disable default
ln -sf /etc/nginx/sites-available/patient-management /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl restart nginx
systemctl enable nginx

echo ">>> Nginx configured and running."

# ---- 5. Configure Firewall (UFW) ----
echo ">>> Configuring firewall..."
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP (Nginx)
ufw allow 443/tcp   # HTTPS (future SSL)
ufw --force enable

echo ">>> Firewall configured: ports 22, 80, 443 open."

# ---- 6. Create app directory structure ----
echo ">>> Setting up app directory at $APP_DIR ..."
mkdir -p "$APP_DIR"
chown -R "$ACTUAL_USER:$ACTUAL_USER" "$APP_DIR"

echo ""
echo "============================================="
echo " Setup Complete!"
echo "============================================="
echo ""
echo " Next steps:"
echo "   1. Copy .env.prod to $APP_DIR/.env"
echo "   2. Copy docker-compose.prod.yml to $APP_DIR/"
echo "   3. Copy scripts/deploy.sh to $APP_DIR/"
echo "   4. Edit $APP_DIR/.env with your actual values"
echo "   5. Run: cd $APP_DIR && chmod +x deploy.sh && ./deploy.sh"
echo ""
echo " Log out and back in for Docker group to take effect."
echo "============================================="
