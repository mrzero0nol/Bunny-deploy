#!/bin/bash
# ===============================================
#  BUNNY DEPLOY - PRECISION UI (BD-38)
#  Code: Fixed Alignment + Input Boxes
#  Features: Full Box UI, Secure Input, Smart Align
# ===============================================

# --- CONFIGURATION ---
DEFAULT_PHP="8.2"
DEFAULT_NODE="20"
# ---------------------

export DEBIAN_FRONTEND=noninteractive
APT_OPTS="-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# Cek Root
if [ "$EUID" -ne 0 ]; then echo "Harap jalankan sebagai root (sudo -i)"; exit; fi

echo "Memuat Interface BD-38..."

# 1. Basic Tools
if ! command -v zip &> /dev/null; then
    apt update -y; apt install -y $APT_OPTS curl git unzip zip build-essential ufw software-properties-common mariadb-server bc
fi

# 2. Service
systemctl start mariadb >/dev/null 2>&1
systemctl enable mariadb >/dev/null 2>&1

# 3. Base PHP/Nginx
if ! command -v nginx &> /dev/null; then
    add-apt-repository -y ppa:ondrej/php
    apt update -y
    apt install -y $APT_OPTS nginx certbot python3-certbot-nginx
    apt install -y $APT_OPTS php$DEFAULT_PHP php$DEFAULT_PHP-fpm php$DEFAULT_PHP-mysql php$DEFAULT_PHP-curl php$DEFAULT_PHP-xml php$DEFAULT_PHP-mbstring php$DEFAULT_PHP-zip php$DEFAULT_PHP-gd composer
fi

# 4. Base Node
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_${DEFAULT_NODE}.x | bash -
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
# 6. GENERATE SCRIPT 'bd' (BOX UI EDITION)
# ==========================================
cat << 'EOF' > /usr/local/bin/bd
#!/bin/bash
# COLORS
CYAN=$'\e[0;36m'; WHITE=$'\e[1;37m'; GREEN=$'\e[0;32m'; YELLOW=$'\e[1;33m'; RED=$'\e[0;31m'; NC=$'\e[0m'

PHP_V="8.2"
BACKUP_DIR="/root/backups"
UPDATE_URL="https://raw.githubusercontent.com/mrzero0nol/Bunny-deploy/refs/heads/main/bd-22.sh"

# --- UI DRAWING FUNCTIONS (BOX LOGIC) ---
# Total Width = 60 chars (termasuk border)
# Inner Width = 56 chars

