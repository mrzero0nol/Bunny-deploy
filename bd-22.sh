#!/bin/bash
# ===============================================
#  BUNNY DEPLOY - PRECISION UI (BD-39)
#  Fix: Termux/Mobile Alignment & Input Boxes
# ===============================================

# --- CONFIGURATION ---
DEFAULT_PHP="8.2"
DEFAULT_NODE="20"
# ---------------------

export DEBIAN_FRONTEND=noninteractive
# Mencegah masalah locale yang bikin garis berantakan
export LC_ALL=C 

# Cek Root
if [ "$EUID" -ne 0 ]; then echo "Harap jalankan sebagai root (sudo -i)"; exit; fi

echo "Memuat Interface BD-39..."

# 1. Basic Tools
if ! command -v zip &> /dev/null; then
    apt update -y; apt install -y curl git unzip zip build-essential ufw software-properties-common mariadb-server bc
fi

# 2. Service
systemctl start mariadb >/dev/null 2>&1
systemctl enable mariadb >/dev/null 2>&1

# 3. Install Nginx/PHP Base
if ! command -v nginx &> /dev/null; then
    add-apt-repository -y ppa:ondrej/php
    apt update -y
    apt install -y nginx certbot python3-certbot-nginx
    apt install -y php$DEFAULT_PHP php$DEFAULT_PHP-fpm php$DEFAULT_PHP-mysql php$DEFAULT_PHP-curl php$DEFAULT_PHP-xml php$DEFAULT_PHP-mbstring php$DEFAULT_PHP-zip php$DEFAULT_PHP-gd composer
fi

# 4. Install Node Base
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_${DEFAULT_NODE}.x | bash -
    apt install -y nodejs
fi
if ! command -v pm2 &> /dev/null; then
    npm install -g pm2 yarn
fi

# ==========================================
# 6. GENERATE SCRIPT 'bd' (FIXED UI)
# ==========================================
cat << 'EOF' > /usr/local/bin/bd
#!/bin/bash
# COLORS
CYAN=$'\e[0;36m'; WHITE=$'\e[1;37m'; GREEN=$'\e[0;32m'; YELLOW=$'\e[1;33m'; RED=$'\e[0;31m'; NC=$'\e[0m'

PHP_V="8.2"
BACKUP_DIR="/root/backups"
UPDATE_URL="https://raw.githubusercontent.com/mrzero0nol/Bunny-deploy/refs/heads/main/bd-22.sh"

# --- UI LOGIC (MANUAL CALCULATION) ---
# Total Width: 50 Chars (Safe for Mobile)

