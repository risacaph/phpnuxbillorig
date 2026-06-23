#!/usr/bin/env bash
#
# PHPNuxBill — Proxmox VE LXC installer
# ---------------------------------------------------------------------------
# Run this ON A PROXMOX VE HOST (not inside a container). It creates a Debian
# 12 LXC container and installs PHPNuxBill (Apache + MariaDB + PHP 8.2) inside
# it, imports the database, sets up cron jobs and finishes with a working
# admin login.
#
# Usage:
#   bash proxmox-install.sh
#
# Everything is configurable through environment variables, e.g.:
#   CTID=120 CT_HOSTNAME=billing DISK_GB=12 RAM_MB=2048 \
#   NET=192.168.1.50/24 GATEWAY=192.168.1.1 bash proxmox-install.sh
#
# Re-run with a different REPO_BRANCH to track your release branch once the
# feature/security work is merged into main.
# ---------------------------------------------------------------------------

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration (override any of these via the environment)
# ---------------------------------------------------------------------------
CTID="${CTID:-}"                       # container id; auto-picks next free id if empty
CT_HOSTNAME="${CT_HOSTNAME:-phpnuxbill}"  # container hostname (avoid the host's own $HOSTNAME)
DISK_GB="${DISK_GB:-8}"                # rootfs size in GB
RAM_MB="${RAM_MB:-1024}"               # memory in MB
CORES="${CORES:-2}"                    # cpu cores
BRIDGE="${BRIDGE:-vmbr0}"              # network bridge
STORAGE="${STORAGE:-local-lvm}"        # storage for the container rootfs
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"  # storage that holds LXC templates
NET="${NET:-dhcp}"                     # "dhcp" or a static CIDR e.g. 192.168.1.50/24
GATEWAY="${GATEWAY:-}"                 # gateway IP, required when NET is static
NAMESERVER="${NAMESERVER:-}"           # optional DNS server for the container
CT_PASSWORD="${CT_PASSWORD:-}"         # container root password; random if empty
UNPRIVILEGED="${UNPRIVILEGED:-1}"      # 1 = unprivileged container (recommended)

REPO_URL="${REPO_URL:-https://github.com/risacaph/phpnuxbillorig.git}"
REPO_BRANCH="${REPO_BRANCH:-claude/adoring-wozniak-bx5m24}"

DB_NAME="${DB_NAME:-phpnuxbill}"
DB_USER="${DB_USER:-phpnuxbill}"
DB_PASS="${DB_PASS:-}"                 # random if empty

