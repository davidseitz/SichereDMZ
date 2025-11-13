# Starte vom offiziellen Nginx/WAF-Image
FROM owasp/modsecurity-crs:nginx

USER root
# Installiere den SSH-Server und räume danach auf
RUN apt-get update && \
    apt-get install -y openssh-server iproute2 curl nftables && \
    rm -rf /var/lib/apt/lists/*

# --- NEUE SSH-Konfiguration ---
# Schreibe die Konfiguration direkt in die Datei im Image.
RUN echo "Port 3025" > /etc/ssh/sshd_config && \
    echo "PasswordAuthentication no" >> /etc/ssh/sshd_config && \
    echo "ChallengeResponseAuthentication no" >> /etc/ssh/sshd_config && \
    echo "PermitRootLogin prohibit-password" >> /etc/ssh/sshd_config && \
    echo "Subsystem sftp /usr/lib/openssh/sftp-server" >> /etc/ssh/sshd_config && \
    # ÄNDERUNG: Beschränke Logins auf EINE EINZIGE IP-Adresse
    echo "AllowUsers root@10.10.30.3" >> /etc/ssh/sshd_config

# --- SSH-Key-Setup (wie zuvor) ---
# 1. Erstelle das .ssh Verzeichnis mit den richtigen Rechten
RUN mkdir -p /root/.ssh && \
    chmod 700 /root/.ssh

# 2. Kopiere den Key
COPY sshkey.pub /root/.ssh/authorized_keys

# 3. Setze die strikten SSH-Rechte
RUN chmod 600 /root/.ssh/authorized_keys && \
    chown root:root /root/.ssh/authorized_keys

# Erstelle die Verzeichnisse, die sshd zum Starten braucht
RUN mkdir -p /var/run/sshd
RUN mkdir -p /run/sshd

# Kopiere Start-Skript in das Image
COPY start_waf.sh /start_waf.sh
RUN chmod +x /start_waf.sh

# Setze das neue Start-Skript als Standardbefehl
CMD ["/start_waf.sh"]