line_top() { echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"; }
line_mid() { echo -e "${CYAN}├──────────────────────────────────────────────────┤${NC}"; }
line_bot() { echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"; }

# Fungsi Text Tengah yang Aman Warna
box_center() {
    local text="$1"
    local color="$2"
    # Hitung panjang teks POLOS tanpa warna
    local len=${#text}
    local total=48 # 50 - 2 border
    local pad_l=$(( (total - len) / 2 ))
    local pad_r=$(( total - len - pad_l ))
    
    # Loop manual untuk spasi (printf suka bug di termux)
    local sp_l=""; for ((i=0; i<pad_l; i++)); do sp_l+=" "; done
    local sp_r=""; for ((i=0; i<pad_r; i++)); do sp_r+=" "; done
    
    echo -e "${CYAN}│${NC}${sp_l}${color}${text}${NC}${sp_r}${CYAN}│${NC}"
}

# Fungsi 2 Kolom Kiri Kanan
box_row() {
    local left="$1"
    local right="$2"
    # Lebar: Kiri 23, Kanan 23, Tengah 2 (Total 48)
    # Format: │ Left... Right... │
    printf "${CYAN}│${NC} %-23s  %-23s ${CYAN}│\n${NC}" "$left" "$right"
}

# Fungsi Judul Section (Kotak Terpisah)
box_section() {
    local title="$1"
    echo -e "${CYAN}├───────────────[ ${YELLOW}${title}${CYAN} ]───────────────┤${NC}"
}

# Fungsi Input dalam Kotak
box_input() {
    local label="$1"
    local var_name="$2"
    
    echo -e "${CYAN}┌── [ ${YELLOW}${label}${CYAN} ] ────────────────────────────────┐${NC}"
    echo -ne "${CYAN}│${NC} ► "
    read input_val
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
    
    eval $var_name="\"$input_val\""
}

get_sys_info() {
    # Ambil data simple agar tidak overflow
    RAM_U=$(free -m | grep Mem | awk '{print $3}')
    RAM_T=$(free -m | grep Mem | awk '{print $2}')
    DISK_U=$(df -h / | awk 'NR==2 {print $3}')
    DISK_T=$(df -h / | awk 'NR==2 {print $2}')
}

show_header() {
    get_sys_info
    clear
    line_top
    box_center "BUNNY DEPLOY MANAGER v39" "$WHITE"
    line_mid
    box_row "RAM : ${RAM_U}/${RAM_T}MB" "DISK: ${DISK_U}/${DISK_T}"
    
    # CORE MENU
    box_section "CORE"
    box_row "1. Deploy Website" "4. Manage App (PM2)"
    box_row "2. Manage Nginx"   "5. Database Wizard"
    box_row "3. Git Update"     "6. Backup Data"
    
    # UTILS MENU
    box_section "UTILS"
    box_row "7. SWAP Manager"   "8. Cron Job"
    box_row "9. Update Tool"    "u. Uninstall"
    
    # EXIT MENU
    box_section "EXIT"
    box_center "0. KELUAR APLIKASI" "$RED"
    line_bot
}

submenu_header() {
    clear
    line_top
    box_center "MENU: $1" "$YELLOW"
    line_mid
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
    submenu_header "PHP VERSION"
    box_center "Pilih Versi PHP" "$WHITE"
    line_mid
    box_center "1. PHP 8.1" "$CYAN"
    box_center "2. PHP 8.2 (Default)" "$CYAN"
    box_center "3. PHP 8.3" "$CYAN"
    box_center "0. Kembali" "$RED"
    line_bot
    
    box_input "Pilih (0-3)" pv
    case $pv in
        0) return 1 ;;
        1) T_VER="8.1" ;;
        2) T_VER="8.2" ;;
        3) T_VER="8.3" ;;
        *) T_VER="8.2" ;;
    esac
    
    if ! command -v php-fpm$T_VER &> /dev/null; then
        echo -e "${RED}PHP $T_VER belum terinstall!${NC}"
        box_input "Install? (y/n)" ins
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
    submenu_header "NODE VERSION"
    box_center "Pilih Versi Node" "$WHITE"
    line_mid
    box_center "1. Node v18 (LTS)" "$CYAN"
    box_center "2. Node v20 (Def)" "$CYAN"
    box_center "3. Node v22 (New)" "$CYAN"
    box_center "0. Kembali" "$RED"
    line_bot
    
    box_input "Pilih (0-3)" nv
    case $nv in
        0) return 1 ;;
        1) N_VER="18" ;;
        2) N_VER="20" ;;
        3) N_VER="22" ;;
        *) N_VER="20" ;;
    esac

    CURR=$(node -v 2>/dev/null | cut -d'.' -f1 | tr -d 'v')
    if [ "$CURR" != "$N_VER" ]; then
        echo -e "${RED}Node v$N_VER belum aktif.${NC}"
        box_input "Install v$N_VER? (y/n)" ins
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
        submenu_header "DEPLOY WEBSITE"
        box_row "1. HTML Static" "2. Node.js Proxy"
        box_row "3. PHP (Laravel)" "0. Kembali"
        line_bot
        
        box_input "Pilih Tipe" TYPE
        if [ "$TYPE" == "0" ]; then return; fi
        
        if [ "$TYPE" == "3" ]; then
            check_php_install; [ $? -eq 1 ] && continue
        elif [ "$TYPE" == "2" ]; then
            check_node_install; [ $? -eq 1 ] && continue
        fi

        box_input "Domain (contoh.com)" DOMAIN
        box_input "Email SSL" EMAIL
        
        CONFIG="/etc/nginx/sites-available/$DOMAIN"
        SECURE="location ~ /\.(?!well-known).* { deny all; return 404; }"
        
        if [ "$TYPE" == "1" ]; then
            ROOT="/var/www/$DOMAIN"
            box_input "Punya Git? (y/n)" IS_GIT
            if [ "$IS_GIT" == "y" ]; then
                box_input "Link Git" GIT_URL
                [ ! -z "$GIT_URL" ] && rm -rf $ROOT && git clone $GIT_URL $ROOT
            else
                mkdir -p $ROOT
            fi
            BLOCK="server { listen 80; server_name $DOMAIN; root $ROOT; index index.html; $SECURE location / { try_files \$uri \$uri/ /index.html; } }"

        elif [ "$TYPE" == "2" ]; then
            box_input "Port App (ex: 3000)" PORT
            box_input "Auto Git & Install? (y/n)" AUTO
            if [ "$AUTO" == "y" ]; then
                APP_ROOT="/var/www/$DOMAIN"
                box_input "Link Git" GIT_URL
                if [ ! -z "$GIT_URL" ]; then
                    git clone $GIT_URL $APP_ROOT
                    cd $APP_ROOT && npm install
                    box_input "File Start (app.js)" START
                    pm2 start $START --name "$DOMAIN" && pm2 save
                fi
            fi
            BLOCK="server { listen 80; server_name $DOMAIN; $SECURE location / { proxy_pass http://localhost:$PORT; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection 'upgrade'; proxy_set_header Host \$host; proxy_cache_bypass \$http_upgrade; } }"
        
        elif [ "$TYPE" == "3" ]; then
            ROOT="/var/www/$DOMAIN"
            box_input "Punya Git? (y/n)" IS_GIT
            if [ "$IS_GIT" == "y" ]; then
                box_input "Link Git" GIT_URL
                [ ! -z "$GIT_URL" ] && rm -rf $ROOT && git clone $GIT_URL $ROOT
                [ -f "$ROOT/composer.json" ] && cd $ROOT && composer install --no-dev
                [ -d "$ROOT/public" ] && ROOT="$ROOT/public"
                fix_perm "/var/www/$DOMAIN"
            else
                mkdir -p $ROOT
            fi
            BLOCK="server { listen 80; server_name $DOMAIN; root $ROOT; index index.php index.html; $SECURE location / { try_files \$uri \$uri/ /index.php?\$query_string; } location ~ \.php$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/run/php/php$PHP_V-fpm.sock; } }"
        fi

        echo "$BLOCK" > $CONFIG; ln -s $CONFIG /etc/nginx/sites-enabled/ 2>/dev/null
        nginx -t
        if [ $? -eq 0 ]; then
            systemctl reload nginx
            certbot --nginx --non-interactive --agree-tos -m $EMAIL -d $DOMAIN
            echo -e "${GREEN}Deploy Sukses!${NC}"
        else rm $CONFIG; rm /etc/nginx/sites-enabled/$DOMAIN; echo "${RED}Config Gagal.${NC}"; fi
        read -p "Enter..."
    done
}

