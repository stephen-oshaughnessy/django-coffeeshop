FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

# OS deps (the networking tools are used as the "attacker" side in later labs)
RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo tzdata ca-certificates locales \
    openssh-server \
    python3 python3-dev python3-pip python3-venv python3-setuptools python3-wheel \
    build-essential \
    postgresql postgresql-contrib libpq-dev \
    libsqlite3-dev \
    apache2 libapache2-mod-wsgi-py3 \
    curl git vim nano ruby-full rubygems-integration \
    telnet lsof net-tools iputils-ping netcat-openbsd nmap pwgen \
  && rm -rf /var/lib/apt/lists/*

# Python libs, pinned to known-good versions so every student gets the same build
COPY csthirdpartysite/requirements.txt constraints.txt /tmp/pip/
RUN pip3 install --no-cache-dir -r /tmp/pip/requirements.txt -c /tmp/pip/constraints.txt

# There is no systemd in the container, but the lab sheets use `systemctl` for
# apache2/postgresql. Provide a shim that maps to `service` so those work.
RUN printf '#!/bin/sh\n# Minimal systemctl shim (no systemd in this container).\nsvc="$2"\ncase "$svc" in\n  *.service) svc="${svc%%.service}";;\nesac\ncase "$1" in\n  start|stop|restart|reload|force-reload|status)\n    exec service "$svc" "$1";;\n  *)\n    echo "systemctl shim: ignoring: $*" >&2; exit 0;;\nesac\n' > /usr/local/bin/systemctl && \
    chmod 755 /usr/local/bin/systemctl

# Mailcatcher used by lab
RUN gem install mailcatcher --no-document

# Vagrant SSH user setup
RUN mkdir -p /var/run/sshd && \
    useradd -m -s /bin/bash vagrant && echo "vagrant:vagrant" | chpasswd && \
    chmod 755 /home/vagrant && \
    usermod -aG sudo vagrant && \
    echo "vagrant ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/zz-vagrant && \
    chmod 440 /etc/sudoers.d/zz-vagrant && \
    sed -ri 's/^#?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -ri 's@session\\s*required\\s*pam_loginuid.so@session optional pam_loginuid.so@g' /etc/pam.d/sshd && \
    printf "UseDNS no\nClientAliveInterval 180\nClientAliveCountMax 3\n" >> /etc/ssh/sshd_config

# Start the services whenever the container starts, then hand over to sshd
COPY reboot-provision.sh /usr/local/bin/start-services.sh
RUN chmod 755 /usr/local/bin/start-services.sh

EXPOSE 22
CMD ["/bin/bash", "-c", "/usr/local/bin/start-services.sh; exec /usr/sbin/sshd -D"]
