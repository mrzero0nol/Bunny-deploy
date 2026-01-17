#!/bin/bash
# ===============================================
#  BUNNY DEPLOY - PRO DASHBOARD (BD-28)
#  Code: UI Overhaul + Swap Manager + SysInfo
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
apt install -y $APT_OPTS curl git unzip zip build-essential ufw software-properties-common mariadb-server bc

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
# 6. GENERATE SCRIPT 'bd' (PRO UI)
# ==========================================
cat << 'EOF' > /usr/local/bin/bd
#!/bin/bash
# COLORS
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'
BG_BLUE='\033[44m'; BG_RED='\033[41m'

PHP_V="8.2"
BACKUP_DIR="/root/backups"
UPDATE_URL="https://raw.githubusercontent.com/username-anda/repo-anda/main/bd.sh"

# --- SYSTEM INFO DASHBOARD ---
get_sys_info() {
    # RAM Usage
    RAM_USED=$(free -m | grep Mem | awk '{print $3}')
    RAM_TOTAL=$(free -m | grep Mem | awk '{print $2}')
    RAM_PERC=$((RAM_USED * 100 / RAM_TOTAL))
    
    # Swap Usage
    SWAP_USED=$(free -m | grep Swap | awk '{print $3}')
    SWAP_TOTAL=$(free -m | grep Swap | awk '{print $2}')
    if [ "$SWAP_TOTAL" -eq 0 ]; then SWAP_PERC=0; else SWAP_PERC=$((SWAP_USED * 100 / SWAP_TOTAL)); fi
    
    # Disk Usage
    DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}')
    
    # Load Average
    LOAD=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1 | xargs)
}

