# WEB-01 — HTTP Credential Exposure (Ubuntu 24.04 + Apache2)

**Lingkungan latihan TERISOLASI.** Gunakan akun dummy saja. Jangan tempatkan jaringan lab langsung di Internet. Aplikasi ini sengaja membuat akses HTTP tidak aman pada tahap awal, agar peserta dapat mengamati kebocoran kredensial dari PCAP.

## 1. Spesifikasi

| Peran | OS | IP | Software |
|---|---|---|---|
| Blue Team (target) | Ubuntu Server 24.04 | 192.168.36.233 | Apache2, PHP, OpenSSL, tcpdump, SSH |
| Red Team | Kali Linux | 192.168.36.248 | Wireshark, tshark, tcpdump, curl, OpenSSL |

Domain FQDN: `web01.lab.example.com`. Set kedua VM dalam subnet lab yang dapat saling berkomunikasi. Pastikan IP target memang `192.168.36.233` dari konfigurasi Netplan/hypervisor. Script hanya mengatur **pemetaan domain di `/etc/hosts`**, bukan alamat jaringan statis atau DNS pusat. Jika lab memerlukan DNS sungguhan, buat A record `web01.lab.example.com -> 192.168.36.233` pada DNS internal di luar skrip.

## 2. Instalasi Blue Team (Ubuntu)

Salin atau unzip folder `web01_ctf` ke Ubuntu, misalnya di `/opt/web01_ctf`, kemudian:

```bash
cd /opt/web01_ctf
sudo bash setup.sh
```

Script melakukan hal berikut: periksa versi OS dan keberadaan IP; `apt-get update`; instal apache2, PHP, openssl, curl, tcpdump, ca-certificates, openssh-server, python3, utilitas jaringan; aktifkan SSH; tambah domain di `/etc/hosts`; buat aplikasi login dummy; buat CA internal dan server certificate dengan SAN; pasang CA di trust store Ubuntu; buat dua virtualhost; aktifkan hanya HTTP port 80; buat PCAP awal di `lo`; bila UFW sudah aktif izinkan TCP 80/443 dari IP Kali (aturan SSH harus ditangani admin); uji HTTP dan sertifikat.

> Tidak mengatur IP statis, gateway, routing, atau VM hypervisor. Ini berbeda di tiap lingkungan dan harus disiapkan admin terlebih dahulu. Menjalankan `setup.sh` kembali **tidak akan menonaktifkan HTTPS** apabila virtualhost HTTPS sudah diaktifkan. Untuk sengaja kembali ke HTTP-only gunakan `sudo bash setup.sh --reset-http`. Konfigurasi aplikasi dan virtualhost tetap dikelola installer; ambil snapshot sebelum ujian.

Cek di Blue Team:

```bash
ip -4 addr
getent hosts web01.lab.example.com
sudo systemctl status apache2 --no-pager
sudo apache2ctl -S
sudo ss -lntp | grep -E ':80|:443'
curl -I --noproxy '*' http://web01.lab.example.com/
curl --noproxy '*' -d 'username=taruna01&password=LatihanHTTP2026%21' http://web01.lab.example.com/login.php
ls -lh /var/www/web01/public/training/login-http.pcap
sudo bash setup.sh --status
```

Kondisi awal: HTTP `200 OK`; port 443 belum aktif; `http://web01.lab.example.com/training/login-http.pcap` bisa diunduh. Akun simulasi: `taruna01` / `LatihanHTTP2026!`.

**Jika SSH/UFW:** Blue menginstal layanan SSH, namun `setup.sh` tidak membuka aturan UFW port 22 secara otomatis agar tidak mengubah kebijakan akses administratif. Administrator dapat mengizinkan koneksi SSH dari Kali jika sesuai kebijakan, misalnya `sudo ufw allow from 192.168.36.248 to any port 22 proto tcp`. Pastikan tidak memutus sesi remote. Karena pemindahan CA memerlukan login, siapkan akun user SSH di Ubuntu (akun bawaan administrator sudah cukup).

