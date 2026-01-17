#!/bin/bash
# ===============================================
#  BUNNY DEPLOY - FIXED MENU & CONFIG (BD-25)
#  Code: Fixed by Gemini (Menu Sorted + Nginx Fix)
# ===============================================

# --- CONFIGURATION ---
PHP_VER="8.2"
NODE_VER="20"
# ---------------------

export DEBIAN_FRONTEND=noninteractive
APT_OPTS="-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# Cek Root
if [ "$EUID" -ne 0 ]; then echo "Harap jalankan sebagai root (sudo -i)"; exit; fi

echo "Updating System & Installing Dependencies..."

# 1. Update & Tools
apt update -y
apt upgrade -y $APT_OPTS
apt install -y $APT_OPTS curl git unzip zip build-essential ufw software-properties-common mariadb-server

# 2. Service Database
systemctl start mariadb
systemctl enable mariadb

# 3. Install PHP & Nginx
add-apt-repository -y ppa:ondrej/php
apt update -y
apt install -y $APT_OPTS nginx certbot python3-certbot-nginx
apt install -y $APT_OPTS php$PHP_VER php$PHP_VER-fpm php$PHP_VER-mysql php$PHP_VER-curl php$PHP_VER-xml php$PHP_VER-mbstring php$PHP_VER-zip php$PHP_VER-gd composer

# 4. Install Node.js
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VER}.x | bash -
    apt install -y $APT_OPTS nodejs
fi
if ! command -v pm2 &> /dev/null; then
    npm install -g pm2 yarn
fi

# 5. Firewall Setup
ufw allow 'Nginx Full'
ufw allow OpenSSH
if ! ufw status | grep -q "Status: active"; then echo "y" | ufw enable; fi

# ==========================================
# 6. GENERATE SCRIPT 'bd' (FIXED)
# ==========================================
cat << 'EOF' > /usr/local/bin/bd
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
PHP_V="8.2"
BACKUP_DIR="/root/backups"

# GANTI URL INI DENGAN RAW GITHUB ANDA
UPDATE_URL="https://raw.githubusercontent.com/username-anda/repo-anda/main/bd.sh"

show_header() {
    clear
    echo -e "${BLUE}======================================${NC}"
    echo -e "${YELLOW}   BUNNY DEPLOY - MANAGER (v25)${NC}"
    echo -e "${BLUE}======================================${NC}"
}

# --- HELPER: Fix Permissions ---
fix_perm() {
    local TARGET=$1
    echo "Fixing permissions for $TARGET..."
    chown -R www-data:www-data $TARGET
    find $TARGET -type f -exec chmod 644 {} \;
    find $TARGET -type d -exec chmod 755 {} \;
    if [ -d "$TARGET/storage" ]; then chmod -R 775 "$TARGET/storage"; fi
    if [ -d "$TARGET/bootstrap/cache" ]; then chmod -R 775 "$TARGET/bootstrap/cache"; fi
}

