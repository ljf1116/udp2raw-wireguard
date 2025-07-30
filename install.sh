#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Check root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}" 
   exit 1
fi

# Function to generate random password
generate_password() {
    local length=25
    tr -dc 'A-Za-z0-9!@#$%^&*()_+{}|:<>?=' < /dev/urandom | head -c $length
}

# Get server IP interactively
read -p "Enter your server public IP address: " SERVER_IP
while [[ -z "$SERVER_IP" ]]; do
    echo -e "${RED}Server IP cannot be empty!${NC}"
    read -p "Enter your server public IP address: " SERVER_IP
done

# Generate random password
PASSWORD=$(generate_password)
echo -e "${GREEN}Generated UDP2Raw password: ${PASSWORD}${NC}"
echo -e "${YELLOW}Please save this password as it won't be shown again!${NC}"
read -p "Press Enter to continue..."

# Check OS
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
else
    echo -e "${RED}Could not detect OS${NC}"
    exit 1
fi

# Install dependencies
echo -e "${YELLOW}[1/6] Installing dependencies...${NC}"
if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    apt update
    apt install -y git build-essential cmake libssl-dev wireguard qrencode
elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "fedora" ]]; then
    yum install -y git gcc-c++ make cmake openssl-devel wireguard-tools qrencode
else
    echo -e "${RED}Unsupported OS${NC}"
    exit 1
fi

# Clone and build udp2raw
echo -e "${YELLOW}[2/6] Building udp2raw...${NC}"
git clone https://github.com/wangyu-/udp2raw-tunnel.git
cd udp2raw-tunnel
make
cp udp2raw /usr/local/bin/
cd ..
rm -rf udp2raw-tunnel

# Generate WireGuard config
echo -e "${YELLOW}[3/6] Generating WireGuard configuration...${NC}"
PRIVATE_KEY=$(wg genkey)
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)
PORT=$((RANDOM % 50000 + 10000))
CLIENT_IP="10.0.0.2"

# Create WireGuard config
mkdir -p /etc/wireguard
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $PRIVATE_KEY
Address = 10.0.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = $(wg genkey | wg pubkey)
AllowedIPs = 10.0.0.2/32
EOF

# Create client config
echo -e "${YELLOW}[4/6] Creating client configuration...${NC}"
mkdir -p /root/wg_client
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)

cat > /root/wg_client/client.conf <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_IP/24
DNS = 8.8.8.8

[Peer]
PublicKey = $PUBLIC_KEY
Endpoint = 127.0.0.1:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

# Update WireGuard config with client public key
wg set wg0 peer "$CLIENT_PUBLIC_KEY" allowed-ips "$CLIENT_IP/32"
wg-quick save wg0

# Create systemd service for udp2raw
echo -e "${YELLOW}[5/6] Setting up udp2raw service...${NC}"
cat > /etc/systemd/system/udp2raw.service <<EOF
[Unit]
Description=UDP2RAW Tunnel
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/udp2raw -s -l0.0.0.0:$PORT -r127.0.0.1:51820 -k "$PASSWORD" --raw-mode faketcp -a
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable and start services
systemctl daemon-reload
systemctl enable wg-quick@wg0
systemctl enable udp2raw
systemctl start wg-quick@wg0
systemctl start udp2raw

# Create client setup script
cat > /root/wg_client/setup_client.sh <<EOF
#!/bin/bash

# Install dependencies
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=\$ID
else
    echo "Could not detect OS"
    exit 1
fi

if [[ "\$OS" == "ubuntu" || "\$OS" == "debian" ]]; then
    apt update
    apt install -y wireguard qrencode
elif [[ "\$OS" == "centos" || "\$OS" == "rhel" || "\$OS" == "fedora" ]]; then
    yum install -y wireguard-tools qrencode
else
    echo "Unsupported OS"
    exit 1
fi

# Build and install udp2raw
git clone https://github.com/wangyu-/udp2raw-tunnel.git
cd udp2raw-tunnel
make
cp udp2raw /usr/local/bin/
cd ..
rm -rf udp2raw-tunnel

# Create systemd service for udp2raw client
cat > /etc/systemd/system/udp2raw-client.service <<EOL
[Unit]
Description=UDP2RAW Client Tunnel
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/udp2raw -c -l127.0.0.1:51820 -r$SERVER_IP:$PORT -k "$PASSWORD" --raw-mode faketcp -a
Restart=always

[Install]
WantedBy=multi-user.target
EOL

# Start services
systemctl daemon-reload
systemctl enable udp2raw-client
systemctl start udp2raw-client

# Start WireGuard
wg-quick up wg0-client
EOF

# Generate QR code
echo -e "${YELLOW}[6/6] Generating QR code...${NC}"
qrencode -t ansiutf8 < /root/wg_client/client.conf

# Save connection info
cat > /root/wg_client/connection_info.txt <<EOF
Server IP: $SERVER_IP
UDP2Raw Port: $PORT
WireGuard Port: 51820
Password: $PASSWORD
Client Config Path: /root/wg_client/client.conf
EOF

echo -e "${GREEN}Installation completed!${NC}"
echo -e "${YELLOW}Connection information saved in /root/wg_client/connection_info.txt${NC}"
echo -e "${GREEN}Client configuration:${NC}"
cat /root/wg_client/client.conf
