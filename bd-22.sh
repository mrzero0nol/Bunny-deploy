#!/bin/bash
# ===============================================
#  BUNNY DEPLOY - ULTIMATE UI (BD-31)
#  Code: New UI + Disk Detail + Separated Exit
# ===============================================

# --- CONFIGURATION ---
PHP_VER="8.2"
NODE_VER="20"
# ---------------------

export DEBIAN_FRONTEND=noninteractive
APT_OPTS="-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# Cek Root
if [ "$EUID" -ne 0 ]; then echo "Harap jalankan sebagai root (sudo -i)"; exit; fi

echo "Memuat Bunny Deploy v31..."

# 1. Update & Tools (Basic)
if ! command -v zip &> /dev/null; then
    apt update -y; apt install -y $APT_OPTS curl git unzip zip build-essential ufw software-properties-common mariadb-server bc
fi

# 2. Service Database
systemctl start mariadb
systemctl enable mariadb

# 3. Install PHP & Nginx (Only if missing)
if ! command -v nginx &> /dev/null; then
    add-apt-repository -y ppa:ondrej/php
    apt update -y
    apt install -y $APT_OPTS nginx certbot python3-certbot-nginx
    apt install -y $APT_OPTS php$PHP_VER php$PHP_VER-fpm php$PHP_VER-mysql php$PHP_VER-curl php$PHP_VER-xml php$PHP_VER-mbstring php$PHP_VER-zip php$PHP_VER-gd composer
fi

# 4. Install Node.js
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VER}.x | bash -
    apt install -y $APT_OPTS nodejs
fi
if ! command -v pm2 &> /dev/null; then
    npm install -g pm2 yarn
fi

# 5. Firewall Setup
ufw allow 'Nginx Full' >/dev/null 2>&1
ufw allow OpenSSH >/dev/null 2>&1
if ! ufw status | grep -q "Status: active"; then echo "y" | ufw enable >/dev/null 2>&1; fi

# ==========================================
# 6. GENERATE SCRIPT 'bd' (NEW UI)
# ==========================================
cat << 'EOF' > /usr/local/bin/bd
#!/bin/bash
# COLORS & STYLES
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'
BOLD='\033[1m'

PHP_V="8.2"
BACKUP_DIR="/root/backups"
UPDATE_URL="https://raw.githubusercontent.com/mrzero0nol/Bunny-deploy/refs/heads/main/bd-22.sh"

# --- SYSTEM INFO DASHBOARD ---
get_sys_info() {
    # RAM
    RAM_USED=$(free -m | grep Mem | awk '{print $3}')
    RAM_TOTAL=$(free -m | grep Mem | awk '{print $2}')
    RAM_PERC=$((RAM_USED * 100 / RAM_TOTAL))
    
    # SWAP
    SWAP_USED=$(free -m | grep Swap | awk '{print $3}')
    SWAP_TOTAL=$(free -m | grep Swap | awk '{print $2}')
    if [ "$SWAP_TOTAL" -eq 0 ]; then SWAP_PERC=0; else SWAP_PERC=$((SWAP_USED * 100 / SWAP_TOTAL)); fi
    
    # DISK (Used / Total)
    DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
    DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
    DISK_PERC=$(df -h / | awk 'NR==2 {print $5}')
    
    # CPU Load
    LOAD=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1 | xargs)
}

show_header() {
    get_sys_info
    clear
    echo -e "${CYAN}┌───────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${WHITE} ${BOLD}🐰 BUNNY DEPLOY - PRO MANAGER v31${NC}                    ${CYAN}│${NC}"
    echo -e "${CYAN}├───────────────────────────┬───────────────────────────┤${NC}"
    # Baris 1: RAM & DISK
    printf "${CYAN}│${NC} ● RAM:  %-17s ${CYAN}│${NC} ● DISK: %-17s ${CYAN}│${NC}\n" "${RAM_USED}/${RAM_TOTAL}MB ($RAM_PERC%)" "${DISK_USED}/${DISK_TOTAL} ($DISK_PERC)"
    # Baris 2: SWAP & CPU
    printf "${CYAN}│${NC} ● SWAP: %-17s ${CYAN}│${NC} ● CPU:  %-17s ${CYAN}│${NC}\n" "${SWAP_USED}/${SWAP_TOTAL}MB ($SWAP_PERC%)" "Load $LOAD"
    echo -e "${CYAN}└───────────────────────────┴───────────────────────────┘${NC}"
    echo ""
}