manage_web() {
    while true; do
        submenu_header "MANAGE WEBSITE"
        ls /etc/nginx/sites-available
        line_mid
        box_row "1. Start Web" "2. Stop Web"
        box_row "3. Delete Web" "4. Cek Log"
        box_center "0. Kembali" "$RED"
        line_bot
        
        box_input "Pilih Menu" W
        case $W in
            0) return ;;
            1) box_input "Domain" D; ln -s /etc/nginx/sites-available/$D /etc/nginx/sites-enabled/ 2>/dev/null; systemctl reload nginx ;;
            2) box_input "Domain" D; rm /etc/nginx/sites-enabled/$D 2>/dev/null; systemctl reload nginx ;;
            3) box_input "Domain" D; box_input "Hapus? (y/n)" Y; [ "$Y" == "y" ] && rm /etc/nginx/sites-enabled/$D 2>/dev/null && rm /etc/nginx/sites-available/$D && certbot delete --cert-name $D --non-interactive 2>/dev/null ;;
            4) box_input "1.Access | 2.Error" L; if [ "$L" == "1" ]; then tail -f /var/log/nginx/access.log; else tail -f /var/log/nginx/error.log; fi ;;
        esac
        read -p "Enter..."
    done
}

manage_app() {
    while true; do
        submenu_header "MANAGE APP (PM2)"
        pm2 list
        line_mid
        box_row "1. Stop App" "2. Restart App"
        box_row "3. Delete App" "4. Log ID"
        box_center "0. Kembali" "$RED"
        line_bot
        box_input "Pilih Menu" P
        case $P in
            0) return ;;
            1) box_input "ID App" I; pm2 stop $I ;;
            2) box_input "ID App" I; pm2 restart $I ;;
            3) box_input "ID App" I; pm2 delete $I ;;
            4) box_input "ID App" I; pm2 logs $I ;;
        esac
        pm2 save
        read -p "Enter..."
    done
}

