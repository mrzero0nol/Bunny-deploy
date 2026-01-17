#!/bin/bash
# ===============================================
#  BUNNY DEPLOY - RESPONSIVE UI (BD-40)
#  Fitur: Auto-Detect Lebar Layar (Anti-Pecah)
# ===============================================

# --- CONFIGURATION ---
DEFAULT_PHP="8.2"
DEFAULT_NODE="20"
# ---------------------

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C

# Cek Root
if [ "$EUID" -ne 0 ]; then echo "Harap jalankan sebagai root (sudo -i)"; exit; fi

# Detect Lebar Layar Real-time
TERM_W=$(tput cols)
# Beri jarak aman 2 karakter agar tidak mentok kanan
MAX_W=$((TERM_W - 2))
# Batasi maksimal lebar 55 karakter agar tidak terlalu lebar di PC
if [ "$MAX_W" -gt 55 ]; then MAX_W=55; fi

# 1. Basic Tools
if ! command -v zip &> /dev/null; then
    apt update -y; apt install -y curl git unzip zip build-essential ufw software-properties-common mariadb-server bc
fi

# 2. Service
systemctl start mariadb >/dev/null 2>&1
systemctl enable mariadb >/dev/null 2>&1

# 3. Install Base
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

# ==========================================
# 6. GENERATE SCRIPT 'bd' (RESPONSIVE)
# ==========================================
cat << 'EOF' > /usr/local/bin/bd
#!/bin/bash
# COLORS
CYAN=$'\e[0;36m'; WHITE=$'\e[1;37m'; GREEN=$'\e[0;32m'; YELLOW=$'\e[1;33m'; RED=$'\e[0;31m'; NC=$'\e[0m'

PHP_V="8.2"
BACKUP_DIR="/root/backups"
UPDATE_URL="https://raw.githubusercontent.com/mrzero0nol/Bunny-deploy/refs/heads/main/bd-22.sh"

# --- DYNAMIC UI FUNCTIONS ---
get_width() {
    TERM_W=$(tput cols)
    BOX_W=$((TERM_W - 4)) # Padding aman
    if [ "$BOX_W" -gt 50 ]; then BOX_W=50; fi
}

draw_line() {
    local type=$1 # 1=Top, 2=Mid, 3=Bot
    local line=""
    for ((i=0; i<BOX_W; i++)); do line+="─"; done
    
    if [ "$type" == "1" ]; then echo -e "${CYAN}┌${line}┐${NC}";
    elif [ "$type" == "2" ]; then echo -e "${CYAN}├${line}┤${NC}";
    elif [ "$type" == "3" ]; then echo -e "${CYAN}└${line}┘${NC}"; 
    fi
}

