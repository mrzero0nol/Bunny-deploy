# Review Script: bd-22.sh

Berikut adalah analisa dan pendapat mengenai script deployment `bd-22.sh`.

## Ringkasan
Script ini bertujuan untuk mengotomatisasi instalasi LEMP Stack (Linux, Nginx, MariaDB, PHP) dan Node.js pada server Ubuntu 22/24. Script ini juga membuat utility command bernama `bd` untuk mempermudah manajemen website dan database.

## Kelebihan (Pros)
1.  **Otomatisasi Lengkap**: Script menangani instalasi dependency yang cukup banyak (PHP 8.2, Extensions, Nginx, Certbot, Node.js, PM2) dengan satu perintah.
2.  **Kemudahan Penggunaan (DX)**: Command `bd` sangat membantu sysadmin pemula atau developer untuk deploy aplikasi tanpa harus menyentuh config Nginx secara manual.
3.  **Fleksibilitas**: Mendukung 3 tipe deployment umum: Static HTML, Node.js (Reverse Proxy), dan PHP (Laravel).
4.  **Database helper**: Fitur `create_db` memudahkan pembuatan database dan user tanpa perlu mengetik query SQL manual.
5.  **Vault Feature**: Penyimpanan kredensial database lokal memudahkan jika lupa password.

## Kekurangan & Resiko (Cons & Risks)

### 1. Keamanan (Security)
*   **Penyimpanan Password Plaintext**: File `/root/.bd_db_vault.txt` menyimpan password database tanpa enkripsi. Walaupun berada di folder `/root`, ini tetap dianggap bad practice. Jika server kompromi, semua kredensial database terekspos.
    *   *Saran*: Set permission file menjadi 600 (`chmod 600 /root/.bd_db_vault.txt`) agar hanya root yang bisa baca.
*   **Konfigurasi Firewall (UFW)**: Script menjalankan `ufw allow OpenSSH` lalu `echo "y" | ufw enable`.
    *   *Resiko*: Jika user menggunakan custom SSH port (bukan 22), perintah ini berpotensi mengunci user dari server (lockout) karena hanya port 22 yang dibuka secara default oleh rule `OpenSSH`.

### 2. Validasi & Error Handling
*   **Validasi Input Minim**: Tidak ada pengecekan ketat pada input user (misal: nama domain, nama database). Karakter aneh bisa menyebabkan error pada Nginx atau SQL.
*   **Duplikasi Data Vault**: Fungsi `create_db` selalu melakukan append (`>>`) ke file vault. Jika database dengan nama sama dibuat ulang (atau script dijalankan ulang), akan ada duplikasi entry di list password.
*   **Penanganan Error Nginx**: Pada fungsi `deploy_web`, config dibuat dan di-link. Jika `nginx -t` gagal, symlink tetap tertinggal di `sites-enabled` yang bisa membuat Nginx gagal restart di masa depan.

### 3. Fleksibilitas
*   **Hardcoded Version**: Versi PHP dikunci di 8.2. Jika user membutuhkan versi lain (misal 8.3 atau 8.1), script harus diedit manual.

## Kesimpulan & Saran Perbaikan
Secara umum, script ini **sangat berguna untuk setup server cepat (prototyping/staging)**. Namun untuk production grade yang serius, perlu perbaikan di sisi keamanan dan validasi.

**Saran Perbaikan Cepat:**
1.  Tambahkan `chmod 600 "$VAULT"` setelah pembuatan file vault.
2.  Tambahkan pengecekan port SSH sebelum enable UFW (atau tanya user).
3.  Tambahkan validasi sederhana (cek apakah input kosong).
4.  Cek apakah config Nginx sudah ada sebelum overwrite.

**Rating:** 7.5/10 (Fungsional & Efisien, tapi perlu hati-hati di Security/Firewall).
