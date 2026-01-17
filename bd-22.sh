#!/bin/bash
# ===============================================
#  BUNNY DEPLOY - BOXED UI EDITION (BD-32)
#  Code: Full Box Interface + Submenu Back Button
# ===============================================

# --- CONFIGURATION ---
PHP_VER="8.2"
NODE_VER="20"
# ---------------------

export DEBIAN_FRONTEND=noninteractive
APT_OPTS="-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# Cek Root
if [ "$EUID" -ne 0 ]; then echo "Harap jalankan sebagai root (sudo -i)"; exit; fi

echo "Memuat Interface BD-32..."

# 1. Basic Tools (Install jika belum ada)
if ! command -v zip &> /dev/null; then
    apt update -y; apt install -y $APT_OPTS curl git unzip zip build-essential ufw software-properties-common mariadb-server bc
fi

# 2. Service
systemctl start mariadb >/dev/null 2>&1
systemctl enable mariadb >/dev/null 2>&1

# 3. Install PHP/Nginx (Cek dulu)
if ! command -v nginx &> /dev/null; then
    add-apt-repository -y ppa:ondrej/php
    apt update -y
    apt install -y $APT_OPTS nginx certbot python3-certbot-nginx
    apt install -y $APT_OPTS php$PHP_VER php$PHP_VER-fpm php$PHP_VER-mysql php$PHP_VER-curl php$PHP_VER-xml php$PHP_VER-mbstring php$PHP_VER-zip php$PHP_VER-gd composer
fi

# 4. Install Node
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VER}.x | bash -
    apt install -y $APT_OPTS nodejs
fi
if ! command -v pm2 &> /dev/null; then
    npm install -g pm2 yarn
fi

# 5. Firewall
ufw allow 'Nginx Full' >/dev/null 2>&1
ufw allow OpenSSH >/dev/null 2>&1
if ! ufw status | grep -q "Status: active"; then echo "y" | ufw enable >/dev/null 2>&1; fi

# ==========================================
# 6. GENERATE SCRIPT 'bd' (BOXED UI)
# ==========================================
cat << 'EOF' > /usr/local/bin/bd
#!/bin/bash
# COLORS
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'
BOLD='\033[1m'

PHP_V="8.2"
BACKUP_DIR="/root/backups"
UPDATE_URL="https://raw.githubusercontent.com/mrzero0nol/Bunny-deploy/refs/heads/main/bd-22.sh"

# --- UI HELPER FUNCTIONS ---

draw_line() {
    echo -e "${CYAN}├───────────────────────────────┼───────────────────────────────┤${NC}"
}
draw_top() {
    echo -e "${CYAN}┌───────────────────────────────────────────────────────────────┐${NC}"
}
draw_bottom() {
    echo -e "${CYAN}└───────────────────────────────────────────────────────────────┘${NC}"
}

get_sys_info() {
    # RAM
    RAM_USED=$(free -m | grep Mem | awk '{print $3}')
    RAM_TOTAL=$(free -m | grep Mem | awk '{print $2}')
    RAM_PERC=$((RAM_USED * 100 / RAM_TOTAL))
    
    # SWAP
    SWAP_USED=$(free -m | grep Swap | awk '{print $3}')
    SWAP_TOTAL=$(free -m | grep Swap | awk '{print $2}')
    if [ "$SWAP_TOTAL" -eq 0 ]; then SWAP_PERC=0; else SWAP_PERC=$((SWAP_USED * 100 / SWAP_TOTAL)); fi
    
    # DISK
    DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
    DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
    DISK_PERC=$(df -h / | awk 'NR==2 {print $5}')
    
    # CPU
    LOAD=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1 | xargs)
}

