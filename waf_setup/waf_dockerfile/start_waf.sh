#!/bin/bash

# 1. Starte den SSH-Daemon direkt (umgeht "service" und den gid-Fehler)
/usr/sbin/sshd

# 2. Rufe das *originale* Entrypoint-Skript des Basis-Images auf.
# Dieses Skript generiert die korrekte nginx.conf (mit ModSecurity)
# und startet dann Nginx selbst.
exec /docker-entrypoint.sh nginx -g 'daemon off;'