draw_top() { echo -e "${CYAN}┌────────────────────────────────────────────────────────┐${NC}"; }
draw_mid() { echo -e "${CYAN}├────────────────────────────────────────────────────────┤${NC}"; }
draw_bot() { echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"; }
draw_div() { echo -e "${CYAN}├───────────────────────────┬────────────────────────────┤${NC}"; }

# Fungsi Divider dengan Text: ├───── JUDUL ─────┤
draw_sec() {
    local text="$1"
    local clean_text=$(echo -e "$text" | sed "s/\x1B\[[0-9;]*[a-zA-Z]//g")
    local len=${#clean_text}
    local total_len=56
    local dash_len=$(( (total_len - len - 2) / 2 )) # -2 spasi kiri kanan
    local right_fix=$(( total_len - len - 2 - dash_len ))
    
    # Generate dashes
    local dash_l=""; for ((i=0; i<dash_len; i++)); do dash_l+="─"; done
    local dash_r=""; for ((i=0; i<right_fix; i++)); do dash_r+="─"; done
    
    echo -e "${CYAN}├${dash_l} ${WHITE}${text} ${CYAN}${dash_r}┤${NC}"
}

print_center() {
    local text="$1"
    local clean_text=$(echo -e "$text" | sed "s/\x1B\[[0-9;]*[a-zA-Z]//g")
    local width=56
    local padding=$(( (width - ${#clean_text}) / 2 ))
    local r_padding=$(( width - padding - ${#clean_text} ))
    printf "${CYAN}│${WHITE}%*s%s%*s${CYAN}│\n${NC}" $padding "" "$text" $r_padding ""
}

print_row() {
    local left="$1"
    local right="$2"
    printf "${CYAN}│${NC} %-25s ${CYAN}│${NC} %-26s ${CYAN}│\n${NC}" "$left" "$right"
}

# Fungsi Input Box Baru
# Menampilkan kotak input terpisah di bawah menu
input_box() {
    local prompt_text="$1"
    local result_var="$2"
    
    echo -e "${CYAN}┌───────────────────────[ INPUT ]────────────────────────┐${NC}"
    # Menggunakan printf untuk prompt di dalam box (simulasi)
    # Kita baca input di baris yang sama agar terlihat di dalam
    printf "${CYAN}│${YELLOW} ► ${WHITE}%-51s${CYAN}│${NC}\n" "$prompt_text"
    echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"
    
    # Pindah kursor naik 2 baris, lalu geser ke kanan untuk typing area?
    # Agak berisiko di berbagai terminal. Kita pakai style "Prompt Line" di bawah box saja.
    # Atau style "Isi di dalam":
    
    # REVISI: Simple Input Box
    echo -ne "\033[1A" # Naik 1 baris (ke garis border bawah)
    echo -ne "\r${CYAN}│${YELLOW} ► ${NC}" # Overwrite awal baris
    read -p "" input_val
    echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"
    
    # Simpan hasil ke variabel global atau eval
    eval $result_var="\"$input_val\""
}

# Wrapper input sederhana untuk kompatibilitas menu
ask_opt() {
    echo -e "${CYAN}┌──────────────────────[ OPTION ]────────────────────────┐${NC}"
    echo -ne "${CYAN}│${YELLOW} ► Pilih Menu (0-9/u): ${NC}"
    read opt_val
    echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"
    OPT=$opt_val
}

get_sys_info() {
    RAM_USED=$(free -m | grep Mem | awk '{print $3}')
    RAM_TOTAL=$(free -m | grep Mem | awk '{print $2}')
    RAM_PERC=$((RAM_USED * 100 / RAM_TOTAL))
    
    SWAP_USED=$(free -m | grep Swap | awk '{print $3}')
    SWAP_TOTAL=$(free -m | grep Swap | awk '{print $2}')
    if [ "$SWAP_TOTAL" -eq 0 ] || [ -z "$SWAP_TOTAL" ]; then SWAP_INFO="Disabled"; else SWAP_PERC=$((SWAP_USED * 100 / SWAP_TOTAL)); SWAP_INFO="${SWAP_USED}/${SWAP_TOTAL}MB ($SWAP_PERC%)"; fi
    
    DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
    DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
    DISK_PERC=$(df -h / | awk 'NR==2 {print $5}')
    LOAD=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1 | xargs)
}

show_header() {
    get_sys_info
    clear
    draw_top
    # Hapus Emoji di sini untuk presisi garis
    print_center "${YELLOW}BUNNY DEPLOY - PRO MANAGER v38${NC}" 
    draw_div
    print_row "RAM : ${RAM_USED}/${RAM_TOTAL}MB ($RAM_PERC%)" "DISK: ${DISK_USED}/${DISK_TOTAL} ($DISK_PERC)"
    print_row "SWAP: ${SWAP_INFO}" "CPU : Load $LOAD"
    
    # Style Baru: Kotak Judul Kategori
    draw_sec "CORE FEATURES"
    print_row "1. Deploy Website"       "4. Manage App (PM2)"
    print_row "2. Manage Web (Nginx)"   "5. Database Wizard"
    print_row "3. Git Pull Update"      "6. Backup Data"
    
    draw_sec "UTILITIES"
    print_row "7. SWAP Manager"         "8. Cron Job"
    print_row "9. Update Tools"         "u. Uninstall"
    
    draw_sec "EXIT"
    print_center "${RED}0. KELUAR APLIKASI${NC}"
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
    submenu_header "SELECT PHP VERSION"
    echo -e "${CYAN}│${NC} 1) PHP 8.1                            ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC} 2) PHP 8.2 (Default)                  ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC} 3) PHP 8.3                            ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC} 0) Kembali                            ${CYAN}│${NC}"
    draw_bot
    input_box "Pilih Versi (0-3)" pv
    
    case $pv in
        0) return 1 ;;
        1) T_VER="8.1" ;;
        2) T_VER="8.2" ;;
        3) T_VER="8.3" ;;
        *) T_VER="8.2" ;;
    esac
    
    if ! command -v php-fpm$T_VER &> /dev/null; then
        echo -e "${RED}PHP $T_VER belum terinstall!${NC}"
        input_box "Install sekarang? (y/n)" ins
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

check_node_install() {
    submenu_header "SELECT NODE VERSION"
    echo -e "${CYAN}│${NC} 1) Node.js v18 (LTS)                  ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC} 2) Node.js v20 (LTS Default)          ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC} 3) Node.js v22 (Current)              ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC} 0) Kembali                            ${CYAN}│${NC}"
    draw_bot
    input_box "Pilih Versi (0-3)" nv
    
    case $nv in
        0) return 1 ;;
        1) N_VER="18" ;;
        2) N_VER="20" ;;
        3) N_VER="22" ;;
        *) N_VER="20" ;;
    esac

    CURRENT_NODE=$(node -v 2>/dev/null | cut -d'.' -f1 | tr -d 'v')
    if [ "$CURRENT_NODE" != "$N_VER" ]; then
        echo -e "${RED}Node v$N_VER belum aktif.${NC}"
        input_box "Switch ke v$N_VER? (y/n)" ins
        if [ "$ins" == "y" ]; then
            curl -fsSL https://deb.nodesource.com/setup_${N_VER}.x | bash -
            apt install -y nodejs
        else
            return 1
        fi
    fi
    return 0
}

