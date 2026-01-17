#!/bin/bash
# ===============================================
#  BUNNY DEPLOY - ADAPTIVE UI (BD-41)
#  Fitur: Mobile Mode (Tanpa Kotak jika layar sempit)
# ===============================================

# --- CONFIGURATION ---
DEFAULT_PHP="8.2"
DEFAULT_NODE="20"
# ---------------------

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C

# Cek Root
if [ "$EUID" -ne 0 ]; then echo "Harap jalankan sebagai root (sudo -i)"; exit; fi

# Detect Lebar Layar
TERM_W=$(tput cols)
if [ -z "$TERM_W" ]; then TERM_W=80; fi

# Mode Tampilan: MOBILE vs DESKTOP
if [ "$TERM_W" -lt 52 ]; then
    UI_MODE="MOBILE"
else
    UI_MODE="DESKTOP"
fi

# 1. Basic Tools
if ! command -v zip &> /dev/null; then
    apt update -y; apt install -y curl git unzip zip build-essential ufw software-properties-common mariadb-server bc
fi

# 2. Service
systemctl start mariadb >/dev/null 2>&1
systemctl enable mariadb >/dev/null 2>&1

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

# ==========================================
# 6. GENERATE SCRIPT 'bd' (ADAPTIVE)
# ==========================================
cat << 'EOF' > /usr/local/bin/bd
#!/bin/bash
# COLORS
CYAN=$'\e[0;36m'; WHITE=$'\e[1;37m'; GREEN=$'\e[0;32m'; YELLOW=$'\e[1;33m'; RED=$'\e[0;31m'; NC=$'\e[0m'

PHP_V="8.2"
BACKUP_DIR="/root/backups"

# --- PENTING: GANTI LINK INI DENGAN LINK RAW GITHUB KAMU SENDIRI ---
UPDATE_URL="https://raw.githubusercontent.com/mrzero0nol/Bunny-deploy/refs/heads/main/bd-22.sh" 
# -------------------------------------------------------------------

# --- ADAPTIVE UI LOGIC ---
get_ui_mode() {
    TERM_W=$(tput cols)
    [ -z "$TERM_W" ] && TERM_W=80
    if [ "$TERM_W" -lt 52 ]; then
        UI_MODE="MOBILE"
        LINE_CHAR="-"
    else
        UI_MODE="DESKTOP"
        BOX_W=50
        LINE_CHAR="─"
    fi
}

draw_separator() {
    local char=$1
    local color=$2
    local line=""
    local width=$TERM_W
    [ "$UI_MODE" == "DESKTOP" ] && width=$BOX_W
    
    for ((i=0; i<width; i++)); do line+="$char"; done
    echo -e "${color}${line}${NC}"
}

header_text() {
    local text="$1"
    echo -e "${CYAN}[ ${YELLOW}${text} ${CYAN}]${NC}"
}

