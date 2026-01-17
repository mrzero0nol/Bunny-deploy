#!/bin/bash
# ===============================================
#  BUNNY DEPLOY - PRECISION UI (BD-34)
#  Code: Fixed Width + printf Alignment
#  Features: Smart Install, Security Headers, Safe Update
# ===============================================

# --- CONFIGURATION ---
DEFAULT_PHP="8.2"
NODE_VER="20"
# ---------------------

export DEBIAN_FRONTEND=noninteractive
APT_OPTS="-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# Cek Root
if [ "$EUID" -ne 0 ]; then echo "Harap jalankan sebagai root (sudo -i)"; exit; fi

echo "Memuat Interface BD-34..."

# 1. Basic Tools
if ! command -v zip &> /dev/null; then
    apt update -y; apt install -y $APT_OPTS curl git unzip zip build-essential ufw software-properties-common mariadb-server bc
fi

# 2. Service
systemctl start mariadb >/dev/null 2>&1
systemctl enable mariadb >/dev/null 2>&1

# 3. Base PHP/Nginx (Install Default 8.2 first)
if ! command -v nginx &> /dev/null; then
    add-apt-repository -y ppa:ondrej/php
    apt update -y
    apt install -y $APT_OPTS nginx certbot python3-certbot-nginx
    apt install -y $APT_OPTS php$DEFAULT_PHP php$DEFAULT_PHP-fpm php$DEFAULT_PHP-mysql php$DEFAULT_PHP-curl php$DEFAULT_PHP-xml php$DEFAULT_PHP-mbstring php$DEFAULT_PHP-zip php$DEFAULT_PHP-gd composer
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
# 6. GENERATE SCRIPT 'bd' (PRECISION UI)
# ==========================================
cat << 'EOF' > /usr/local/bin/bd
#!/bin/bash
# COLORS
CYAN='\033[0;36m'; WHITE='\033[1;37m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

PHP_V="8.2" # Default
BACKUP_DIR="/root/backups"
UPDATE_URL="https://raw.githubusercontent.com/mrzero0nol/Bunny-deploy/refs/heads/main/bd-22.sh"

