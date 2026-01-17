#!/bin/bash
# ===============================================
#  BUNNY DEPLOY - REFINED LAYOUT (BD-53)
#  Fitur: Horizontal Ordering + Universal Back Button
#  Logic: Organized + Config + Fail2Ban
# ===============================================

# --- LOAD CONFIGURATION ---
CONFIG_FILE="/root/.bd_config"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "UPLOAD_LIMIT=\"64M\"" > "$CONFIG_FILE"
    echo "DEFAULT_PHP=\"8.2\"" >> "$CONFIG_FILE"
    echo "DEFAULT_NODE=\"20\"" >> "$CONFIG_FILE"
fi
source "$CONFIG_FILE"
# ---------------------

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C

# Cek Root
if [ "$EUID" -ne 0 ]; then echo "Harap jalankan sebagai root (sudo -i)"; exit; fi

# 1. Basic Tools
if ! command -v zip &> /dev/null; then
    apt update -y; apt install -y curl git unzip zip build-essential ufw software-properties-common mariadb-server bc jq
fi

# 2. Service
if ! systemctl is-active --quiet mariadb; then systemctl start mariadb; systemctl enable mariadb; fi

# 3. Base Install
if ! command -v nginx &> /dev/null; then
    add-apt-repository -y ppa:ondrej/php
    apt update -y
    apt install -y nginx certbot python3-certbot-nginx
    apt install -y php$DEFAULT_PHP php$DEFAULT_PHP-fpm php$DEFAULT_PHP-mysql php$DEFAULT_PHP-curl php$DEFAULT_PHP-xml php$DEFAULT_PHP-mbstring php$DEFAULT_PHP-zip php$DEFAULT_PHP-gd composer
fi
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_${DEFAULT_NODE}.x | bash -
    apt install -y nodejs
fi
if ! command -v pm2 &> /dev/null; then
    npm install -g pm2 yarn
fi

# 4. Security (Fail2Ban)
if ! command -v fail2ban-client &> /dev/null; then
    apt install -y fail2ban; cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    systemctl restart fail2ban; systemctl enable fail2ban
fi

# ==========================================
# 6. GENERATE SCRIPT 'bd'
# ==========================================
cat << 'EOF' > /usr/local/bin/bd
#!/bin/bash
# COLORS
CYAN=$'\e[0;36m'; WHITE=$'\e[1;37m'; GREEN=$'\e[0;32m'; YELLOW=$'\e[1;33m'; RED=$'\e[0;31m'; NC=$'\e[0m'

CONFIG_FILE="/root/.bd_config"
source "$CONFIG_FILE" 2>/dev/null || UPLOAD_LIMIT="64M"

BACKUP_DIR="/root/backups"
UPDATE_URL="https://raw.githubusercontent.com/mrzero0nol/Bunny-deploy/refs/heads/main/bd-22.sh"

# --- HELPER: PATH FINDER ---
get_site_root() {
    local dom=$1
    local path=$(awk '/root/ && !/^[ \t]*#/ {print $2}' /etc/nginx/sites-available/$dom 2>/dev/null | tr -d ';')
    echo "$path"
}

# --- UI DRAWING ---
get_width() {
    TERM_W=$(tput cols)
    [ -z "$TERM_W" ] && TERM_W=80
    BOX_W=$((TERM_W - 4))
    if [ "$BOX_W" -gt 55 ]; then BOX_W=55; fi
}

draw_line() {
    local type=$1 
    local line=""
    for ((i=0; i<BOX_W; i++)); do line+="─"; done
    if [ "$type" == "1" ]; then echo -e "${CYAN}┌${line}┐${NC}";
    elif [ "$type" == "2" ]; then echo -e "${CYAN}├${line}┤${NC}";
    elif [ "$type" == "3" ]; then echo -e "${CYAN}└${line}┘${NC}"; fi
}

