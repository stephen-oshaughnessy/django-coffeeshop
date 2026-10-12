#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/vagrant/coffeeshopsite"
SCRIPTS_DIR="$APP_DIR"      # use the repo copy of the scripts
cd "$APP_DIR"

# 0) Config & env
if [ -f /secrets/config.env ]; then
  # shellcheck disable=SC1091
  source /secrets/config.env
else
  echo "ERROR: /secrets/config.env not found. Please create it with DBOWNER and DBOWNERPWD (and optionally DBNAME, SECRET_KEY)." >&2
  exit 1
fi

DBNAME="${DBNAME:-coffeeshop}"
# Generate a SECRET_KEY if not provided (fine for lab)
if [ -z "${SECRET_KEY:-}" ]; then
  SECRET_KEY="$(python3 - <<'PY'
import secrets; print(secrets.token_urlsafe(50))
PY
)"
fi

# 1) Ensure PostgreSQL is reachable and DB role exists
if ! sudo -u postgres psql -tAc "SELECT 1" >/dev/null 2>&1; then
  echo "ERROR: PostgreSQL service is not reachable as 'postgres'. Is it installed/running?" >&2
  exit 1
fi

# Create DB owner if missing
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${DBOWNER}'" | grep -q 1; then
  sudo -u postgres psql -c "CREATE ROLE ${DBOWNER} LOGIN PASSWORD '${DBOWNERPWD}';"
fi

# 2) Recreate database
# WITH (FORCE) disconnects any open sessions (e.g. Apache) that would block the drop
sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${DBNAME} WITH (FORCE);"
sudo -u postgres psql -c "CREATE DATABASE ${DBNAME} OWNER ${DBOWNER};"
sudo -u postgres psql -c "ALTER DATABASE ${DBNAME} OWNER TO ${DBOWNER};"

# 3) Migrate as the web user with required env
sudo -u www-data env SECRET_KEY="$SECRET_KEY" DBOWNER="$DBOWNER" DBOWNERPWD="$DBOWNERPWD" \
  python3 manage.py migrate --noinput

# 4) Seed data using your helper scripts (run from repo path)
[ -x "$SCRIPTS_DIR/create_users.sh" ]   && sudo -u www-data bash "$SCRIPTS_DIR/create_users.sh"   || true
[ -x "$SCRIPTS_DIR/loaddata.sh" ]       && sudo -u www-data bash "$SCRIPTS_DIR/loaddata.sh"       || true
[ -x "$SCRIPTS_DIR/collectstatic.sh" ]  && sudo -u www-data bash "$SCRIPTS_DIR/collectstatic.sh"  || \
  sudo -u www-data env SECRET_KEY="$SECRET_KEY" DBOWNER="$DBOWNER" DBOWNERPWD="$DBOWNERPWD" \
    python3 manage.py collectstatic --noinput || true

# 5) Restart Apache (systemd or no-systemd)
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart apache2
else
  sudo apachectl -k restart
fi

sudo chmod +x /vagrant/coffeeshopsite/rebuild_database.sh


echo "Database rebuilt and app restarted."