# --- UI DRAWING FUNCTIONS ---
draw_top() { echo -e "${CYAN}┌────────────────────────────────────────────────────────┐${NC}"; }
draw_mid() { echo -e "${CYAN}├────────────────────────────────────────────────────────┤${NC}"; }
draw_bot() { echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"; }
draw_div() { echo -e "${CYAN}├───────────────────────────┬────────────────────────────┤${NC}"; }

print_center() {
    local text="$1"
    local width=56
    local padding=$(( (width - ${#text}) / 2 ))
    printf "${CYAN}│${WHITE}%*s%s%*s${CYAN}│\n${NC}" $padding "" "$text" $(( width - padding - ${#text} )) ""
}

print_row() {
    local left="$1"
    local right="$2"
    printf "${CYAN}│${NC} %-25s ${CYAN}│${NC} %-26s ${CYAN}│\n${NC}" "$left" "$right"
}

get_sys_info() {
    RAM_USED=$(free -m | grep Mem | awk '{print $3}')
    RAM_TOTAL=$(free -m | grep Mem | awk '{print $2}')
    RAM_PERC=$((RAM_USED * 100 / RAM_TOTAL))
    
    SWAP_USED=$(free -m | grep Swap | awk '{print $3}')
    SWAP_TOTAL=$(free -m | grep Swap | awk '{print $2}')
    if [ "$SWAP_TOTAL" -eq 0 ] || [ -z "$SWAP_TOTAL" ]; then 
        SWAP_INFO="Disabled"
    else 
        SWAP_PERC=$((SWAP_USED * 100 / SWAP_TOTAL))
        SWAP_INFO="${SWAP_USED}/${SWAP_TOTAL}MB ($SWAP_PERC%)"
    fi
    
    DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
    DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
    DISK_PERC=$(df -h / | awk 'NR==2 {print $5}')
    LOAD=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1 | xargs)
}

show_header() {
    get_sys_info
    clear
    draw_top
    print_center "🐰 BUNNY DEPLOY - PRO MANAGER v34"
    draw_div
    print_row "RAM : ${RAM_USED}/${RAM_TOTAL}MB ($RAM_PERC%)" "DISK: ${DISK_USED}/${DISK_TOTAL} ($DISK_PERC)"
    print_row "SWAP: ${SWAP_INFO}" "CPU : Load $LOAD"
    draw_mid
    print_center "${YELLOW}CORE FEATURES${NC}"
    print_row "1. Deploy Website"       "4. Manage App (PM2)"
    print_row "2. Manage Web (Nginx)"   "5. Database Wizard"
    print_row "3. Git Pull Update"      "6. Backup Data"
    draw_mid
    print_center "${YELLOW}UTILITIES${NC}"
    print_row "7. SWAP Manager"         "8. Cron Job"
    print_row "9. Update Tools"         "u. Uninstall"
    draw_mid
    print_center "${RED}0. KELUAR (Exit)${NC}"
    draw_bot
}

submenu_header() {
    clear
    draw_top
    print_center "MENU: $1"
    draw_mid
}

# --- LOGIC FUNCTIONS ---
fix_perm() {
    echo "Fixing permission..."
    chown -R www-data:www-data $1
    find $1 -type f -exec chmod 644 {} \;
    find $1 -type d -exec chmod 755 {} \;
    if [ -d "$1/storage" ]; then chmod -R 775 "$1/storage"; fi
}

check_php_install() {
    echo -e "${YELLOW}Pilih Versi PHP:${NC}"
    echo "1) PHP 8.1"
    echo "2) PHP 8.2 (Default)"
    echo "3) PHP 8.3"
    read -p " ► Pilihan (1-3): " pv
    case $pv in
        1) T_VER="8.1" ;;
        2) T_VER="8.2" ;;
        3) T_VER="8.3" ;;
        *) T_VER="8.2" ;;
    esac
    
    if ! command -v php-fpm$T_VER &> /dev/null; then
        echo -e "${RED}PHP $T_VER belum terinstall!${NC}"
        read -p " ► Install sekarang? (y/n): " ins
        if [ "$ins" == "y" ]; then
            apt update -y
            apt install -y php$T_VER php$T_VER-fpm php$T_VER-mysql php$T_VER-curl php$T_VER-xml php$T_VER-mbstring php$T_VER-zip php$T_VER-gd
        else
            return 1
        fi
    fi
    PHP_V=$T_VER
    return 0
}

deploy_web() {
    while true; do
        submenu_header "DEPLOY NEW WEBSITE"
        print_row "1. HTML Static" "2. Node.js Proxy"
        print_row "3. PHP (Laravel/CI)" "0. Kembali"
        draw_bot
        read -p " ► Pilih: " TYPE
        if [ "$TYPE" == "0" ]; then return; fi
        
        # PHP Version Check
        if [ "$TYPE" == "3" ]; then
            check_php_install
            if [ $? -eq 1 ]; then continue; fi
        fi

        read -p " ► Domain: " DOMAIN
        read -p " ► Email SSL: " EMAIL
        CONFIG="/etc/nginx/sites-available/$DOMAIN"
        
        # SECURITY & PERFORMANCE BLOCK
        SEC_HEADERS='add_header X-Frame-Options "SAMEORIGIN"; add_header X-XSS-Protection "1; mode=block"; add_header X-Content-Type-Options "nosniff";'
        GZIP_CONF='gzip on; gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;'
        SECURE="location ~ /\.(?!well-known).* { deny all; return 404; }"
        
        if [ "$TYPE" == "1" ]; then
            read -p " Path: " ROOT; mkdir -p $ROOT
            BLOCK="server { listen 80; server_name $DOMAIN; root $ROOT; index index.html; $SEC_HEADERS $GZIP_CONF $SECURE location / { try_files \$uri \$uri/ /index.html; } }"
        elif [ "$TYPE" == "2" ]; then
            read -p " Port App (Contoh 3000): " PORT
            BLOCK="server { listen 80; server_name $DOMAIN; $SEC_HEADERS $GZIP_CONF $SECURE location / { proxy_pass http://localhost:$PORT; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection 'upgrade'; proxy_set_header Host \$host; proxy_cache_bypass \$http_upgrade; } }"
        elif [ "$TYPE" == "3" ]; then
            read -p " Path: " ROOT; mkdir -p $ROOT
            BLOCK="server { listen 80; server_name $DOMAIN; root $ROOT; index index.php index.html; $SEC_HEADERS $GZIP_CONF $SECURE location / { try_files \$uri \$uri/ /index.php?\$query_string; } location ~ \.php$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/run/php/php$PHP_V-fpm.sock; } }"
        else continue; fi

        echo "$BLOCK" > $CONFIG; ln -s $CONFIG /etc/nginx/sites-enabled/ 2>/dev/null
        nginx -t
        if [ $? -eq 0 ]; then
            systemctl reload nginx; [ ! -z "$ROOT" ] && fix_perm $ROOT
            certbot --nginx --non-interactive --agree-tos -m $EMAIL -d $DOMAIN
            echo -e "${GREEN}Deploy Berhasil! (Secured)${NC}"
        else rm $CONFIG; rm /etc/nginx/sites-enabled/$DOMAIN; echo "${RED}Gagal Config.${NC}"; fi
        read -p "Enter..."
    done
}

manage_web() {
    while true; do
        submenu_header "MANAGE WEBSITE"
        ls /etc/nginx/sites-available
        draw_mid
        print_row "1. Start Web" "2. Stop Web"
        print_row "3. Delete Web" "4. Cek Log (Live)"
        print_center "0. Kembali"
        draw_bot
        read -p " ► Pilih: " W
        case $W in
            0) return ;;
            1) read -p " Domain: " D; ln -s /etc/nginx/sites-available/$D /etc/nginx/sites-enabled/ 2>/dev/null; systemctl reload nginx; echo "Started." ;;
            2) read -p " Domain: " D; rm /etc/nginx/sites-enabled/$D 2>/dev/null; systemctl reload nginx; echo "Stopped." ;;
            3) read -p " Domain: " D; read -p " Yakin? (y/n): " Y; if [ "$Y" == "y" ]; then rm /etc/nginx/sites-enabled/$D 2>/dev/null; rm /etc/nginx/sites-available/$D; certbot delete --cert-name $D --non-interactive 2>/dev/null; echo "Deleted."; fi ;;
            4) echo "1. Access Log | 2. Error Log"; read -p " Mode: " L
               if [ "$L" == "1" ]; then tail -f /var/log/nginx/access.log; else tail -f /var/log/nginx/error.log; fi ;;
        esac
        read -p "Enter..."
    done
}