print_menu() {
    local l="$1"
    local r="$2"
    if [ "$UI_MODE" == "MOBILE" ]; then
        echo -e " ${CYAN}●${NC} $l"
        [ ! -z "$r" ] && echo -e " ${CYAN}●${NC} $r"
    else
        # Desktop Box Logic
        local sp_len=$((BOX_W - ${#l} - ${#r} - 5))
        local sp=""; for ((i=0; i<sp_len; i++)); do sp+=" "; done
        echo -e "${CYAN}│${NC} $l$sp$r ${CYAN}│${NC}"
    fi
}

get_sys_info() {
    RAM=$(free -m | grep Mem | awk '{print $3"/"$2"MB"}')
    DISK=$(df -h / | awk 'NR==2 {print $3"/"$2}')
}

show_header() {
    get_ui_mode
    get_sys_info
    clear
    
    if [ "$UI_MODE" == "MOBILE" ]; then
        draw_separator "=" "$CYAN"
        echo -e "${WHITE}  BUNNY DEPLOY v41 (Mobile)${NC}"
        draw_separator "-" "$CYAN"
        echo -e "RAM : $RAM"
        echo -e "DISK: $DISK"
        draw_separator "=" "$CYAN"
        
        header_text "CORE FEATURES"
        print_menu "1. Deploy Website" "4. App Manager (PM2)"
        print_menu "2. Manage Nginx"   "5. Database Wizard"
        print_menu "3. Git Update"     "6. Backup Data"
        echo ""
        header_text "UTILITIES"
        print_menu "7. SWAP Manager"   "8. Cron Job"
        print_menu "9. Update Tool"    "u. Uninstall"
        
        draw_separator "-" "$RED"
        echo -e " ${RED}0. KELUAR APLIKASI${NC}"
        draw_separator "=" "$CYAN"
    else
        # DESKTOP MODE (BOX)
        echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${WHITE}           BUNNY DEPLOY v41 (PRO)                 ${CYAN}│${NC}"
        echo -e "${CYAN}├──────────────────────────────────────────────────┤${NC}"
        printf "${CYAN}│${NC} RAM: %-18s DISK: %-16s ${CYAN}│\n${NC}" "$RAM" "$DISK"
        echo -e "${CYAN}├─────────────────────[ CORE ]─────────────────────┤${NC}"
        print_menu "1. Deploy Website" "4. App Manager"
        print_menu "2. Manage Nginx"   "5. Database"
        print_menu "3. Git Update"     "6. Backup"
        echo -e "${CYAN}├────────────────────[ UTILS ]─────────────────────┤${NC}"
        print_menu "7. SWAP Manager"   "8. Cron Job"
        print_menu "9. Update Tool"    "u. Uninstall"
        echo -e "${CYAN}├─────────────────────[ EXIT ]─────────────────────┤${NC}"
        echo -e "${CYAN}│${RED}               0. KELUAR APLIKASI                 ${CYAN}│${NC}"
        echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
    fi
}

submenu_header() {
    clear
    echo -e "${CYAN}=== MENU: ${YELLOW}$1${CYAN} ===${NC}"
    echo ""
}

# --- INPUT HELPER ---
ask() {
    local prompt="$1"
    local var="$2"
    echo -ne "${CYAN}► ${YELLOW}$prompt: ${NC}"
    read input_val
    eval $var="\"$input_val\""
}

# --- LOGIC FUNCTIONS ---
fix_perm() {
    echo "Fixing permission..."
    chown -R www-data:www-data $1
    find $1 -type f -exec chmod 644 {} \;
    find $1 -type d -exec chmod 755 {} \;
    if [ -d "$1/storage" ]; then chmod -R 775 "$1/storage"; fi
}

check_php() {
    echo -e "\n${YELLOW}[ Pilih Versi PHP ]${NC}"
    echo "1) PHP 8.1"
    echo "2) PHP 8.2"
    echo "3) PHP 8.3"
    ask "Pilih (1-3)" pv
    case $pv in 1) V="8.1";; 2) V="8.2";; 3) V="8.3";; *) V="8.2";; esac
    
    if ! command -v php-fpm$V &> /dev/null; then
        echo "Installing PHP $V..."
        apt update -y; apt install -y php$V php$V-fpm php$V-mysql php$V-curl php$V-xml php$V-mbstring php$V-zip php$V-gd
    fi
    PHP_V=$V
}

check_node() {
    echo -e "\n${YELLOW}[ Pilih Versi Node ]${NC}"
    echo "1) v18 (LTS)"
    echo "2) v20 (Def)"
    echo "3) v22 (New)"
    ask "Pilih (1-3)" nv
    case $nv in 1) V="18";; 2) V="20";; 3) V="22";; *) V="20";; esac
    
    CURR=$(node -v 2>/dev/null | cut -d'.' -f1 | tr -d 'v')
    if [ "$CURR" != "$V" ]; then
        curl -fsSL https://deb.nodesource.com/setup_${V}.x | bash -; apt install -y nodejs
    fi
}

