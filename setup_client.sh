#!/bin/bash

# 自动获取 VPS 公网 IP
PUBLIC_IP=$(curl -s ifconfig.me || wget -qO- ifconfig.me)
if [[ -z "$PUBLIC_IP" ]]; then
  echo "❌ 无法获取公网 IP，请检查网络或手动填写 IP"
  exit 1
fi
echo "🌐 检测到公网 IP: $PUBLIC_IP"

SERVER_PUBLIC_KEY="your_server_public_key"
CLIENT_PRIVATE_KEY="your_client_private_key"

mkdir -p ./output
cat > ./output/client.conf <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = 10.0.0.2/24
DNS = 8.8.8.8

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $PUBLIC_IP:443
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

echo "✅ 客户端配置已生成：./output/client.conf"
