#!/usr/bin/env bash
set -Eeuo pipefail
DOMAIN=web01.lab.example.com
SERVER_IP=192.168.36.233
BASE="https://$DOMAIN"
PCAP=/tmp/web01-https-validation-$$.pcap
fail(){ echo "[GAGAL] $*"; exit 1; }
pass(){ echo "[LULUS] $*"; }
[[ $EUID -eq 0 ]] || fail 'Jalankan sudo bash validate_web01.sh di Ubuntu Blue Team.'
trap 'rm -f "$PCAP"' EXIT
apache2ctl configtest >/dev/null 2>&1 || fail 'Konfigurasi Apache tidak valid.'
pass 'Konfigurasi Apache valid'
# Hostname+chain harus terverifikasi TANPA -k.
curl --silent --show-error --fail --noproxy '*' --resolve "$DOMAIN:443:$SERVER_IP" "$BASE/" >/dev/null || fail 'HTTPS gagal diverifikasi (CA, SAN, firewall, atau virtualhost).'
pass 'HTTPS + sertifikat CA dipercaya + hostname cocok'
status=$(curl --silent --noproxy '*' -o /dev/null -w '%{http_code}' --resolve "$DOMAIN:80:$SERVER_IP" "http://$DOMAIN/")
[[ "$status" =~ ^30[12378]$ ]] || fail "HTTP harus redirect 301/302/307/308 (dapat $status)."
location=$(curl --silent --noproxy '*' -D - -o /dev/null --resolve "$DOMAIN:80:$SERVER_IP" "http://$DOMAIN/" | tr -d '\r' | awk 'tolower($1)=="location:" {print $2; exit}')
[[ "$location" == "https://$DOMAIN/" ]] || fail "Location redirect salah: $location"
pass 'Port 80 redirect ke hostname HTTPS'
code=$(curl --silent --show-error --noproxy '*' -o /dev/null -w '%{http_code}' --resolve "$DOMAIN:443:$SERVER_IP" -d 'username=taruna01&password=LatihanHTTP2026%21' "$BASE/login.php")
[[ "$code" == 200 ]] || fail "Login HTTPS tidak sukses ($code)."
pass 'Login dummy berjalan di HTTPS'
# Sniff traffic lokal HOST: HTTPS payload tidak boleh berisi dummy plaintext.
timeout 8 tcpdump -i any -U -s 0 -w "$PCAP" "host $SERVER_IP and tcp port 443" >/dev/null 2>&1 & CAP_PID=$!
sleep 1
curl --silent --show-error --fail --noproxy '*' --resolve "$DOMAIN:443:$SERVER_IP" -d 'username=taruna01&password=LatihanHTTP2026%21' "$BASE/login.php" >/dev/null || fail 'Request HTTPS gagal.'
wait "$CAP_PID" || true
[[ -s "$PCAP" ]] || fail 'PCAP kosong: periksa interface/routing.'
if strings "$PCAP" | grep -Eq 'LatihanHTTP2026|taruna01'; then fail 'Kredensial terdeteksi plaintext pada capture TLS.'; fi
pass 'Capture TLS tidak menampilkan kredensial plaintext'
echo 'FLAG{WEB01_HTTPS_SECURED}'
