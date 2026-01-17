#!/bin/bash
# ==========================================
#  BUNNY DEPLOY - UBUNTU 22/24 (ULTIMATE DB)
#  Dev: Kang Sarip
# ==========================================

export DEBIAN_FRONTEND=noninteractive
APT_OPTS="-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

if [ "$EUID" -ne 0 ]; then echo "Harap jalankan sebagai root (sudo -i)"; exit; fi

echo "Installing Bunny Deploy (Ubuntu 22/24)..."

# 1. Update & Tools
apt update -y
apt upgrade -y $APT_OPTS
apt install -y $APT_OPTS curl git unzip build-essential ufw software-properties-common mariadb-server

# 2. Service Database
systemctl start mariadb
systemctl enable mariadb

# 3. Install PHP 8.2
add-apt-repository -y ppa:ondrej/php
apt update -y
apt install -y $APT_OPTS nginx certbot python3-certbot-nginx
apt install -y $APT_OPTS php8.2 php8.2-fpm php8.2-mysql php8.2-curl php8.2-xml php8.2-mbstring composer

# 4. Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y $APT_OPTS nodejs
npm install -g pm2 yarn

# 5. Firewall (SSH Safe)
systemctl enable nginx php8.2-fpm
ufw allow 'Nginx Full'
ufw allow OpenSSH
echo "y" | ufw enable

# 6. Command 'bd'
cat << 'EOF' > /usr/local/bin/bd
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
VAULT="/root/.bd_db_vault.txt"

show_header() {
    clear
    echo -e "${RED}======================================${NC}"
    echo -e "${YELLOW}   BUNNY DEPLOY - Dev Kang Sarip${NC}"
    echo -e "${RED}======================================${NC}"
}

deploy_web() {
    echo -e "\n[ DEPLOY WEBSITE BARU ]"
    echo "1. HTML5 / Static"
    echo "2. Node.js (Proxy)"
    echo "3. PHP 8.2 (Laravel)"
    read -p "Pilih: " TYPE
    read -p "Domain: " DOMAIN
    read -p "Email SSL: " EMAIL
    CONFIG="/etc/nginx/sites-available/$DOMAIN"

    if [ "$TYPE" == "1" ]; then
        read -p "Folder Path: " ROOT
        BLOCK="server { listen 80; server_name $DOMAIN www.$DOMAIN; root $ROOT; index index.html; location / { try_files \$uri \$uri/ /index.html; } }"
    elif [ "$TYPE" == "2" ]; then
        read -p "Port App: " PORT
        BLOCK="server { listen 80; server_name $DOMAIN www.$DOMAIN; location / { proxy_pass http://localhost:$PORT; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection 'upgrade'; proxy_set_header Host \$host; proxy_cache_bypass \$http_upgrade; } }"
    elif [ "$TYPE" == "3" ]; then
        read -p "Folder Path: " ROOT
        BLOCK="server { listen 80; server_name $DOMAIN www.$DOMAIN; root $ROOT; index index.php index.html; location / { try_files \$uri \$uri/ /index.php?\$query_string; } location ~ \.php$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/run/php/php8.2-fpm.sock; } }"
    else echo "Salah pilih"; return; fi

    echo "$BLOCK" > $CONFIG
    ln -s $CONFIG /etc/nginx/sites-enabled/ 2>/dev/null
    nginx -t && systemctl reload nginx
    certbot --nginx --non-interactive --agree-tos -m $EMAIL -d $DOMAIN -d www.$DOMAIN
    read -p "Sukses. Enter..."
}

update_app() {
    echo -e "\n[ UPDATE APP/WEB (GIT PULL) ]"
    read -p "Masukkan Domain: " DOMAIN
    ROOT=$(grep "root" /etc/nginx/sites-available/$DOMAIN 2>/dev/null | awk '{print $2}' | tr -d ';')
    if [ -z "$ROOT" ]; then read -p "Path Folder Project: " ROOT; fi

    if [ -d "$ROOT/.git" ]; then
        echo "Updating $ROOT..."
        cd $ROOT && git pull
        if [ -f "package.json" ]; then
            npm install
            read -p "Restart PM2? (y/n): " R
            if [ "$R" == "y" ]; then read -p "ID App: " ID; pm2 restart $ID; fi
        fi
        echo -e "${GREEN}Update Selesai!${NC}"
    else
        echo -e "${RED}Bukan Git Repo.${NC}"
    fi
    read -p "Enter..."
}

