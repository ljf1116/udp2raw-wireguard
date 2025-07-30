#!/bin/bash
# client/gen_client.sh

set -e
apt update
apt install -y qrencode python3-pip
pip3 install qrcode

mkdir -p ./output
cd ./output
umask 077

wg genkey | tee client_privatekey | wg pubkey > client_publickey

read -p "请输入服务端公网 IP 或域名: " SERVER_IP

cat > wg0-client.conf <<EOF
[Interface]
PrivateKey = $(cat client_privatekey)
Address = 10.0.0.2/24
DNS = 1.1.1.1

[Peer]
PublicKey = PLACEHOLDER_SERVER_PUBKEY
Endpoint = ${SERVER_IP}:443
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

# 替换服务端公钥
read -p "请输入服务端 PublicKey（从服务端输出中复制）: " SERVER_PUBKEY
sed -i "s|PLACEHOLDER_SERVER_PUBKEY|$SERVER_PUBKEY|" wg0-client.conf

# 生成二维码
qrencode -o wg_qr.png < wg0-client.conf

# 显示二维码和导入链接
echo "📄 WireGuard 配置文件位于 ./output/wg0-client.conf"
echo "📸 二维码已生成：./output/wg_qr.png"
echo
echo "URI 导入链接："
echo "wg://$(base64 -w0 < wg0-client.conf)"
