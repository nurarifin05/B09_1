#!/usr/bin/env bash
# WEB01 Ubuntu 24.04 installer - lab terisolasi, kredensial dummy saja.
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
DOMAIN='web01.lab.example.com'
IP='192.168.36.233'
RED_IP='192.168.36.248'
WEB='/var/www/web01/public'
CERT='/etc/ssl/web01'
CA='/opt/web01-ca'
STATE='/var/lib/web01'
MODE="${1:-install}"
log(){ printf '\n[WEB01] %s\n' "$*"; }
die(){ echo "[ERROR] $*" >&2; exit 1; }
trap 'echo "[ERROR] Baris $LINENO gagal (exit $?). Periksa pesan tepat di atas; untuk error apt, cek unattended-upgrades; untuk Apache, cek journalctl -u apache2." >&2' ERR
[[ $EUID == 0 ]] || die 'Jalankan: sudo bash setup.sh'
[[ -f /etc/os-release ]] && . /etc/os-release
[[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 24.04 ]] || die 'Script ini ditujukan untuk Ubuntu Server 24.04.'
[[ "$MODE" == install || "$MODE" == --secure || "$MODE" == --status || "$MODE" == --reset-http ]] || die 'Argumen: [install|--secure|--status|--reset-http]'
check_hosts(){
  if ! grep -Eq "^[[:space:]]*$IP[[:space:]].*(^|[[:space:]])${DOMAIN//./\.}([[:space:]]|$)" /etc/hosts; then
    sed -i "/[[:space:]]${DOMAIN//./\.}\([[:space:]]\|$\)/d" /etc/hosts
    printf '%s %s\n' "$IP" "$DOMAIN" >> /etc/hosts
  fi
}
status(){
  echo "Domain: $DOMAIN -> $IP"
  getent hosts "$DOMAIN" || true
  systemctl is-active apache2 || true
  apache2ctl -S 2>/dev/null || true
  curl -sS --noproxy '*' -o /dev/null -w 'HTTP: %{http_code}\n' --resolve "$DOMAIN:80:$IP" "http://$DOMAIN/" || true
  if systemctl is-active --quiet apache2 && ss -ltn | grep -qE ":[4]43[[:space:]]"; then
    curl -sS --noproxy '*' -o /dev/null -w 'HTTPS: %{http_code}\n' --resolve "$DOMAIN:443:$IP" "https://$DOMAIN/" || echo "HTTPS belum dapat diverifikasi"
  else
    echo "HTTPS: NONAKTIF (normal pada tahap awal CTF)"
  fi
}
if [[ "$MODE" == --status ]]; then status; exit 0; fi
if [[ "$MODE" == --secure ]]; then
  [[ -f /etc/apache2/sites-available/web01-https.conf ]] || die 'Jalankan setup.sh terlebih dahulu.'
  a2enmod ssl headers >/dev/null
  a2ensite web01-https.conf >/dev/null
  # Apache port 80 hanya redirect; file statis PCAP tidak dipaksakan HTTPS pada fase awal.
  cat > /etc/apache2/sites-available/web01-http.conf <<EOF
<VirtualHost *:80>
 ServerName $DOMAIN
 Redirect permanent / https://$DOMAIN/
 ErrorLog \${APACHE_LOG_DIR}/web01_http_error.log
 CustomLog \${APACHE_LOG_DIR}/web01_http_access.log combined
</VirtualHost>
EOF
  apache2ctl configtest
  systemctl reload apache2
  log 'Mode HTTPS aktif; instal sertifikat CA di Kali secara terpisah.'
  status
  exit 0
fi
log 'Memeriksa IP pada Blue Team'
if ! ip -4 addr show | grep -Fq "$IP/"; then
  echo "[PERINGATAN] IP $IP tidak tampak di antarmuka; atur IP statis melalui Netplan/hypervisor sebelum memakai lab."
