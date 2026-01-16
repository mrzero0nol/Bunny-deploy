#!/bin/bash
# ==========================================
#  🐰 BUNNY DEPLOY - MODERN (Ubuntu 22+)
#  PHP Version: 8.2
# ==========================================

export DEBIAN_FRONTEND=noninteractive
APT_OPTS="-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# Cek Root
if [ "$EUID" -ne 0 ]; then echo "Harap jalankan sebagai root (sudo -i)"; exit; fi

echo "=== INSTALLING BUNNY DEPLOY (MODERN VERSION) ==="

# 1. Update & Tools
apt update -y
apt upgrade -y $APT_OPTS
apt install -y $APT_OPTS curl git unzip build-essential ufw software-properties-common

# 2. Install PHP 8.2 (Via PPA agar konsisten di Ubuntu 22/24)
add-apt-repository -y ppa:ondrej/php
apt update -y
apt install -y $APT_OPTS nginx certbot python3-certbot-nginx
apt install -y $APT_OPTS php8.2 php8.2-fpm php8.2-mysql php8.2-curl php8.2-xml php8.2-mbstring composer

# 3. Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y $APT_OPTS nodejs
npm install -g pm2 yarn

# 4. Config & Firewall
systemctl enable nginx php8.2-fpm
systemctl start nginx php8.2-fpm
ufw allow 'Nginx Full'
echo "y" | ufw enable

# 5. Buat Command 'bd' (PHP 8.2 Config)
cat << 'EOF' > /usr/local/bin/bd
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'

deploy_web() {
    echo -e "\n${GREEN}--- DEPLOY WEBSITE (MODERN PHP 8.2) ---${NC}"
    echo "1. HTML5 / React (Static)"
    echo "2. Node.js (Proxy)"
    echo "3. PHP 8.2 (Laravel/Native)"
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
        # Perhatikan: Socket PHP 8.2
        BLOCK="server { listen 80; server_name $DOMAIN www.$DOMAIN; root $ROOT; index index.php index.html; location / { try_files \$uri \$uri/ /index.php?\$query_string; } location ~ \.php$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/run/php/php8.2-fpm.sock; } }"
    else
        echo "Salah pilih."; return
    fi

    echo "$BLOCK" > $CONFIG
    ln -s $CONFIG /etc/nginx/sites-enabled/ 2>/dev/null
    nginx -t && systemctl reload nginx
    certbot --nginx --non-interactive --agree-tos -m $EMAIL -d $DOMAIN -d www.$DOMAIN
}

# Simple Menu Logic
clear
echo -e "${CYAN}🐰 BUNNY DEPLOY (MODERN)${NC}"
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
echo "INSTALASI MODERN SELESAI! Ketik: bd"
