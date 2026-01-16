#!/bin/bash
# ==========================================
#  BUNNY DEPLOY - UBUNTU 20.04
#  Dev: Kang Sarip
# ==========================================

export DEBIAN_FRONTEND=noninteractive
APT_OPTS="-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

if [ "$EUID" -ne 0 ]; then echo "Harap jalankan sebagai root (sudo -i)"; exit; fi

echo "Installing Bunny Deploy (Ubuntu 20)..."

# 1. Update & Fix Repos
apt update -y
apt upgrade -y $APT_OPTS
apt install -y $APT_OPTS curl git unzip build-essential ufw software-properties-common

# 2. Paksa Install PHP 8.2 (Via PPA karena Ubuntu 20 bawaannya cuma PHP 7.4)
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
apt update -y
apt install -y $APT_OPTS nginx certbot python3-certbot-nginx
apt install -y $APT_OPTS php8.2 php8.2-fpm php8.2-mysql php8.2-curl php8.2-xml php8.2-mbstring composer

# 3. Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y $APT_OPTS nodejs
npm install -g pm2 yarn

# 4. Config
systemctl enable nginx php8.2-fpm
systemctl start nginx php8.2-fpm
ufw allow 'Nginx Full'
echo "y" | ufw enable

# 5. Buat Command 'bd' (Sama persis dengan V22)
cat << 'EOF' > /usr/local/bin/bd
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

show_header() {
    clear
    echo -e "${RED}======================================${NC}"
    echo -e "${YELLOW}   BUNNY DEPLOY - Dev Kang Sarip${NC}"
    echo -e "${RED}======================================${NC}"
}

deploy_web() {
    echo -e "\n[ DEPLOY WEBSITE BARU ]"
    echo "1. HTML5 / Static"
    echo "2. Node.js (Proxy)"
    echo "3. PHP 8.2 (Laravel)"
    read -p "Pilih: " TYPE
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
        BLOCK="server { listen 80; server_name $DOMAIN www.$DOMAIN; root $ROOT; index index.php index.html; location / { try_files \$uri \$uri/ /index.php?\$query_string; } location ~ \.php$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/run/php/php8.2-fpm.sock; } }"
    else echo "Salah pilih"; return; fi

    echo "$BLOCK" > $CONFIG
    ln -s $CONFIG /etc/nginx/sites-enabled/ 2>/dev/null
    nginx -t && systemctl reload nginx
    certbot --nginx --non-interactive --agree-tos -m $EMAIL -d $DOMAIN -d www.$DOMAIN
    read -p "Sukses. Enter..."
}

delete_web() {
    read -p "Domain yg dihapus: " D
    rm /etc/nginx/sites-enabled/$D /etc/nginx/sites-available/$D
    certbot delete --cert-name $D
    systemctl reload nginx
    echo "Website dihapus."
    read -p "Enter..."
}

uninstall_bd() {
    read -p "Hapus script bd? (y/n): " C
    if [ "$C" == "y" ]; then rm /usr/local/bin/bd; echo "Script dihapus."; exit; fi
}

while true; do
    show_header
    echo "1. Deploy Website"
    echo "2. Hapus Website"
    echo "-----------------"
    echo "3. List Aplikasi (PM2)"
    echo "4. Restart App"
    echo "5. Stop App"
    echo "6. Delete App"
    echo "7. Cek Logs"
    echo "-----------------"
    echo "8. Restart System (Nginx/PHP)"
    echo "9. Uninstall Script"
    echo "0. Keluar"
    read -p "Pilih: " OPT
    case $OPT in
        1) deploy_web ;;
        2) delete_web ;;
        3) pm2 list; read -p "Enter..." ;;
        4) read -p "ID: " I; pm2 restart $I; read -p "Enter..." ;;
        5) read -p "ID: " I; pm2 stop $I; read -p "Enter..." ;;
        6) read -p "ID: " I; pm2 delete $I; pm2 save; read -p "Enter..." ;;
        7) read -p "ID: " I; pm2 logs $I ;;
        8) systemctl restart nginx php8.2-fpm; echo "Refreshed."; read -p "Enter..." ;;
        9) uninstall_bd ;;
        0) exit ;;
    esac
done
EOF

chmod +x /usr/local/bin/bd
echo "SELESAI. Ketik: bd"
