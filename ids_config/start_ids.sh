#!/bin/sh
set -e

# === IDS-Start-Skript (V55) ===
# Führt in einem schreibbaren /etc/suricata-Verzeichnis aus

# 1. Konfiguriere das Interface
echo "1. Konfiguriere eth1..."
ip addr add 10.10.1.20/24 dev eth1
ip route add 10.10.3.0/24 via 10.10.1.2

# 2. Lade/Initialisiere Regeln
# Da /etc/suricata jetzt schreibbar ist, wird suricata-update:
#  a) Die Standard-YAML-Datei dorthin kopieren (beim ersten Lauf)
#  b) Die Regeln (ET Open) herunterladen
#  c) Die YAML-Datei bearbeiten, um die Regeln zu laden
echo "2. Starte suricata-update (Initialisierung und Regel-Download)..."
suricata-update

# 3. Starte Suricata IM VORDERGRUND
echo "3. Starte Suricata-Engine auf eth1..."
exec suricata -c /etc/suricata/suricata.yaml -i eth1