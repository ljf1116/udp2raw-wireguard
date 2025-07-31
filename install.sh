#!/bin/bash

set -e

# === 系统检测 ===
if [ "$(id -u)" -ne 0 ]; then
  echo "请使用 root 用户运行此脚本"
  exit 1
fi

if ! grep -q Debian /etc/os-release; then
  echo "本脚本仅支持 Debian 系统"
  exit 1
fi

# === 安装依赖 ===
apt update
apt install -y wireguard qrencode curl wget unzip net-tools

# === 获取公网 IP ===
IP=$(curl -s ipv4.icanhazip.com)

# === 生成 WireGuard 密钥对 ===
wg genkey | tee server_private.key | wg pubkey > server_public.key
wg genkey | tee client_private.key | wg pubkey > client_public.key

SERVER_PRIVATE=$(cat server_private.key)
SERVER_PUBLIC=$(cat server_public.key)
CLIENT_PRIVATE=$(cat client_private.key)
CLIENT_PUBLIC=$(cat client_public.key)

# === 服务端配置 ===
WG_CONF="/etc/wireguard/wg0.conf"
PORT=51820

cat > $WG_CONF <<EOF
[Interface]
PrivateKey = $SERVER_PRIVATE
Address = 10.0.0.1/24
ListenPort = $PORT

[Peer]
PublicKey = $CLIENT_PUBLIC
AllowedIPs = 10.0.0.2/32
EOF

chmod 600 $WG_CONF
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# === 安装并配置 udp2raw ===
cd /opt
wget -O udp2raw.tgz https://github.com/wangyu-/udp2raw/releases/download/20230206.0/udp2raw_binaries.tar.gz
tar -zxvf udp2raw.tgz
mv udp2raw_amd64 /usr/local/bin/udp2raw
chmod +x /usr/local/bin/udp2raw

# 后台启动 udp2raw，伪装为 TCP
nohup udp2raw -s -l0.0.0.0:4096 -r127.0.0.1:$PORT -k "wireguardpass" --raw-mode faketcp -a > /dev/null 2>&1 &

# === 生成客户端配置文件 ===
WG_CLIENT_CONF="wg-client.conf"
cat > $WG_CLIENT_CONF <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE
Address = 10.0.0.2/24
DNS = 8.8.8.8

[Peer]
PublicKey = $SERVER_PUBLIC
Endpoint = $IP:4096
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

# === 生成二维码和提示 ===
echo "WireGuard 客户端配置如下（可导入 App 使用）："
qrencode -t ansiutf8 < $WG_CLIENT_CONF
echo -e "\n💾 文件保存为：$(pwd)/$WG_CLIENT_CONF"
echo -e "🌐 公网 IP: $IP"
echo -e "🛡️ 端口: 4096（已伪装为 TCP）"
echo -e "\n请将该配置文件手动上传到 GitHub 或其它安全位置。"
