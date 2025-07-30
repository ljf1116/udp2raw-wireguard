#!/bin/bash
set -e

WG_PORT=51820
UDP2RAW_PORT=443
PASSWORD="yourpassword"
WG_PRIVKEY=$(wg genkey)
WG_PUBKEY=$(echo "$WG_PRIVKEY" | wg pubkey)
WG_CONF="/etc/wireguard/wg0.conf"

apt update && apt install -y wireguard curl iptables

mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

cat > "$WG_CONF" <<EOF
[Interface]
Address = 10.0.0.1/24
ListenPort = $WG_PORT
PrivateKey = $WG_PRIVKEY

EOF

chmod 600 "$WG_CONF"

sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

iptables -A INPUT -p udp --dport $WG_PORT ! -s 127.0.0.1 -j DROP

cd /usr/local/bin
curl -LO https://github.com/wangyu-/udp2raw/releases/download/20200729.0/udp2raw_binaries.tar.gz
tar -xzf udp2raw_binaries.tar.gz
mv udp2raw_amd64 udp2raw
chmod +x udp2raw
rm -f udp2raw_binaries.tar.gz

cat > /etc/systemd/system/udp2raw-server.service <<EOF
[Unit]
Description=udp2raw Server (faketcp)
After=network.target

[Service]
ExecStart=/usr/local/bin/udp2raw \
 -s -l0.0.0.0:$UDP2RAW_PORT -r 127.0.0.1:$WG_PORT \
 -k "$PASSWORD" \
 --raw-mode faketcp --cipher-mode xor --auth-mode simple
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now wg-quick@wg0
systemctl enable --now udp2raw-server

echo -e "\n✅ VPS 端部署完成！"
echo "WireGuard 私钥: $WG_PRIVKEY"
echo "WireGuard 公钥（发送给客户端使用）:"
echo "$WG_PUBKEY"