show_header() {
    get_sys_info
    clear
    draw_top
    echo -e "${CYAN}│${WHITE}${BOLD}               🐰 BUNNY DEPLOY - PRO MANAGER v32               ${CYAN}│${NC}"
    draw_line
    # Kolom kiri (RAM/SWAP) lebar 30, Kanan (DISK/CPU) lebar 30. Total 63 char + border.
    # Menggunakan printf agar garis vertikal tengah dan kanan selalu lurus.
    
    printf "${CYAN}│${NC} ● RAM : %-20s ${CYAN}│${NC} ● DISK: %-20s ${CYAN}│${NC}\n" "${RAM_USED}/${RAM_TOTAL}MB ($RAM_PERC%)" "${DISK_USED}/${DISK_TOTAL} ($DISK_PERC)"
    printf "${CYAN}│${NC} ● SWAP: %-20s ${CYAN}│${NC} ● CPU : %-20s ${CYAN}│${NC}\n" "${SWAP_USED}/${SWAP_TOTAL}MB ($SWAP_PERC%)" "Load $LOAD"
    
    draw_line
    echo -e "${CYAN}│${YELLOW}                        CORE FEATURES                          ${CYAN}│${NC}"
    printf "${CYAN}│${NC} 1. Deploy Website             ${CYAN}│${NC} 4. Manage App (PM2)           ${CYAN}│${NC}\n"
    printf "${CYAN}│${NC} 2. Manage Web (Nginx)         ${CYAN}│${NC} 5. Database Wizard            ${CYAN}│${NC}\n"
    printf "${CYAN}│${NC} 3. Git Pull Update            ${CYAN}│${NC} 6. Backup Data                ${CYAN}│${NC}\n"
    
    draw_line
    echo -e "${CYAN}│${YELLOW}                          UTILITIES                            ${CYAN}│${NC}"
    printf "${CYAN}│${NC} 7. SWAP Manager               ${CYAN}│${NC} 8. Cron Job                   ${CYAN}│${NC}\n"
    printf "${CYAN}│${NC} 9. Update Tools               ${CYAN}│${NC} u. Uninstall                  ${CYAN}│${NC}\n"
    
    draw_line
    echo -e "${CYAN}│${RED}                      0. KELUAR (Exit)                         ${CYAN}│${NC}"
    draw_bottom
}

# --- SUBMENU UI ---
submenu_header() {
    local TITLE=$1
    echo -e "\n${CYAN}┌───────────────────────────────────────────────────────────────┐${NC}"
    printf "${CYAN}│${WHITE}${BOLD} %-61s ${CYAN}│${NC}\n" "MENU: $TITLE"
    echo -e "${CYAN}└───────────────────────────────────────────────────────────────┘${NC}"
}

fix_perm() {
    chown -R www-data:www-data $1
    find $1 -type f -exec chmod 644 {} \;
    find $1 -type d -exec chmod 755 {} \;
    if [ -d "$1/storage" ]; then chmod -R 775 "$1/storage"; fi
}

# --- FEATURES ---

deploy_web() {
    while true; do
        submenu_header "DEPLOY NEW WEBSITE"
        echo "1. HTML Static"
        echo "2. Node.js Proxy (Port)"
        echo "3. PHP (Laravel/CI)"
        echo "0. Kembali"
        read -p "► Pilih: " TYPE
        
        if [ "$TYPE" == "0" ]; then return; fi
        
        read -p "► Domain: " DOMAIN
        read -p "► Email SSL: " EMAIL
        CONFIG="/etc/nginx/sites-available/$DOMAIN"
        SECURE="location ~ /\.(?!well-known).* { deny all; return 404; }"
        
        if [ "$TYPE" == "1" ]; then
            read -p "Path: " ROOT; mkdir -p $ROOT
            BLOCK="server { listen 80; server_name $DOMAIN; root $ROOT; index index.html; $SECURE location / { try_files \$uri \$uri/ /index.html; } }"
        elif [ "$TYPE" == "2" ]; then
            read -p "Port: " PORT
            BLOCK="server { listen 80; server_name $DOMAIN; $SECURE location / { proxy_pass http://localhost:$PORT; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection 'upgrade'; proxy_set_header Host \$host; proxy_cache_bypass \$http_upgrade; } }"
        elif [ "$TYPE" == "3" ]; then
            read -p "Path: " ROOT; mkdir -p $ROOT
            BLOCK="server { listen 80; server_name $DOMAIN; root $ROOT; index index.php index.html; $SECURE location / { try_files \$uri \$uri/ /index.php?\$query_string; } location ~ \.php$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/run/php/php$PHP_V-fpm.sock; } }"
        else echo "Invalid."; continue; fi

        echo "$BLOCK" > $CONFIG; ln -s $CONFIG /etc/nginx/sites-enabled/ 2>/dev/null
        nginx -t
        if [ $? -eq 0 ]; then
            systemctl reload nginx; [ ! -z "$ROOT" ] && fix_perm $ROOT
            certbot --nginx --non-interactive --agree-tos -m $EMAIL -d $DOMAIN
            echo -e "${GREEN}Deploy Berhasil!${NC}"
        else rm $CONFIG; rm /etc/nginx/sites-enabled/$DOMAIN; echo "${RED}Gagal Config.${NC}"; fi
        read -p "Enter..."
    done
}

