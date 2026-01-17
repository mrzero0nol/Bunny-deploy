#!/bin/bash
# ==========================================
#  BUNNY DEPLOY - UBUNTU 22/24 (FULL FEATURES)
#  Dev: Kang Sarip
# ==========================================

export DEBIAN_FRONTEND=noninteractive
APT_OPTS="-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

if [ "$EUID" -ne 0 ]; then echo "Harap jalankan sebagai root (sudo -i)"; exit; fi

echo "Installing Bunny Deploy (Ubuntu 22/24)..."

# 1. Update & Tools
apt update -y
apt upgrade -y $APT_OPTS
apt install -y $APT_OPTS curl git unzip build-essential ufw software-properties-common mariadb-server

# 2. Service Database
systemctl start mariadb
systemctl enable mariadb

# 3. Install PHP 8.2
add-apt-repository -y ppa:ondrej/php
apt update -y
apt install -y $APT_OPTS nginx certbot python3-certbot-nginx
apt install -y $APT_OPTS php8.2 php8.2-fpm php8.2-mysql php8.2-curl php8.2-xml php8.2-mbstring composer

# 4. Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y $APT_OPTS nodejs
npm install -g pm2 yarn

# 5. Firewall (SSH Safe)
systemctl enable nginx php8.2-fpm
ufw allow 'Nginx Full'
ufw allow OpenSSH
echo "y" | ufw enable

# 6. Command 'bd'
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

update_app() {
    echo -e "\n[ UPDATE APP/WEB (GIT PULL) ]"
    read -p "Masukkan Domain: " DOMAIN
    # Cari path root dari config nginx
    ROOT=$(grep "root" /etc/nginx/sites-available/$DOMAIN 2>/dev/null | awk '{print $2}' | tr -d ';')
    
    # Jika tidak ketemu root (berarti mode Proxy/Nodejs), tanya manual
    if [ -z "$ROOT" ]; then
        read -p "Path Folder Project: " ROOT
    fi

    if [ -d "$ROOT/.git" ]; then
        echo "Mengupdate Source Code di $ROOT..."
        cd $ROOT
        git pull
        
        # Cek jika Node.js, tawarkan npm install
        if [ -f "package.json" ]; then
            echo "Mendeteksi Node.js..."
            npm install
            read -p "Restart App di PM2? (y/n): " R
            if [ "$R" == "y" ]; then
                read -p "Masukkan ID App PM2: " ID
                pm2 restart $ID
            fi
        fi
        echo -e "${GREEN}Update Selesai!${NC}"
    else
        echo -e "${RED}Error: Folder $ROOT bukan Git Repository / Tidak ditemukan.${NC}"
    fi
    read -p "Enter..."
}

system_update() {
    echo "Mengupdate System Tools..."
    apt update -y && apt upgrade -y
    echo -e "${GREEN}System Updated.${NC}"
    read -p "Enter..."
}

# Database Menu
create_db() {
    read -p "DB Name: " D; read -p "DB User: " U; read -p "DB Pass: " P
    mysql -e "CREATE DATABASE IF NOT EXISTS $D;"
    mysql -e "CREATE USER IF NOT EXISTS '$U'@'localhost' IDENTIFIED BY '$P';"
    mysql -e "GRANT ALL PRIVILEGES ON $D.* TO '$U'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    echo "DB Created."; read -p "Enter..."
}

delete_db() {
    read -p "DB Name: " D; mysql -e "DROP DATABASE IF EXISTS $D;"; echo "Deleted."; read -p "Enter..."
}

uninstall_bd() {
    read -p "Hapus script? (y/n): " C; if [ "$C" == "y" ]; then rm /usr/local/bin/bd; exit; fi
}

while true; do
    show_header
    echo "1. Deploy Website Baru"
    echo "2. Update Web/App (Git Pull)"
    echo "3. Hapus Website"
    echo "-----------------"
    echo "4. Database Manager (Buat/Hapus)"
    echo "5. PM2 Manager (List/Logs/Stop)"
    echo "-----------------"
    echo "6. Update System Tools (OS)"
    echo "7. Restart Nginx/PHP"
    echo "8. Uninstall Script"
    echo "0. Keluar"
    read -p "Pilih: " OPT
    case $OPT in
        1) deploy_web ;;
        2) update_app ;;
        3) read -p "Domain: " D; rm /etc/nginx/sites-enabled/$D /etc/nginx/sites-available/$D; certbot delete --cert-name $D; systemctl reload nginx; read -p "Deleted." ;;
        4) echo "1. Create | 2. Delete"; read -p "Pilih: " DOPT; if [ $DOPT == 1 ]; then create_db; else delete_db; fi ;;
        5) pm2 list; echo "Logs/Restart/Stop?"; read -p "Command (logs/restart/stop [ID]): " C I; pm2 $C $I --lines 50 --nostream; read -p "Enter..." ;;
        6) system_update ;;
        7) systemctl restart nginx php8.2-fpm; echo "Refreshed."; read -p "Enter..." ;;
        8) uninstall_bd ;;
        0) exit ;;
    esac
done
EOF

chmod +x /usr/local/bin/bd
echo "SELESAI. Ketik: bd"