deploy_web() {
    while true; do
        submenu_header "DEPLOY NEW WEBSITE"
        print_row "1. HTML Static" "2. Node.js Proxy"
        print_row "3. PHP (Laravel/CI)" "0. Kembali"
        draw_bot
        
        input_box "Pilih Tipe Website" TYPE
        if [ "$TYPE" == "0" ]; then return; fi
        
        if [ "$TYPE" == "3" ]; then
            check_php_install; [ $? -eq 1 ] && continue
        elif [ "$TYPE" == "2" ]; then
            check_node_install; [ $? -eq 1 ] && continue
        fi

        input_box "Masukkan Domain" DOMAIN
        input_box "Email untuk SSL" EMAIL
        
        CONFIG="/etc/nginx/sites-available/$DOMAIN"
        SEC_HEADERS='add_header X-Frame-Options "SAMEORIGIN"; add_header X-XSS-Protection "1; mode=block"; add_header X-Content-Type-Options "nosniff";'
        GZIP_CONF='gzip on; gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;'
        SECURE="location ~ /\.(?!well-known).* { deny all; return 404; }"
        
        # --- HTML DEPLOY ---
        if [ "$TYPE" == "1" ]; then
            ROOT="/var/www/$DOMAIN"
            input_box "Punya Git Repo? (y/n)" IS_GIT
            if [ "$IS_GIT" == "y" ]; then
                input_box "Link Git Repo" GIT_URL
                if [ ! -z "$GIT_URL" ]; then
                    rm -rf $ROOT; git clone $GIT_URL $ROOT
                fi
            else
                input_box "Path Manual (Enter for Default)" CUST_ROOT
                [ ! -z "$CUST_ROOT" ] && ROOT=$CUST_ROOT
                mkdir -p $ROOT
            fi
            BLOCK="server { listen 80; server_name $DOMAIN; root $ROOT; index index.html; $SEC_HEADERS $GZIP_CONF $SECURE location / { try_files \$uri \$uri/ /index.html; } }"

        # --- NODE DEPLOY ---
        elif [ "$TYPE" == "2" ]; then
            input_box "Port App (Contoh: 3000)" PORT
            input_box "Auto Clone Git & Install? (y/n)" AUTO_SETUP
            
            if [ "$AUTO_SETUP" == "y" ]; then
                APP_ROOT="/var/www/$DOMAIN"
                input_box "Link Git Repo" GIT_URL
                if [ ! -z "$GIT_URL" ]; then
                    git clone $GIT_URL $APP_ROOT
                    if [ -d "$APP_ROOT" ]; then
                        cd $APP_ROOT && npm install
                        input_box "File Utama (app.js/index.js)" START_FILE
                        [ ! -z "$START_FILE" ] && pm2 start $START_FILE --name "$DOMAIN" && pm2 save
                    fi
                fi
            fi
            BLOCK="server { listen 80; server_name $DOMAIN; $SEC_HEADERS $GZIP_CONF $SECURE location / { proxy_pass http://localhost:$PORT; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection 'upgrade'; proxy_set_header Host \$host; proxy_cache_bypass \$http_upgrade; } }"
        
        # --- PHP DEPLOY ---
        elif [ "$TYPE" == "3" ]; then
            ROOT="/var/www/$DOMAIN"
            input_box "Punya Git Repo? (y/n)" IS_GIT
            if [ "$IS_GIT" == "y" ]; then
                input_box "Link Git Repo" GIT_URL
                if [ ! -z "$GIT_URL" ]; then
                    rm -rf $ROOT; git clone $GIT_URL $ROOT
                    [ -f "$ROOT/composer.json" ] && cd $ROOT && composer install --no-dev
                    [ -d "$ROOT/public" ] && ROOT="$ROOT/public"
                    fix_perm "/var/www/$DOMAIN"
                fi
            else
                input_box "Path Manual (Enter for Default)" CUST_ROOT
                [ ! -z "$CUST_ROOT" ] && ROOT=$CUST_ROOT
                mkdir -p $ROOT
            fi
            BLOCK="server { listen 80; server_name $DOMAIN; root $ROOT; index index.php index.html; $SEC_HEADERS $GZIP_CONF $SECURE location / { try_files \$uri \$uri/ /index.php?\$query_string; } location ~ \.php$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/run/php/php$PHP_V-fpm.sock; } }"
        else continue; fi

        echo "$BLOCK" > $CONFIG; ln -s $CONFIG /etc/nginx/sites-enabled/ 2>/dev/null
        nginx -t
        if [ $? -eq 0 ]; then
            systemctl reload nginx
            certbot --nginx --non-interactive --agree-tos -m $EMAIL -d $DOMAIN
            echo -e "${GREEN}Deploy Berhasil!${NC}"
        else rm $CONFIG; rm /etc/nginx/sites-enabled/$DOMAIN; echo "${RED}Gagal Config.${NC}"; fi
        read -p "Press Enter..."
    done
}