## 3. Konfigurasi Kali Linux

Ekstrak folder yang sama ke Kali:

```bash
cd ~/web01_ctf
sudo bash setup_kali.sh NAMA_USER_UBUNTU
```

Ganti `NAMA_USER_UBUNTU` dengan nama akun SSH yang dapat login ke Blue Team. Kali akan menginstal alat, memperbarui `/etc/hosts`, menyalin **sertifikat CA publik saja** dari Blue lewat SCP, memasangnya ke `/usr/local/share/ca-certificates`, memperbarui CA trust store, dan mengunduh PCAP awal ke `~/web01-lab/login-http.pcap`. Pada koneksi pertama, installer sekarang menjalankan SSH **interaktif melalui terminal** sebelum SCP. **Bandingkan fingerprint SSH Blue Team melalui konsol Ubuntu** sebelum mengetik `yes`. Installer tidak menonaktifkan SSH host-key checking. Password SSH dapat diminta dua kali (SSH lalu SCP).

Jika belum punya akses SSH atau Kali belum bisa terhubung, jalankan `sudo bash setup_kali.sh` tanpa username (instal alat dan domain saja). Kemudian administrator memindahkan file publik `/usr/local/share/ca-certificates/web01-lab-ca.crt` dari Ubuntu melalui media/kanal terpercaya. Di Kali:

```bash
sudo cp web01-lab-ca.crt /usr/local/share/ca-certificates/web01-lab-ca.crt
sudo update-ca-certificates
```

**Jangan menyalin** `/opt/web01-ca/ca.key` atau `/etc/ssl/web01/server.key` ke Kali. Periksa fingerprint sertifikat CA dari kedua sisi:

```bash
openssl x509 -in /usr/local/share/ca-certificates/web01-lab-ca.crt -noout -fingerprint -sha256
```

Perintah di atas sama di Blue dan Kali. Samakan nilainya. Jangan mengambil CA lewat endpoint HTTP lab lalu mempercayainya tanpa autentikasi.

Pengecekan Kali awal:

```bash
getent hosts web01.lab.example.com
ping -c 3 192.168.36.233
curl -I http://web01.lab.example.com/
wireshark ~/web01-lab/login-http.pcap
```

Di Wireshark filter `http.request.method == "POST"`; klik paket → klik kanan → **Follow → TCP Stream**. Data formulir dummy dapat dibaca. `%21` adalah URL encoding dari `!`.

**Catatan jaringan:** Kali dengan IP `192.168.36.248` tidak otomatis dapat melihat traffic antara komputer lain dan Blue Team hanya karena berada dalam subnet yang sama. Gunakan file PCAP yang disediakan atau capture pada endpoint/interface milik sendiri. Praktikum ini tidak membutuhkan ARP spoofing atau man-in-the-middle.

## 4. Daftar 15 soal (230 poin)

| No | Tantangan | Poin | Indikator jawaban |
|---|---|---:|---|
| 1 | Identifikasi protokol di PCAP | 10 | HTTP over TCP |
| 2 | Metode request login | 10 | POST |
| 3 | Endpoint login | 10 | `/login.php` |
| 4 | HTTP Host header | 10 | `web01.lab.example.com` |
| 5 | Content-Type form | 10 | `application/x-www-form-urlencoded` |
| 6 | Username dummy pada request | 15 | `taruna01` |
| 7 | Password dummy pada request | 15 | `LatihanHTTP2026!` |
| 8 | Interpretasi `%21` | 10 | `!` |
| 9 | TCP stream yang menyimpan request | 10 | Follow TCP Stream, tangkapan layar bukti |
| 10 | Mengapa data dapat dibaca | 15 | HTTP tidak mengenkripsi isi transport |
| 11 | Analisis port server | 10 | Awal 80; akhir 443 |
| 12 | Pemeriksaan SAN dan trust CA | 15 | OpenSSL + curl tanpa `-k` |
| 13 | Implementasi HTTPS valid | 35 | Cert chain, hostname, login HTTPS sukses |
| 14 | Enforce redirect HTTP -> HTTPS | 25 | 301 menuju HTTPS, mencegah POST HTTP secara langsung |
| 15 | Pembandingan PCAP dan validator | 30 | Tidak ada password plaintext pada TLS capture; flag akhir |
| | **Total** | **230** | |

