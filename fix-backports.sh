#!/bin/bash
set -e

echo "🧹 清理旧的 bullseye-backports 配置..."

# 删除所有出现旧 backports 的配置文件
grep -rl 'bullseye-backports' /etc/apt/ | while read -r file; do
  echo "🚫 删除旧配置: $file"
  rm -f "$file"
done

echo "✅ 添加 archive.debian.org 的 backports 源..."
echo 'deb http://archive.debian.org/debian bullseye-backports main contrib non-free' > /etc/apt/sources.list.d/backports.list

echo "⚙️ 禁用有效期检查..."
echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until

echo "🔄 更新软件包索引..."
apt update

echo -e "\n✅ 已完成修复，您现在可以继续使用安装脚本。"