# --- FUNCTIONS ---
fix_perm() {
    local TARGET=$1
    echo "Fixing permissions..."
    chown -R www-data:www-data $TARGET
    find $TARGET -type f -exec chmod 644 {} \;
    find $TARGET -type d -exec chmod 755 {} \;
    if [ -d "$TARGET/storage" ]; then chmod -R 775 "$TARGET/storage"; fi
}

manage_swap() {
    echo -e "\n${YELLOW}[ SWAP MANAGER ]${NC}"
    echo -e "Current Swap: ${WHITE}${SWAP_TOTAL} MB${NC}"
    echo "1. Set Swap Baru"
    echo "2. Hapus Swap"
    read -p "Pilih: " S_OPT
    if [ "$S_OPT" == "1" ]; then
        read -p "Ukuran (GB): " GB
        if [[ ! "$GB" =~ ^[0-9]+$ ]]; then echo "Error: Harus Angka"; sleep 1; return; fi
        swapoff -a; rm -f /swapfile
        fallocate -l ${GB}G /swapfile; chmod 600 /swapfile; mkswap /swapfile; swapon /swapfile
        cp /etc/fstab /etc/fstab.bak; grep -v swap /etc/fstab > /etc/fstab.tmp; mv /etc/fstab.tmp /etc/fstab
        echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
        echo -e "${GREEN}Swap ${GB}GB Aktif.${NC}"
    elif [ "$S_OPT" == "2" ]; then
        swapoff -a; rm -f /swapfile; grep -v swap /etc/fstab > /etc/fstab.tmp; mv /etc/fstab.tmp /etc/fstab
        echo "Swap Nonaktif."
    fi
    sleep 1
}

cron_manager() {
    echo -e "\n${YELLOW}[ CRON SCHEDULER ]${NC}"
    echo "1. List Jobs"
    echo "2. Edit Manual"
    echo "3. Auto Laravel Schedule"
    read -p "► Pilih: " C
    case $C in
        1) crontab -l ;;
        2) crontab -e ;;
        3) read -p "Path Project: " P
           if [ -d "$P" ]; then (crontab -l 2>/dev/null; echo "* * * * * cd $P && php artisan schedule:run >> /dev/null 2>&1") | crontab -; echo "Sukses."; else echo "Folder 404"; fi ;;
    esac
    read -p "Enter..."
}

deploy_web() {
    echo -e "\n${YELLOW}[ NEW DEPLOYMENT ]${NC}"
    echo "1. HTML Static"
    echo "2. Node.js Proxy"
    echo "3. PHP (Laravel/CI)"
    read -p "► Tipe: " TYPE
    read -p "► Domain: " DOMAIN
    read -p "► Email SSL: " EMAIL
    CONFIG="/etc/nginx/sites-available/$DOMAIN"
    SECURE="location ~ /\.(?!well-known).* { deny all; return 404; }"
    
    if [ "$TYPE" == "1" ]; then
        read -p "Folder Path: " ROOT; mkdir -p $ROOT
        BLOCK="server { listen 80; server_name $DOMAIN; root $ROOT; index index.html; $SECURE location / { try_files \$uri \$uri/ /index.html; } }"
    elif [ "$TYPE" == "2" ]; then
        read -p "Port App: " PORT
        BLOCK="server { listen 80; server_name $DOMAIN; $SECURE location / { proxy_pass http://localhost:$PORT; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection 'upgrade'; proxy_set_header Host \$host; proxy_cache_bypass \$http_upgrade; } }"
    elif [ "$TYPE" == "3" ]; then
        read -p "Folder Path: " ROOT; mkdir -p $ROOT
        BLOCK="server { listen 80; server_name $DOMAIN; root $ROOT; index index.php index.html; $SECURE location / { try_files \$uri \$uri/ /index.php?\$query_string; } location ~ \.php$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/run/php/php$PHP_V-fpm.sock; } }"
    fi
    
    echo "$BLOCK" > $CONFIG; ln -s $CONFIG /etc/nginx/sites-enabled/ 2>/dev/null
    nginx -t
    if [ $? -eq 0 ]; then
        systemctl reload nginx; [ ! -z "$ROOT" ] && fix_perm $ROOT
        certbot --nginx --non-interactive --agree-tos -m $EMAIL -d $DOMAIN
        echo -e "${GREEN}Deploy Berhasil!${NC}"
    else rm $CONFIG; rm /etc/nginx/sites-enabled/$DOMAIN; echo "${RED}Gagal. Config Rollback.${NC}"; fi
    read -p "Enter..."
}

