#!/usr/bin/env bash
# Start the csthirdparty services. Safe to run repeatedly.
# Runs on every `vagrant up` and is also the container's start command, so the
# site comes back after `vagrant halt`, a Docker Desktop restart or a reboot.

service postgresql start
service apache2 start

# Django sends mail to localhost:25 (see EMAIL_PORT in settings.py)
if ! pgrep -f mailcatcher >/dev/null; then
  mailcatcher --ip 0.0.0.0 --smtp-port 25 --http-port 1080 >/dev/null
fi
