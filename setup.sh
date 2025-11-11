#!/bin/bash
#
# Setup-Skript für das 'security_lab'
#

set -e

# Container-Namen (lab-name ist 'security_lab' aus der topology.yaml)
# Router
ER="clab-security_lab-edge_router"
IR="clab-security_lab-internal_router"
# Switches (jetzt Container)
DMS="clab-security_lab-dmz_switch"
CLS="clab-security_lab-client_switch"
SES="clab-security_lab-security_switch"
RES="clab-security_lab-resource_switch"
MGS="clab-security_lab-mgmt_switch"
# Hosts
ATT1="clab-security_lab-attacker_1"
ATT2="clab-security_lab-attacker_2"
WEB="clab-security_lab-web_server"
RP="clab-security_lab-reverse_proxy"
ADM="clab-security_lab-admin"
SIEM="clab-security_lab-siem"
BAS="clab-security_lab-bastion"
DB="clab-security_lab-database"

# Funktion zum Bereitstellen der Topologie
deploy() {
    echo "Stelle Containerlab-Topologie 'topology.yaml' bereit..."
    containerlab deploy -t topology.yaml
    echo "Topologie bereitgestellt."
}

# Funktion zum Zerstören der Topologie
destroy() {
    echo "Zerstöre Containerlab-Topologie..."
    containerlab destroy -t topology.yaml --cleanup
    echo "Topologie zerstört."
}