fi
log 'Instal dependensi apt'
# Tunggu lock dpkg/apt milik unattended-upgrades, tanpa menghapus lock file.
# apt-get install menggunakan DPkg::Lock::Timeout; apt-get update dapat memakai lock lists.
wait_apt_locks(){
  local attempt
  for attempt in $(seq 1 60); do
    if ! fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1; then
      return 0
    fi
    echo "[WEB01] APT sedang digunakan proses lain; percobaan $attempt/60 (tunggu 5 detik)..."
    sleep 5
  done
  die 'APT masih terkunci setelah 5 menit. Periksa: ps aux | grep -E "apt|dpkg|unattended"; jangan hapus lock.'
}
wait_apt_locks
apt-get update
wait_apt_locks
apt-get -o DPkg::Lock::Timeout=300 install -y apache2 libapache2-mod-php php-cli openssl curl tcpdump ca-certificates python3 iproute2 iputils-ping unzip openssh-server
systemctl enable --now ssh >/dev/null
log 'Menyiapkan domain /etc/hosts'
check_hosts
log 'Membuat folder dan login dummy'
install -d -m 755 "$WEB/training" "$CERT"
install -d -m 700 "$CA" "$STATE"
cat > "$WEB/index.php" <<'PHP'
<?php
header('Cache-Control: no-store');
?><!doctype html><html lang="id"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>SIM Akademik Taruna - WEB01</title><style>body{font-family:system-ui;background:#eef2f8;display:grid;place-items:center;min-height:100vh}main{background:#fff;padding:2rem;border-radius:1rem;width:90%;max-width:480px;box-shadow:0 12px 30px #2233}label,input,button{display:block;width:100%;box-sizing:border-box;margin:12px 0;padding:10px}button{background:#123b71;color:#fff;border:0;border-radius:6px}</style></head><body><main><h1>Sistem Informasi Akademik Taruna</h1><p>WEB-01: HTTP Credential Exposure</p><form method="post" action="/login.php"><label>Username<input name="username" required></label><label>Password<input type="password" name="password" required></label><button>Masuk</button></form><small>Gunakan akun dummy khusus lab.</small></main></body></html>
PHP
cat > "$WEB/login.php" <<'PHP'
<?php
header('Content-Type: text/html; charset=UTF-8');
header('Cache-Control: no-store');
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {http_response_code(405);header('Allow: POST');exit('POST only');}
$u = (string)($_POST['username'] ?? '');
$p = (string)($_POST['password'] ?? '');
$ok = hash_equals('taruna01',$u) && hash_equals('LatihanHTTP2026!',$p);
http_response_code($ok ? 200 : 401);
?><!doctype html><html lang="id"><meta charset="utf-8"><title>Login WEB01</title><body><h1><?= $ok ? 'Login dummy berhasil' : 'Login dummy gagal' ?></h1><a href="/">Kembali</a></body></html>
PHP
chmod -R a+rX "$WEB"
log 'Membuat Root CA internal dan server certificate (server key tidak dipublikasi)'
umask 077
if [[ ! -s "$CA/ca.key" || ! -s "$CA/ca.crt" ]]; then
  openssl req -x509 -newkey rsa:3072 -nodes -sha256 -days 3650 -keyout "$CA/ca.key" -out "$CA/ca.crt" -subj '/CN=WEB01 Lab Root CA/O=WEB01 Training' -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,keyCertSign,cRLSign'
fi
if [[ ! -s "$CERT/server.key" || ! -s "$CERT/server.crt" ]]; then
  openssl req -new -newkey rsa:3072 -nodes -keyout "$CERT/server.key" -out "$CERT/server.csr" -subj "/CN=$DOMAIN/O=WEB01 Training"
  cat > "$CERT/server.ext" <<EOF
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:$DOMAIN,IP:$IP
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF
  openssl x509 -req -in "$CERT/server.csr" -CA "$CA/ca.crt" -CAkey "$CA/ca.key" -CAcreateserial -out "$CERT/server.crt" -days 365 -sha256 -extfile "$CERT/server.ext"
fi
chmod 600 "$CA/ca.key" "$CERT/server.key"
chmod 644 "$CA/ca.crt" "$CERT/server.crt"
install -m 644 "$CA/ca.crt" /usr/local/share/ca-certificates/web01-lab-ca.crt
update-ca-certificates >/dev/null
log 'Menyiapkan Apache (mempertahankan mode aman bila sudah aktif)'
cat > /etc/apache2/sites-available/web01-http.conf <<EOF
<VirtualHost *:80>
 ServerName $DOMAIN
 DocumentRoot $WEB
 <Directory $WEB>
  Options -Indexes -FollowSymLinks
  AllowOverride None
  Require all granted
 </Directory>
 ErrorLog \${APACHE_LOG_DIR}/web01_http_error.log
 CustomLog \${APACHE_LOG_DIR}/web01_http_access.log combined
</VirtualHost>
EOF
cat > /etc/apache2/sites-available/web01-https.conf <<EOF
<VirtualHost *:443>
 ServerName $DOMAIN
 DocumentRoot $WEB
 SSLEngine on
 SSLCertificateFile $CERT/server.crt
 SSLCertificateKeyFile $CERT/server.key
 SSLProtocol -all +TLSv1.2 +TLSv1.3
 Header always set Strict-Transport-Security "max-age=300"
 <Directory $WEB>
  Options -Indexes -FollowSymLinks
  AllowOverride None
  Require all granted
 </Directory>
 ErrorLog \${APACHE_LOG_DIR}/web01_https_error.log
 CustomLog \${APACHE_LOG_DIR}/web01_https_access.log combined
</VirtualHost>
EOF
# Mode install sekarang idempotent: jangan mereset HTTPS yang telah diamankan.
# Reset eksplisit hanya dengan --reset-http.
KEEP_SECURE=false
if [[ "$MODE" != --reset-http && -e /etc/apache2/sites-enabled/web01-https.conf ]]; then
  KEEP_SECURE=true
  log 'HTTPS telah aktif: konfigurasi hardening dipertahankan saat install ulang.'
fi
a2enmod ssl headers >/dev/null
a2dissite 000-default.conf default-ssl.conf >/dev/null 2>&1 || true
if [[ "$KEEP_SECURE" == true ]]; then
  # Jangan timpa perubahan instructor/peserta yang sudah aktif:
  cat > /etc/apache2/sites-available/web01-http.conf <<EOF
<VirtualHost *:80>
 ServerName $DOMAIN
 Redirect permanent / https://$DOMAIN/
 ErrorLog \${APACHE_LOG_DIR}/web01_http_error.log
 CustomLog \${APACHE_LOG_DIR}/web01_http_access.log combined
</VirtualHost>
EOF
  a2ensite web01-https.conf >/dev/null
else
  a2dissite web01-https.conf >/dev/null 2>&1 || true
fi
a2ensite web01-http.conf >/dev/null
apache2ctl configtest
systemctl enable --now apache2 >/dev/null
systemctl reload apache2
if command -v ufw >/dev/null && ufw status | grep -q 'Status: active'; then
  ufw allow from "$RED_IP" to any port 80 proto tcp >/dev/null
  ufw allow from "$RED_IP" to any port 443 proto tcp >/dev/null
  echo '[WEB01] UFW aktif: mengizinkan 80/443 khusus IP Kali.'
fi
log 'Menghasilkan PCAP awal pada interface loopback (akun dummy)'
PCAP="$WEB/training/login-http.pcap"
if [[ ! -s "$PCAP" && "$KEEP_SECURE" == false ]]; then
  timeout 10 tcpdump -i lo -U -s 0 -w "$PCAP" 'tcp port 80' >/dev/null 2>&1 & CAP_PID=$!
  sleep 2
  curl -fsS --noproxy '*' --resolve "$DOMAIN:80:127.0.0.1" -d 'username=taruna01&password=LatihanHTTP2026%21' "http://$DOMAIN/login.php" >/dev/null
  wait "$CAP_PID" || true
  [[ -s "$PCAP" ]] || die 'PCAP gagal dibuat, cek tcpdump.'
fi
[[ -s "$PCAP" ]] && chmod 644 "$PCAP" || log "PCAP awal belum tersedia; buat saat mode HTTP awal."
log 'Pemeriksaan akhir tahap awal'
HTTP_CODE="$(curl -sS --noproxy '*' -o /dev/null -w '%{http_code}' --resolve "$DOMAIN:80:127.0.0.1" "http://$DOMAIN/")"
if [[ "$KEEP_SECURE" == true ]]; then
  [[ "$HTTP_CODE" == 301 ]] || die "HTTP harus redirect 301 (didapat $HTTP_CODE)"
else
  [[ "$HTTP_CODE" == 200 ]] || die "HTTP belum menghasilkan 200 (didapat $HTTP_CODE)"
fi
openssl verify -CAfile "$CA/ca.crt" "$CERT/server.crt"
status
cat <<EOF

=== LAB READY: mode terdeteksi (lihat status di atas) ===
Blue Team : $IP
Red Team  : $RED_IP
URL       : http://$DOMAIN/
Akun dummy: taruna01 / LatihanHTTP2026!
PCAP      : http://$DOMAIN/training/login-http.pcap
CA PUBLIK : $CA/ca.crt  (AMAN dipindahkan melalui SCP)
KUNCI CA  : $CA/ca.key  (JANGAN disalin atau dibagikan)

Setelah soal analisis selesai, peserta dapat melakukan hardening:
  sudo bash setup.sh --secure
  # Reset ke HTTP awal HANYA jika disengaja:
  sudo bash setup.sh --reset-http
  sudo bash validate_web01.sh

Perhatian: Kali harus mengatur /etc/hosts dan trust CA sendiri.
EOF
