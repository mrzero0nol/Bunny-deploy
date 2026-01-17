#!/bin/bash
# ===============================================
#  BUNNY DEPLOY - ULTIMATE (FIXED NO WWW)
#  Dev: Kang Sarip (Fixed by Gemini)
# ===============================================

# --- CONFIGURATION ---
PHP_VER="8.2"
NODE_VER="20"
# ---------------------

export DEBIAN_FRONTEND=noninteractive
APT_OPTS="-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

if [ "$EUID" -ne 0 ]; then echo "Harap jalankan sebagai root (sudo -i)"; exit; fi

echo "Updating Bunny Deploy..."

# 1. Update & Tools
apt update -y
apt upgrade -y $APT_OPTS
apt install -y $APT_OPTS curl git unzip zip build-essential ufw software-properties-common mariadb-server

# 2. Service Database
systemctl start mariadb
systemctl enable mariadb

# 3. Install PHP
add-apt-repository -y ppa:ondrej/php
apt update -y
apt install -y $APT_OPTS nginx certbot python3-certbot-nginx
apt install -y $APT_OPTS php$PHP_VER php$PHP_VER-fpm php$PHP_VER-mysql php$PHP_VER-curl php$PHP_VER-xml php$PHP_VER-mbstring composer

# 4. Install Node.js
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VER}.x | bash -
    apt install -y $APT_OPTS nodejs
fi
if ! command -v pm2 &> /dev/null; then
    npm install -g pm2 yarn
fi

# 5. Firewall
systemctl enable nginx php$PHP_VER-fpm
ufw allow 'Nginx Full'
ufw allow OpenSSH
if ! ufw status | grep -q "Status: active"; then echo "y" | ufw enable; fi

# 6. Create Command 'bd' (FIXED VERSION)
cat << EOF > /usr/local/bin/bd
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
PHP_V="$PHP_VER"
BACKUP_DIR="/root/backups"

show_header() {
    clear
    echo -e "\${BLUE}======================================\${NC}"
    echo -e "\${YELLOW}   BUNNY DEPLOY - ULTIMATE (FIXED)\${NC}"
    echo -e "\${BLUE}======================================\${NC}"
}

deploy_web() {
    echo -e "\n\${YELLOW}[ DEPLOY WEBSITE BARU ]\${NC}"
    echo "1. HTML5 / Static"
    echo "2. Node.js (Proxy)"
    echo "3. PHP \$PHP_V (Laravel/CodeIgniter)"
    read -p "Pilih: " TYPE
    read -p "Domain: " DOMAIN
    
    if [[ ! "\$DOMAIN" =~ ^[a-zA-Z0-9.-]+$ ]]; then echo "Domain invalid!"; return; fi

    read -p "Email SSL: " EMAIL
    CONFIG="/etc/nginx/sites-available/\$DOMAIN"

    if [ "\$TYPE" == "1" ]; then
        read -p "Folder Path: " ROOT
        BLOCK="server { listen 80; server_name \$DOMAIN; root \$ROOT; index index.html; location / { try_files \\\$uri \\\$uri/ /index.html; } }"
    elif [ "\$TYPE" == "2" ]; then
        read -p "Port App: " PORT
        BLOCK="server { listen 80; server_name \$DOMAIN; location / { proxy_pass http://localhost:\$PORT; proxy_http_version 1.1; proxy_set_header Upgrade \\\$http_upgrade; proxy_set_header Connection 'upgrade'; proxy_set_header Host \\\$host; proxy_cache_bypass \\\$http_upgrade; } }"
    elif [ "\$TYPE" == "3" ]; then
        read -p "Folder Path: " ROOT
        BLOCK="server { listen 80; server_name \$DOMAIN; root \$ROOT; index index.php index.html; location / { try_files \\\$uri \\\$uri/ /index.php?\\\$query_string; } location ~ \.php$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/run/php/php\$PHP_V-fpm.sock; } }"
    else echo "Salah pilih"; return; fi

    echo "\$BLOCK" > \$CONFIG
    ln -s \$CONFIG /etc/nginx/sites-enabled/ 2>/dev/null
    
    nginx -t
    if [ \$? -eq 0 ]; then
        systemctl reload nginx
        # FIX: Hapus -d www.\$DOMAIN agar subdomain aman
        certbot --nginx --non-interactive --agree-tos -m \$EMAIL -d \$DOMAIN
        echo -e "\${GREEN}Deploy Sukses!\${NC}"
    else
        echo -e "\${RED}Config Error. Rollback.\${NC}"; rm \$CONFIG; rm /etc/nginx/sites-enabled/\$DOMAIN
    fi
    read -p "Enter..."
}