# Funktion zur Konfiguration der Netzwerkeinstellungen
configure() {
    echo "Konfiguriere Netzwerk auf allen Knoten..."

    # --- 1. SWITCH-KONFIGURATION (NEU) ---
    # Konfiguriere alle Switch-Container als L2-Bridge
    echo "Konfiguriere Linux-Bridges in Switch-Containern..."

    # DMZ Switch
    docker exec $DMS apk add --no-cache iproute2-bridge
    docker exec $DMS ip link add name br0 type bridge
    docker exec $DMS ip link set dev p1 master br0
    docker exec $DMS ip link set dev p2 master br0
    docker exec $DMS ip link set dev p3 master br0
    docker exec $DMS ip link set dev br0 up
    docker exec $DMS ip link set dev p1 up
    docker exec $DMS ip link set dev p2 up
    docker exec $DMS ip link set dev p3 up

    # Client Switch
    docker exec $CLS apk add --no-cache iproute2-bridge
    docker exec $CLS ip link add name br0 type bridge
    docker exec $CLS ip link set dev p1 master br0
    docker exec $CLS ip link set dev p2 master br0
    docker exec $CLS ip link set dev p3 master br0
    docker exec $CLS ip link set dev br0 up
    docker exec $CLS ip link set dev p1 up
    docker exec $CLS ip link set dev p2 up
    docker exec $CLS ip link set dev p3 up

    # Security Switch
    docker exec $SES apk add --no-cache iproute2-bridge
    docker exec $SES ip link add name br0 type bridge
    docker exec $SES ip link set dev p1 master br0
    docker exec $SES ip link set dev p2 master br0
    docker exec $SES ip link set dev p3 master br0
    docker exec $SES ip link set dev br0 up
    docker exec $SES ip link set dev p1 up
    docker exec $SES ip link set dev p2 up
    docker exec $SES ip link set dev p3 up

    # Resource Switch
    docker exec $RES apk add --no-cache iproute2-bridge
    docker exec $RES ip link add name br0 type bridge
    docker exec $RES ip link set dev p1 master br0
    docker exec $RES ip link set dev p2 master br0
    docker exec $RES ip link set dev br0 up
    docker exec $RES ip link set dev p1 up
    docker exec $RES ip link set dev p2 up

    # Management Switch
    docker exec $MGS apk add --no-cache iproute2-bridge
    docker exec $MGS ip link add name br0 type bridge
    docker exec $MGS ip link set dev p1 master br0
    docker exec $MGS ip link set dev p2 master br0
    docker exec $MGS ip link set dev p3 master br0
    docker exec $MGS ip link set dev p4 master br0
    docker exec $MGS ip link set dev p5 master br0
    docker exec $MGS ip link set dev p6 master br0
    docker exec $MGS ip link set dev br0 up
    docker exec $MGS ip link set dev p1 up
    docker exec $MGS ip link set dev p2 up
    docker exec $MGS ip link set dev p3 up
    docker exec $MGS ip link set dev p4 up
    docker exec $MGS ip link set dev p5 up
    docker exec $MGS ip link set dev p6 up

    echo "Switch-Konfiguration abgeschlossen."

    # --- 2. ROUTER-KONFIGURATION (Ubuntu-Images) ---
    echo "Konfiguriere $ER (edge_router)..."
    docker exec $ER sysctl -w net.ipv4.ip_forward=1
    docker exec $ER ip addr add 1.1.1.1/24 dev eth-wan
    docker exec $ER ip addr add 10.10.255.1/30 dev eth-transit
    docker exec $ER ip addr add 10.10.50.1/29 dev eth-mgmt
    # Routen zu internen Netzen
    docker exec $ER ip route add 10.10.0.0/29 via 10.10.255.2
    docker exec $ER ip route add 10.10.20.0/29 via 10.10.255.2
    docker exec $ER ip route add 10.10.30.0/29 via 10.10.255.2
    docker exec $ER ip route add 10.10.40.0/29 via 10.10.255.2

    echo "Konfiguriere $IR (internal_router)..."
    docker exec $IR sysctl -w net.ipv4.ip_forward=1
    docker exec $IR ip addr add 10.10.255.2/30 dev eth-transit
    docker exec $IR ip addr add 10.10.0.1/29 dev eth-dmz
    docker exec $IR ip addr add 10.10.20.1/29 dev eth-plant
    docker exec $IR ip addr add 10.10.30.1/29 dev eth-security
    docker exec $IR ip addr add 10.10.40.1/29 dev eth-resource
    docker exec $IR ip addr add 10.10.50.2/29 dev eth-mgmt
    # Default-Route
    docker exec $IR ip route add default via 10.10.255.1

    # --- 3. HOST-KONFIGURATION (Alpine-Images) ---
    echo "Konfiguriere $ATT1 (attacker_1)..."
    docker exec $ATT1 apk add --no-cache iproute2
    docker exec $ATT1 ip addr add 1.1.1.2/24 dev eth0
    docker exec $ATT1 ip route add default via 1.1.1.1

    echo "Konfiguriere $ATT2 (attacker_2)..."
    docker exec $ATT2 apk add --no-cache iproute2
    docker exec $ATT2 ip addr add 10.10.20.3/29 dev eth0
    docker exec $ATT2 ip route add default via 10.10.20.1

    echo "Konfiguriere $WEB (web_server)..."
    docker exec $WEB apk add --no-cache iproute2
    docker exec $WEB ip addr add 10.10.0.2/29 dev eth0
    docker exec $WEB ip addr add 10.10.50.3/29 dev eth-mgmt
    docker exec $WEB ip route add default via 10.10.0.1

    echo "Konfiguriere $RP (reverse_proxy)..."
    docker exec $RP apk add --no-cache iproute2
    docker exec $RP ip addr add 10.10.0.3/29 dev eth0
    docker exec $RP ip addr add 10.10.50.4/29 dev eth-mgmt
    docker exec $RP ip route add default via 10.10.0.1

    echo "Konfiguriere $ADM (admin)..."
    docker exec $ADM apk add --no-cache iproute2
    docker exec $ADM ip addr add 10.10.20.2/29 dev eth0
    docker exec $ADM ip route add default via 10.10.20.1

    echo "Konfiguriere $SIEM (siem)..."
    docker exec $SIEM apk add --no-cache iproute2
    docker exec $SIEM ip addr add 10.10.30.2/29 dev eth0
    docker exec $SIEM ip route add default via 10.10.30.1

    echo "Konfiguriere $BAS (bastion)..."
    docker exec $BAS apk add --no-cache iproute2
    docker exec $BAS ip addr add 10.10.30.3/29 dev eth0
    docker exec $BAS ip addr add 10.10.50.5/29 dev eth-mgmt
    docker exec $BAS ip route add default via 10.10.30.1

    echo "Konfiguriere $DB (database)..."
    docker exec $DB apk add --no-cache iproute2
    docker exec $DB ip addr add 10.10.40.2/29 dev eth0
    docker exec $DB ip addr add 10.10.50.6/29 dev eth-mgmt
    docker exec $DB ip route add default via 10.10.40.1

    echo "Netzwerkkonfiguration abgeschlossen. Das Lab ist bereit!"
}

# Hilfefunktion
usage() {
    echo "Benutzung: $0 [deploy|configure|destroy|all]"
    echo "  deploy:     Startet die Containerlab-Topologie."
    echo "  configure:  Konfiguriert Switches, IPs und Routen auf allen Knoten."
    echo "  destroy:    Stoppt und löscht die Topologie."
    echo "  all:        Führt 'deploy' und 'configure' nacheinander aus."
}

# Haupt-Logik
case "$1" in
    deploy)
        deploy
        ;;
    configure)
        configure
        ;;
    destroy)
        destroy
        ;;
    all)
        deploy
        configure
        ;;
    *)
        usage
        exit 1
        ;;
esac

exit 0