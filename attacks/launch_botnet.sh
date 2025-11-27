#!/bin/bash

# Usage:
#   ./launch_botnet.sh [count]      -> Launches 'count' bots (default 50)
#   ./launch_botnet.sh stop         -> Destroys all active bot containers

# --- MODE CHECK: STOP ---
if [ "$1" == "stop" ]; then
    echo "[*] Stopping and removing all botnet containers..."
    # Filter for containers starting with "bot_"
    BOTS=$(docker ps -aq --filter name=bot_)
    
    if [ -z "$BOTS" ]; then
        echo "[+] No active bots found."
    else
        docker rm -f $BOTS > /dev/null 2>&1
        echo "[+] Botnet destroyed successfully."
    fi
    exit 0
fi

# --- CONFIGURATION ---
BOT_COUNT=$1
START_IP_OCTET=129
SUBNET_PREFIX="172.20.1"
BRIDGE_NAME="network_bridge"  # Must match create_bridge.sh
GATEWAY_IP="172.20.1.9"       # The Edge Router IP on the ethwan interface
IMAGE_NAME="attacker-image"   # Name of your built attacker image
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_SOURCE="$SCRIPT_DIR/python-scripts/flood_users_rate_limited.py"

# Default to 50 bots if not specified
if [ -z "$BOT_COUNT" ]; then
    BOT_COUNT=50
fi

echo "[+] Launching Botnet on bridge: $BRIDGE_NAME"
echo "[+] Target Gateway: $GATEWAY_IP"
echo "[+] Spawning $BOT_COUNT bots..."

# 1. Verify Native Bridge Exists (Linux level)
if ! ip link show "$BRIDGE_NAME" > /dev/null 2>&1; then
    echo "[-] Error: Native Bridge '$BRIDGE_NAME' not found."
    echo "    Please run './create_bridge.sh' first."
    exit 1
fi

# 2. Ensure Docker knows about this bridge (so --net works)
# We define a Docker network that wraps the existing native bridge.
if ! docker network ls | grep -q "$BRIDGE_NAME"; then
    echo "[*] Adapting native bridge '$BRIDGE_NAME' for Docker..."
    docker network create \
        --driver bridge \
        --subnet=172.20.1.0/24 \
        --gateway=172.20.1.1 \
        --opt com.docker.network.bridge.name="$BRIDGE_NAME" \
        --opt com.docker.network.bridge.enable_ip_masquerade=false \
        "$BRIDGE_NAME" > /dev/null
fi

# 3. Spawn Loop
for ((i=0; i<BOT_COUNT; i++)); do
    # Calculate IP
    CURRENT_OCTET=$((START_IP_OCTET + i))
    
    # Safety check for /24 boundary
    if [ $CURRENT_OCTET -gt 254 ]; then
        echo "[-] IP range exhausted at .254"
        break
    fi
    
    BOT_IP="${SUBNET_PREFIX}.${CURRENT_OCTET}"
    BOT_NAME="bot_${CURRENT_OCTET}"

    # Remove existing bot
    docker rm -f $BOT_NAME > /dev/null 2>&1

    # A. Run Container
    # We mount the new flood_users.py dynamically
    docker run -d --rm \
        --name $BOT_NAME \
        --net $BRIDGE_NAME \
        --ip $BOT_IP \
        --cap-add=NET_ADMIN \
        -v "$SCRIPT_SOURCE":/flood_users.py \
        $IMAGE_NAME \
        sleep infinity > /dev/null

    # B. Configure Routing
    # Routes 10.10.0.0/16 traffic to the edge router (172.20.1.9)
    docker exec $BOT_NAME ip route add 10.10.0.0/16 via $GATEWAY_IP

    # C. Start Attack
    # Uses the venv python we set up in Dockerfile.attacker
    docker exec -d $BOT_NAME /opt/venv/bin/python3 /flood_users.py

    echo -e "    [*] Bot $BOT_NAME ($BOT_IP) -> ACTIVE"
done

echo "[+] Botnet Deployed. Logs: docker logs -f bot_XXX"