box_center() {
    local text="$1"
    local color="$2"
    local clean_text=$(echo -e "$text" | sed "s/\x1B\[[0-9;]*[a-zA-Z]//g")
    local len=${#clean_text}
    local space_total=$((BOX_W - len))
    [ "$space_total" -lt 0 ] && space_total=0
    local pad_l=$((space_total / 2))
    local pad_r=$((space_total - pad_l))
    local sp_l=""; for ((i=0; i<pad_l; i++)); do sp_l+=" "; done
    local sp_r=""; for ((i=0; i<pad_r; i++)); do sp_r+=" "; done
    echo -e "${CYAN}│${NC}${sp_l}${color}${text}${NC}${sp_r}${CYAN}│${NC}"
}

box_row() {
    local l_txt="$1"
    local r_txt="$2"
    local clean_l=$(echo -e "$l_txt" | sed "s/\x1B\[[0-9;]*[a-zA-Z]//g")
    local clean_r=$(echo -e "$r_txt" | sed "s/\x1B\[[0-9;]*[a-zA-Z]//g")
    local len_l=${#clean_l}
    local len_r=${#clean_r}
    local gap=$((BOX_W - len_l - len_r - 2))
    local sp=""; for ((i=0; i<gap; i++)); do sp+=" "; done
    if [ "$gap" -lt 1 ]; then
        echo -e "${CYAN}│${NC} ${l_txt}"
        echo -e "${CYAN}│${NC} ${r_txt}"
    else
        echo -e "${CYAN}│${NC} ${l_txt}${sp}${r_txt} ${CYAN}│${NC}"
    fi
}

box_input() {
    local label="$1"
    local var_name="$2"
    echo -e "${CYAN}┌─ [ ${YELLOW}${label}${CYAN} ]${NC}"
    echo -ne "${CYAN}└─► ${NC}"
    read input_val
    eval $var_name="\"$input_val\""
}

get_sys_info() {
    RAM=$(free -m | grep Mem | awk '{print $3"/"$2"MB"}')
    DISK=$(df -h / | awk 'NR==2 {print $3"/"$2}')
}

# --- MENU UTAMA (Layout Horizontal Konsisten) ---
show_header() {
    get_width
    get_sys_info
    clear
    draw_line 1
    box_center "BUNNY DEPLOY v53 (Refined)" "$WHITE"
    draw_line 2
    box_row "RAM: $RAM" "DISK: $DISK"
    
    draw_line 2
    box_center "--- MAIN MENU ---" "$YELLOW"
    # Urutan Horizontal: 1 Kiri, 2 Kanan, dst.
    box_row "1. Deploy Wizard"  "2. Manage Web"
    box_row "3. App Manager"    "4. File Manager"
    box_row "5. Database"       "6. Backup"
    
    draw_line 2
    box_center "--- UTILITIES ---" "$YELLOW"
    box_row "7. Cron Job"       "8. Upload Limit"
    box_row "9. Update Tool"    "u. Uninstall"
    
    draw_line 2
    box_center "0. KELUAR (EXIT)" "$RED"
    draw_line 3
}

submenu_header() {
    get_width
    clear
    draw_line 1
    box_center "MENU: $1" "$YELLOW"
    draw_line 2
}

# --- HELPER FUNCTIONS (With Return Option) ---
save_config() {
    echo "UPLOAD_LIMIT=\"$UPLOAD_LIMIT\"" > "$CONFIG_FILE"
    echo "DEFAULT_PHP=\"8.2\"" >> "$CONFIG_FILE"
    echo "DEFAULT_NODE=\"20\"" >> "$CONFIG_FILE"
}

set_limit() {
    while true; do
        submenu_header "SET UPLOAD LIMIT"
        box_center "Current: $UPLOAD_LIMIT" "$WHITE"
        draw_line 2
        box_row "1. Set 10MB" "2. Set 64MB"
        box_row "3. Set 128MB" "4. Set 512MB"
        box_row "5. Set 1GB"   "6. Custom"
        box_center "0. Kembali" "$RED"
        draw_line 3
        
        box_input "Pilih" L
        case $L in
            0) return ;;
            1) UPLOAD_LIMIT="10M";; 2) UPLOAD_LIMIT="64M";; 3) UPLOAD_LIMIT="128M";; 4) UPLOAD_LIMIT="512M";; 5) UPLOAD_LIMIT="1G";;
            6) box_input "Input Manual (e.g 100M)" UPLOAD_LIMIT ;;
        esac
        
        if [ "$L" != "0" ]; then
            save_config
            echo -e "${GREEN}Sukses! Limit diubah ke $UPLOAD_LIMIT${NC}"
            echo "Akan berlaku pada deploy berikutnya."
            read -p "Enter..."
            return
        fi
    done
}