manage_web() {
    while true; do
        submenu_header "MANAGE WEBSITE (NGINX)"
        ls /etc/nginx/sites-available
        echo "--------------------------------"
        echo "1. Start Website"
        echo "2. Stop Website"
        echo "3. Delete Website (Full)"
        echo "4. Cek Log (Live)"
        echo "0. Kembali"
        read -p "► Pilih: " W
        
        case $W in
            0) return ;;
            1) read -p "Domain: " D; ln -s /etc/nginx/sites-available/$D /etc/nginx/sites-enabled/ 2>/dev/null; systemctl reload nginx; echo "Started." ;;
            2) read -p "Domain: " D; rm /etc/nginx/sites-enabled/$D 2>/dev/null; systemctl reload nginx; echo "Stopped." ;;
            3) read -p "Domain: " D; read -p "Yakin? (y/n): " Y; if [ "$Y" == "y" ]; then rm /etc/nginx/sites-enabled/$D 2>/dev/null; rm /etc/nginx/sites-available/$D; certbot delete --cert-name $D --non-interactive 2>/dev/null; echo "Deleted."; fi ;;
            4) echo "1. All Traffic | 2. All Errors | 3. Filter Domain"; read -p "Mode: " L
               echo -e "${YELLOW}(Ctrl+C untuk keluar)${NC}"
               if [ "$L" == "1" ]; then tail -f /var/log/nginx/access.log; 
               elif [ "$L" == "2" ]; then tail -f /var/log/nginx/error.log; 
               elif [ "$L" == "3" ]; then read -p "Domain: " D; tail -f /var/log/nginx/access.log | grep --line-buffered "$D"; fi ;;
        esac
        read -p "Enter..."
    done
}

manage_app() {
    while true; do
        submenu_header "MANAGE APP (PM2)"
        pm2 list
        echo "--------------------------------"
        echo "1. Stop App"
        echo "2. Restart App"
        echo "3. Delete App"
        echo "4. Cek Log ID"
        echo "5. Dashboard Monitor"
        echo "0. Kembali"
        read -p "► Pilih: " P
        
        case $P in
            0) return ;;
            1) read -p "ID App: " I; pm2 stop $I ;;
            2) read -p "ID App: " I; pm2 restart $I ;;
            3) read -p "ID App: " I; pm2 delete $I ;;
            4) read -p "ID App: " I; pm2 logs $I ;;
            5) pm2 monit ;;
        esac
        pm2 save
        read -p "Enter..."
    done
}

create_db() {
    submenu_header "DATABASE WIZARD"
    echo "1. Buat Database Baru"
    echo "0. Kembali"
    read -p "► Pilih: " O
    if [ "$O" == "0" ]; then return; fi
    
    read -p "Nama DB: " D; read -p "User DB: " U
    DB=$(echo "$D" | tr -dc 'a-zA-Z0-9_'); USER=$(echo "$U" | tr -dc 'a-zA-Z0-9_')
    PASS=$(openssl rand -base64 12); echo "Pass Generated: $PASS"
    read -p "Pakai pass ini? (y/n): " C
    if [ "$C" == "n" ]; then read -s -p "Pass Manual: " PASS; echo ""; fi
    mysql -e "CREATE DATABASE IF NOT EXISTS $DB;"
    mysql -e "CREATE USER IF NOT EXISTS '$USER'@'localhost' IDENTIFIED BY '$PASS';"
    mysql -e "GRANT ALL PRIVILEGES ON $DB.* TO '$USER'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    echo "Database Created."; read -p "Enter..."
}