show_header() {
    get_sys_info
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${WHITE}           🐰 BUNNY DEPLOY - PRO MANAGER v28          ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    
    # Dashboard Grid
    echo -e "${WHITE} SYSTEM STATUS:${NC}"
    echo -e " ----------------------------------------------------"
    printf " | RAM:  %-15s | SWAP: %-15s |\n" "${RAM_USED}MB / ${RAM_TOTAL}MB (${RAM_PERC}%)" "${SWAP_USED}MB / ${SWAP_TOTAL}MB (${SWAP_PERC}%)"
    printf " | DISK: %-15s | CPU:  %-15s |\n" "$DISK_USAGE Used" "Load: $LOAD"
    echo -e " ----------------------------------------------------"
    echo ""
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

# --- FEATURES ---

manage_swap() {
    echo -e "\n${YELLOW}[ SWAP MEMORY MANAGER ]${NC}"
    echo "Swap membantu VPS agar tidak crash saat RAM penuh."
    echo -e "Swap saat ini: ${WHITE}${SWAP_TOTAL} MB${NC}"
    echo "-----------------------------------"
    echo "1. Buat/Ubah Ukuran Swap"
    echo "2. Hapus Swap (Matikan)"
    echo "0. Kembali"
    read -p "Pilih: " S_OPT

    if [ "$S_OPT" == "1" ]; then
        read -p "Masukkan ukuran Swap (GB), cth 1, 2, 4: " GB
        if [[ ! "$GB" =~ ^[0-9]+$ ]]; then echo "Input harus angka!"; sleep 1; return; fi
        
        echo "Menyiapkan Swap ${GB}GB..."
        # Matikan swap lama
        swapoff -a
        rm -f /swapfile
        
        # Buat baru
        fallocate -l ${GB}G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        
        # Persist di fstab
        cp /etc/fstab /etc/fstab.bak
        grep -v swap /etc/fstab > /etc/fstab.tmp
        mv /etc/fstab.tmp /etc/fstab
        echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
        
        echo -e "${GREEN}Sukses! Swap ${GB}GB aktif.${NC}"
        
    elif [ "$S_OPT" == "2" ]; then
        swapoff -a
        rm -f /swapfile
        grep -v swap /etc/fstab > /etc/fstab.tmp
        mv /etc/fstab.tmp /etc/fstab
        echo -e "${RED}Swap dimatikan.${NC}"
    fi
    read -p "Press Enter..."
}

cron_manager() {
    echo -e "\n${YELLOW}[ CRON JOB SCHEDULER ]${NC}"
    echo "1. Lihat List Cron Job"
    echo "2. Edit Cron Job (Manual)"
    echo "3. Tambah Scheduler Laravel (Otomatis)"
    read -p "Pilih: " C_OPT
    
    if [ "$C_OPT" == "1" ]; then
        echo "----------------"
        crontab -l
        echo "----------------"
    elif [ "$C_OPT" == "2" ]; then
        crontab -e
    elif [ "$C_OPT" == "3" ]; then
        read -p "Masukkan Path Project (cth: /var/www/html/api): " P_PATH
        if [ -d "$P_PATH" ]; then
            (crontab -l 2>/dev/null; echo "* * * * * cd $P_PATH && php artisan schedule:run >> /dev/null 2>&1") | crontab -
            echo -e "${GREEN}Scheduler Laravel ditambahkan!${NC}"
        else
            echo "Folder tidak ditemukan."
        fi
    fi
    read -p "Press Enter..."
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

manage_web() {
    echo -e "\n${YELLOW}[ MANAGE WEBSITE ]${NC}"
    echo -e "${BLUE}Website Configured:${NC}"
    ls /etc/nginx/sites-available
    echo "-----------------------------"
    echo "1. Start Website (Enable)"
    echo "2. Stop Website (Disable)"
    echo "3. Restart Nginx"
    echo "4. Hapus Website (Total)"
    echo "5. Cek Log (Access/Error)"
    read -p "Pilih: " W_OPT
    
    case $W_OPT in
        1) 
           read -p "Domain: " D; ln -s /etc/nginx/sites-available/$D /etc/nginx/sites-enabled/ 2>/dev/null; systemctl reload nginx; echo "Done." ;;
        2) 
           read -p "Domain: " D; rm /etc/nginx/sites-enabled/$D 2>/dev/null; systemctl reload nginx; echo "Done." ;;
        3) systemctl reload nginx; echo "Reloaded." ;;
        4) 
           read -p "Domain Hapus: " D
           read -p "Yakin? (y/n): " Y
           if [ "$Y" == "y" ]; then
               rm /etc/nginx/sites-enabled/$D 2>/dev/null; rm /etc/nginx/sites-available/$D; certbot delete --cert-name $D --non-interactive 2>/dev/null
               echo "Config & SSL Deleted."
           fi ;;
        5)
           echo "1. Access Log | 2. Error Log"; read -p "> " L
           if [ "$L" == "1" ]; then tail -f /var/log/nginx/access.log; else tail -f /var/log/nginx/error.log; fi ;;
    esac
    read -p "Press Enter..."
}

manage_app() {
    echo -e "\n${YELLOW}[ MANAGE APP (PM2) ]${NC}"
    pm2 list
    echo "-----------------------------"
    echo "1. Stop  | 2. Start  | 3. Delete"
    echo "4. Log   | 5. Save State"
    read -p "Pilih: " P_OPT
    case $P_OPT in
        1) read -p "ID: " I; pm2 stop $I ;;
        2) read -p "ID: " I; pm2 restart $I ;;
        3) read -p "ID: " I; pm2 delete $I ;;
        4) pm2 monit ;;
        5) pm2 save; echo "Saved." ;;
    esac
    read -p "Press Enter..."
}