deploy_web() {
    while true; do
        submenu_header "DEPLOY WEBSITE"
        echo "1. HTML Static"
        echo "2. Node.js App"
        echo "3. PHP (Laravel/CI)"
        echo "0. Kembali"
        echo ""
        ask "Pilih Menu" TYPE
        if [ "$TYPE" == "0" ]; then return; fi
        
        [ "$TYPE" == "3" ] && check_php
        [ "$TYPE" == "2" ] && check_node

        ask "Domain" DOMAIN
        ask "Email SSL" EMAIL
        
        ROOT="/var/www/$DOMAIN"
        CONFIG="/etc/nginx/sites-available/$DOMAIN"
        SECURE="location ~ /\.(?!well-known).* { deny all; return 404; }"

        if [ "$TYPE" == "1" ]; then
            ask "Git URL (Enter = Kosong)" GIT
            if [ ! -z "$GIT" ]; then rm -rf $ROOT; git clone $GIT $ROOT; else mkdir -p $ROOT; fi
            BLOCK="server { listen 80; server_name $DOMAIN; root $ROOT; index index.html; $SECURE location / { try_files \$uri \$uri/ /index.html; } }"
        
        elif [ "$TYPE" == "2" ]; then
            ask "Port App (e.g 3000)" PORT
            ask "Auto Git? (y/n)" AG
            if [ "$AG" == "y" ]; then
                ask "Git URL" GIT
                if [ ! -z "$GIT" ]; then
                    git clone $GIT $ROOT; cd $ROOT && npm install
                    ask "File Start (app.js)" START
                    pm2 start $START --name "$DOMAIN" && pm2 save
                fi
            fi
            BLOCK="server { listen 80; server_name $DOMAIN; $SECURE location / { proxy_pass http://localhost:$PORT; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection 'upgrade'; proxy_set_header Host \$host; proxy_cache_bypass \$http_upgrade; } }"
        
        elif [ "$TYPE" == "3" ]; then
            ask "Git URL (Enter = Kosong)" GIT
            if [ ! -z "$GIT" ]; then
                rm -rf $ROOT; git clone $GIT $ROOT
                [ -f "$ROOT/composer.json" ] && cd $ROOT && composer install --no-dev
                [ -d "$ROOT/public" ] && ROOT="$ROOT/public"
                fix_perm "/var/www/$DOMAIN"
            else mkdir -p $ROOT; fi
            BLOCK="server { listen 80; server_name $DOMAIN; root $ROOT; index index.php index.html; $SECURE location / { try_files \$uri \$uri/ /index.php?\$query_string; } location ~ \.php$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/run/php/php$PHP_V-fpm.sock; } }"
        fi

        echo "$BLOCK" > $CONFIG; ln -s $CONFIG /etc/nginx/sites-enabled/ 2>/dev/null; nginx -t
        if [ $? -eq 0 ]; then systemctl reload nginx; certbot --nginx -n -m $EMAIL -d $DOMAIN --agree-tos; echo -e "${GREEN}Deploy Berhasil!${NC}"; else echo -e "${RED}Error Config${NC}"; fi
        read -p "Enter..."
    done
}

manage_web() {
    submenu_header "MANAGE WEB"
    ls /etc/nginx/sites-available
    echo "-------------------"
    echo "1. Start | 2. Stop | 3. Delete | 4. Log"
    echo "0. Kembali"
    ask "Pilih" W
    case $W in
        1) ask "Domain" D; ln -s /etc/nginx/sites-available/$D /etc/nginx/sites-enabled/ 2>/dev/null; systemctl reload nginx;;
        2) ask "Domain" D; rm /etc/nginx/sites-enabled/$D 2>/dev/null; systemctl reload nginx;;
        3) ask "Domain" D; ask "Yakin? (y/n)" Y; [ "$Y" == "y" ] && rm /etc/nginx/sites-enabled/$D 2>/dev/null && rm /etc/nginx/sites-available/$D && certbot delete --cert-name $D -n;;
        4) ask "1.Access 2.Error" L; if [ "$L" == "1" ]; then tail -f /var/log/nginx/access.log; else tail -f /var/log/nginx/error.log; fi;;
    esac
}

update_tool() {
    echo "Updating..."
    curl -sL "$UPDATE_URL" -o /tmp/bd_latest
    if grep -q "#!/bin/bash" /tmp/bd_latest; then mv /tmp/bd_latest /usr/local/bin/bd; chmod +x /usr/local/bin/bd; exec bd; else echo "Gagal Update."; fi
}

# --- MAIN LOOP ---
while true; do
    show_header
    ask "Select Option" OPT
    case $OPT in
        1) deploy_web;; 2) manage_web;; 3) update_tool;; 4) pm2 list; ask "PM2 CMD" P; pm2 $P; read -p "Enter";; 9) update_tool;; 0) clear; exit;; u) rm /usr/local/bin/bd && exit;; *) echo "Invalid"; sleep 1;;
    esac
done
EOF

chmod +x /usr/local/bin/bd
echo -e "${GREEN}SUKSES: Bunny Deploy v41 (Adaptive) Terinstall.${NC}"
echo "Ketik 'bd' untuk memulai."
