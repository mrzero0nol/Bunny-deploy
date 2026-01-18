#!/bin/bash
# INSTALL SCRIPT MUDAH

echo "========================================"
echo "   BUNNY DEPLOY MANAGER INSTALLER"
echo "========================================"

# 1. Update system
echo "[1] Update system..."
apt update -y && apt upgrade -y

# 2. Install tools dasar
echo "[2] Install tools..."
apt install -y curl git unzip nginx certbot mariadb-server fail2ban

# 3. Download script utama
echo "[3] Download Bunny Deploy Manager..."
curl -L https://raw.githubusercontent.com/mrzero0nol/Bunny-deploy/main/bdm.sh -o /usr/local/bin/bd

# 4. Kasih permission
echo "[4] Kasih permission..."
chmod +x /usr/local/bin/bd

# 5. Setup awal
echo "[5] Setup awal..."
mkdir -p /var/www
mkdir -p /root/backups

# 6. Start services
echo "[6] Start services..."
systemctl start nginx
systemctl enable nginx
systemctl start mariadb
systemctl enable mariadb

# 7. Setup firewall sederhana
echo "[7] Setup firewall..."
ufw allow 22  # SSH
ufw allow 80  # HTTP
ufw allow 443 # HTTPS
ufw --force enable

# 8. Selesai
echo "========================================"
echo "   ✅ INSTALL SELESAI!"
echo "========================================"
echo ""
echo "CARA PAKAI:"
echo "1. Ketik: bd"
echo "2. Tekan ENTER"
echo "3. Pilih menu dengan angka"
echo ""
echo "Contoh:"
echo "   Pilih 1 → Deploy website baru"
echo "   Pilih 2 → Manage website yang ada"
echo ""
echo "🔥 TIPS PENTING:"
echo "- Simpan password MySQL yang dibuat"
echo "- Backup sebelum hapus/hapus"
echo "- Jangan share password ke siapapun"
echo "========================================"