Pekerjaan perubahan konfigurasi di Blue Team hanya dilakukan oleh peserta yang diberi izin admin. Pengajar dapat memberi akses sudo terbatas atau mendampingi.

## 5. Hardening HTTPS pada Blue Team

### Cara otomatis (untuk instruktur atau pengecekan akhir)

```bash
sudo bash setup.sh --secure
```

Ini mengaktifkan virtualhost HTTPS dan mengganti virtualhost HTTP menjadi redirect permanen. Tidak membuat ulang sertifikat. Pengajar yang ingin menilai kemampuan konfigurasi manual sebaiknya **tidak memberi tahu parameter `--secure` kepada taruna** sebelum penilaian.

### Cara manual (disarankan untuk kompetensi taruna)

1. Cek berkas `/etc/apache2/sites-available/web01-https.conf` dan sertifikat `/etc/ssl/web01/server.crt`.
2. Jalankan `sudo a2enmod ssl headers && sudo a2ensite web01-https.conf`.
3. Edit `/etc/apache2/sites-available/web01-http.conf` sehingga port 80 berisi `Redirect permanent / https://web01.lab.example.com/`. Hapus konfigurasi DocumentRoot lama jika mau, jangan tambahkan redirect di VirtualHost 443.
4. Jalankan `sudo apache2ctl configtest && sudo systemctl reload apache2`.
5. Pada Kali yang sudah trust CA, jalankan:

```bash
curl -Iv https://web01.lab.example.com/
curl -I http://web01.lab.example.com/
curl -sS -d 'username=taruna01&password=LatihanHTTP2026%21' https://web01.lab.example.com/login.php
openssl s_client -connect 192.168.36.233:443 -servername web01.lab.example.com -verify_return_error -CAfile /usr/local/share/ca-certificates/web01-lab-ca.crt </dev/null 2>&1 | grep -E 'Verify return code|subject=|issuer='
```

HTTPS harus sukses **tanpa** `curl -k` dan OpenSSL menampilkan `Verify return code: 0 (ok)`. HTTP harus `301` dengan `Location: https://web01.lab.example.com/`. Form login `POST` ke HTTP **tidak boleh diproses** sebagai login lewat HTTP: server hanya merespons redirect; browser baru perlu mengirim data ulang ke HTTPS. Catatan: 301/302 dapat mengubah POST menjadi GET pada sebagian client; browser harus memuat halaman HTTPS **sebelum** submit login.

### Uji PCAP setelah hardening

Di Blue Team, terminal 1:

```bash
sudo tcpdump -i any -s 0 -w /tmp/web01-https.pcap 'tcp port 443'
```

Di Kali, terminal 2:

```bash
curl -sS -d 'username=taruna01&password=LatihanHTTP2026%21' https://web01.lab.example.com/login.php
```

Setelah request, hentikan tcpdump di Blue dengan `Ctrl+C`; baca capture:

```bash
sudo tcpdump -A -r /tmp/web01-https.pcap | grep -E 'taruna01|LatihanHTTP2026' || echo 'Tidak terlihat dalam payload TLS terenkripsi'
```

Hasil grep negatif **bukan** bukti tunggal keamanan: lihat pula TLS handshake, sertifikat, dan konfigurasi redirect. Capture HTTPS tidak otomatis menyembunyikan alamat IP, port dan semua metadata.

## 6. Validator / flag

Pada Blue Team, dari folder paket:

```bash
sudo bash validate_web01.sh
```

Saat semua tes lolos, keluaran: `FLAG{WEB01_HTTPS_SECURED}`. Validator lokal cocok untuk **praktikum**, bukan anti-cheat ujian tingkat lanjut karena peserta sudo dapat membaca file/flag. Untuk kompetisi formal, jalankan penilaian di mesin terpisah.