backup_wizard() {
    while true; do
        submenu_header "BACKUP & RESTORE"
        echo "1. Backup Web & DB (Zip)"
        echo "2. Backup DB Only (.sql)"
        echo "0. Kembali"
        read -p "► Pilih: " B
        
        if [ "$B" == "0" ]; then return; fi
        
        if [ "$B" == "1" ]; then
            read -p "Domain: " DOM; ROOT=$(grep "root" /etc/nginx/sites-available/$DOM 2>/dev/null | awk '{print $2}' | tr -d ';')
            [ -z "$ROOT" ] && read -p "Path Manual: " ROOT
            read -p "DB Name (Optional): " DB
            FILE="backup_${DOM}_$(date +%F_%H%M).zip"; TMP="/tmp/dump.sql"
            CMD="zip -r \"$BACKUP_DIR/$FILE\" . -x \"node_modules/*\" \"vendor/*\" \"storage/*.log\""
            [ ! -z "$DB" ] && mysqldump $DB > $TMP 2>/dev/null && CMD="$CMD -j \"$TMP\""
            cd $ROOT && eval $CMD && rm -f $TMP
            echo "Saved: $BACKUP_DIR/$FILE"
        elif [ "$B" == "2" ]; then
            read -p "DB Name: " DB; mysqldump $DB > "$BACKUP_DIR/${DB}_$(date +%F).sql"
            echo "Done."
        fi
        read -p "Enter..."
    done
}

manage_swap() {
    submenu_header "SWAP MEMORY"
    echo "1. Set Swap Baru"
    echo "2. Hapus Swap"
    echo "0. Kembali"
    read -p "► Pilih: " S
    if [ "$S" == "0" ]; then return; fi
    if [ "$S" == "1" ]; then
        read -p "Ukuran (GB): " GB
        swapoff -a; rm -f /swapfile; fallocate -l ${GB}G /swapfile; chmod 600 /swapfile; mkswap /swapfile; swapon /swapfile
        cp /etc/fstab /etc/fstab.bak; grep -v swap /etc/fstab > /etc/fstab.tmp; mv /etc/fstab.tmp /etc/fstab
        echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
        echo "Swap Aktif."
    elif [ "$S" == "2" ]; then
        swapoff -a; rm -f /swapfile; grep -v swap /etc/fstab > /etc/fstab.tmp; mv /etc/fstab.tmp /etc/fstab
        echo "Swap Dihapus."
    fi
    read -p "Enter..."
}

cron_manager() {
    submenu_header "CRON JOB"
    echo "1. List Jobs"
    echo "2. Edit Manual"
    echo "3. Auto Laravel Schedule"
    echo "0. Kembali"
    read -p "► Pilih: " C
    if [ "$C" == "0" ]; then return; fi
    case $C in
        1) crontab -l ;;
        2) crontab -e ;;
        3) read -p "Path: " P
           if [ -d "$P" ]; then (crontab -l 2>/dev/null; echo "* * * * * cd $P && php artisan schedule:run >> /dev/null 2>&1") | crontab -; echo "Added."; else echo "404 Not Found"; fi ;;
    esac
    read -p "Enter..."
}

update_app_git() {
    submenu_header "GIT UPDATE"
    read -p "Domain/Path: " D
    ROOT=$(grep "root" /etc/nginx/sites-available/$D 2>/dev/null | awk '{print $2}' | tr -d ';')
    [ -z "$ROOT" ] && ROOT=$D
    if [ -d "$ROOT/.git" ]; then
        cd $ROOT && git pull; [ -f "package.json" ] && npm install; [ -f "composer.json" ] && composer install --no-dev
        fix_perm $ROOT
        echo "Updated."
    else echo "Bukan repo git."; fi
    read -p "Enter..."
}

update_tool() {
    echo "Downloading update..."
    curl -sL "$UPDATE_URL" -o /tmp/bd_latest
    if grep -q "#!/bin/bash" /tmp/bd_latest; then mv /tmp/bd_latest /usr/local/bin/bd; chmod +x /usr/local/bin/bd; exec bd; else echo "Failed."; fi
}

uninstall_script() {
    read -p "Hapus Script? (y/n): " Y
    if [ "$Y" == "y" ]; then rm /usr/local/bin/bd; echo "Bye."; exit; fi
}

# --- MAIN LOOP ---
while true; do
    show_header
    read -p " ► Select Option: " OPT
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
        *) echo "Invalid option."; sleep 1 ;;
    esac
done
EOF

chmod +x /usr/local/bin/bd
echo -e "${GREEN}UPDATE SELESAI.${NC}"
echo "Tampilan Boxed UI (BD-32) siap digunakan. Ketik: bd"
