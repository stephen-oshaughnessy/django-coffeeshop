#!/usr/bin/env bash
# One-off provisioning for the csthirdparty Docker container.
# OS packages, Python packages and Mailcatcher are installed by the Dockerfile.
set -euo pipefail

APP_DIR="/vagrant/csthirdpartysite"

# shellcheck disable=SC1091
source /secrets/config.env

# Load the secrets in interactive shells too, so manage.py works after `vagrant ssh`
grep -q 'secrets/config.env' /home/vagrant/.bashrc || echo ". /secrets/config.env" >> /home/vagrant/.bashrc
usermod -a -G www-data vagrant

# ---- Python requirements (no-op unless requirements.txt has changed) ----
pip3 install --no-cache-dir -r "$APP_DIR/requirements.txt" -c /vagrant/constraints.txt

# ---- Apache: link project path & create vhost ----
[ -e /var/www/csthirdpartysite ] || ln -s "$APP_DIR" /var/www/csthirdpartysite

echo 'ServerName localhost' > /etc/apache2/conf-available/servername.conf
a2enconf servername >/dev/null

cat >/etc/apache2/sites-available/csthirdparty.conf <<'CONF'
<VirtualHost *:80>
    ServerName localhost

    # Django via mod_wsgi
    WSGIDaemonProcess csthirdparty python-path=/var/www/csthirdpartysite
    WSGIProcessGroup  csthirdparty
    WSGIScriptAlias / /var/www/csthirdpartysite/csthirdpartysite/wsgi.py

    # Static files
    Alias /static/ /var/www/csthirdpartysite/csthirdparty/static/
    <Directory /var/www/csthirdpartysite/csthirdparty/static>
        Require all granted
    </Directory>

    <Directory /var/www/csthirdpartysite/csthirdpartysite>
        <Files wsgi.py>
            Require all granted
        </Files>
    </Directory>

    ErrorLog  ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
CONF

a2enmod wsgi rewrite headers >/dev/null
a2ensite csthirdparty >/dev/null
a2dissite 000-default >/dev/null

# ---- Database ----
service postgresql start
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${DBOWNER}'" | grep -q 1; then
  sudo -u postgres psql -c "CREATE ROLE ${DBOWNER} LOGIN PASSWORD '${DBOWNERPWD}';"
  sudo -u postgres psql -c "ALTER ROLE ${DBOWNER} SET client_encoding TO 'utf8'; ALTER ROLE ${DBOWNER} SET timezone TO 'UTC';"
fi
sudo -u postgres psql -c "DROP DATABASE IF EXISTS csthirdparty WITH (FORCE);"
sudo -u postgres psql -c "CREATE DATABASE csthirdparty OWNER ${DBOWNER};"

cd "$APP_DIR"
sudo -u www-data python3 manage.py migrate --noinput
sudo -u www-data bash "$APP_DIR/create_users.sh"
sudo -u www-data bash "$APP_DIR/loaddata.sh"
sudo -u www-data bash "$APP_DIR/collectstatic.sh"

service apache2 restart

echo "✅ Provisioning complete:"
echo "   App:         http://localhost:8081"
echo "   Mailcatcher: http://localhost:1081"
