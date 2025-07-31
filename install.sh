#!/bin/bash

set -e

# === 用户自定义 GitHub 配置 ===
GITHUB_TOKEN="your_github_token_here"
GITHUB_REPO="yourusername/yourrepo"
GITHUB_BRANCH="main"

# === 系统检测 ===
if [ "$(id -u)" != "0" ]; then
  echo "请使用 root 用户运行此脚本"
  exit 1
fi

if ! grep -q Debian /etc/os-release; then
  echo "本脚本仅支持 Debian 系统"
  exit 1
fi

# === 安装依赖 ===
apt update && apt install -y wireguard qrencode curl git unzip wget net-tools

# === 获取公网 IP ===
IP=$(curl -s ipv4.icanhazip.com)

# === 生成 WireGuard 密钥对 ===
wg genkey | tee server_private.key | wg pubkey > server_public.key
wg genkey | tee client_private.key | wg pubkey > client_public.key

SERVER_PRIVATE=$(cat server_private.key)
SERVER_PUBLIC=$(cat server_public.key)
CLIENT_PRIVATE=$(cat client_private.key)
CLIENT_PUBLIC=$(cat client_public.key)

# === 配置 WireGuard 服务端 ===
PORT=51820
WG_CONF="/etc/wireguard/wg0.conf"

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

# === 配置 udp2raw ===
cd /opt
wget -O udp2raw.tgz https://github.com/wangyu-/udp2raw/releases/download/20230206.0/udp2raw_binaries.tar.gz
tar -zxvf udp2raw.tgz
mv udp2raw_amd64 /usr/local/bin/udp2raw
chmod +x /usr/local/bin/udp2raw

# 后台运行 udp2raw（伪装为 TCP）
nohup udp2raw -s -l0.0.0.0:4096 -r127.0.0.1:$PORT -k "mysecret" --raw-mode faketcp -a > /dev/null 2>&1 &

# === 生成客户端配置 ===
cat > wg-client.conf <<EOF
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

# === 生成二维码 ===
qrencode -t ansiutf8 < wg-client.conf

# === 上传配置到 GitHub ===
mkdir tmp-repo
cd tmp-repo
git init
git remote add origin https://$GITHUB_TOKEN@github.com/$GITHUB_REPO.git
git checkout -b $GITHUB_BRANCH

cp ../wg-client.conf ./wg-client.conf
git add wg-client.conf
git commit -m "Add WireGuard client config"
git push -u origin $GITHUB_BRANCH --force

# === 输出导入链接 ===
IMPORT_LINK="https://github.com/$GITHUB_REPO/raw/$GITHUB_BRANCH/wg-client.conf"
echo -e "\n✅ WireGuard 安装完成"
echo -e "🔗 导入链接：$IMPORT_LINK"
echo -e "📱 用二维码扫描导入配置\n"

qrencode -o wg-client.png < wg-client.conf