update_app_git() {
    echo -e "\n${YELLOW}[ GIT PULL UPDATE ]${NC}"
    read -p "Domain: " DOMAIN
    ROOT=$(grep "root" /etc/nginx/sites-available/$DOMAIN 2>/dev/null | awk '{print $2}' | tr -d ';')
    if [ -z "$ROOT" ]; then read -p "Path Folder: " ROOT; fi
    if [ -d "$ROOT/.git" ]; then
        cd $ROOT && git pull
        if [ -f "package.json" ]; then npm install; elif [ -f "composer.json" ]; then composer install --no-dev; fi
        fix_perm $ROOT
        echo -e "${GREEN}Updated.${NC}"
    else echo "Bukan Git Repo."; fi
    read -p "Press Enter..."
}

create_db() {
    echo -e "\n${YELLOW}[ DATABASE WIZARD ]${NC}"
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
    echo -e "${GREEN}DB Created!${NC}"; read -p "Enter..."
}

backup_wizard() {
    mkdir -p $BACKUP_DIR
    echo -e "\n${YELLOW}[ BACKUP SYSTEM ]${NC}"
    echo "1. Full Backup (File + DB)"; echo "2. DB Only"
    read -p "Pilih: " BTYPE
    if [ "$BTYPE" == "1" ]; then
        read -p "Domain: " DOMAIN
        ROOT=$(grep "root" /etc/nginx/sites-available/$DOMAIN 2>/dev/null | awk '{print $2}' | tr -d ';')
        if [ -z "$ROOT" ]; then read -p "Path: " ROOT; fi
        read -p "DB Name (Enter jika tidak ada): " DBNAME
        DATE=$(date +%Y-%m-%d_%H-%M); FILE="backup_${DOMAIN}_${DATE}.zip"; TMP="/tmp/dump.sql"
        echo "Zipping..."
        CMD="zip -r \"$BACKUP_DIR/$FILE\" ."
        if [ ! -z "$DBNAME" ]; then mysqldump $DBNAME > $TMP 2>/dev/null; CMD="$CMD -j \"$TMP\""; fi
        cd $ROOT; eval "$CMD -x \"node_modules/*\" \"vendor/*\" \"storage/*.log\""; rm -f $TMP
        echo "Saved: $BACKUP_DIR/$FILE"
    elif [ "$BTYPE" == "2" ]; then
        read -p "DB Name: " DBNAME; mysqldump $DBNAME > "$BACKUP_DIR/${DBNAME}_$(date +%F).sql"; echo "Done."
    fi
    read -p "Enter..."
}

update_tool() {
    echo "Updating..."
    curl -sL "$UPDATE_URL" -o /tmp/bd_latest
    if grep -q "#!/bin/bash" /tmp/bd_latest; then mv /tmp/bd_latest /usr/local/bin/bd; chmod +x /usr/local/bin/bd; exec bd; else echo "Error."; fi
}

uninstall_script() {
    read -p "Hapus script? (y/n): " Y; if [ "$Y" == "y" ]; then rm /usr/local/bin/bd; exit; fi
}

# --- MAIN LOOP ---
while true; do
    show_header
    echo -e "${GREEN}CORE FEATURES:${NC}"
    echo " 1. Deploy Website (New)       4. Git Update & Fix Perms"
    echo " 2. Manage Website (Nginx)     5. Database Wizard"
    echo " 3. Manage App (PM2)           6. Backup Data"
    echo ""
    echo -e "${GREEN}SYSTEM UTILITIES:${NC}"
    echo " 7. SWAP Manager (Anti-Crash)  8. Cron Job (Scheduler)"
    echo " 9. Update This Script         0. Exit / Uninstall"
    echo ""
    read -p " Select Option [0-9]: " OPT
    case $OPT in
        1) deploy_web ;;
        2) manage_web ;;
        3) manage_app ;;
        4) update_app_git ;;
        5) create_db ;;
        6) backup_wizard ;;
        7) manage_swap ;;
        8) cron_manager ;;
        9) update_tool ;;
        0) echo "Bye!"; exit ;;
        u) uninstall_script ;;
        *) echo "Invalid."; sleep 1 ;;
    esac
done
EOF

chmod +x /usr/local/bin/bd
echo "UPDATE COMPLETE. Ketik: bd"
