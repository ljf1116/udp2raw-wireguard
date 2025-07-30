#!/bin/bash

if [ ! -f "/root/wg_client/client.conf" ]; then
    echo "Client configuration not found. Please install first."
    exit 1
fi

echo "Scan this QR code with your WireGuard app:"
qrencode -t ansiutf8 < /root/wg_client/client.conf

echo ""
echo "Or use this direct link:"
echo "https://link.wireguard.com/?$(base64 -w0 < /root/wg_client/client.conf)"
