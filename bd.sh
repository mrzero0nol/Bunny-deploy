#!/bin/bash

# ==========================================
#  🐰 BUNNY DEPLOY 🐰
#    Dev:Kang Sarip
# ==========================================

# Warna System
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Cek Root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Harap jalankan sebagai root! (sudo su)${NC}"
    exit
fi

clear
echo -e "${PURPLE}=====================================================${NC}"
echo -e "${CYAN}      SEDANG MEMASANG ENGINE (BUNNY DEPLOY)...  ${NC}"
echo -e "${PURPLE}=====================================================${NC}"

# --- 1. UPDATE SYSTEM & INSTALL TOOLS ---
echo -e "${YELLOW}[1/5] Update System & Install Tools Dasar...${NC}"
apt update && apt upgrade -y
apt install -y curl git unzip build-essential ufw software-properties-common

# --- 2. INSTALL NGINX & SSL CERTBOT ---
echo -e "${YELLOW}[2/5] Install Nginx & Certbot...${NC}"
apt install -y nginx certbot python3-certbot-nginx
systemctl enable nginx
systemctl start nginx

# --- 3. INSTALL NODE.JS 20 & PM2 ---
echo -e "${YELLOW}[3/5] Install Node.js 20 (LTS) & PM2...${NC}"
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs
npm install -g pm2 yarn typescript
pm2 startup

# --- 4. INSTALL PHP 8.2 & EXTENSIONS ---
echo -e "${YELLOW}[4/5] Install PHP 8.2 & Composer...${NC}"
add-apt-repository ppa:ondrej/php -y
apt update
apt install -y php8.2 php8.2-fpm php8.2-mysql php8.2-curl php8.2-xml php8.2-mbstring composer
systemctl start php8.2-fpm
systemctl enable php8.2-fpm

# --- 5. SETUP FIREWALL ---
ufw allow OpenSSH
ufw allow 'Nginx Full'
echo "y" | ufw enable

# --- 6. MEMBUAT COMMAND 'bd' ---
echo -e "${YELLOW}[5/5] Merakit Command 'bd'...${NC}"

cat << 'EOF' > /usr/local/bin/bd
#!/bin/bash

# Warna CLI
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

show_header() {
    clear
    echo -e "${PURPLE}"
    echo "   (\_/)  ${BOLD}BUNNY DEPLOY v2.0${NC}${PURPLE}"
    echo "   (o.o)  ${CYAN}Command: bd${PURPLE}"
    echo "   (> <)  ${NC}"
    echo -e "${PURPLE}======================================${NC}"
}

pause() {
    echo -e "\n${CYAN}Tekan [Enter] untuk kembali ke menu...${NC}"
    read
}

deploy_web() {
    echo -e "\n${YELLOW}--- DEPLOY WEBSITE BARU ---${NC}"
    echo "1. HTML5 / React / Vue (Static)"
    echo "2. Node.js (Proxy Port)"
    echo "3. PHP (Laravel/Native)"
    read -p "Pilih Tipe [1-3]: " TYPE
    
    read -p "Masukkan Domain (contoh: toko.com): " DOMAIN
    read -p "Masukkan Email (untuk SSL): " EMAIL
    CONFIG="/etc/nginx/sites-available/$DOMAIN"

    if [ "$TYPE" == "1" ]; then
        # Config Static
        read -p "Path Folder (misal /var/www/dist): " ROOT
        BLOCK="server { listen 80; server_name $DOMAIN www.$DOMAIN; root $ROOT; index index.html; location / { try_files \$uri \$uri/ /index.html; } }"
    elif [ "$TYPE" == "2" ]; then
        # Config Proxy Node
        read -p "Port Aplikasi (misal 3000): " PORT
        BLOCK="server { listen 80; server_name $DOMAIN www.$DOMAIN; location / { proxy_pass http://localhost:$PORT; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection 'upgrade'; proxy_set_header Host \$host; proxy_cache_bypass \$http_upgrade; } }"
    elif [ "$TYPE" == "3" ]; then
        # Config PHP
        read -p "Path Folder (misal /var/www/web): " ROOT
        BLOCK="server { listen 80; server_name $DOMAIN www.$DOMAIN; root $ROOT; index index.php index.html; location / { try_files \$uri \$uri/ /index.php?\$query_string; } location ~ \.php$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/run/php/php8.2-fpm.sock; } }"
    else
        echo -e "${RED}Pilihan salah!${NC}"; pause; return
    fi

    echo "$BLOCK" > $CONFIG
    ln -s $CONFIG /etc/nginx/sites-enabled/ 2>/dev/null
    
    nginx -t
    if [ $? -eq 0 ]; then
        systemctl reload nginx
        echo -e "${GREEN}Config OK! Menginstall SSL...${NC}"
        certbot --nginx --non-interactive --agree-tos -m $EMAIL -d $DOMAIN -d www.$DOMAIN
        echo -e "${GREEN}SUKSES! $DOMAIN sudah online!${NC}"
    else
        echo -e "${RED}Config Error. Cek path folder Anda.${NC}"
        rm $CONFIG
    fi
    pause
}