manage_web() {
    while true; do
        submenu_header "MANAGE WEBSITE"
        ls /etc/nginx/sites-available
        draw_mid
        print_row "1. Start Web" "2. Stop Web"
        print_row "3. Delete Web" "4. Cek Log"
        print_center "0. Kembali"
        draw_bot
        input_box "Pilih Opsi" W
        case $W in
            0) return ;;
            1) input_box "Domain" D; ln -s /etc/nginx/sites-available/$D /etc/nginx/sites-enabled/ 2>/dev/null; systemctl reload nginx ;;
            2) input_box "Domain" D; rm /etc/nginx/sites-enabled/$D 2>/dev/null; systemctl reload nginx ;;
            3) input_box "Domain" D; input_box "Yakin Hapus? (y/n)" Y; if [ "$Y" == "y" ]; then rm /etc/nginx/sites-enabled/$D 2>/dev/null; rm /etc/nginx/sites-available/$D; certbot delete --cert-name $D --non-interactive 2>/dev/null; fi ;;
            4) input_box "1.Access | 2.Error" L; if [ "$L" == "1" ]; then tail -f /var/log/nginx/access.log; else tail -f /var/log/nginx/error.log; fi ;;
        esac
    done
}

manage_app() {
    while true; do
        submenu_header "MANAGE APP (PM2)"
        pm2 list
        draw_mid
        print_row "1. Stop App" "2. Restart App"
        print_row "3. Delete App" "4. Log ID"
        print_center "0. Kembali"
        draw_bot
        input_box "Pilih Opsi" P
        case $P in
            0) return ;;
            1) input_box "ID App" I; pm2 stop $I ;;
            2) input_box "ID App" I; pm2 restart $I ;;
            3) input_box "ID App" I; pm2 delete $I ;;
            4) input_box "ID App" I; pm2 logs $I ;;
        esac
        pm2 save
    done
}