box_center() {
    local text="$1"
    local color="$2"
    
    # Strip warna untuk hitung panjang asli
    local clean_text=$(echo -e "$text" | sed "s/\x1B\[[0-9;]*[a-zA-Z]//g")
    local len=${#clean_text}
    
    local space_total=$((BOX_W - len))
    if [ "$space_total" -lt 0 ]; then space_total=0; fi # Safety
    
    local pad_l=$((space_total / 2))
    local pad_r=$((space_total - pad_l))
    
    local sp_l=""; for ((i=0; i<pad_l; i++)); do sp_l+=" "; done
    local sp_r=""; for ((i=0; i<pad_r; i++)); do sp_r+=" "; done
    
    echo -e "${CYAN}│${NC}${sp_l}${color}${text}${NC}${sp_r}${CYAN}│${NC}"
}

box_row() {
    local l_txt="$1"
    local r_txt="$2"
    
    # Simple Layout for Mobile (No vertical split lines inside)
    # Just Align Left and Right safely
    local clean_l=$(echo -e "$l_txt" | sed "s/\x1B\[[0-9;]*[a-zA-Z]//g")
    local clean_r=$(echo -e "$r_txt" | sed "s/\x1B\[[0-9;]*[a-zA-Z]//g")
    
    local len_l=${#clean_l}
    local len_r=${#clean_r}
    local gap=$((BOX_W - len_l - len_r - 2))
    
    local sp=""; for ((i=0; i<gap; i++)); do sp+=" "; done
    
    # Jika layar kekecilan, print baris baru
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

show_header() {
    get_width
    get_sys_info
    clear
    
    draw_line 1
    box_center "BUNNY DEPLOY v40 (Auto-Fit)" "$WHITE"
    draw_line 2
    box_row "RAM: $RAM" "DISK: $DISK"
    
    draw_line 2
    box_center "--- CORE FEATURES ---" "$YELLOW"
    box_row "1. Deploy Web" "4. App Manager"
    box_row "2. Manage Web" "5. Database"
    box_row "3. Git Update" "6. Backup"
    
    draw_line 2
    box_center "--- UTILITIES ---" "$YELLOW"
    box_row "7. SWAP"       "8. Cron Job"
    box_row "9. Update"     "u. Uninstall"
    
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

# --- LOGIC FUNCTIONS (SAME AS BEFORE) ---
fix_perm() {
    echo "Fixing permission..."
    chown -R www-data:www-data $1
    find $1 -type f -exec chmod 644 {} \;
    find $1 -type d -exec chmod 755 {} \;
    if [ -d "$1/storage" ]; then chmod -R 775 "$1/storage"; fi
}

check_php_install() {
    submenu_header "PHP VERSION"
    box_center "1. PHP 8.1" "$CYAN"
    box_center "2. PHP 8.2 (Def)" "$CYAN"
    box_center "3. PHP 8.3" "$CYAN"
    box_center "0. Kembali" "$RED"
    draw_line 3
    box_input "Pilih (0-3)" pv
    case $pv in
        0) return 1 ;; 1) T_VER="8.1" ;; 2) T_VER="8.2" ;; 3) T_VER="8.3" ;; *) T_VER="8.2" ;;
    esac
    if ! command -v php-fpm$T_VER &> /dev/null; then
        echo "Installing PHP $T_VER..."
        apt update -y; apt install -y php$T_VER php$T_VER-fpm php$T_VER-mysql php$T_VER-curl php$T_VER-xml php$T_VER-mbstring php$T_VER-zip php$T_VER-gd
    fi
    PHP_V=$T_VER
    return 0
}

check_node_install() {
    submenu_header "NODE VERSION"
    box_center "1. v18 (LTS)" "$CYAN"
    box_center "2. v20 (Def)" "$CYAN"
    box_center "3. v22 (New)" "$CYAN"
    box_center "0. Kembali" "$RED"
    draw_line 3
    box_input "Pilih (0-3)" nv
    case $nv in
        0) return 1 ;; 1) N_VER="18" ;; 2) N_VER="20" ;; 3) N_VER="22" ;; *) N_VER="20" ;;
    esac
    CURR=$(node -v 2>/dev/null | cut -d'.' -f1 | tr -d 'v')
    if [ "$CURR" != "$N_VER" ]; then
        curl -fsSL https://deb.nodesource.com/setup_${N_VER}.x | bash -; apt install -y nodejs
    fi
    return 0
}

