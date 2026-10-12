#!/usr/bin/env bash
set -euo pipefail

# ---- systemctl shim for Docker ----
if ! command -v systemctl >/dev/null 2>&1; then
  systemctl() {
    case "$*" in
      *"restart apache2"*)    apachectl -k restart || true ;;
      *"reload apache2"*)     apachectl -k graceful || true ;;
      *"start apache2"*)      apachectl -k start || true ;;
      *"restart postgresql"*) pg_lsclusters | awk 'NR>1{print $1,$2}' | while read -r v n; do pg_ctlcluster "$v" "$n" restart || true; done ;;
      *"start postgresql"*)   pg_lsclusters | awk 'NR>1{print $1,$2}' | while read -r v n; do pg_ctlcluster "$v" "$n" start || true; done ;;
      *"restart mailcatcher"*) pkill -f mailcatcher || true; mailcatcher --smtp-ip 0.0.0.0 --http-ip 0.0.0.0 || true ;;
      *"start mailcatcher"*)  mailcatcher --smtp-ip 0.0.0.0 --http-ip 0.0.0.0 || true ;;
      *) true ;;
    esac
  }
fi

APP_DIR="/vagrant/coffeeshopsite"
SECRETS_DIR="/secrets"
cd "$APP_DIR"

echo "Ensuring scripts are executable…"
chmod +x "$APP_DIR"/*.sh 2>/dev/null || true

# ---- Secrets / env ----
if [ -f "$SECRETS_DIR/config.env" ]; then
  # shellcheck disable=SC1091
  source "$SECRETS_DIR/config.env"
else
  echo "Creating $SECRETS_DIR/config.env with lab defaults…"
  mkdir -p "$SECRETS_DIR"
  : "${DBOWNER:=dbuser}"
  : "${DBOWNERPWD:=dbpass}"
  : "${DBNAME:=coffeeshop}"
  : "${SECRET_KEY:=}"
  if [ -z "$SECRET_KEY" ]; then
    SECRET_KEY="$(python3 - <<'PY'
import secrets; print(secrets.token_urlsafe(50))
PY
)"
  fi
  cat > "$SECRETS_DIR/config.env" <<EOF
SECRET_KEY=$SECRET_KEY
DBOWNER=$DBOWNER
DBOWNERPWD=$DBOWNERPWD
DBNAME=$DBNAME
EOF
fi
# If settings.py calls: from dotenv import load_dotenv; load_dotenv('/secrets/config.env')
# …then manage.py sees these automatically.

# ---- Optional: install project requirements ----
if [ -f "$APP_DIR/requirements.txt" ]; then
  echo "Installing Python requirements.txt…"
  pip3 install --no-cache-dir -r "$APP_DIR/requirements.txt" -c /vagrant/constraints.txt
fi

# ---- Start PostgreSQL cluster if needed ----
echo "Starting PostgreSQL if needed…"
if command -v pg_lsclusters >/dev/null 2>&1; then
  pg_lsclusters | awk 'NR>1{print $1,$2,$4}' | while read -r ver name state; do
    [ "$state" = "online" ] || pg_ctlcluster "$ver" "$name" start || true
  done
fi

# Ensure DB role exists
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${DBOWNER}'" | grep -q 1; then
  sudo -u postgres psql -c "CREATE ROLE ${DBOWNER} LOGIN PASSWORD '${DBOWNERPWD}';" || true
fi

# ---- Apache: link project path & create vhost ----
# Use a stable path Apache can read; keep /vagrant as the source of truth
[ -d /var/www/coffeeshopsite ] || ln -s "$APP_DIR" /var/www/coffeeshopsite

# Also answer on 8080 inside the box, so `curl http://localhost:8080` gives the
# same result inside and outside the container
grep -q '^Listen 8080' /etc/apache2/ports.conf || echo 'Listen 8080' >> /etc/apache2/ports.conf
echo 'ServerName localhost' > /etc/apache2/conf-available/servername.conf
a2enconf servername >/dev/null

if [ ! -f /etc/apache2/sites-available/coffeeshop.conf ]; then
  cat >/etc/apache2/sites-available/coffeeshop.conf <<'CONF'
<VirtualHost *:80 *:8080>
    ServerName localhost

    # Django via mod_wsgi
    WSGIDaemonProcess coffeeshop python-path=/var/www/coffeeshopsite
    WSGIProcessGroup  coffeeshop
    WSGIScriptAlias / /var/www/coffeeshopsite/coffeeshopsite/wsgi.py

    # Static files
    Alias /static/ /var/www/coffeeshopsite/coffeeshop/static/
    <Directory /var/www/coffeeshopsite/coffeeshop/static>
        Require all granted
    </Directory>

    <Directory /var/www/coffeeshopsite/coffeeshopsite>
        <Files wsgi.py>
            Require all granted
        </Files>
    </Directory>

    # Standard log names, as used in the troubleshooting sheet
    ErrorLog  ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
CONF
fi

a2enmod wsgi rewrite >/dev/null 2>&1 || true
a2ensite coffeeshop >/dev/null 2>&1 || true
a2dissite 000-default >/dev/null 2>&1 || true

# ---- Rebuild DB & seed data (idempotent; also restarts Apache) ----
# Runs after the Apache setup because the seed scripts use /var/www/coffeeshopsite
bash "$APP_DIR/rebuild_database.sh"

echo "✅ Provisioning complete:"
echo "   App:        http://localhost:8080"
echo "   Mailcatcher: http://localhost:1080"
