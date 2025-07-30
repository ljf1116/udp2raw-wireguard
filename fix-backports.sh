#!/bin/bash

set -e

echo "🛠 替换 bullseye-backports 为 archive.debian.org..."

# 写入新的 backports 源
echo 'deb http://archive.debian.org/debian bullseye-backports main contrib non-free' > /etc/apt/sources.list.d/backports.list

# 禁用有效期检查（因为 archive 源都已过期）
echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until

# 更新 apt 源
echo "🔄 执行 apt update..."
apt update

echo -e "\n✅ 修复完成。现在可以重新运行安装脚本。"