fix_perm() {
    echo "Fixing permission..."
    if [ -d "$1" ]; then
        chown -R www-data:www-data $1
        find $1 -type f -exec chmod 644 {} \;
        find $1 -type d -exec chmod 755 {} \;
        if [ -d "$1/storage" ]; then chmod -R 775 "$1/storage"; fi
    fi
}

# PHP Selector dengan opsi Kembali
check_php() {
    echo -e "${YELLOW}[ Pilih Versi PHP ]${NC}"
    echo "1. PHP 8.1"
    echo "2. PHP 8.2 (Default)"
    echo "3. PHP 8.3"
    echo "0. Batal/Kembali"
    box_input "Pilih (0-3)" pv
    
    if [ "$pv" == "0" ]; then return 1; fi # Return error code 1 jika batal
    
    case $pv in 1) V="8.1";; 2) V="8.2";; 3) V="8.3";; *) V="8.2";; esac
    
    if ! command -v php-fpm$V &> /dev/null; then
        echo "Menginstall PHP $V..."
        apt update -y; apt install -y php$V php$V-fpm php$V-mysql php$V-curl php$V-xml php$V-mbstring php$V-zip php$V-gd
    fi
    PHP_V=$V
    return 0
}

# Node Selector dengan opsi Kembali
check_node() {
    echo -e "${YELLOW}[ Pilih Versi Node.js ]${NC}"
    echo "1. v18 (LTS)"
    echo "2. v20 (Default)"
    echo "3. v22 (Latest)"
    echo "0. Batal/Kembali"
    box_input "Pilih (0-3)" nv
    
    if [ "$nv" == "0" ]; then return 1; fi

    case $nv in 1) V="18";; 2) V="20";; 3) V="22";; *) V="20";; esac
    
    CURR=$(node -v 2>/dev/null | cut -d'.' -f1 | tr -d 'v')
    if [ "$CURR" != "$V" ]; then
        echo "Menginstall Node v$V..."
        curl -fsSL https://deb.nodesource.com/setup_${V}.x | bash -; apt install -y nodejs
    fi
    return 0
}

open_file_manager() {
    if ! command -v mc &> /dev/null || ! command -v micro &> /dev/null; then apt install -y mc micro; fi
    mkdir -p ~/.config/mc; CONFIG_FILE=~/.config/mc/ini
    grep -q "use_internal_edit" "$CONFIG_FILE" && sed -i 's/^use_internal_edit=.*/use_internal_edit=0/' "$CONFIG_FILE" || echo -e "[Midnight-Commander]\nuse_internal_edit=0" >> "$CONFIG_FILE"
    export EDITOR=micro; [ -d "/var/www" ] && mc /var/www || mc
}

cron_manager() {
    submenu_header "CRON JOB MANAGER"
    box_row "1. List Jobs" "2. Edit Manual"
    box_row "3. Laravel Auto" "0. Kembali"
    draw_line 3
    box_input "Pilih Menu" C
    case $C in
        1) crontab -l; read -p "Enter..." ;;
        2) crontab -e ;;
        3) box_input "Path Project" P; (crontab -l 2>/dev/null; echo "* * * * * cd $P && php artisan schedule:run >> /dev/null 2>&1") | crontab -; echo "Done."; read -p "Enter..." ;;
    esac
}