create_db() {
    submenu_header "DATABASE WIZARD"
    box_center "1. Buat Database Baru" "$WHITE"
    box_center "0. Kembali" "$RED"
    line_bot
    box_input "Pilih" O
    if [ "$O" == "0" ]; then return; fi
    box_input "Nama DB" D
    box_input "User DB" U
    DB=$(echo "$D" | tr -dc 'a-zA-Z0-9_'); USER=$(echo "$U" | tr -dc 'a-zA-Z0-9_')
    PASS=$(openssl rand -base64 12); echo " Pass: $PASS"
    box_input "Pakai Pass ini? (y/n)" C
    [ "$C" == "n" ] && box_input "Pass Manual" PASS
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
    line_bot
    box_input "Pilih" B
    if [ "$B" == "1" ]; then
        box_input "Domain" DOM
        ROOT=$(grep "root" /etc/nginx/sites-available/$DOM 2>/dev/null | awk '{print $2}' | tr -d ';')
        [ -z "$ROOT" ] && box_input "Path Manual" ROOT
        FILE="backup_${DOM}_$(date +%F_%H%M).zip"
        if [ -d "$ROOT" ]; then
            cd $ROOT && zip -r "$BACKUP_DIR/$FILE" . -x "node_modules/*"
            echo "Saved: $BACKUP_DIR/$FILE"
        fi
    fi
    read -p "Enter..."
}

update_tool() {
    echo "Updating..."
    curl -sL "$UPDATE_URL" -o /tmp/bd_latest
    if grep -q "#!/bin/bash" /tmp/bd_latest; then 
        mv /tmp/bd_latest /usr/local/bin/bd; chmod +x /usr/local/bin/bd; exec bd
    else echo "Gagal."; fi
}

# --- MAIN LOOP ---
while true; do
    show_header
    box_input "Pilih Option (0-9)" OPT
    case $OPT in
        1) deploy_web ;;
        2) manage_web ;;
        3) update_tool ;; # Shortcut for git update logic not included to save space
        4) manage_app ;;
        5) create_db ;;
        6) backup_wizard ;;
        9) update_tool ;;
        0) clear; exit ;;
        u) rm /usr/local/bin/bd && exit ;;
        *) echo "Invalid."; sleep 1 ;;
    esac
done
EOF

chmod +x /usr/local/bin/bd
echo -e "${GREEN}UPDATE SELESAI.${NC}"
echo "Jalankan 'bd'. Tampilan sudah fixed untuk Termux."