delete_web() {
    echo -e "\n${RED}--- HAPUS WEBSITE (UNINSTALL WEB) ---${NC}"
    read -p "Masukkan Domain yang ingin dihapus: " DOMAIN
    
    if [ -f "/etc/nginx/sites-available/$DOMAIN" ]; then
        echo -e "${YELLOW}Menghapus Config Nginx...${NC}"
        rm /etc/nginx/sites-available/$DOMAIN
        rm /etc/nginx/sites-enabled/$DOMAIN
        
        echo -e "${YELLOW}Menghapus Sertifikat SSL...${NC}"
        certbot delete --cert-name $DOMAIN
        
        systemctl reload nginx
        echo -e "${GREEN}Website $DOMAIN berhasil dihapus dari sistem.${NC}"
        echo -e "${CYAN}Catatan: Folder file codingan TIDAK dihapus (biar aman).${NC}"
    else
        echo -e "${RED}Domain tidak ditemukan!${NC}"
    fi
    pause
}

uninstall_bd() {
    echo -e "\n${RED}!!! PERINGATAN UNINSTALL !!!${NC}"
    echo "Ini akan menghapus tool CLI 'bd' dari sistem."
    echo "Website yang sudah dideploy TIDAK AKAN hilang."
    read -p "Yakin ingin menghapus bd? (y/n): " CONFIRM
    if [ "$CONFIRM" == "y" ]; then
        rm /usr/local/bin/bd
        echo -e "${GREEN}Script 'bd' berhasil dihapus.${NC}"
        echo "Bye bye!"
        exit 0
    else
        echo "Dibatalkan."
        pause
    fi
}

while true; do
    show_header
    echo -e "${YELLOW}[ DEPLOYMENT ]${NC}"
    echo "1) Deploy Website Baru"
    echo "2) Hapus Website"
    
    echo -e "\n${YELLOW}[ MANAJEMEN APP (PM2) ]${NC}"
    echo "3) List Aplikasi"
    echo "4) Restart Aplikasi"
    echo "5) Stop Aplikasi"
    echo "6) Hapus Aplikasi dari PM2"
    echo "7) Monitor Log (Realtime)"
    
    echo -e "\n${YELLOW}[ SYSTEM ]${NC}"
    echo "8) Restart Nginx & PHP (Refresh Server)"
    echo "9) Uninstall Script 'bd'"
    echo "0) Keluar"
    
    echo -e "${PURPLE}======================================${NC}"
    read -p "Pilih Menu [0-9]: " OPT
    
    case $OPT in
        1) deploy_web ;;
        2) delete_web ;;
        3) pm2 status; pause ;;
        4) read -p "ID App: " ID; pm2 restart $ID; pause ;;
        5) read -p "ID App: " ID; pm2 stop $ID; pause ;;
        6) read -p "ID App: " ID; pm2 delete $ID; pm2 save; pause ;;
        7) read -p "ID App: " ID; pm2 logs $ID ;;
        8) systemctl restart nginx; systemctl restart php8.2-fpm; echo -e "${GREEN}Sistem Direfresh!${NC}"; pause ;;
        9) uninstall_bd ;;
        0) echo "Bye bye!"; exit 0 ;;
        *) echo "Pilihan tidak ada."; pause ;;
    esac
done
EOF

chmod +x /usr/local/bin/bd

echo -e "${PURPLE}=====================================================${NC}"
echo -e "${GREEN} INSTALASI SELESAI! ${NC}"
echo -e "${CYAN} Silakan ketik perintah: ${BOLD}bd${NC}"
echo -e "${PURPLE}=====================================================${NC}"