deploy_web() {
    while true; do
        submenu_header "DEPLOY WIZARD"
        # Layout Horizontal
        box_row "1. HTML Static" "2. Node.js App"
        box_row "3. PHP Web"     "0. Kembali"
        draw_line 3
        
        box_input "Pilih Tipe" TYPE
        if [ "$TYPE" == "0" ]; then return; fi
        
        # Cek cancel dari sub-menu
        if [ "$TYPE" == "3" ]; then check_php; if [ $? -eq 1 ]; then continue; fi; fi
        if [ "$TYPE" == "2" ]; then check_node; if [ $? -eq 1 ]; then continue; fi; fi

        box_input "Domain" DOMAIN
        box_input "Email SSL" EMAIL
        
        ROOT="/var/www/$DOMAIN"
        CONFIG="/etc/nginx/sites-available/$DOMAIN"
        
        # Security & Config
        DENY_HIDDEN="location ~ /\.(?!well-known).* { deny all; return 404; }"
        NGINX_OPTS="client_max_body_size ${UPLOAD_LIMIT}; fastcgi_read_timeout 300;"
        SEC_H="add_header X-Frame-Options \"SAMEORIGIN\"; add_header X-XSS-Protection \"1; mode=block\"; add_header X-Content-Type-Options \"nosniff\";"
        HIDE_VER="server_tokens off;"

        if [ "$TYPE" == "1" ]; then
            box_input "Git URL (Enter=Skip)" GIT
            if [ ! -z "$GIT" ]; then rm -rf $ROOT; git clone $GIT $ROOT; else mkdir -p $ROOT; fi
            BLOCK="server { listen 80; server_name $DOMAIN; root $ROOT; index index.html; $HIDE_VER $NGINX_OPTS $SEC_H $DENY_HIDDEN location / { try_files \$uri \$uri/ /index.html; } }"
        
        elif [ "$TYPE" == "2" ]; then
            box_input "Port App (e.g 3000)" PORT
            box_input "Git URL" GIT
            if [ ! -z "$GIT" ]; then
                git clone $GIT $ROOT; cd $ROOT && npm install
                box_input "File Start (app.js)" START
                pm2 start $START --name "$DOMAIN" && pm2 save
            fi
            BLOCK="server { listen 80; server_name $DOMAIN; $HIDE_VER $NGINX_OPTS $SEC_H $DENY_HIDDEN location / { proxy_pass http://localhost:$PORT; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection 'upgrade'; proxy_set_header Host \$host; proxy_cache_bypass \$http_upgrade; } }"
        
        elif [ "$TYPE" == "3" ]; then
            box_input "Git URL" GIT
            if [ ! -z "$GIT" ]; then 
                rm -rf $ROOT; git clone $GIT $ROOT
                [ -f "$ROOT/composer.json" ] && cd $ROOT && composer install --no-dev
                [ -d "$ROOT/public" ] && ROOT="$ROOT/public"
                fix_perm "/var/www/$DOMAIN"
            else mkdir -p $ROOT; fi
            BLOCK="server { listen 80; server_name $DOMAIN; root $ROOT; index index.php index.html; $HIDE_VER $NGINX_OPTS $SEC_H $DENY_HIDDEN location / { try_files \$uri \$uri/ /index.php?\$query_string; } location ~ \.php$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/run/php/php$PHP_V-fpm.sock; } }"
        fi

        echo "$BLOCK" > $CONFIG; ln -s $CONFIG /etc/nginx/sites-enabled/ 2>/dev/null; nginx -t
        if [ $? -eq 0 ]; then systemctl reload nginx; certbot --nginx -n -m $EMAIL -d $DOMAIN --agree-tos; echo -e "${GREEN}Deploy Berhasil!${NC}"; else echo -e "${RED}Error Config${NC}"; fi
        read -p "Enter..."
    done
}

