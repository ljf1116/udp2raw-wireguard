#!/bin/bash
set -e

# ========== 用户配置部分（请务必修改） ==========
GITHUB_USERNAME="ljf1116"
GITHUB_REPO="udp2raw-wireguard"
GITHUB_BRANCH="main"  # 或 master，根据你实际分支填写
# ==============================================

# 检查权限
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ 请使用 root 用户运行此脚本"
  exit 1
fi

# 检查系统
if ! grep -qi debian /etc/os-release; then
  echo "❌ 此脚本仅支持 Debian 系统"
  exit 1
fi

# 安装必要工具
apt update
apt install -y wireguard qrencode curl wget unzip net-tools

# 获取公网 IP
IP=$(curl -s ipv4.icanhazip.com)

# 生成密钥对
wg genkey | tee server_private.key | wg pubkey > server_public.key
wg genkey | tee client_private.key | wg pubkey > client_public.key

SERVER_PRIVATE=$(cat server_private.key)
SERVER_PUBLIC=$(cat server_public.key)
CLIENT_PRIVATE=$(cat client_private.key)
CLIENT_PUBLIC=$(cat client_public.key)

# 生成服务端配置
WG_CONF="/etc/wireguard/wg0.conf"
WG_PORT=51820
cat > $WG_CONF <<EOF
[Interface]
PrivateKey = $SERVER_PRIVATE
Address = 10.0.0.1/24
ListenPort = $WG_PORT

[Peer]
PublicKey = $CLIENT_PUBLIC
AllowedIPs = 10.0.0.2/32
EOF

chmod 600 $WG_CONF
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# 安装并启动 udp2raw
cd /opt
wget -O udp2raw.tgz https://github.com/wangyu-/udp2raw/releases/download/20230206.0/udp2raw_binaries.tar.gz
tar -zxvf udp2raw.tgz
mv udp2raw_amd64 /usr/local/bin/udp2raw
chmod +x /usr/local/bin/udp2raw

nohup udp2raw -s -l0.0.0.0:40963 -r127.0.0.1:$WG_PORT -k "wireguardpass" --raw-mode faketcp -a > /dev/null 2>&1 &

# 生成客户端配置
WG_CLIENT_CONF="wg-client.conf"
cat > $WG_CLIENT_CONF <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE
Address = 10.0.0.2/24
DNS = 8.8.8.8

[Peer]
PublicKey = $SERVER_PUBLIC
Endpoint = 37.123.194.205:40963
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

# 显示二维码
echo
echo "📱 WireGuard 客户端二维码（可用 App 扫码导入）："
qrencode -t ansiutf8 < $WG_CLIENT_CONF

# 显示导入链接（假设你上传到 GitHub 后）
RAW_LINK="https://raw.githubusercontent.com/$GITHUB_USERNAME/$GITHUB_REPO/$GITHUB_BRANCH/$WG_CLIENT_CONF"

echo
echo "✅ 客户端配置已生成：$WG_CLIENT_CONF"
echo "🌐 你的公网 IP：$IP"
echo "🔗 上传后导入链接（你手动上传到 GitHub 后可用）："
echo "$RAW_LINK"

# 清理密钥文件（防止泄露）
rm -f server_private.key server_public.key client_private.key client_public.key
