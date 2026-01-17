#!/bin/bash
# ===============================================
#  BUNNY DEPLOY - MODULAR & LAZY LOAD (BD-60)
#  Fitur: On-Demand Install + Python Support + Secure Input
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

# 1. Basic Tools (Hanya tool sistem, BUKAN bahasa pemrograman)
echo "Memeriksa system tools dasar..."
if ! command -v zip &> /dev/null; then
    apt update -y; apt install -y curl git unzip zip build-essential ufw software-properties-common mariadb-server bc jq
fi

# 2. Service Database & Web Server Core (Nginx wajib ada di awal sebagai reverse proxy)
if ! systemctl is-active --quiet mariadb; then systemctl start mariadb; systemctl enable mariadb; fi

if ! command -v nginx &> /dev/null; then
    add-apt-repository -y ppa:ondrej/php # Siapkan repo saja, jangan install php dulu
    add-apt-repository -y ppa:deadsnakes/ppa # Siapkan repo python
    apt update -y
    apt install -y nginx certbot python3-certbot-nginx
fi

# 3. Security (Fail2Ban)
if ! command -v fail2ban-client &> /dev/null; then
    apt install -y fail2ban; cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    systemctl restart fail2ban; systemctl enable fail2ban
fi

# ==========================================
# GENERATE SCRIPT 'bd'
# ==========================================
cat << 'EOF' > /usr/local/bin/bd
#!/bin/bash
# COLORS
CYAN=$'\e[0;36m'; WHITE=$'\e[1;37m'; GREEN=$'\e[0;32m'; YELLOW=$'\e[1;33m'; RED=$'\e[0;31m'; NC=$'\e[0m'

CONFIG_FILE="/root/.bd_config"
source "$CONFIG_FILE" 2>/dev/null || UPLOAD_LIMIT="64M"

BACKUP_DIR="/root/backups"
mkdir -p $BACKUP_DIR

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

# --- SECURITY FIX: NO EVAL ---
box_input() {
    local label="$1"
    # Argumen $2 adalah nama variabel tujuan
    echo -e "${CYAN}┌─ [ ${YELLOW}${label}${CYAN} ]${NC}"
    echo -ne "${CYAN}└─► ${NC}"
    read -r temp_input
    # Assign nilai ke variabel yang namanya ada di $2
    printf -v "$2" '%s' "$temp_input"
}

get_sys_info() {
    RAM=$(free -m | grep Mem | awk '{print $3"/"$2"MB"}')
    DISK=$(df -h / | awk 'NR==2 {print $3"/"$2}')
}

# --- MENU SYSTEM ---
show_header() {
    get_width
    get_sys_info
    clear
    draw_line 1
    box_center "BUNNY DEPLOY v60 (Modular)" "$WHITE"
    draw_line 2
    box_row "RAM: $RAM" "DISK: $DISK"
    
    draw_line 2
    box_center "--- MAIN MENU ---" "$YELLOW"
    box_row "1. Deploy Wizard"  "2. Manage Web"
    box_row "3. App Manager"    "4. File Manager"
    box_row "5. Database"       "6. Backup"
    
    draw_line 2
    box_center "--- UTILITIES ---" "$YELLOW"
    box_row "7. Cron Job"       "8. Upload Limit"
    box_row "9. System Check"   "u. Uninstall"
    
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

# --- LAZY INSTALLER FUNCTIONS ---

ensure_php() {
    local ver=$1
    if ! command -v php-fpm$ver &> /dev/null; then
        echo -e "${YELLOW}[INFO] PHP $ver belum terinstall. Menginstall sekarang...${NC}"
        apt update -y
        apt install -y php$ver php$ver-fpm php$ver-mysql php$ver-curl php$ver-xml php$ver-mbstring php$ver-zip php$ver-gd composer
        echo -e "${GREEN}[OK] PHP $ver siap.${NC}"
    fi
}

ensure_node() {
    local ver=$1
    CURR=$(node -v 2>/dev/null | cut -d'.' -f1 | tr -d 'v')
    if [ "$CURR" != "$ver" ]; then
        echo -e "${YELLOW}[INFO] Node.js v$ver belum terinstall/beda versi. Menginstall...${NC}"
        curl -fsSL https://deb.nodesource.com/setup_${ver}.x | bash -
        apt install -y nodejs build-essential
        npm install -g pm2 yarn
        echo -e "${GREEN}[OK] Node.js $ver siap.${NC}"
    fi
}

ensure_python() {
    if ! command -v python3-venv &> /dev/null; then
        echo -e "${YELLOW}[INFO] Python3 venv & pip belum lengkap. Menginstall...${NC}"
        apt update -y
        apt install -y python3-pip python3-venv python3-dev
        # Kita butuh PM2 untuk manage python juga agar konsisten
        if ! command -v pm2 &> /dev/null; then
             echo "Menginstall PM2 via npm untuk process manager..."
             ensure_node "20" # Default node untuk jalanin PM2
        fi
        echo -e "${GREEN}[OK] Python environment siap.${NC}"
    fi
}

# --- SELECTORS ---

check_php_ver() {
    echo -e "${YELLOW}[ Pilih Versi PHP ]${NC}"
    echo "1. PHP 8.1"
    echo "2. PHP 8.2 (Default)"
    echo "3. PHP 8.3"
    echo "0. Batal"
    box_input "Pilih (0-3)" pv
    if [ "$pv" == "0" ]; then return 1; fi
    case $pv in 1) V="8.1";; 2) V="8.2";; 3) V="8.3";; *) V="8.2";; esac
    
    ensure_php "$V"
    PHP_V=$V
    return 0
}