manage_app() {
    while true; do
        submenu_header "MANAGE APP (PM2)"
        pm2 list
        draw_mid
        print_row "1. Stop App" "2. Restart App"
        print_row "3. Delete App" "4. Log ID"
        print_row "5. Dashboard" "0. Kembali"
        draw_bot
        read -p " ► Pilih: " P
        case $P in
            0) return ;;
            1) read -p " ID: " I; pm2 stop $I ;;
            2) read -p " ID: " I; pm2 restart $I ;;
            3) read -p " ID: " I; pm2 delete $I ;;
            4) read -p " ID: " I; pm2 logs $I ;;
            5) pm2 monit ;;
        esac
        pm2 save
        read -p "Enter..."
    done
}

create_db() {
    submenu_header "DATABASE WIZARD"
    print_center "1. Buat Database Baru"
    print_center "0. Kembali"
    draw_bot
    read -p " ► Pilih: " O
    if [ "$O" == "0" ]; then return; fi
    read -p " Nama DB: " D; read -p " User DB: " U
    DB=$(echo "$D" | tr -dc 'a-zA-Z0-9_'); USER=$(echo "$U" | tr -dc 'a-zA-Z0-9_')
    PASS=$(openssl rand -base64 12); echo " Pass: $PASS"
    read -p " Pakai? (y/n): " C; [ "$C" == "n" ] && read -s -p " Pass Manual: " PASS
    mysql -e "CREATE DATABASE IF NOT EXISTS $DB;"
    mysql -e "CREATE USER IF NOT EXISTS '$USER'@'localhost' IDENTIFIED BY '$PASS';"
    mysql -e "GRANT ALL PRIVILEGES ON $DB.* TO '$USER'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    echo "Done."; read -p "Enter..."
}

