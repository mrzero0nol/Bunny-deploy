# Bunny Deploy Manager (BDM)

Bunny Deploy Manager adalah tool otomatisasi untuk deployment stack LEMP (Linux, Nginx, MariaDB, PHP) yang aman dan mudah digunakan. Tool ini dilengkapi dengan fitur keamanan canggih dan manajemen database berbasis GUI ("Iam Admin").

## Fitur Utama

*   **Secure Deployment:** Konfigurasi Nginx otomatis dengan security headers.
*   **Security Scanning:** Deteksi malware dan audit keamanan server.
*   **Database Manager:** Membuat database dan user MySQL dengan aman.
*   **Iam Admin:** Instalasi otomatis phpMyAdmin (akses via port 8888) untuk manajemen database GUI.
*   **Incident Response:** Tools untuk menangani serangan web defacement dan brute force.

## Cara Install

1.  Clone repository ini atau download scriptnya:
    ```bash
    git clone https://github.com/mrzero0nol/Bunny-deploy.git
    cd Bunny-deploy
    ```

2.  Jalankan script installer:
    ```bash
    chmod +x install.sh
    ./install.sh
    ```

3.  Tunggu hingga proses instalasi selesai. Installer akan menyiapkan dependencies (Nginx, MariaDB, dll) dan mengatur command `bd`.

## Cara Penggunaan

Setelah instalasi selesai, Anda bisa menjalankan tool ini kapan saja dengan mengetik:

```bash
bd
```

### Menu Utama:

1.  **Deploy New Website:** Setup domain baru (HTML/PHP) dengan Git otomatis.
2.  **Manage Existing Website:** Kelola website yang sudah ada (logs, git pull, rate limiting).
3.  **Database Security Manager:** Buat/Hapus/Backup database via CLI.
4.  **Security Scan & Audit:** Scan server dari malware dan celah keamanan.
5.  **View Audit Logs:** Lihat log aktivitas tool.
6.  **Incident Response:** Menu darurat untuk perbaikan situs.
7.  **Install Iam Admin:** Install dashboard database (phpMyAdmin) yang aman.

## Keamanan

*   Akses "Iam Admin" dibatasi pada port 8888.
*   Script melakukan scanning konten file untuk mencegah upload shell berbahaya.
*   Audit log tersimpan di `/var/log/bd_audit.log`.