WEBROOT="/var/www/html"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'; BLU=$'\e[34m'; CLR=$'\e[0m'
msg()  { echo "${BLU}==>${CLR} $*"; }
ok()   { echo "${GRN}  ✓${CLR} $*"; }
warn() { echo "${YLW}  !${CLR} $*"; }
die()  { echo "${RED}ERROR:${CLR} $*" >&2; exit 1; }

rand() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${1:-20}"; }

trap 'die "installation failed on line $LINENO"' ERR

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || die "run this script as root on the Proxmox VE host"
command -v pct       >/dev/null 2>&1 || die "'pct' not found — run this on a Proxmox VE host"
command -v pveam     >/dev/null 2>&1 || die "'pveam' not found — run this on a Proxmox VE host"
command -v pvesh     >/dev/null 2>&1 || die "'pvesh' not found — run this on a Proxmox VE host"

if [ "$NET" != "dhcp" ] && [ -z "$GATEWAY" ]; then
    die "NET is static ($NET) but GATEWAY is empty — set GATEWAY=<your-gateway-ip>"
fi

# Secrets
[ -n "$CT_PASSWORD" ] || CT_PASSWORD="$(rand 16)"
[ -n "$DB_PASS" ]     || DB_PASS="$(rand 24)"

# Container id
if [ -z "$CTID" ]; then
    CTID="$(pvesh get /cluster/nextid)"
fi
pct status "$CTID" >/dev/null 2>&1 && die "container $CTID already exists — set CTID to a free id"

msg "Container ID : $CTID"
msg "Hostname     : $CT_HOSTNAME"
msg "Resources    : ${CORES} cores, ${RAM_MB} MB RAM, ${DISK_GB} GB disk"
msg "Network      : $NET${GATEWAY:+ (gw $GATEWAY)} on $BRIDGE"
msg "Source       : $REPO_URL @ $REPO_BRANCH"

# ---------------------------------------------------------------------------
# Ensure a Debian 12 template is available
# ---------------------------------------------------------------------------
msg "Updating template catalogue..."
pveam update >/dev/null 2>&1 || warn "pveam update failed (continuing with cached list)"

TEMPLATE="$(pveam available --section system 2>/dev/null \
    | awk '{print $2}' \
    | grep -E '^debian-12-standard_.*_amd64\.tar\.(zst|gz)$' \
    | sort -V | tail -1)"
[ -n "$TEMPLATE" ] || die "could not find a debian-12-standard template in the catalogue"

if ! pveam list "$TEMPLATE_STORAGE" 2>/dev/null | grep -q "$TEMPLATE"; then
    msg "Downloading template $TEMPLATE ..."
    pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"
fi
TEMPLATE_REF="$TEMPLATE_STORAGE:vztmpl/$TEMPLATE"
ok "Template ready: $TEMPLATE_REF"

# ---------------------------------------------------------------------------
# Create + start the container
# ---------------------------------------------------------------------------
if [ "$NET" = "dhcp" ]; then
    NETCONF="name=eth0,bridge=${BRIDGE},ip=dhcp"
else
    NETCONF="name=eth0,bridge=${BRIDGE},ip=${NET},gw=${GATEWAY}"
fi

msg "Creating container..."
pct create "$CTID" "$TEMPLATE_REF" \
    --hostname "$CT_HOSTNAME" \
    --cores "$CORES" \
    --memory "$RAM_MB" \
    --swap "$RAM_MB" \
    --rootfs "${STORAGE}:${DISK_GB}" \
    --net0 "$NETCONF" \
    ${NAMESERVER:+--nameserver "$NAMESERVER"} \
    --features nesting=1 \
    --unprivileged "$UNPRIVILEGED" \
    --onboot 1 \
    --ostype debian \
    --password "$CT_PASSWORD" >/dev/null
ok "Container $CTID created"

msg "Starting container..."
pct start "$CTID" >/dev/null

msg "Waiting for network..."
for i in $(seq 1 30); do
    if pct exec "$CTID" -- bash -lc 'getent hosts deb.debian.org >/dev/null 2>&1'; then
        ok "Network is up"
        break
    fi
    [ "$i" -eq 30 ] && die "container has no network after 60s — check bridge/DHCP/gateway"
    sleep 2
done

# ---------------------------------------------------------------------------
# Build the in-container provisioning script and run it
# ---------------------------------------------------------------------------
INNER="$(mktemp /tmp/phpnuxbill-inner.XXXXXX.sh)"
trap 'rm -f "$INNER"' EXIT

{
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    echo 'export DEBIAN_FRONTEND=noninteractive'
    # inject host-side values, safely quoted
    echo "REPO_URL=$(printf '%q' "$REPO_URL")"
    echo "REPO_BRANCH=$(printf '%q' "$REPO_BRANCH")"
    echo "DB_NAME=$(printf '%q' "$DB_NAME")"
    echo "DB_USER=$(printf '%q' "$DB_USER")"
    echo "DB_PASS=$(printf '%q' "$DB_PASS")"
    echo "WEBROOT=$(printf '%q' "$WEBROOT")"
    cat <<'INNEREOF'

say() { echo "    -> $*"; }

say "Installing packages (Apache, MariaDB, PHP 8.2)..."
apt-get update -qq
apt-get install -y -qq \
    apache2 mariadb-server git unzip cron ca-certificates \
    php php-cli libapache2-mod-php \
    php-mysql php-gd php-curl php-mbstring php-xml php-zip php-bcmath php-intl \
    >/dev/null

systemctl enable --now mariadb >/dev/null 2>&1 || true
systemctl enable --now apache2 >/dev/null 2>&1 || true
systemctl enable --now cron    >/dev/null 2>&1 || true

say "Waiting for MariaDB..."
for i in $(seq 1 30); do
    mysqladmin ping >/dev/null 2>&1 && break
    [ "$i" -eq 30 ] && { echo "MariaDB did not start"; exit 1; }
    sleep 1
done

say "Fetching PHPNuxBill ($REPO_BRANCH)..."
rm -rf "$WEBROOT"
git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$WEBROOT" >/dev/null 2>&1 \
    || git clone --depth 1 "$REPO_URL" "$WEBROOT" >/dev/null 2>&1
cd "$WEBROOT"

# Page content lives in pages_template until first install
if [ -d pages_template ] && [ ! -d pages ]; then
    cp -a pages_template pages
fi

say "Creating database and user..."
mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

say "Importing schema..."
mysql "${DB_NAME}" < "${WEBROOT}/install/phpnuxbill.sql"

say "Writing config.php..."
cat > "${WEBROOT}/config.php" <<PHPEOF
<?php
\$protocol = (!empty(\$_SERVER['HTTPS']) && \$_SERVER['HTTPS'] !== 'off' || (isset(\$_SERVER['SERVER_PORT']) && \$_SERVER['SERVER_PORT'] == 443)) ? "https://" : "http://";
\$host = isset(\$_SERVER['HTTP_HOST']) ? \$_SERVER['HTTP_HOST'] : (isset(\$_SERVER['SERVER_NAME']) ? \$_SERVER['SERVER_NAME'] : 'localhost');
\$baseDir = rtrim(dirname(\$_SERVER['SCRIPT_NAME']), '/\\\\');
define('APP_URL', \$protocol . \$host . \$baseDir);

\$_app_stage = 'Live';

\$db_host = 'localhost';
\$db_port = '';
\$db_user = '${DB_USER}';
\$db_pass = '${DB_PASS}';
\$db_name = '${DB_NAME}';

error_reporting(E_ERROR);
ini_set('display_errors', 0);
ini_set('display_startup_errors', 0);
PHPEOF

say "Configuring Apache..."
a2enmod rewrite >/dev/null 2>&1 || true
# Activate the shipped firewall/rewrite rules
if [ -f "${WEBROOT}/.htaccess_firewall" ] && [ ! -f "${WEBROOT}/.htaccess" ]; then
    cp "${WEBROOT}/.htaccess_firewall" "${WEBROOT}/.htaccess"
fi
cat > /etc/apache2/sites-available/phpnuxbill.conf <<CONF
<VirtualHost *:80>
    DocumentRoot ${WEBROOT}
    <Directory ${WEBROOT}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/phpnuxbill-error.log
    CustomLog \${APACHE_LOG_DIR}/phpnuxbill-access.log combined
</VirtualHost>
CONF
a2dissite 000-default.conf >/dev/null 2>&1 || true
a2ensite phpnuxbill.conf >/dev/null 2>&1 || true
systemctl reload apache2

say "Setting permissions..."
chown -R www-data:www-data "$WEBROOT"
find "$WEBROOT" -type d -exec chmod 755 {} \;
find "$WEBROOT" -type f -exec chmod 644 {} \;

say "Locking down the web installer..."
rm -rf "${WEBROOT}/install"

say "Installing cron jobs..."
cat > /etc/cron.d/phpnuxbill <<CRON
# PHPNuxBill scheduled tasks
*/5 * * * * www-data /usr/bin/php ${WEBROOT}/system/cron.php >/dev/null 2>&1
0 8 * * *   www-data /usr/bin/php ${WEBROOT}/system/cron_reminder.php >/dev/null 2>&1
CRON
chmod 644 /etc/cron.d/phpnuxbill

# Persist credentials for reference
cat > /root/phpnuxbill.creds <<CREDS
PHPNuxBill installation
=======================
Admin login : admin / admin   (change this immediately)
Database    : ${DB_NAME}
DB user     : ${DB_USER}
DB password : ${DB_PASS}
Web root    : ${WEBROOT}
CREDS
chmod 600 /root/phpnuxbill.creds

say "Done inside container."
INNEREOF
} > "$INNER"

msg "Provisioning inside the container (this can take a few minutes)..."
pct push "$CTID" "$INNER" /root/phpnuxbill-inner.sh >/dev/null
pct exec "$CTID" -- bash /root/phpnuxbill-inner.sh
pct exec "$CTID" -- rm -f /root/phpnuxbill-inner.sh

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
IP="$(pct exec "$CTID" -- bash -lc "hostname -I | awk '{print \$1}'" 2>/dev/null | tr -d '\r' || true)"

echo
echo "${GRN}============================================================${CLR}"
echo "${GRN} PHPNuxBill is installed in LXC ${CTID} (${CT_HOSTNAME})${CLR}"
echo "${GRN}============================================================${CLR}"
echo "  Admin portal : http://${IP:-<container-ip>}/admin"
echo "  Login        : admin / admin   ${YLW}(change immediately)${CLR}"
echo
echo "  DB name      : ${DB_NAME}"
echo "  DB user      : ${DB_USER}"
echo "  DB password  : ${DB_PASS}"
echo "  Container root password : ${CT_PASSWORD}"
echo
echo "  Credentials also saved in the container at /root/phpnuxbill.creds"
echo "  Enter the container with: ${BLU}pct enter ${CTID}${CLR}"
echo
warn "First steps: log in, change the admin password, then add your router"
warn "under Network → Routers and verify Active Connections / PoE."
echo