backup_wizard() {
    while true; do
        submenu_header "BACKUP SYSTEM"
        print_row "1. Web+DB (Zip)" "2. DB Only"
        print_center "0. Kembali"
        draw_bot
        read -p " ► Pilih: " B
        if [ "$B" == "0" ]; then return; fi
        if [ "$B" == "1" ]; then
            read -p " Domain: " DOM
            # FIX: Menggunakan AWK agar tidak salah baca config yang dikomentari
            ROOT=$(awk '/root/ && !/^[ \t]*#/ {print $2}' /etc/nginx/sites-available/$DOM 2>/dev/null | tr -d ';')
            
            [ -z "$ROOT" ] && read -p " Path: " ROOT
            read -p " DB Name (Opt): " DB
            FILE="backup_${DOM}_$(date +%F_%H%M).zip"; TMP="/tmp/dump.sql"
            CMD="zip -r \"$BACKUP_DIR/$FILE\" . -x \"node_modules/*\" \"vendor/*\" \"storage/*.log\""
            [ ! -z "$DB" ] && mysqldump $DB > $TMP 2>/dev/null && CMD="$CMD -j \"$TMP\""
            
            if [ -d "$ROOT" ]; then
                cd $ROOT && eval $CMD && rm -f $TMP
                echo "Saved: $BACKUP_DIR/$FILE"
            else
                echo "Path Root tidak ditemukan."
            fi
        elif [ "$B" == "2" ]; then
            read -p " DB Name: " DB; mysqldump $DB > "$BACKUP_DIR/${DB}_$(date +%F).sql"; echo "Done."
        fi
        read -p "Enter..."
    done
}

manage_swap() {
    submenu_header "SWAP MANAGER"
    print_row "1. Set Swap" "2. Del Swap"
    print_center "0. Kembali"
    draw_bot
    read -p " ► Pilih: " S
    if [ "$S" == "1" ]; then
        read -p " GB: " GB
        swapoff -a; rm -f /swapfile; fallocate -l ${GB}G /swapfile; chmod 600 /swapfile; mkswap /swapfile; swapon /swapfile
        cp /etc/fstab /etc/fstab.bak; grep -v swap /etc/fstab > /etc/fstab.tmp; mv /etc/fstab.tmp /etc/fstab
        echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
    elif [ "$S" == "2" ]; then
        swapoff -a; rm -f /swapfile; grep -v swap /etc/fstab > /etc/fstab.tmp; mv /etc/fstab.tmp /etc/fstab
    fi
}

cron_manager() {
    submenu_header "CRON JOB"
    print_row "1. List Jobs" "2. Edit Manual"
    print_row "3. Laravel Auto" "0. Kembali"
    draw_bot
    read -p " ► Pilih: " C
    if [ "$C" == "0" ]; then return; fi
    case $C in
        1) crontab -l ;;
        2) crontab -e ;;
        3) read -p " Path: " P; if [ -d "$P" ]; then (crontab -l 2>/dev/null; echo "* * * * * cd $P && php artisan schedule:run >> /dev/null 2>&1") | crontab -; else echo "404"; fi ;;
    esac
    read -p "Enter..."
}

update_app_git() {
    submenu_header "GIT UPDATE"
    read -p " Domain: " D
    # FIX: Logic pencarian root yang sama dengan backup
    ROOT=$(awk '/root/ && !/^[ \t]*#/ {print $2}' /etc/nginx/sites-available/$D 2>/dev/null | tr -d ';')
    [ -z "$ROOT" ] && ROOT=$D
    if [ -d "$ROOT/.git" ]; then
        cd $ROOT && git pull; [ -f "package.json" ] && npm install; [ -f "composer.json" ] && composer install --no-dev
        fix_perm $ROOT; echo "Updated."
    else echo "Not Git Repo."; fi
    read -p "Enter..."
}

update_tool() {
    echo "Checking for updates..."
    curl -sL "$UPDATE_URL" -o /tmp/bd_latest
    # Sanity Check: Pastikan file tidak kosong dan adalah bash script
    if [ -s /tmp/bd_latest ] && grep -q "#!/bin/bash" /tmp/bd_latest; then 
        mv /tmp/bd_latest /usr/local/bin/bd
        chmod +x /usr/local/bin/bd
        echo -e "${GREEN}Update Success! Restarting...${NC}"
        sleep 1
        exec bd
    else 
        echo -e "${RED}Update Failed/Corrupt File. Aborting.${NC}"
    fi
    read -p "Enter..."
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
        u) read -p "Del? (y/n): " Y; [ "$Y" == "y" ] && rm /usr/local/bin/bd && exit ;;
        *) echo "Invalid."; sleep 1 ;;
    esac
done
EOF

chmod +x /usr/local/bin/bd
echo -e "${GREEN}UPDATE SELESAI.${NC}"
echo "Ketik 'bd' untuk menjalankan Bunny Deploy v34 (Secure)."