check_node_ver() {
    echo -e "${YELLOW}[ Pilih Versi Node.js ]${NC}"
    echo "1. v18 (LTS)"
    echo "2. v20 (Default)"
    echo "3. v22 (Latest)"
    echo "0. Batal"
    box_input "Pilih (0-3)" nv
    if [ "$nv" == "0" ]; then return 1; fi
    case $nv in 1) V="18";; 2) V="20";; 3) V="22";; *) V="20";; esac
    
    ensure_node "$V"
    return 0
}

# --- DEPLOYMENT LOGIC ---

deploy_web() {
    while true; do
        submenu_header "DEPLOY WIZARD"
        box_row "1. HTML Static" "2. PHP Web"
        box_row "3. Node.js App" "4. Python App"
        box_center "0. Kembali" "$RED"
        draw_line 3
        
        box_input "Pilih Tipe" TYPE
        if [ "$TYPE" == "0" ]; then return; fi
        
        # --- PRE-FLIGHT CHECK (Install Runtime Only Here) ---
        if [ "$TYPE" == "2" ]; then check_php_ver; if [ $? -eq 1 ]; then continue; fi; fi
        if [ "$TYPE" == "3" ]; then check_node_ver; if [ $? -eq 1 ]; then continue; fi; fi
        if [ "$TYPE" == "4" ]; then ensure_python; fi

        box_input "Domain (contoh.com)" DOMAIN
        box_input "Email SSL" EMAIL
        
        ROOT="/var/www/$DOMAIN"
        CONFIG="/etc/nginx/sites-available/$DOMAIN"
        
        # Security & Config Generic
        DENY_HIDDEN="location ~ /\.(?!well-known).* { deny all; return 404; }"
        NGINX_OPTS="client_max_body_size ${UPLOAD_LIMIT}; fastcgi_read_timeout 300;"
        SEC_H="add_header X-Frame-Options \"SAMEORIGIN\"; add_header X-XSS-Protection \"1; mode=block\"; add_header X-Content-Type-Options \"nosniff\";"
        HIDE_VER="server_tokens off;"

        # --- LOGIC PER TYPE ---
        
        # 1. HTML STATIC
        if [ "$TYPE" == "1" ]; then
            box_input "Git URL (Enter=Kosong)" GIT
            if [ ! -z "$GIT" ]; then rm -rf $ROOT; git clone $GIT $ROOT; else mkdir -p $ROOT; fi
            BLOCK="server { listen 80; server_name $DOMAIN; root $ROOT; index index.html; $HIDE_VER $NGINX_OPTS $SEC_H $DENY_HIDDEN location / { try_files \$uri \$uri/ /index.html; } }"
        
        # 2. PHP
        elif [ "$TYPE" == "2" ]; then
            box_input "Git URL" GIT
            if [ ! -z "$GIT" ]; then 
                rm -rf $ROOT; git clone $GIT $ROOT
                [ -f "$ROOT/composer.json" ] && cd $ROOT && composer install --no-dev
                [ -d "$ROOT/public" ] && ROOT="$ROOT/public"
                
                # Fix Permissions
                chown -R www-data:www-data "/var/www/$DOMAIN"
                chmod -R 775 "/var/www/$DOMAIN/storage" 2>/dev/null
            else mkdir -p $ROOT; fi
            BLOCK="server { listen 80; server_name $DOMAIN; root $ROOT; index index.php index.html; $HIDE_VER $NGINX_OPTS $SEC_H $DENY_HIDDEN location / { try_files \$uri \$uri/ /index.php?\$query_string; } location ~ \.php$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/run/php/php$PHP_V-fpm.sock; } }"

        # 3. NODE.JS
        elif [ "$TYPE" == "3" ]; then
            box_input "Port App (e.g 3000)" PORT
            box_input "Git URL" GIT
            if [ ! -z "$GIT" ]; then
                git clone $GIT $ROOT; cd $ROOT && npm install
                box_input "File Start (e.g app.js)" START
                pm2 start $START --name "$DOMAIN" && pm2 save
            fi
            BLOCK="server { listen 80; server_name $DOMAIN; $HIDE_VER $NGINX_OPTS $SEC_H $DENY_HIDDEN location / { proxy_pass http://localhost:$PORT; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection 'upgrade'; proxy_set_header Host \$host; proxy_cache_bypass \$http_upgrade; } }"

        # 4. PYTHON (NEW!)
        elif [ "$TYPE" == "4" ]; then
            box_input "Port App (e.g 5000)" PORT
            box_input "Git URL" GIT
            if [ ! -z "$GIT" ]; then
                git clone $GIT $ROOT; cd $ROOT
                echo "Setup Python Venv..."
                python3 -m venv venv
                source venv/bin/activate
                if [ -f "requirements.txt" ]; then pip install -r requirements.txt; fi
                pip install gunicorn
                
                box_input "WSGI Entry (e.g app:app)" WSGI
                # Start Gunicorn via PM2 agar termanage di menu 3
                pm2 start "gunicorn -w 4 -b 127.0.0.1:$PORT $WSGI" --name "$DOMAIN" && pm2 save
            fi
            BLOCK="server { listen 80; server_name $DOMAIN; $HIDE_VER $NGINX_OPTS $SEC_H $DENY_HIDDEN location / { proxy_pass http://localhost:$PORT; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection 'upgrade'; proxy_set_header Host \$host; proxy_cache_bypass \$http_upgrade; } }"
        fi

        # --- FINALIZING ---
        echo "$BLOCK" > $CONFIG; ln -s $CONFIG /etc/nginx/sites-enabled/ 2>/dev/null; nginx -t
        if [ $? -eq 0 ]; then 
            systemctl reload nginx
            certbot --nginx -n -m $EMAIL -d $DOMAIN --agree-tos
            echo -e "${GREEN}Deploy $DOMAIN Berhasil!${NC}"
        else 
            echo -e "${RED}Error Config Nginx${NC}"
        fi
        read -p "Tekan Enter..."
    done
}

