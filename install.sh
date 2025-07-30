#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
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

# Detect public IP
detect_ip() {
    local ipv4=$(curl -4 -s ifconfig.co)
    local ipv6=$(curl -6 -s ifconfig.co)
    echo -e "${BLUE}Detected Server IP Addresses:${NC}"
    echo -e "IPv4: ${GREEN}$ipv4${NC}"
    [[ -n "$ipv6" ]] && echo -e "IPv6: ${GREEN}$ipv6${NC}"
    echo ""
}

# Get server connection info
get_connection_info() {
    detect_ip
    
    # IP configuration
    read -p "Enter your server public IP address [$DEFAULT_IPV4]: " SERVER_IP
    SERVER_IP=${SERVER_IP:-$DEFAULT_IPV4}
    
    # TLS configuration
    echo -e "\n${BLUE}Optional TLS Configuration:${NC}"
    read -p "Do you want to configure TLS domain? (y/n) [n]: " USE_TLS
    USE_TLS=${USE_TLS:-n}
    
    if [[ "$USE_TLS" =~ ^[Yy] ]]; then
        read -p "Enter your domain (e.g. vpn.example.com): " TLS_DOMAIN
        while [[ -z "$TLS_DOMAIN" ]]; do
            echo -e "${RED}Domain cannot be empty!${NC}"
            read -p "Enter your domain: " TLS_DOMAIN
        done
        
        read -p "Enter email for Let's Encrypt (optional): " TLS_EMAIL
        echo -e "${YELLOW}Note: You need to point your domain to this server's IP before continuing!${NC}"
        read -p "Press Enter to confirm DNS is configured..."
    fi
}

# Install TLS certificates
install_tls() {
    if [[ "$USE_TLS" =~ ^[Yy] ]]; then
        echo -e "${YELLOW}[TLS] Installing certbot...${NC}"
        if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
            apt install -y certbot
        elif [[ "$OS" == "centos" || "$OS" == "rhel" ]]; then
            yum install -y certbot
        fi
        
        echo -e "${YELLOW}[TLS] Obtaining certificates...${NC}"
        if [[ -n "$TLS_EMAIL" ]]; then
            certbot certonly --standalone --agree-tos --non-interactive --email "$TLS_EMAIL" -d "$TLS_DOMAIN"
        else
            certbot certonly --standalone --agree-tos --non-interactive -d "$TLS_DOMAIN"
        fi
        
        # Create renewal hook
        echo -e "#!/bin/bash\nsystemctl restart udp2raw" > /etc/letsencrypt/renewal-hooks/post/restart-udp2raw.sh
        chmod +x /etc/letsencrypt/renewal-hooks/post/restart-udp2raw.sh
    fi
}

# Main installation
main() {
    # Initial setup
    DEFAULT_IPV4=$(curl -4 -s ifconfig.co)
    get_connection_info
    PASSWORD=$(generate_password)
    
    echo -e "\n${GREEN}Generated UDP2Raw password: ${PASSWORD}${NC}"
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
    echo -e "${YELLOW}[1/7] Installing dependencies...${NC}"
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        apt update
        apt install -y git build-essential cmake libssl-dev wireguard qrencode
    elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "fedora" ]]; then
        yum install -y git gcc-c++ make cmake openssl-devel wireguard-tools qrencode
    else
        echo -e "${RED}Unsupported OS${NC}"
        exit 1
    fi

    # Install TLS if needed
    install_tls

    # Clone and build udp2raw
    echo -e "${YELLOW}[2/7] Building udp2raw...${NC}"
    git clone https://github.com/wangyu-/udp2raw-tunnel.git
    cd udp2raw-tunnel
    make
    cp udp2raw /usr/local/bin/
    cd ..
    rm -rf udp2raw-tunnel

    # Generate WireGuard config
    echo -e "${YELLOW}[3/7] Generating WireGuard configuration...${NC}"
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
    echo -e "${YELLOW}[4/7] Creating client configuration...${NC}"
    mkdir -p /root/wg_client
    CLIENT_PRIVATE_KEY=$(wg genkey)
    CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)

    # Determine endpoint
    if [[ "$USE_TLS" =~ ^[Yy] ]]; then
        ENDPOINT="$TLS_DOMAIN:$PORT"
    else
        ENDPOINT="$SERVER_IP:$PORT"
    fi

    cat > /root/wg_client/client.conf <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_IP/24
DNS = 8.8.8.8

[Peer]
PublicKey = $PUBLIC_KEY
Endpoint = $ENDPOINT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

    # Update WireGuard config with client public key
    wg set wg0 peer "$CLIENT_PUBLIC_KEY" allowed-ips "$CLIENT_IP/32"
    wg-quick save wg0

    # Create systemd service for udp2raw
    echo -e "${YELLOW}[5/7] Setting up udp2raw service...${NC}"
    if [[ "$USE_TLS" =~ ^[Yy] ]]; then
        cat > /etc/systemd/system/udp2raw.service <<EOF
[Unit]
Description=UDP2RAW Tunnel with TLS
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/udp2raw -s -l0.0.0.0:$PORT -r127.0.0.1:51820 -k "$PASSWORD" --raw-mode faketcp --tls-cert /etc/letsencrypt/live/$TLS_DOMAIN/fullchain.pem --tls-key /etc/letsencrypt/live/$TLS_DOMAIN/privkey.pem -a
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    else
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
    fi

    # Enable and start services
    echo -e "${YELLOW}[6/7] Starting services...${NC}"
    systemctl daemon-reload
    systemctl enable wg-quick@wg0
    systemctl enable udp2raw
    systemctl start wg-quick@wg0
    systemctl start udp2raw

    # Create client setup script
    echo -e "${YELLOW}[7/7] Creating client setup script...${NC}"
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
ExecStart=/usr/local/bin/udp2raw -c -l127.0.0.1:51820 -r$ENDPOINT -k "$PASSWORD" --raw-mode faketcp $([[ "$USE_TLS" =~ ^[Yy] ]] && echo "--tls-verify")
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
    qrencode -t ansiutf8 < /root/wg_client/client.conf

    # Save connection info
    cat > /root/wg_client/connection_info.txt <<EOF
Server IP: $SERVER_IP
TLS Domain: ${TLS_DOMAIN:-Not configured}
UDP2Raw Port: $PORT
WireGuard Port: 51820
Password: $PASSWORD
Connection Mode: $([[ "$USE_TLS" =~ ^[Yy] ]] && echo "TLS (Domain: $TLS_DOMAIN)" || echo "Direct IP")
Client Config Path: /root/wg_client/client.conf
EOF

    echo -e "\n${GREEN}Installation completed!${NC}"
    echo -e "${BLUE}Connection Information:${NC}"
    cat /root/wg_client/connection_info.txt
    echo -e "\n${BLUE}Client configuration QR code:${NC}"
    qrencode -t ansiutf8 < /root/wg_client/client.conf
    echo -e "\n${YELLOW}Client config file saved to: /root/wg_client/client.conf${NC}"
}

main
