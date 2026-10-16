#!/usr/bin/env bash
# Jalankan dari Kali: sudo bash setup_kali.sh ubuntu
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
DOMAIN='web01.lab.example.com'
BLUE='192.168.36.233'
BLUE_USER="${1:-}"
[[ $EUID -eq 0 ]] || { echo '[ERROR] Jalankan menggunakan sudo.' >&2; exit 1; }
log(){ printf '\n[KALI] %s\n' "$*"; }
fail(){ echo "[ERROR] $*" >&2; exit 1; }
trap 'echo "[ERROR] setup_kali gagal pada baris $LINENO. Periksa pesan di atas." >&2' ERR

log 'Memasang dependensi, menunggu APT lock secara aman.'
apt-get -o DPkg::Lock::Timeout=300 update
apt-get -o DPkg::Lock::Timeout=300 install -y wireshark tshark tcpdump curl openssl ca-certificates openssh-client iputils-ping

log 'Memperbarui hosts tanpa membuat entri ganda.'
cp -n /etc/hosts /etc/hosts.web01.backup || true
sed -i '/[[:space:]]web01\.lab\.example\.com\([[:space:]]\|$\)/d' /etc/hosts
printf '%s %s\n' "$BLUE" "$DOMAIN" >> /etc/hosts

LOCAL_USER="${SUDO_USER:-root}"
if [[ "$LOCAL_USER" != root ]]; then
  HOME_DIR="$(getent passwd "$LOCAL_USER" | cut -d: -f6)"
else
  HOME_DIR=/root
fi
DEST="$HOME_DIR/web01-lab"
install -d -m 755 "$DEST"

if [[ -n "$BLUE_USER" ]]; then
  log "Membuka koneksi SSH pertama ke $BLUE_USER@$BLUE."
  echo 'Periksa fingerprint SSH server sebelum mengetik yes.'
  echo 'Di Ubuntu, fingerprint dapat dicek: sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub'
  echo 'Jika tampil pertanyaan authenticity, cocokkan fingerprint dengan Ubuntu lalu ketik yes.'
  # SSH interaktif dengan alokasi TTY: prompt host key terlihat (SCP sering gagal saat first-connect).
  # Jangan nonaktifkan StrictHostKeyChecking. Host key yang berubah tetap ditolak.
  [[ -r /dev/tty ]] || fail 'Dibutuhkan terminal interaktif untuk verifikasi fingerprint SSH.'
  if ! ssh -tt -o StrictHostKeyChecking=ask -o BatchMode=no \
    -o ConnectTimeout=12 -o NumberOfPasswordPrompts=3 \
    "$BLUE_USER@$BLUE" 'printf "[KALI] SSH Blue Team terverifikasi.\n"' </dev/tty; then
    fail 'Verifikasi/koneksi SSH gagal. Cek fingerprint, password user Ubuntu, SSH dan firewall.'
  fi
  log 'Mengambil sertifikat CA publik melalui SCP (SSH host sudah terverifikasi).'
  scp -o StrictHostKeyChecking=yes -o ConnectTimeout=12 \
    "$BLUE_USER@$BLUE:/usr/local/share/ca-certificates/web01-lab-ca.crt" \
    /usr/local/share/ca-certificates/web01-lab-ca.crt
  # Perlindungan dasar: pastikan benar CA certificate.
  openssl x509 -in /usr/local/share/ca-certificates/web01-lab-ca.crt -noout -subject -issuer -fingerprint -sha256
  log 'Bandingkan fingerprint CA di atas dengan Ubuntu: openssl x509 -in /usr/local/share/ca-certificates/web01-lab-ca.crt -noout -fingerprint -sha256'
  update-ca-certificates
else
  log 'Username SSH tidak diberikan: hanya menyiapkan Kali, CA belum ditransfer.'
fi

log 'Mengunduh PCAP HTTP awal dari server lab.'
if curl -fsS --noproxy '*' -o "$DEST/login-http.pcap" "http://$DOMAIN/training/login-http.pcap"; then
  log "PCAP tersimpan: $DEST/login-http.pcap"
else
  log 'PCAP tidak dapat diunduh melalui HTTP (bila server sudah --secure, unduh dengan HTTPS setelah trust CA).'
  if [[ -f /usr/local/share/ca-certificates/web01-lab-ca.crt ]]; then
    curl -fsS --noproxy '*' -o "$DEST/login-http.pcap" "https://$DOMAIN/training/login-http.pcap" || true
  fi
fi
if [[ "$LOCAL_USER" != root ]]; then chown -R "$LOCAL_USER:$(id -gn "$LOCAL_USER")" "$DEST"; fi
log 'Pengujian status tanpa memaksa HTTPS aktif.'
curl -sS --noproxy '*' -o /dev/null -w 'HTTP: %{http_code}\n' "http://$DOMAIN/" || true
if [[ -f /usr/local/share/ca-certificates/web01-lab-ca.crt ]]; then
  curl -fsS --noproxy '*' -o /dev/null -w 'HTTPS: %{http_code}\n' "https://$DOMAIN/" || echo '[KALI] HTTPS belum aktif: normal pada fase awal.'
fi
printf '\n[KALI] Selesai. Buka Wireshark: wireshark %s/login-http.pcap\n' "$DEST"
echo '[KALI] Filter: http.request.method == "POST"'