manage_web() {
    echo -e "\n${YELLOW}[ MANAGE WEBSITE ]${NC}"
    ls /etc/nginx/sites-available
    echo "--------------------------------"
    echo "1. Start   | 2. Stop   | 3. Delete"
    echo "4. Cek Log (Live)"
    read -p "► Pilih: " W
    case $W in
        1) read -p "Domain: " D; ln -s /etc/nginx/sites-available/$D /etc/nginx/sites-enabled/ 2>/dev/null; systemctl reload nginx; echo "On." ;;
        2) read -p "Domain: " D; rm /etc/nginx/sites-enabled/$D 2>/dev/null; systemctl reload nginx; echo "Off." ;;
        3) read -p "Domain: " D; read -p "Yakin (y/n)? " Y; if [ "$Y" == "y" ]; then rm /etc/nginx/sites-enabled/$D 2>/dev/null; rm /etc/nginx/sites-available/$D; certbot delete --cert-name $D --non-interactive 2>/dev/null; echo "Deleted."; fi ;;
        4) echo "1. All Traffic | 2. All Errors | 3. Filter Domain"; read -p "Mode: " L
           echo -e "${YELLOW}(Ctrl+C untuk keluar)${NC}"
           if [ "$L" == "1" ]; then tail -f /var/log/nginx/access.log; 
           elif [ "$L" == "2" ]; then tail -f /var/log/nginx/error.log; 
           elif [ "$L" == "3" ]; then read -p "Domain: " D; tail -f /var/log/nginx/access.log | grep --line-buffered "$D"; fi ;;
    esac
    read -p "Enter..."
}

manage_app() {
    echo -e "\n${YELLOW}[ MANAGE PM2 APP ]${NC}"
    pm2 list
    echo "--------------------------------"
    echo "1. Stop    | 2. Restart | 3. Delete"
    echo "4. Log ID  | 5. Dashboard"
    read -p "► Pilih: " P
    case $P in
        1) read -p "ID App: " I; pm2 stop $I ;;
        2) read -p "ID App: " I; pm2 restart $I ;;
        3) read -p "ID App: " I; pm2 delete $I ;;
        4) read -p "ID App: " I; pm2 logs $I ;;
        5) pm2 monit ;;
    esac
    pm2 save
    read -p "Enter..."
}

create_db() {
    echo -e "\n${YELLOW}[ DATABASE WIZARD ]${NC}"
    read -p "Nama DB: " D; read -p "User DB: " U
    DB=$(echo "$D" | tr -dc 'a-zA-Z0-9_'); USER=$(echo "$U" | tr -dc 'a-zA-Z0-9_')
    PASS=$(openssl rand -base64 12); echo "Pass: $PASS"
    read -p "Pakai pass ini? (y/n): " C
    if [ "$C" == "n" ]; then read -s -p "Pass Manual: " PASS; echo ""; fi
    mysql -e "CREATE DATABASE IF NOT EXISTS $DB;"
    mysql -e "CREATE USER IF NOT EXISTS '$USER'@'localhost' IDENTIFIED BY '$PASS';"
    mysql -e "GRANT ALL PRIVILEGES ON $DB.* TO '$USER'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    echo "Database Siap."; read -p "Enter..."
}

