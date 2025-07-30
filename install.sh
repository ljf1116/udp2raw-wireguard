#!/bin/bash
echo "请选择角色："
echo "1. 安装 VPS 端 (WireGuard + udp2raw)"
echo "2. 生成客户端配置 (二维码 + URI)"
read -p "输入编号 [1/2]: " role

if [ "$role" == "1" ]; then
    bash ./setup_server.sh
elif [ "$role" == "2" ]; then
    bash ./setup_client.sh
else
    echo "无效输入"
    exit 1
fi
