#!/bin/bash
# ==========================================
#  🐰 BUNNY DEPLOY - SUPER LEGACY (Ubuntu 18.04)
#  Node.js: 16.x | PHP: 7.4 | Certbot via Snap
# ==========================================

export DEBIAN_FRONTEND=noninteractive

if [ "$EUID" -ne 0 ]; then echo "Harap jalankan sebagai root (sudo -i)"; exit; fi

echo "=== INSTALLING BUNNY DEPLOY (UBUNTU 18.04) ==="
echo "WARNING: OS ini sudah EOL. Keamanan tidak terjamin."

# 1. Update System
apt update -y
apt install -y curl git unzip build-essential ufw software-properties-common

# 2. Install PHP 7.4 (PPA Ondrej wajib untuk Ubuntu 18)
add-apt-repository -y ppa:ondrej/php
apt update -y
apt install -y nginx php7.4 php7.4-fpm php7.4-mysql php7.4-curl php7.4-xml php7.4-mbstring composer

# 3. Install Node.js 16 (Node 18+ GAGAL di Ubuntu 18.04 karena glibc tua)
curl -fsSL https://deb.nodesource.com/setup_16.x | bash -
apt install -y nodejs
npm install -g pm2 yarn

# 4. Install Certbot (Wajib via SNAP di Ubuntu 18, apt-nya error)
apt install -y snapd
snap install core; snap refresh core
snap install --classic certbot
ln -s /snap/bin/certbot /usr/bin/certbot

# 5. Config & Firewall
systemctl enable nginx php7.4-fpm
systemctl start nginx php7.4-fpm
ufw allow 'Nginx Full'
echo "y" | ufw enable

# 6. Buat Command 'bd' (PHP 7.4 Config)
cat << 'EOF' > /usr/local/bin/bd
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'

deploy_web() {
    echo -e "\n${GREEN}--- DEPLOY WEBSITE (UBUNTU 18.04 / PHP 7.4) ---${NC}"
    echo "1. HTML5 / React (Static)"
    echo "2. Node.js (Proxy)"
    echo "3. PHP 7.4 (Legacy)"
    read -p "Pilih [1-3]: " TYPE
    read -p "Domain: " DOMAIN
    read -p "Email SSL: " EMAIL
    CONFIG="/etc/nginx/sites-available/$DOMAIN"

    if [ "$TYPE" == "1" ]; then
        read -p "Folder Path: " ROOT
        BLOCK="server { listen 80; server_name $DOMAIN www.$DOMAIN; root $ROOT; index index.html; location / { try_files \$uri \$uri/ /index.html; } }"
    elif [ "$TYPE" == "2" ]; then
        read -p "Port App: " PORT
        BLOCK="server { listen 80; server_name $DOMAIN www.$DOMAIN; location / { proxy_pass http://localhost:$PORT; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection 'upgrade'; proxy_set_header Host \$host; proxy_cache_bypass \$http_upgrade; } }"
    elif [ "$TYPE" == "3" ]; then
        read -p "Folder Path: " ROOT
        # Socket PHP 7.4
        BLOCK="server { listen 80; server_name $DOMAIN www.$DOMAIN; root $ROOT; index index.php index.html; location / { try_files \$uri \$uri/ /index.php?\$query_string; } location ~ \.php$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/run/php/php7.4-fpm.sock; } }"
    else
        echo "Salah pilih."; return
    fi

    echo "$BLOCK" > $CONFIG
    ln -s $CONFIG /etc/nginx/sites-enabled/ 2>/dev/null
    nginx -t && systemctl reload nginx
    # Certbot Command via Snap
    certbot --nginx --non-interactive --agree-tos -m $EMAIL -d $DOMAIN -d www.$DOMAIN
}

clear
echo -e "${CYAN}🐰 BUNNY DEPLOY (UBUNTU 18.04 LEGACY)${NC}"
echo "1. Deploy Web"
echo "2. Hapus Web"
echo "3. PM2 Menu"
echo "0. Keluar"
read -p "Pilih: " OPT
case $OPT in
    1) deploy_web ;;
    2) read -p "Domain hapus: " D; rm /etc/nginx/sites-enabled/$D /etc/nginx/sites-available/$D; certbot delete --cert-name $D; systemctl reload nginx; echo "Dihapus." ;;
    3) pm2 list; read -p "Enter..." ;;
    0) exit ;;
esac
EOF

chmod +x /usr/local/bin/bd
echo "INSTALASI UBUNTU 18.04 SELESAI! Ketik: bd"
