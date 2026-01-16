#!/bin/bash

# ==========================================
#  🐰 BUNNY DEPLOY - ULTIMATE EDITION
#  Created for: Kang Sarip
#  Support: Ubuntu 20.04, 22.04, 24.04
# ==========================================

# 1. SETTING ANTI-MACET (Bypass Layar Pink)
export DEBIAN_FRONTEND=noninteractive
# Opsi apt agar otomatis pilih "Keep Default" saat update
APT_OPTS="-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

# Warna
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
echo -e "${CYAN}      MEMASANG BUNNY DEPLOY (ULTIMATE)...            ${NC}"
echo -e "${PURPLE}=====================================================${NC}"

# --- 1. UPDATE SYSTEM & DETEKSI OS ---
echo -e "${YELLOW}[1/5] Update System & Persiapan...${NC}"
apt update -y
apt upgrade -y $APT_OPTS
apt install -y $APT_OPTS curl git unzip build-essential ufw software-properties-common lsb-release ca-certificates

# --- 2. LOGIKA PINTAR UNTUK PHP (Fix Ubuntu 20.04) ---
echo -e "${YELLOW}[2/5] Menyiapkan Repository PHP...${NC}"
# Kita tambahkan PPA Ondrej agar Ubuntu 20.04 BISA install PHP 8.2
# (Di Ubuntu 22/24 ini juga aman, malah bikin versi PHP lebih update)
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
apt update -y

# --- 3. INSTALL ENGINE UTAMA (Nginx, PHP 8.2, Certbot) ---
echo -e "${YELLOW}[3/5] Install Nginx & PHP 8.2...${NC}"
apt install -y $APT_OPTS nginx certbot python3-certbot-nginx
apt install -y $APT_OPTS php8.2 php8.2-fpm php8.2-mysql php8.2-curl php8.2-xml php8.2-mbstring composer

# Pastikan service jalan
systemctl enable nginx
systemctl start nginx
systemctl enable php8.2-fpm
systemctl start php8.2-fpm

# --- 4. INSTALL NODE.JS 20 & PM2 ---
echo -e "${YELLOW}[4/5] Install Node.js 20 (LTS) & PM2...${NC}"
# Cek versi OS, jika terlalu tua (18.04) pakai Node 16, jika 20+ pakai Node 20
OS_VER=$(lsb_release -rs)
if [[ "$OS_VER" == "18.04" ]]; then
    echo "Terdeteksi OS Lama. Menggunakan Node 16..."
    curl -fsSL https://deb.nodesource.com/setup_16.x | bash -
else
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
fi

apt install -y $APT_OPTS nodejs
npm install -g pm2 yarn typescript
pm2 startup

# --- 5. SETUP FIREWALL ---
ufw allow OpenSSH
ufw allow 'Nginx Full'
echo "y" | ufw enable

# --- 6. MEMBUAT COMMAND 'bd' (FULL FITUR) ---
echo -e "${YELLOW}[5/5] Merakit Command 'bd' Full Version...${NC}"

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
        read -p "Path Folder (misal /var/www/dist): " ROOT
        BLOCK="server { listen 80; server_name $DOMAIN www.$DOMAIN; root $ROOT; index index.html; location / { try_files \$uri \$uri/ /index.html; } }"
    elif [ "$TYPE" == "2" ]; then
        read -p "Port Aplikasi (misal 3000): " PORT
        BLOCK="server { listen 80; server_name $DOMAIN www.$DOMAIN; location / { proxy_pass http://localhost:$PORT; proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection 'upgrade'; proxy_set_header Host \$host; proxy_cache_bypass \$http_upgrade; } }"
    elif [ "$TYPE" == "3" ]; then
        read -p "Path Folder (misal /var/www/web): " ROOT
        # Menggunakan PHP 8.2 Socket
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