# --- FITUR DATABASE BARU ---
create_db() {
    echo -e "\n[ BUAT DATABASE BARU ]"
    read -p "Nama Database: " DBNAME
    read -p "Username DB  : " DBUSER
    read -p "Password DB  : " DBPASS
    
    mysql -e "CREATE DATABASE IF NOT EXISTS $DBNAME;"
    mysql -e "CREATE USER IF NOT EXISTS '$DBUSER'@'localhost' IDENTIFIED BY '$DBPASS';"
    mysql -e "GRANT ALL PRIVILEGES ON $DBNAME.* TO '$DBUSER'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    
    # Simpan ke Brankas (Vault)
    echo "$DBNAME|$DBUSER|$DBPASS" >> $VAULT
    
    echo -e "${GREEN}Database dibuat & disimpan ke vault!${NC}"
    read -p "Enter..."
}

show_db_creds() {
    echo -e "\n[ DAFTAR USER & PASSWORD DATABASE ]"
    echo "Catatan: Hanya menampilkan DB yang dibuat lewat script ini."
    echo "-----------------------------------------------------------"
    printf "%-20s | %-20s | %-20s\n" "DATABASE" "USER" "PASSWORD"
    echo "-----------------------------------------------------------"
    if [ -f "$VAULT" ]; then
        while IFS='|' read -r D U P; do
            printf "%-20s | %-20s | %-20s\n" "$D" "$U" "$P"
        done < $VAULT
    else
        echo "Belum ada data tersimpan."
    fi
    echo "-----------------------------------------------------------"
    read -p "Enter..."
}

view_db_content() {
    echo -e "\n[ INTIP ISI DATABASE ]"
    # List DB dulu
    mysql -e "SHOW DATABASES;"
    echo "---------------------------"
    read -p "Pilih Nama Database: " DBNAME
    
    echo -e "\n[ Tabel di $DBNAME ]"
    mysql -e "SHOW TABLES FROM $DBNAME;"
    
    echo -e "\nIngin melihat isi tabel?"
    read -p "Masukkan Nama Tabel (atau 'n' untuk batal): " TNAME
    if [ "$TNAME" != "n" ]; then
        echo "----------------------------------------"
        echo "Menampilkan 20 baris pertama data..."
        mysql -e "SELECT * FROM $DBNAME.$TNAME LIMIT 20;"
        echo "----------------------------------------"
    fi
    read -p "Enter..."
}

db_manager() {
    while true; do
        clear
        echo -e "${YELLOW}--- DATABASE MANAGER ---${NC}"
        echo "1. Buat Database Baru"
        echo "2. Hapus Database"
        echo "3. Lihat Password DB (Vault)"
        echo "4. Lihat Isi Database (Tabel/Data)"
        echo "0. Kembali"
        read -p "Pilih: " DOPT
        case $DOPT in
            1) create_db ;;
            2) read -p "Hapus DB Name: " D; mysql -e "DROP DATABASE IF EXISTS $D;"; echo "Dihapus."; read -p "Enter..." ;;
            3) show_db_creds ;;
            4) view_db_content ;;
            0) break ;;
        esac
    done
}

while true; do
    show_header
    echo "1. Deploy Website"
    echo "2. Update Web/App"
    echo "3. Hapus Website"
    echo "-----------------"
    echo "4. Database Manager (New!)"
    echo "5. PM2 Manager"
    echo "-----------------"
    echo "6. System Update"
    echo "7. Restart Service"
    echo "8. Uninstall Script"
    echo "0. Keluar"
    read -p "Pilih: " OPT
    case $OPT in
        1) deploy_web ;;
        2) update_app ;;
        3) read -p "Domain: " D; rm /etc/nginx/sites-enabled/$D /etc/nginx/sites-available/$D; certbot delete --cert-name $D; systemctl reload nginx; read -p "Deleted." ;;
        4) db_manager ;;
        5) pm2 list; echo "Logs/Restart/Stop?"; read -p "Command (logs/restart/stop [ID]): " C I; pm2 $C $I --lines 50 --nostream; read -p "Enter..." ;;
        6) apt update -y && apt upgrade -y; echo "Updated."; read -p "Enter..." ;;
        7) systemctl restart nginx php8.2-fpm; echo "Refreshed."; read -p "Enter..." ;;
        8) read -p "Hapus script? (y/n): " C; if [ "$C" == "y" ]; then rm /usr/local/bin/bd; exit; fi ;;
        0) exit ;;
    esac
done
EOF

chmod +x /usr/local/bin/bd
echo "SELESAI. Ketik: bd"