deploy_web() {
    echo -e "\n${YELLOW}[ DEPLOY WEBSITE BARU ]${NC}"
    echo "1. HTML5 / Static"
    echo "2. Node.js (Proxy)"
    echo "3. PHP $PHP_V (Laravel/CodeIgniter)"
    read -p "Pilih: " TYPE
    read -p "Domain (tanpa http/www): " DOMAIN
    
    if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9.-]+$ ]]; then echo -e "${RED}Domain tidak valid!${NC}"; return; fi

    read -p "Email SSL: " EMAIL
    CONFIG="/etc/nginx/sites-available/$DOMAIN"
    
    # NGINX CONFIG (Note: Variables $uri etc are NOT escaped because we use quoted EOF)
    SECURE_HEADERS="location ~ /\.(?!well-known).* { deny all; return 404; }"

    if [ "$TYPE" == "1" ]; then
        read -p "Folder Path (cth: /var/www/html/web): " ROOT
        mkdir -p $ROOT
        BLOCK="server { listen 80; server_name $DOMAIN; root $ROOT; index index.html; $SECURE_HEADERS location / { try_files \$uri \$uri/ /index.html; } }" 
    elif [ "$TYPE" == "2" ]; then
        read -p "Port App (cth: 3000): " PORT
        BLOCK="server { listen 80; server_name $DOMAIN; $SECURE_HEADERS location / { proxy_pass http://localhost:$PORT; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection 'upgrade'; proxy_set_header Host \$host; proxy_cache_bypass \$http_upgrade; } }"
    elif [ "$TYPE" == "3" ]; then
        read -p "Folder Path (cth: /var/www/html/api): " ROOT
        mkdir -p $ROOT
        BLOCK="server { listen 80; server_name $DOMAIN; root $ROOT; index index.php index.html; $SECURE_HEADERS location / { try_files \$uri \$uri/ /index.php?\$query_string; } location ~ \.php$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/run/php/php$PHP_V-fpm.sock; } }"
    else echo "Salah pilih"; return; fi

    echo "$BLOCK" > $CONFIG
    ln -s $CONFIG /etc/nginx/sites-enabled/ 2>/dev/null
    nginx -t
    if [ $? -eq 0 ]; then
        systemctl reload nginx
        if [ ! -z "$ROOT" ]; then fix_perm $ROOT; fi
        certbot --nginx --non-interactive --agree-tos -m $EMAIL -d $DOMAIN
        echo -e "${GREEN}Deploy Sukses!${NC}"
    else
        echo -e "${RED}Config Error. Rollback.${NC}"; rm $CONFIG; rm /etc/nginx/sites-enabled/$DOMAIN
    fi
    read -p "Press Enter..."
}

update_app() {
    echo -e "\n${YELLOW}[ UPDATE APP (GIT PULL) ]${NC}"
    read -p "Domain: " DOMAIN
    ROOT=$(grep "root" /etc/nginx/sites-available/$DOMAIN 2>/dev/null | awk '{print $2}' | tr -d ';')
    if [ -z "$ROOT" ]; then read -p "Path Folder: " ROOT; fi

    if [ -d "$ROOT/.git" ]; then
        cd $ROOT && git pull
        if [ -f "package.json" ]; then npm install; read -p "Restart PM2 ID?: " I; if [ ! -z "$I" ]; then pm2 restart $I; fi
        elif [ -f "composer.json" ]; then composer install --no-dev; php artisan migrate --force 2>/dev/null; fi
        fix_perm $ROOT
        echo -e "${GREEN}Updated & Permission Fixed.${NC}"
    else echo "Bukan Git Repo."; fi
    read -p "Press Enter..."
}

create_db() {
    echo -e "\n${YELLOW}[ BUAT DATABASE ]${NC}"
    read -p "Nama DB: " RAW_DB
    read -p "User DB: " RAW_USER
    DBNAME=$(echo "$RAW_DB" | tr -dc 'a-zA-Z0-9_')
    DBUSER=$(echo "$RAW_USER" | tr -dc 'a-zA-Z0-9_')
    GEN_PASS=$(openssl rand -base64 12)
    echo "Pass: $GEN_PASS"
    read -p "Pakai pass ini? (y/n): " C
    if [ "$C" == "n" ]; then read -s -p "Pass Manual: " DBPASS; echo ""; else DBPASS="$GEN_PASS"; fi
    
    mysql -e "CREATE DATABASE IF NOT EXISTS $DBNAME;"
    mysql -e "CREATE USER IF NOT EXISTS '$DBUSER'@'localhost' IDENTIFIED BY '$DBPASS';"
    mysql -e "GRANT ALL PRIVILEGES ON $DBNAME.* TO '$DBUSER'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    
    echo -e "${GREEN}DB $DBNAME Dibuat! Simpan passwordnya.${NC}"
    read -p "Press Enter..."
}

