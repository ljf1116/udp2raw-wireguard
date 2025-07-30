#!/bin/bash
set -e

# 配置参数
LISTEN_PORT=443
DST_IP=127.0.0.1$(curl -s ifconfig.me || wget -qO- ifconfig.me)
if [[ -z "$PUBLIC_IP" ]]; then
  echo "❌ 无法获取公网 IP，请检查网络或手动填写 IP"
  exit 1
fi
echo "🌐 检测到公网 IP: $PUBLIC_IP"
DST_PORT=51820
PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 25)
echo "✅ 生成密码：$PASSWORD"

MODE="faketcp"

echo "🚀 安装 udp2raw (faketcp)..."

apt update
apt install -y curl wget unzip

cd /opt
if [ ! -d "udp2raw" ]; then
  mkdir -p udp2raw && cd udp2raw
  wget -O udp2raw_binaries.zip https://github.com/wangyu-/udp2raw-tunnel/releases/latest/download/udp2raw_binaries.zip
  unzip -o udp2raw_binaries.zip
  chmod +x udp2raw_amd64
else
  cd udp2raw
fi

cat >/etc/systemd/system/udp2raw.service <<EOF
[Unit]
Description=udp2raw (faketcp)
After=network.target

[Service]
ExecStart=/opt/udp2raw/udp2raw_amd64 -s -l0.0.0.0:${LISTEN_PORT} -r${DST_IP}:${DST_PORT} -k "${PASSWORD}" --raw-mode ${MODE} --fix-gro
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now udp2raw

echo
echo "✅ udp2raw 服务已部署并启用！"
echo "· 监听：0.0.0.0:${LISTEN_PORT} (模式：${MODE})"
echo "· 转发至：${DST_IP}:${DST_PORT}"
echo "· 密码：${PASSWORD}"
