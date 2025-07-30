#!/bin/bash
set -e

read -p "输入 VPS 公钥: " SERVER_PUBKEY
read -p "输入 udp2raw 伪装地址（IP:端口）: " ENDPOINT
read -p "输入你设置的密码（必须与服务端一致）: " PASSWORD

PRIVKEY=$(wg genkey)
PUBKEY=$(echo "$PRIVKEY" | wg pubkey)

cat > wg0-client.conf <<EOF
[Interface]
PrivateKey = $PRIVKEY
Address = 10.0.0.2/24
DNS = 8.8.8.8

[Peer]
PublicKey = $SERVER_PUBKEY
Endpoint = 127.0.0.1:51821
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

echo "✅ 已生成 WireGuard 配置文件: wg0-client.conf"
echo
echo "🔑 客户端公钥（请发送给 VPS 配置）:"
echo "$PUBKEY"
echo

echo "🔧 正在生成二维码与导入链接..."
python3 ./assets/wg2qr.py wg0-client.conf
