# Warkop Remote Multi-Server v3.5 Modular
# GNU General Public License v3.0
# Contributor: Babygore hdteam/MHL

Modularized layout of the original `warkopv3.3.sh` https://github.com/sigithdteam-lab/warkop-Remote-Multi-Server to make maintenance easier. 

## Structure

- `warkop.sh` - single entrypoint/loader
- `modules/00-core.sh` - configuration, helpers, package detection, common SSH helpers
- `modules/10-ssh.sh` - SSH key/connection management
- `modules/20-maintainer.sh` - server maintenance
- `modules/30-information.sh` - server information
- `modules/40-users.sh` - user management
- `modules/50-security.sh` - firewall, antivirus, SSL/security
- `modules/60-services.sh` - service management
- `modules/70-mail.sh` - mail/DNS checks
- `modules/80-network.sh` - local network tools
- `modules/90-menus.sh` - menus
- `modules/100-installation.sh` - server installation, tuning, farm provisioning
- `modules/99-main.sh` - initialization and main entry

## Run

```bash
chmod +x warkop.sh
./warkop.sh
```

`listserver.txt` should live beside `warkop.sh` unless `SERVER_LIST` is changed in `modules/00-core.sh`.

## Validation

Run:

```bash
bash -n warkop.sh
for f in modules/*.sh; do bash -n "$f" || exit 1; done
```

This package is a structural modularization of v3.3. It does not claim that every remote provisioning path has been integration-tested against every supported Linux distribution.

## v3.5 Hardening
- Central SSH timeout, keepalive and retry handling.
- Root/sudo-safe local package installation and correct OpenSSH package mapping.
- Removed `eval` from local network command execution.
- Username validation and safer password transport preparation.
- Farm server inputs are normalized to host-only values for NFS/DB/HAProxy.
- NFS uses `root_squash` and `/etc/fstab` entries are idempotent.
- Farm database credentials are generated and stored under `/root/.config/warkop/appdb.env` with restrictive permissions.
- Removed the `phpinfo()` test endpoint.
- Added runtime logging and a process lock to reduce accidental concurrent execution.


## v3.5 OS Detection & Command Adapter

Versi 3.5 menambahkan lapisan kompatibilitas OS untuk operasi remote. Setiap script yang dikirim melalui executor menerima OS adapter terlebih dahulu. Adapter membaca `/etc/os-release` dan mendeteksi family:

- Debian/Ubuntu family → `apt-get`
- RHEL/CentOS/Rocky/Alma/Fedora/Amazon family → `dnf` atau `yum`
- SUSE → `zypper`
- Alpine → `apk`
- Arch/Manjaro → `pacman`

Init/service manager juga dideteksi (`systemd`, `openrc`, atau `sysv`). Abstraksi utama remote:

- `warkop_pkg_update`
- `warkop_pkg_upgrade`
- `warkop_pkg_install`
- `warkop_pkg_clean`
- `warkop_service`
- `warkop_service_enable`
- `warkop_service_active`
- `warkop_detect_webserver`
- `warkop_detect_php_fpm_service`
- `warkop_detect_database`
- `warkop_firewall`

Dengan demikian command maintenance/service tidak lagi mengasumsikan `apt` atau `systemctl` pada semua server. Operasi instalasi aplikasi yang memang memiliki konfigurasi distro-spesifik tetap mempertahankan logic khusus di modul instalasi.

### Catatan kompatibilitas

OS yang tidak dikenali tidak akan dipaksa menjalankan command package manager. Script akan mengembalikan status unsupported. Untuk operasi network/firewall/database/webserver, command tetap menggunakan capability detection sehingga nama service/path dapat disesuaikan berdasarkan software yang benar-benar terpasang.