## 7. Troubleshooting

- **Kali tidak resolve domain:** `getent hosts web01.lab.example.com`, ulangi pemetaan `/etc/hosts` di Kali.
- **No route/timeout:** cek `ip -4 addr`, `ip route`, VLAN/virtual switch, dan firewall. IP Blue harus benar-benar aktif di Ubuntu.
- **404 PCAP:** pastikan setup dijalankan dan `ls -l /var/www/web01/public/training/login-http.pcap`.
- **SSL certificate problem:** cek CA publik sudah terpasang Kali dan `sudo update-ca-certificates`, SAN memakai FQDN, dan tanggal sistem VM masuk akal. Jangan gunakan `-k` untuk meloloskan uji.
- **Apache gagal restart:** `sudo apache2ctl configtest`, `sudo journalctl -u apache2 -n 60 --no-pager`, `sudo ss -lntp`.
- **Perintah SCP permission denied:** gunakan path publik `/usr/local/share/ca-certificates/web01-lab-ca.crt`, bukan folder `/opt/web01-ca` yang root-only.
- **Tidak muncul trafik Kali dalam capture:** gunakan `-i any` pada Blue Team, atau analisis PCAP contoh. Periksa jumlah paket dan filter.
- **Port 443 tidak aktif:** aktifkan `web01-https.conf`, mod `ssl`, lalu reload.
- **Setup ulang setelah secure:** `sudo bash setup.sh` sengaja kembali ke mode HTTP-only untuk latihan; catat bahwa aplikasi kembali rentan.

## 8. Kriteria penerimaan

Setup harus idempotent secara praktis (CA/cert tidak diubah jika sudah ada), HTTP awal dapat login dummy, PCAP memuat data dummy, CA private tidak dibuka, HTTPS dapat diaktifkan, chain dan SAN lolos verifikasi Kali, HTTP redirect, login tetap sukses, dan validator mencetak flag. Validasi pada VM aktual tetap harus dilakukan sebelum ujian karena paket dibuat tanpa menjalankan VM Ubuntu/Kali milik pengguna.

## Troubleshooting: dpkg terkunci unattended-upgrades

Jika `Could not get lock /var/lib/dpkg/lock-frontend` muncul, Ubuntu sedang memperbarui paket. Jangan hapus lock. Installer kini menunggu sampai 5 menit sebelum `apt-get update` dan `apt-get install`; instalasi juga memakai `DPkg::Lock::Timeout=300`. Bila masih gagal, periksa `ps aux | grep -E 'apt|dpkg|unattended'` dan `sudo systemctl status unattended-upgrades`, biarkan proses selesai, lalu ulangi `sudo bash setup.sh`.

## Pembaruan installer (Oktober 2026)

- Blue Team: `sudo bash setup.sh` aman untuk diulang tanpa mengembalikan instalasi yang sudah dalam mode HTTPS menjadi HTTP-only. `--reset-http` secara sengaja mengembalikan kondisi rentan. `--secure` mengaktifkan HTTPS; `--status` membaca status tanpa mengubah konfigurasi.
- Kali: `sudo bash setup_kali.sh ubuntu` melakukan koneksi SSH interaktif terlebih dahulu agar verifikasi fingerprint pertama tidak gagal dengan `Host key verification failed` saat SCP. Cocokkan fingerprint dengan `sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` di Ubuntu sebelum menyetujui.
- Jika terdapat kegagalan SSH, pastikan akun `ubuntu` boleh login, layanan SSH aktif, TCP/22 dapat diakses Kali, dan fingerprint cocok. Jangan menghapus `known_hosts` atau mematikan pemeriksaan host key hanya agar instalasi berhasil.
- Domain di `/etc/hosts` dan sertifikat CA internal bersifat lokal untuk masing-masing VM, tidak menggantikan konfigurasi IP statis jaringan.