update_web_source() {
    box_input "Domain Website (0=Batal)" D
    if [ "$D" == "0" ]; then return; fi
    
    ROOT=$(get_site_root "$D")
    if [ -d "$ROOT/.git" ]; then
        cd $ROOT && git pull
        if [ -f "composer.json" ]; then
            composer install --no-dev; fix_perm $ROOT; systemctl reload php8.2-fpm 2>/dev/null
            echo -e "${GREEN}PHP Web Updated.${NC}"
        elif [ -f "package.json" ]; then
            echo -e "${YELLOW}Ini Node.js App. Gunakan App Manager untuk restart.${NC}"
        else
            fix_perm $ROOT
            echo -e "${GREEN}Static Web Updated.${NC}"
        fi
    else
        echo -e "${RED}Bukan folder Git.${NC}"
    fi
}

manage_web() {
    while true; do
        submenu_header "MANAGE WEBSITE"
        box_row "DOMAIN" "TYPE & STATUS"
        draw_line 2
        
        for file in /etc/nginx/sites-available/*; do
            [ -e "$file" ] || continue
            domain=$(basename "$file")
            if [ "$domain" == "default" ]; then continue; fi
            
            if grep -q "proxy_pass" "$file"; then TYPE="${CYAN}[NODE]${NC}";
            else TYPE="${YELLOW}[WEB]${NC}"; fi
            
            if [ -L "/etc/nginx/sites-enabled/$domain" ]; then STATUS="${GREEN}[ON]${NC}"; else STATUS="${RED}[OFF]${NC}"; fi
            box_row "$domain" "$TYPE $STATUS"
        done
        
        draw_line 2
        # Layout Horizontal Konsisten
        box_row "1. Start Web"  "2. Stop Web"
        box_row "3. Restart Web" "4. Delete Web"
        box_row "5. View Logs"   "6. UPDATE GIT"
        box_center "0. Kembali" "$RED"
        draw_line 3
        
        box_input "Pilih" W
        case $W in
            0) return ;;
            1) box_input "Domain" D; ln -s /etc/nginx/sites-available/$D /etc/nginx/sites-enabled/ 2>/dev/null; systemctl reload nginx; echo -e "${GREEN}Running.${NC}" ;;
            2) box_input "Domain" D; rm /etc/nginx/sites-enabled/$D 2>/dev/null; systemctl reload nginx; echo -e "${RED}Stopped.${NC}" ;;
            3) box_input "Domain" D; nginx -t && systemctl reload nginx; echo -e "${GREEN}Restarted.${NC}" ;;
            4) box_input "Domain" D; box_input "Hapus? (y/n)" Y; [ "$Y" == "y" ] && rm /etc/nginx/sites-enabled/$D 2>/dev/null && rm /etc/nginx/sites-available/$D && certbot delete --cert-name $D -n ;;
            5) box_input "1.Acc 2.Err" L; if [ "$L" == "1" ]; then tail -f /var/log/nginx/access.log; else tail -f /var/log/nginx/error.log; fi ;;
            6) update_web_source ;;
        esac
        read -p "Enter..."
    done
}

update_app_source() {
    box_input "ID PM2 (0=Batal)" ID
    if [ "$ID" == "0" ]; then return; fi
    
    PATH_APP=$(pm2 describe $ID | grep "script path" | awk '{print $4}' | xargs dirname)
    if [ -d "$PATH_APP/.git" ]; then
        echo -e "${YELLOW}Updating...${NC}"
        cd $PATH_APP && git pull && npm install
        pm2 restart $ID
        echo -e "${GREEN}Updated!${NC}"
    else
        echo -e "${RED}Bukan Git Repo.${NC}"
    fi
}

manage_app() {
    while true; do
        submenu_header "APP MANAGER (NODE/PYTHON)"
        pm2 list
        draw_line 2
        # Layout Horizontal
        box_row "1. Stop App"   "2. Restart App"
        box_row "3. Delete App" "4. View Logs"
        box_row "5. UPDATE GIT" "0. Kembali"
        draw_line 3
        box_input "Pilih" P
        case $P in
            0) return ;; 
            1) box_input "ID" I; pm2 stop $I ;; 
            2) box_input "ID" I; pm2 restart $I ;; 
            3) box_input "ID" I; pm2 delete $I ;; 
            4) box_input "ID" I; pm2 logs $I ;;
            5) update_app_source ;;
        esac
        read -p "Enter..."
    done
}

create_db() {
    submenu_header "DATABASE WIZARD"
    if ! systemctl is-active --quiet mariadb; then systemctl start mariadb; fi
    box_input "1. Buat DB Baru (0=Batal)" O; [ "$O" == "0" ] && return
    box_input "Nama DB" D; box_input "User DB" U
    DB=$(echo "$D" | tr -dc 'a-zA-Z0-9_'); USER=$(echo "$U" | tr -dc 'a-zA-Z0-9_')
    PASS=$(openssl rand -base64 12); echo " Pass: $PASS"
    box_input "Pakai Pass ini? (y/n)" C; [ "$C" == "n" ] && box_input "Pass Manual" PASS
    mysql -e "CREATE DATABASE IF NOT EXISTS $DB;"
    mysql -e "CREATE USER IF NOT EXISTS '$USER'@'localhost' IDENTIFIED BY '$PASS';"
    mysql -e "GRANT ALL PRIVILEGES ON $DB.* TO '$USER'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    echo "Done."; read -p "Enter..."
}

backup_wizard() {
    submenu_header "BACKUP SYSTEM"
    box_row "1. Web+DB (Zip)" "2. DB Only"
    box_center "0. Kembali" "$RED"
    draw_line 3
    box_input "Pilih" B
    if [ "$B" == "1" ]; then
        box_input "Domain (0=Batal)" DOM
        if [ "$DOM" == "0" ]; then return; fi
        ROOT=$(get_site_root "$DOM")
        [ -z "$ROOT" ] && box_input "Path Manual" ROOT
        FILE="backup_${DOM}_$(date +%F_%H%M).zip"
        if [ -d "$ROOT" ]; then cd $ROOT && zip -r "$BACKUP_DIR/$FILE" . -x "node_modules/*" "vendor/*"; echo "Saved: $BACKUP_DIR/$FILE"; else echo -e "${RED}Path 404.${NC}"; fi
    elif [ "$B" == "2" ]; then
        box_input "Nama DB" DB; mysqldump $DB > "$BACKUP_DIR/${DB}_$(date +%F).sql"; echo "Done."
    fi
    read -p "Enter..."
}

update_tool() {
    curl -sL "$UPDATE_URL" -o /tmp/bd_latest
    if grep -q "#!/bin/bash" /tmp/bd_latest; then mv /tmp/bd_latest /usr/local/bin/bd; chmod +x /usr/local/bin/bd; exec bd; else echo "Gagal."; fi
}

# --- MAIN LOOP ---
while true; do
    show_header
    box_input "Pilih Menu" OPT
    case $OPT in
        1) deploy_web ;; 2) manage_web ;; 3) manage_app ;; 4) open_file_manager ;; 5) create_db ;; 6) backup_wizard ;; 7) cron_manager ;; 8) set_limit ;; 9) update_tool ;; 0) clear; exit ;; u) rm /usr/local/bin/bd && exit ;; *) echo "Invalid."; sleep 1 ;;
    esac
done
EOF

chmod +x /usr/local/bin/bd
echo -e "${GREEN}SUKSES: BD-53 (Refined) Terinstall.${NC}"
echo "Tampilan rapi, konsisten, dan tombol '0. Kembali' sudah tersedia di mana-mana."