backup_wizard() {
    mkdir -p $BACKUP_DIR
    echo -e "\n${YELLOW}[ BACKUP WIZARD ]${NC}"
    echo "1. Backup File Website + Database"
    echo "2. Backup Database Saja"
    read -p "Pilih: " BTYPE

    if [ "$BTYPE" == "1" ]; then
        read -p "Masukkan Domain: " DOMAIN
        ROOT=$(grep "root" /etc/nginx/sites-available/$DOMAIN 2>/dev/null | awk '{print $2}' | tr -d ';')
        if [ -z "$ROOT" ]; then read -p "Path Folder Project: " ROOT; fi
        
        read -p "Nama Database (kosongkan jika tidak ada): " DBNAME
        
        DATE=$(date +%Y-%m-%d_%H-%M)
        FILENAME="backup_${DOMAIN}_${DATE}.zip"
        TEMP_SQL="/tmp/db_dump_temp.sql"

        echo "Memproses backup..."
        ZIP_CMD="zip -r \"$BACKUP_DIR/$FILENAME\" ."
        
        if [ ! -z "$DBNAME" ]; then
            mysqldump $DBNAME > "$TEMP_SQL" 2>/dev/null
            ZIP_CMD="$ZIP_CMD -j \"$TEMP_SQL\""
        fi
        
        cd $ROOT
        eval "$ZIP_CMD -x \"node_modules/*\" \"vendor/*\" \"storage/*.log\""
        if [ -f "$TEMP_SQL" ]; then rm "$TEMP_SQL"; fi
        
        echo -e "${GREEN}Backup Selesai: $BACKUP_DIR/$FILENAME${NC}"
        
    elif [ "$BTYPE" == "2" ]; then
        read -p "Nama Database: " DBNAME
        DATE=$(date +%Y-%m-%d_%H-%M)
        mysqldump $DBNAME > "$BACKUP_DIR/db_${DBNAME}_${DATE}.sql"
        echo -e "${GREEN}Database didump.${NC}"
    fi
    read -p "Press Enter..."
}

update_tool() {
    echo -e "\n${YELLOW}[ UPDATE SCRIPT TOOLS ]${NC}"
    echo "Checking updates..."
    if [[ "$UPDATE_URL" == *"username-anda"* ]]; then
        echo -e "${RED}ERROR: URL Update belum disetting!${NC} Edit file: /usr/local/bin/bd"
        read -p "Press Enter..."
        return
    fi
    curl -sL "$UPDATE_URL" -o /tmp/bd_latest
    if grep -q "#!/bin/bash" /tmp/bd_latest; then
        mv /tmp/bd_latest /usr/local/bin/bd
        chmod +x /usr/local/bin/bd
        echo -e "${GREEN}Update Berhasil! Restarting...${NC}"
        sleep 1
        exec bd
    else
        echo -e "${RED}Gagal Update! File korup.${NC}"
        rm /tmp/bd_latest 2>/dev/null
    fi
    read -p "Press Enter..."
}

uninstall_script() {
    read -p "Hapus script 'bd'? (y/n): " Y
    if [ "$Y" == "y" ]; then rm /usr/local/bin/bd; echo "Terhapus."; exit; fi
}

# --- MAIN MENU ---
while true; do
    show_header
    echo "1. Deploy Website (Secured)"
    echo "2. Update Web/App"
    echo "3. Database Manager"
    echo "4. PM2 Manager"
    echo "5. Update Script Tools"
    echo "6. Backup Data"
    echo "7. Uninstall Script"
    echo "0. Keluar"
    read -p "Pilih: " OPT
    case $OPT in
        1) deploy_web ;;
        2) update_app ;;
        3) create_db ;;
        4) pm2 list; read -p "Run PM2 Cmd: " C; $C; read -p "Press Enter..." ;;
        5) update_tool ;;
        6) backup_wizard ;;
        7) uninstall_script ;;
        0) exit ;;
        *) echo "Pilihan salah"; sleep 1 ;;
    esac
done
EOF

chmod +x /usr/local/bin/bd
echo "UPDATE SELESAI. Ketik: bd"
