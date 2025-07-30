#!/bin/bash
# server/setup_server.sh

set -e

echo "📡 正在安装 WireGuard + udp2raw 服务端..."

apt update
apt install -y wireguard curl wget unzip

# 安装 udp2raw
cd /opt
wget -O udp2raw.zip https://github.com/wangyu-/udp2raw-tunnel/releases/latest/download/udp2raw_binaries.zip
unzip udp2raw.zip -d udp2raw
chmod +x udp2raw/udp2raw_amd64
ln -sf /opt/udp2raw/udp2raw_amd64 /usr/local/bin/udp2raw

# 创建 WireGuard 配置
mkdir -p /etc/wireguard
cd /etc/wireguard
umask 077
wg genkey | tee server_privatekey | wg pubkey > server_publickey
cat > wg0.conf <<EOF
[Interface]
PrivateKey = $(cat server_privatekey)
Address = 10.0.0.1/24
ListenPort = 51820
PostUp = ufw route allow in on wg0 out on eth0; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = ufw route delete allow in on wg0 out on eth0; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = PLACEHOLDER_CLIENT_PUBKEY
AllowedIPs = 10.0.0.2/32
EOF

# 启动 wg
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# 启动 udp2raw
nohup udp2raw -s -l0.0.0.0:443 -r 127.0.0.1:51820 -k "passwd123" --raw-mode faketcp -a > /var/log/udp2raw.log 2>&1 &

echo
echo "✅ 服务端安装完成"
echo "服务器公钥：$(cat server_publickey)"
