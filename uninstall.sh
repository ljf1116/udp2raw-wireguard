#!/bin/bash

# Stop and disable services
systemctl stop udp2raw
systemctl disable udp2raw
systemctl stop wg-quick@wg0
systemctl disable wg-quick@wg0

# Remove files
rm -f /usr/local/bin/udp2raw
rm -f /etc/systemd/system/udp2raw.service
rm -rf /etc/wireguard
rm -rf /root/wg_client

# Remove dependencies (optional)
# apt remove -y wireguard qrencode cmake libssl-dev

echo "UDP2Raw + WireGuard has been uninstalled."