deploy_web() {
    while true; do
        submenu_header "DEPLOY WEBSITE"
        box_row "1. HTML" "2. Node.js"
        box_row "3. PHP"  "0. Kembali"
        draw_line 3
        box_input "Pilih Tipe" TYPE
        if [ "$TYPE" == "0" ]; then return; fi
        
        if [ "$TYPE" == "3" ]; then check_php_install; [ $? -eq 1 ] && continue; fi
        if [ "$TYPE" == "2" ]; then check_node_install; [ $? -eq 1 ] && continue; fi

        box_input "Domain" DOMAIN
        box_input "Email SSL" EMAIL
        CONFIG="/etc/nginx/sites-available/$DOMAIN"
        SECURE="location ~ /\.(?!well-known).* { deny all; return 404; }"
        
        if [ "$TYPE" == "1" ]; then
            ROOT="/var/www/$DOMAIN"
            box_input "Git URL (Enter if none)" GIT_URL
            if [ ! -z "$GIT_URL" ]; then rm -rf $ROOT; git clone $GIT_URL $ROOT; else mkdir -p $ROOT; fi
            BLOCK="server { listen 80; server_name $DOMAIN; root $ROOT; index index.html; $SECURE location / { try_files \$uri \$uri/ /index.html; } }"
        elif [ "$TYPE" == "2" ]; then
            box_input "Port App (e.g 3000)" PORT
            box_input "Git URL (Enter if none)" GIT_URL
            if [ ! -z "$GIT_URL" ]; then
                git clone $GIT_URL "/var/www/$DOMAIN"; cd "/var/www/$DOMAIN" && npm install
                box_input "Start File (app.js)" START
                pm2 start $START --name "$DOMAIN" && pm2 save
            fi
            BLOCK="server { listen 80; server_name $DOMAIN; $SECURE location / { proxy_pass http://localhost:$PORT; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection 'upgrade'; proxy_set_header Host \$host; proxy_cache_bypass \$http_upgrade; } }"
        elif [ "$TYPE" == "3" ]; then
            ROOT="/var/www/$DOMAIN"
            box_input "Git URL (Enter if none)" GIT_URL
            if [ ! -z "$GIT_URL" ]; then 
                rm -rf $ROOT; git clone $GIT_URL $ROOT; [ -f "$ROOT/composer.json" ] && cd $ROOT && composer install --no-dev
                [ -d "$ROOT/public" ] && ROOT="$ROOT/public"
                fix_perm "/var/www/$DOMAIN"
            else mkdir -p $ROOT; fi
            BLOCK="server { listen 80; server_name $DOMAIN; root $ROOT; index index.php index.html; $SECURE location / { try_files \$uri \$uri/ /index.php?\$query_string; } location ~ \.php$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/run/php/php$PHP_V-fpm.sock; } }"
        fi

        echo "$BLOCK" > $CONFIG; ln -s $CONFIG /etc/nginx/sites-enabled/ 2>/dev/null; nginx -t
        if [ $? -eq 0 ]; then systemctl reload nginx; certbot --nginx -n -m $EMAIL -d $DOMAIN --agree-tos; echo -e "${GREEN}SUCCESS!${NC}"; else echo -e "${RED}ERROR${NC}"; fi
        read -p "Enter..."
    done
}

manage_web() {
    while true; do
        submenu_header "MANAGE WEBSITE"
        ls /etc/nginx/sites-available
        draw_line 2
        box_row "1. Start" "2. Stop"
        box_row "3. Delete" "4. Log"
        box_center "0. Kembali" "$RED"
        draw_line 3
        box_input "Pilih" W
        case $W in
            0) return ;;
            1) box_input "Domain" D; ln -s /etc/nginx/sites-available/$D /etc/nginx/sites-enabled/ 2>/dev/null; systemctl reload nginx ;;
            2) box_input "Domain" D; rm /etc/nginx/sites-enabled/$D 2>/dev/null; systemctl reload nginx ;;
            3) box_input "Domain" D; rm /etc/nginx/sites-enabled/$D 2>/dev/null; rm /etc/nginx/sites-available/$D; certbot delete --cert-name $D -n 2>/dev/null ;;
            4) box_input "1.Acc 2.Err" L; if [ "$L" == "1" ]; then tail -f /var/log/nginx/access.log; else tail -f /var/log/nginx/error.log; fi ;;
        esac
    done
}

manage_app() {
    while true; do
        submenu_header "APP MANAGER"
        pm2 list; draw_line 2
        box_row "1. Stop" "2. Restart"
        box_row "3. Delete" "4. Log"
        box_center "0. Kembali" "$RED"
        draw_line 3
        box_input "Pilih" P
        case $P in
            0) return ;; 1) box_input "ID" I; pm2 stop $I ;; 2) box_input "ID" I; pm2 restart $I ;; 3) box_input "ID" I; pm2 delete $I ;; 4) box_input "ID" I; pm2 logs $I ;;
        esac
    done
}

update_tool() {
    curl -sL "$UPDATE_URL" -o /tmp/bd_latest
    if grep -q "#!/bin/bash" /tmp/bd_latest; then mv /tmp/bd_latest /usr/local/bin/bd; chmod +x /usr/local/bin/bd; exec bd; fi
}

# --- MAIN LOOP ---
while true; do
    show_header
    box_input "Pilih Menu" OPT
    case $OPT in
        1) deploy_web ;; 2) manage_web ;; 3) update_tool ;; 4) manage_app ;; 9) update_tool ;; 0) clear; exit ;; u) rm /usr/local/bin/bd && exit ;; *) echo "Invalid."; sleep 1 ;;
    esac
done
EOF

chmod +x /usr/local/bin/bd
echo -e "${GREEN}UPDATED TO v40 (RESPONSIVE).${NC}"
echo "Jalankan 'bd' sekarang. Dijamin pas di layar."
