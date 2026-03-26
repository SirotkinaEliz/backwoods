#!/bin/bash
# ==============================================================================
# Backwoods: WireGuard Server Setup Script
# ==============================================================================
# Target: Ubuntu 22.04 / Debian 12 VPS in Netherlands
# Supports up to 30 peers (clients).
#
# Usage:
#   chmod +x setup-wireguard-server.sh
#   sudo ./setup-wireguard-server.sh
#
# After running, the script will:
#   1. Install WireGuard
#   2. Generate server keys
#   3. Create wg0 interface config
#   4. Enable IP forwarding
#   5. Setup firewall (UFW)
#   6. Generate peer configs (saved to /etc/wireguard/peers/)
#   7. Start WireGuard
# ==============================================================================

set -euo pipefail

# --- Configuration ---
WG_INTERFACE="wg0"
WG_PORT=51820
WG_NETWORK="10.0.0.0/24"
WG_SERVER_IP="10.0.0.1"
DNS_SERVERS="1.1.1.1, 1.0.0.1"
NUM_PEERS=30  # Maximum number of clients
MTU=1280

# Detect public IP
SERVER_PUBLIC_IP=$(curl -s4 ifconfig.me || curl -s4 icanhazip.com)
if [ -z "$SERVER_PUBLIC_IP" ]; then
    echo "❌ Не удалось определить внешний IP сервера"
    exit 1
fi

echo "=============================================="
echo "  Backwoods WireGuard Server Setup"
echo "=============================================="
echo "  Внешний IP: $SERVER_PUBLIC_IP"
echo "  Порт: $WG_PORT"
echo "  Подсеть: $WG_NETWORK"
echo "  Пиров: $NUM_PEERS"
echo "=============================================="
echo ""

# Detect default network interface
DEFAULT_IFACE=$(ip route show default | awk '/default/ {print $5}' | head -1)
echo "Сетевой интерфейс: $DEFAULT_IFACE"

# --- Step 1: Install WireGuard ---
echo ""
echo ">>> Шаг 1: Установка WireGuard..."
apt-get update
apt-get install -y wireguard wireguard-tools qrencode

# --- Step 2: Generate server keys ---
echo ""
echo ">>> Шаг 2: Генерация ключей сервера..."
mkdir -p /etc/wireguard/keys
chmod 700 /etc/wireguard/keys

wg genkey | tee /etc/wireguard/keys/server_private.key | wg pubkey > /etc/wireguard/keys/server_public.key
chmod 600 /etc/wireguard/keys/server_private.key

SERVER_PRIVATE_KEY=$(cat /etc/wireguard/keys/server_private.key)
SERVER_PUBLIC_KEY=$(cat /etc/wireguard/keys/server_public.key)

echo "  Публичный ключ сервера: $SERVER_PUBLIC_KEY"

# --- Step 3: Create server config ---
echo ""
echo ">>> Шаг 3: Создание конфигурации сервера..."

cat > /etc/wireguard/$WG_INTERFACE.conf << EOF
# Backwoods WireGuard Server
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

[Interface]
Address = $WG_SERVER_IP/24
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIVATE_KEY
MTU = $MTU

# NAT masquerade
PostUp = iptables -t nat -A POSTROUTING -o $DEFAULT_IFACE -j MASQUERADE; ip6tables -t nat -A POSTROUTING -o $DEFAULT_IFACE -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o $DEFAULT_IFACE -j MASQUERADE; ip6tables -t nat -D POSTROUTING -o $DEFAULT_IFACE -j MASQUERADE

EOF

chmod 600 /etc/wireguard/$WG_INTERFACE.conf

# --- Step 4: Enable IP forwarding ---
echo ""
echo ">>> Шаг 4: Включение IP forwarding..."

cat > /etc/sysctl.d/99-wireguard.conf << EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF

sysctl -p /etc/sysctl.d/99-wireguard.conf

# --- Step 5: Generate peer configs ---
echo ""
echo ">>> Шаг 5: Генерация конфигураций клиентов..."

mkdir -p /etc/wireguard/peers
mkdir -p /etc/wireguard/peers/json

