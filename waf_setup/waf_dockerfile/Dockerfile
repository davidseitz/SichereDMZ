# Starte vom offiziellen Nginx/WAF-Image
FROM owasp/modsecurity-crs:nginx

USER root
# Installiere den SSH-Server und räume danach auf
RUN apt-get update && \
    apt-get install -y openssh-server && \
    apt-get install -y openssh-server iproute2 && \
    apt-get install -y openssh-server iproute2 curl && \
    rm -rf /var/lib/apt/lists/*
    
# 1. Erstelle das .ssh Verzeichnis mit den richtigen Rechten
RUN mkdir -p /root/.ssh && \
    chmod 700 /root/.ssh

# 2. Kopiere den Key, den wir in Schritt 1 vorbereitet haben
COPY sshkey.pub /root/.ssh/authorized_keys

# 3. Setze die strikten SSH-Rechte (SEHR WICHTIG!)
RUN chmod 600 /root/.ssh/authorized_keys && \
    chown root:root /root/.ssh/authorized_keys


# --- ENDE DER ÄNDERUNGEN ---

# Erstelle das Verzeichnis, das sshd zum Starten braucht
RUN mkdir -p /var/run/sshd

# Kopiere unser Start-Skript in das Image
COPY start_waf.sh /start_waf.sh
RUN chmod +x /start_waf.sh


# This is also key: Ensure the /run/sshd dir exists for sshd to work
RUN mkdir -p /run/sshd
# Setze das neue Start-Skript als Standardbefehl
CMD ["/start_waf.sh"]