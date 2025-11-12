# Starte vom offiziellen Nginx/WAF-Image
FROM owasp/modsecurity-crs:nginx

USER root
# Installiere den SSH-Server und räume danach auf
RUN apt-get update && \
    apt-get install -y openssh-server && \
    apt-get install -y openssh-server iproute2 && \
    apt-get install -y openssh-server iproute2 curl && \
    rm -rf /var/lib/apt/lists/*

RUN ssh-keygen -A

# 1. Erstelle das .ssh Verzeichnis mit den richtigen Rechten
RUN mkdir -p /root/.ssh && \
    chmod 700 /root/.ssh

# 2. Kopiere den Key, den wir in Schritt 1 vorbereitet haben
COPY sshkey.pub /root/.ssh/authorized_keys

# 3. Setze die strikten SSH-Rechte (SEHR WICHTIG!)
RUN chmod 600 /root/.ssh/authorized_keys && \
    chown root:root /root/.ssh/authorized_keys

# 4. Verbiete Passwort-Logins in der SSH-Konfiguration
RUN sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    echo "ChallengeResponseAuthentication no" >> /etc/ssh/sshd_config

# --- ENDE DER ÄNDERUNGEN ---

# Erstelle das Verzeichnis, das sshd zum Starten braucht
RUN mkdir -p /var/run/sshd

# Kopiere unser Start-Skript in das Image
COPY start_waf.sh /start.sh
RUN chmod +x /start.sh

# Setze das neue Start-Skript als Standardbefehl
CMD ["/start.sh"]

USER nginx