# --- MANAGERS ---

manage_web() {
    while true; do
        submenu_header "MANAGE WEBSITE"
        for file in /etc/nginx/sites-available/*; do
            [ -e "$file" ] || continue
            domain=$(basename "$file")
            if [ "$domain" == "default" ]; then continue; fi
            if grep -q "proxy_pass" "$file"; then TYPE="${CYAN}[APP]${NC}"; else TYPE="${YELLOW}[WEB]${NC}"; fi
            if [ -L "/etc/nginx/sites-enabled/$domain" ]; then STATUS="${GREEN}[ON]${NC}"; else STATUS="${RED}[OFF]${NC}"; fi
            box_row "$domain" "$TYPE $STATUS"
        done
        draw_line 2
        box_row "1. Start/Stop" "2. Delete Web"
        box_row "3. View Logs"  "4. Git Pull"
        box_center "0. Kembali" "$RED"
        draw_line 3
        box_input "Pilih" W
        case $W in
            0) return ;;
            1) box_input "Domain" D; if [ -L "/etc/nginx/sites-enabled/$D" ]; then rm /etc/nginx/sites-enabled/$D; else ln -s /etc/nginx/sites-available/$D /etc/nginx/sites-enabled/; fi; systemctl reload nginx; echo "Toggled." ;;
            2) box_input "Domain" D; box_input "Yakin? (y/n)" Y; [ "$Y" == "y" ] && rm /etc/nginx/sites-enabled/$D 2>/dev/null && rm /etc/nginx/sites-available/$D && certbot delete --cert-name $D -n ;;
            3) box_input "1.Access 2.Error" L; if [ "$L" == "1" ]; then tail -f /var/log/nginx/access.log; else tail -f /var/log/nginx/error.log; fi ;;
            4) box_input "Domain" D; R=$(get_site_root "$D"); cd $R && git pull && echo "Done.";;
        esac
        read -p "Enter..."
    done
}

manage_app() {
    if ! command -v pm2 &> /dev/null; then
        submenu_header "APP MANAGER"
        box_center "PM2 Belum Terinstall." "$RED"
        box_center "Silakan deploy App Node/Python dulu." "$WHITE"
        read -p "Enter..."; return
    fi

    while true; do
        submenu_header "APP MANAGER (NODE/PYTHON)"
        pm2 list
        draw_line 2
        box_row "1. Restart App" "2. Stop App"
        box_row "3. Delete App"  "4. Logs"
        box_center "0. Kembali" "$RED"
        draw_line 3
        box_input "Pilih" P
        case $P in
            0) return ;;
            1) box_input "ID/Name" I; pm2 restart $I ;;
            2) box_input "ID/Name" I; pm2 stop $I ;;
            3) box_input "ID/Name" I; pm2 delete $I ;;
            4) box_input "ID/Name" I; pm2 logs $I ;;
        esac
        read -p "Enter..."
    done
}

open_file_manager() {
    if ! command -v mc &> /dev/null; then apt install -y mc; fi
    export EDITOR=nano; [ -d "/var/www" ] && mc /var/www || mc
}

create_db() {
    submenu_header "DATABASE WIZARD"
    box_input "Nama DB Baru" D
    box_input "Nama User" U
    PASS=$(openssl rand -base64 12); echo "Pass Auto: $PASS"
    box_input "Gunakan Pass ini? (y/n)" C
    if [ "$C" == "n" ]; then box_input "Pass Manual" PASS; fi
    
    mysql -e "CREATE DATABASE IF NOT EXISTS \`${D}\`;"
    mysql -e "CREATE USER IF NOT EXISTS '${U}'@'localhost' IDENTIFIED BY '${PASS}';"
    mysql -e "GRANT ALL PRIVILEGES ON \`${D}\`.* TO '${U}'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    echo -e "${GREEN}Database $D dibuat!${NC}"; read -p "Enter..."
}

backup_wizard() {
    submenu_header "BACKUP SYSTEM"
    box_row "1. Full Website" "2. Database"
    box_input "Pilih" B
    if [ "$B" == "1" ]; then
         box_input "Domain" D; R=$(get_site_root "$D")
         zip -r "$BACKUP_DIR/backup_${D}.zip" $R -x "node_modules/*"
         echo "Saved to $BACKUP_DIR"
    elif [ "$B" == "2" ]; then
         box_input "DB Name" D; mysqldump $D > "$BACKUP_DIR/$D.sql"
    fi
    read -p "Enter..."
}

# --- MAIN LOOP ---
while true; do
    show_header
    box_input "Pilih Menu" OPT
    case $OPT in
        1) deploy_web ;; 2) manage_web ;; 3) manage_app ;; 4) open_file_manager ;; 5) create_db ;; 6) backup_wizard ;; 7) echo "Coming soon"; sleep 1;; 8) echo "Edit .bd_config"; sleep 1;; 9) apt update; echo "System updated"; sleep 1;; 0) clear; exit ;; u) rm /usr/local/bin/bd; echo "Uninstalled"; exit ;; *) echo "Invalid"; sleep 1 ;;
    esac
done
EOF

chmod +x /usr/local/bin/bd
echo -e "${GREEN}SUKSES: BD-60 Terinstall.${NC}"
echo "Ketik 'bd' untuk menjalankan."
echo "Catatan: PHP/Node/Python belum diinstall. Akan otomatis diinstall saat Anda deploy web."