backup_wizard() {
    mkdir -p $BACKUP_DIR
    echo -e "\n${YELLOW}[ BACKUP SYSTEM ]${NC}"
    echo "1. Web & DB (Zip) | 2. DB Only (.sql)"
    read -p "► Pilih: " B
    if [ "$B" == "1" ]; then
        read -p "Domain: " DOM; ROOT=$(grep "root" /etc/nginx/sites-available/$DOM 2>/dev/null | awk '{print $2}' | tr -d ';')
        [ -z "$ROOT" ] && read -p "Path Manual: " ROOT
        read -p "Nama DB (Optional): " DB
        FILE="backup_${DOM}_$(date +%F_%H%M).zip"; TMP="/tmp/dump.sql"
        CMD="zip -r \"$BACKUP_DIR/$FILE\" . -x \"node_modules/*\" \"vendor/*\" \"storage/*.log\""
        [ ! -z "$DB" ] && mysqldump $DB > $TMP 2>/dev/null && CMD="$CMD -j \"$TMP\""
        cd $ROOT && eval $CMD && rm -f $TMP
        echo "Saved to: $BACKUP_DIR/$FILE"
    elif [ "$B" == "2" ]; then
        read -p "Nama DB: " DB; mysqldump $DB > "$BACKUP_DIR/${DB}_$(date +%F).sql"
        echo "Database Saved."
    fi
    read -p "Enter..."
}

update_app_git() {
    read -p "Domain: " DOM; ROOT=$(grep "root" /etc/nginx/sites-available/$DOM 2>/dev/null | awk '{print $2}' | tr -d ';')
    [ -z "$ROOT" ] && read -p "Path Folder: " ROOT
    if [ -d "$ROOT/.git" ]; then
        cd $ROOT && git pull
        [ -f "package.json" ] && npm install
        [ -f "composer.json" ] && composer install --no-dev
        fix_perm $ROOT
        echo "Updated & Fixed."
    else echo "Bukan folder Git."; fi
    read -p "Enter..."
}

update_tool() {
    curl -sL "$UPDATE_URL" -o /tmp/bd_latest
    if grep -q "#!/bin/bash" /tmp/bd_latest; then mv /tmp/bd_latest /usr/local/bin/bd; chmod +x /usr/local/bin/bd; exec bd; else echo "Gagal Download."; fi
}

uninstall_script() {
    echo -e "${RED}[ PERINGATAN ]${NC} Script ini akan dihapus dari sistem."
    read -p "Yakin? (y/n): " Y
    if [ "$Y" == "y" ]; then rm /usr/local/bin/bd; echo "Terhapus."; exit; fi
}

# --- MAIN LOOP UI ---
while true; do
    show_header
    echo -e "${WHITE}${BOLD} CORE FEATURES:${NC}"
    echo -e " ${CYAN}1.${NC} Deploy Website       ${CYAN}4.${NC} Manage App (PM2)"
    echo -e " ${CYAN}2.${NC} Manage Web (Nginx)   ${CYAN}5.${NC} Database Wizard"
    echo -e " ${CYAN}3.${NC} Git Pull Update      ${CYAN}6.${NC} Backup Data"
    echo ""
    echo -e "${WHITE}${BOLD} UTILITIES:${NC}"
    echo -e " ${CYAN}7.${NC} SWAP Manager         ${CYAN}8.${NC} Cron Job"
    echo -e " ${CYAN}9.${NC} Update Tools         ${RED}0. KELUAR (Exit)${NC}"
    echo ""
    echo -e " ${CYAN}u.${NC} Uninstall Script"
    echo ""
    read -p " Select Option: " OPT
    case $OPT in
        1) deploy_web ;;
        2) manage_web ;;
        3) update_app_git ;;
        4) manage_app ;;
        5) create_db ;;
        6) backup_wizard ;;
        7) manage_swap ;;
        8) cron_manager ;;
        9) update_tool ;;
        0) clear; exit ;;
        u) uninstall_script ;;
        *) echo "Invalid."; sleep 1 ;;
    esac
done
EOF

chmod +x /usr/local/bin/bd
echo -e "${GREEN}UPDATE SELESAI.${NC}"
echo "Tampilan baru siap. Ketik: bd"
