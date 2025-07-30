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

# Function to detect public IP
detect_ip() {
    IPV4=$(curl -4 -s ifconfig.co || echo "未能检测到IPv4地址")
    IPV6=$(curl -6 -s ifconfig.co || echo "未能检测到IPv6地址")
    
    echo -e "${BLUE}检测到的服务器IP地址:${NC}"
    echo -e "IPv4: ${GREEN}$IPV4${NC}"
    [[ -n "$IPV6" ]] && echo -e "IPv6: ${GREEN}$IPV6${NC}"
    echo ""
}

# Function to test port availability
test_port() {
    local port=$1
    if ss -tuln | grep -q ":$port "; then
        echo -e "${RED}端口 $port 已被占用，请选择其他端口！${NC}"
        return 1
    fi
    return 0
}

# Main installation
main() {
    # Initial setup
    clear
    echo -e "${GREEN}=== UDP2Raw + WireGuard 安装脚本 ===${NC}"
    detect_ip

    # Get server IP
    read -p "请输入服务器公网IP地址: " SERVER_IP
    while [[ -z "$SERVER_IP" ]]; do
        echo -e "${RED}服务器IP不能为空！${NC}"
        read -p "请输入服务器公网IP地址: " SERVER_IP
    done

    # Generate random password
    PASSWORD=$(generate_password)
    echo -e "${GREEN}生成的UDP2Raw密码: ${PASSWORD}${NC}"
    echo -e "${YELLOW}请妥善保存此密码，安装完成后不会再次显示！${NC}"
    read -p "按Enter键继续..."

    # Get port number
    DEFAULT_PORT=$((RANDOM % 50000 + 10000))
    read -p "请输入UDP2Raw监听端口 [$DEFAULT_PORT]: " UDP2RAW_PORT
    UDP2RAW_PORT=${UDP2RAW_PORT:-$DEFAULT_PORT}
    while ! test_port $UDP2RAW_PORT; do
        read -p "请重新输入UDP2Raw监听端口: " UDP2RAW_PORT
    done

    # Check OS
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
    else
        echo -e "${RED}无法检测操作系统${NC}"
        exit 1
    fi

    # Install dependencies
    echo -e "${YELLOW}[1/6] 安装依赖...${NC}"
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        apt update
        apt install -y git build-essential cmake libssl-dev wireguard qrencode iptables-persistent
    elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "fedora" ]]; then
        yum install -y git gcc-c++ make cmake openssl-devel wireguard-tools qrencode
    else
        echo -e "${RED}不支持的操作系统${NC}"
        exit 1
    fi

    # Clone and build udp2raw
    echo -e "${YELLOW}[2/6] 编译udp2raw...${NC}"
    git clone https://github.com/wangyu-/udp2raw-tunnel.git
    cd udp2raw-tunnel
    make
    cp udp2raw /usr/local/bin/
    cd ..
    rm -rf udp2raw-tunnel

    # Generate WireGuard config
    echo -e "${YELLOW}[3/6] 生成WireGuard配置...${NC}"
    PRIVATE_KEY=$(wg genkey)
    PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)
    WG_PORT=51820
    CLIENT_IP="10.0.0.2"

    # Create WireGuard config
    mkdir -p /etc/wireguard
    cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $PRIVATE_KEY
Address = 10.0.0.1/24
ListenPort = $WG_PORT
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = $(wg genkey | wg pubkey)
AllowedIPs = 10.0.0.2/32
EOF

    # Create client config
    echo -e "${YELLOW}[4/6] 生成客户端配置...${NC}"
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
Endpoint = $SERVER_IP:$UDP2RAW_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

    # Update WireGuard config with client public key
    wg set wg0 peer "$CLIENT_PUBLIC_KEY" allowed-ips "$CLIENT_IP/32"
    wg-quick save wg0

    # Create systemd service for udp2raw
    echo -e "${YELLOW}[5/6] 配置udp2raw服务...${NC}"
    cat > /etc/systemd/system/udp2raw.service <<EOF
[Unit]
Description=UDP2RAW Tunnel
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/udp2raw -s -l0.0.0.0:$UDP2RAW_PORT -r127.0.0.1:$WG_PORT -k "$PASSWORD" --raw-mode faketcp -a
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # Enable and start services
    echo -e "${YELLOW}[6/6] 启动服务...${NC}"
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
    echo "无法检测操作系统"
    exit 1
fi

if [[ "\$OS" == "ubuntu" || "\$OS" == "debian" ]]; then
    apt update
    apt install -y wireguard qrencode
elif [[ "\$OS" == "centos" || "\$OS" == "rhel" || "\$OS" == "fedora" ]]; then
    yum install -y wireguard-tools qrencode
else
    echo "不支持的操作系统"
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
ExecStart=/usr/local/bin/udp2raw -c -l127.0.0.1:51820 -r$SERVER_IP:$UDP2RAW_PORT -k "$PASSWORD" --raw-mode faketcp -a
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
服务器IP: $SERVER_IP
UDP2Raw端口: $UDP2RAW_PORT
WireGuard端口: $WG_PORT
密码: $PASSWORD
客户端配置文件: /root/wg_client/client.conf
EOF

    # Configure firewall
    iptables -A INPUT -p tcp --dport $UDP2RAW_PORT -j ACCEPT
    iptables -A INPUT -p udp --dport $WG_PORT -j ACCEPT
    
    # Save iptables rules
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        netfilter-persistent save
    fi

    # Display results
    echo -e "\n${GREEN}安装成功完成！${NC}"
    echo -e "${BLUE}连接信息:${NC}"
    cat /root/wg_client/connection_info.txt
    echo -e "\n${BLUE}客户端配置二维码:${NC}"
    qrencode -t ansiutf8 < /root/wg_client/client.conf
    echo -e "\n${YELLOW}客户端配置文件已保存到: /root/wg_client/client.conf${NC}"
    echo -e "${YELLOW}如需在Linux客户端上自动配置，请运行: bash /root/wg_client/setup_client.sh${NC}"
}

main