create_db() {
    submenu_header "DATABASE WIZARD"
    print_center "1. Buat Database Baru"
    print_center "0. Kembali"
    draw_bot
    input_box "Pilih" O
    if [ "$O" == "0" ]; then return; fi
    input_box "Nama DB" D
    input_box "User DB" U
    DB=$(echo "$D" | tr -dc 'a-zA-Z0-9_'); USER=$(echo "$U" | tr -dc 'a-zA-Z0-9_')
    PASS=$(openssl rand -base64 12); echo " Pass: $PASS"
    input_box "Gunakan Pass ini? (y/n)" C
    [ "$C" == "n" ] && input_box "Pass Manual" PASS
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
        input_box "Pilih" B
        if [ "$B" == "0" ]; then return; fi
        if [ "$B" == "1" ]; then
            input_box "Domain" DOM
            ROOT=$(awk '/root/ && !/^[ \t]*#/ {print $2}' /etc/nginx/sites-available/$DOM 2>/dev/null | tr -d ';')
            [ -z "$ROOT" ] && input_box "Path Root" ROOT
            input_box "Nama DB (Optional)" DB
            FILE="backup_${DOM}_$(date +%F_%H%M).zip"; TMP="/tmp/dump.sql"
            CMD="zip -r \"$BACKUP_DIR/$FILE\" . -x \"node_modules/*\" \"vendor/*\" \"storage/*.log\""
            [ ! -z "$DB" ] && mysqldump $DB > $TMP 2>/dev/null && CMD="$CMD -j \"$TMP\""
            [ -d "$ROOT" ] && cd $ROOT && eval $CMD && rm -f $TMP && echo "Saved to $BACKUP_DIR"
        elif [ "$B" == "2" ]; then
            input_box "Nama DB" DB; mysqldump $DB > "$BACKUP_DIR/${DB}_$(date +%F).sql"; echo "Done."
        fi
        read -p "Enter..."
    done
}

manage_swap() {
    submenu_header "SWAP MANAGER"
    print_row "1. Set Swap" "2. Del Swap"
    print_center "0. Kembali"
    draw_bot
    input_box "Pilih" S
    if [ "$S" == "1" ]; then
        input_box "Ukuran (GB)" GB
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
    input_box "Pilih" C
    if [ "$C" == "0" ]; then return; fi
    case $C in
        1) crontab -l; read -p "Enter..." ;;
        2) crontab -e ;;
        3) input_box "Path Project" P; if [ -d "$P" ]; then (crontab -l 2>/dev/null; echo "* * * * * cd $P && php artisan schedule:run >> /dev/null 2>&1") | crontab -; else echo "404"; fi ;;
    esac
}

update_app_git() {
    submenu_header "GIT UPDATE"
    input_box "Domain" D
    ROOT=$(awk '/root/ && !/^[ \t]*#/ {print $2}' /etc/nginx/sites-available/$D 2>/dev/null | tr -d ';')
    [ -z "$ROOT" ] && ROOT=$D
    if [ -d "$ROOT/.git" ]; then
        cd $ROOT && git pull; [ -f "package.json" ] && npm install; [ -f "composer.json" ] && composer install --no-dev
        fix_perm $ROOT; echo "Updated."
    else echo "Not Git Repo."; fi
    read -p "Enter..."
}

update_tool() {
    echo "Checking updates..."
    curl -sL "$UPDATE_URL" -o /tmp/bd_latest
    if [ -s /tmp/bd_latest ] && grep -q "#!/bin/bash" /tmp/bd_latest; then 
        mv /tmp/bd_latest /usr/local/bin/bd; chmod +x /usr/local/bin/bd; exec bd
    else echo "Update Failed."; fi
    read -p "Enter..."
}

# --- MAIN LOOP ---
while true; do
    show_header
    ask_opt
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
        u) input_box "Uninstall? (y/n)" Y; [ "$Y" == "y" ] && rm /usr/local/bin/bd && exit ;;
        *) echo "Invalid."; sleep 1 ;;
    esac
done
EOF

chmod +x /usr/local/bin/bd
echo -e "${GREEN}UPDATE UI V38 SELESAI.${NC}"
echo "Jalankan 'bd' untuk melihat tampilan kotak baru."