for i in $(seq 1 $NUM_PEERS); do
    PEER_IP="10.0.0.$((i + 1))"
    PEER_NAME="peer-$(printf '%02d' $i)"
    
    # Generate peer keys
    PEER_PRIVATE_KEY=$(wg genkey)
    PEER_PUBLIC_KEY=$(echo "$PEER_PRIVATE_KEY" | wg pubkey)
    PEER_PRESHARED_KEY=$(wg genpsk)
    
    # Save keys
    echo "$PEER_PRIVATE_KEY" > /etc/wireguard/keys/${PEER_NAME}_private.key
    echo "$PEER_PUBLIC_KEY" > /etc/wireguard/keys/${PEER_NAME}_public.key
    echo "$PEER_PRESHARED_KEY" > /etc/wireguard/keys/${PEER_NAME}_psk.key
    chmod 600 /etc/wireguard/keys/${PEER_NAME}_*.key
    
    # Add peer to server config
    cat >> /etc/wireguard/$WG_INTERFACE.conf << EOF

# $PEER_NAME ($PEER_IP)
[Peer]
PublicKey = $PEER_PUBLIC_KEY
PresharedKey = $PEER_PRESHARED_KEY
AllowedIPs = $PEER_IP/32
EOF
    
    # Create peer wg-quick config
    cat > /etc/wireguard/peers/${PEER_NAME}.conf << EOF
# Backwoods Client: $PEER_NAME
# IP: $PEER_IP

[Interface]
PrivateKey = $PEER_PRIVATE_KEY
Address = $PEER_IP/32
DNS = $DNS_SERVERS
MTU = $MTU

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
PresharedKey = $PEER_PRESHARED_KEY
Endpoint = $SERVER_PUBLIC_IP:$WG_PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
    
    # Create Backwoods JSON config (for embedding in the app)
    cat > /etc/wireguard/peers/json/${PEER_NAME}.json << EOF
{
    "type": "wireGuard",
    "wireGuard": {
        "interface": {
            "privateKey": "$PEER_PRIVATE_KEY",
            "addresses": ["$PEER_IP/32"],
            "dns": ["1.1.1.1", "1.0.0.1"],
            "mtu": $MTU
        },
        "peer": {
            "publicKey": "$SERVER_PUBLIC_KEY",
            "presharedKey": "$PEER_PRESHARED_KEY",
            "endpoint": "$SERVER_PUBLIC_IP:$WG_PORT",
            "allowedIPs": ["0.0.0.0/0", "::/0"],
            "persistentKeepalive": 25
        }
    }
}
EOF
    
    echo "  ✓ $PEER_NAME ($PEER_IP)"
done

# --- Step 6: Setup firewall ---
echo ""
echo ">>> Шаг 6: Настройка файрвола..."

# Allow WireGuard port
ufw allow $WG_PORT/udp comment "WireGuard"
ufw allow ssh comment "SSH"

# Enable UFW if not already
echo "y" | ufw enable 2>/dev/null || true
ufw reload

# --- Step 7: Start WireGuard ---
echo ""
echo ">>> Шаг 7: Запуск WireGuard..."

systemctl enable wg-quick@$WG_INTERFACE
systemctl start wg-quick@$WG_INTERFACE

# Verify
echo ""
echo ">>> Проверка..."
wg show $WG_INTERFACE

echo ""
echo "=============================================="
echo "  ✅ WireGuard сервер настроен!"
echo "=============================================="
echo ""
echo "  Публичный ключ сервера: $SERVER_PUBLIC_KEY"
echo "  Endpoint: $SERVER_PUBLIC_IP:$WG_PORT"
echo ""
echo "  Конфигурации клиентов: /etc/wireguard/peers/"
echo "  JSON для Backwoods:    /etc/wireguard/peers/json/"
echo ""
echo "  Для проверки:  wg show $WG_INTERFACE"
echo "  Для перезапуска: systemctl restart wg-quick@$WG_INTERFACE"
echo ""
echo "  Чтобы вставить конфигурацию клиента в приложение:"
echo "    cat /etc/wireguard/peers/json/peer-01.json"
echo "  Скопируйте содержимое в Telegram/backwoods-tunnel.json"
echo "=============================================="