update_app() {
    echo -e "\n\${YELLOW}[ UPDATE APP (GIT PULL) ]\${NC}"
    read -p "Domain: " DOMAIN
    ROOT=\$(grep "root" /etc/nginx/sites-available/\$DOMAIN 2>/dev/null | awk '{print \$2}' | tr -d ';')
    if [ -z "\$ROOT" ]; then read -p "Path Folder: " ROOT; fi

    if [ -d "\$ROOT/.git" ]; then
        cd \$ROOT && git pull
        if [ -f "package.json" ]; then npm install; read -p "Restart PM2 ID?: " I; if [ ! -z "\$I" ]; then pm2 restart \$I; fi
        elif [ -f "composer.json" ]; then composer install --no-dev; php artisan migrate --force 2>/dev/null; fi
        echo -e "\${GREEN}Updated.\${NC}"
    else echo "Bukan Git Repo."; fi
    read -p "Enter..."
}

create_db() {
    echo -e "\n\${YELLOW}[ BUAT DATABASE ]\${NC}"
    read -p "Nama DB: " RAW_DB
    read -p "User DB: " RAW_USER
    DBNAME=\$(echo "\$RAW_DB" | tr -dc 'a-zA-Z0-9_')
    DBUSER=\$(echo "\$RAW_USER" | tr -dc 'a-zA-Z0-9_')
    GEN_PASS=\$(openssl rand -base64 12)
    echo "Pass: \$GEN_PASS"
    read -p "Pakai pass ini? (y/n): " C
    if [ "\$C" == "n" ]; then read -s -p "Pass Manual: " DBPASS; echo ""; else DBPASS="\$GEN_PASS"; fi
    
    mysql -e "CREATE DATABASE IF NOT EXISTS \$DBNAME;"
    mysql -e "CREATE USER IF NOT EXISTS '\$DBUSER'@'localhost' IDENTIFIED BY '\$DBPASS';"
    mysql -e "GRANT ALL PRIVILEGES ON \$DBNAME.* TO '\$DBUSER'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    
    echo -e "\${GREEN}DB \$DBNAME Dibuat! Simpan passwordnya.\${NC}"
    read -p "Enter..."
}

backup_wizard() {
    mkdir -p \$BACKUP_DIR
    echo -e "\n\${YELLOW}[ BACKUP WIZARD ]\${NC}"
    echo "1. Backup File Website + Database"
    echo "2. Backup Database Saja"
    read -p "Pilih: " BTYPE

    if [ "\$BTYPE" == "1" ]; then
        read -p "Masukkan Domain: " DOMAIN
        ROOT=\$(grep "root" /etc/nginx/sites-available/\$DOMAIN 2>/dev/null | awk '{print \$2}' | tr -d ';')
        if [ -z "\$ROOT" ]; then read -p "Path Folder Project: " ROOT; fi
        
        read -p "Nama Database (kosongkan jika tidak ada): " DBNAME
        
        DATE=\$(date +%Y-%m-%d_%H-%M)
        FILENAME="backup_\${DOMAIN}_\${DATE}.zip"
        
        echo "Memproses backup..."
        if [ ! -z "\$DBNAME" ]; then
            mysqldump \$DBNAME > "\$ROOT/db_dump.sql" 2>/dev/null
        fi
        
        cd \$ROOT
        zip -r "\$BACKUP_DIR/\$FILENAME" . -x "node_modules/*" "vendor/*"
        
        if [ ! -z "\$DBNAME" ]; then rm "\$ROOT/db_dump.sql"; fi
        
        echo -e "\${GREEN}Backup Selesai!\${NC}"
        echo "Lokasi: \$BACKUP_DIR/\$FILENAME"
        echo "------------------------------------------------"
        echo "Cara download ke PC (buka terminal PC kamu):"
        echo "scp root@\$(curl -s ifconfig.me):\$BACKUP_DIR/\$FILENAME ."
        echo "------------------------------------------------"
        
    elif [ "\$BTYPE" == "2" ]; then
        mysql -e "SHOW DATABASES;" | grep -v "schema\|mysql\|sys"
        read -p "Nama Database: " DBNAME
        DATE=\$(date +%Y-%m-%d_%H-%M)
        mysqldump \$DBNAME > "\$BACKUP_DIR/db_\${DBNAME}_\${DATE}.sql"
        echo -e "\${GREEN}Database didump ke \$BACKUP_DIR/db_\${DBNAME}_\${DATE}.sql\${NC}"
    fi
    read -p "Enter..."
}

uninstall_script() {
    read -p "Hapus script 'bd'? (y/n): " Y
    if [ "\$Y" == "y" ]; then rm /usr/local/bin/bd; echo "Terhapus."; exit; fi
}

while true; do
    show_header
    echo "1. Deploy Website"
    echo "2. Update Web/App"
    echo "3. Database Manager"
    echo "4. PM2 Manager"
    echo "-----------------"
    echo "9. Backup Data (New!)"
    echo "-----------------"
    echo "8. Uninstall Script"
    echo "0. Keluar"
    read -p "Pilih: " OPT
    case \$OPT in
        1) deploy_web ;;
        2) update_app ;;
        3) create_db ;;
        4) pm2 list; read -p "Cmd: " C; \$C; read -p "..." ;;
        9) backup_wizard ;;
        8) uninstall_script ;;
        0) exit ;;
    esac
done
EOF

chmod +x /usr/local/bin/bd
echo "UPDATE SELESAI. Ketik: bd"
