# wg-udp2raw-autosetup

一个用于绕过 UDP 封锁的 WireGuard + udp2raw 自动部署脚本，支持一键安装 VPS 服务端、自动生成客户端配置与二维码导入。

---

## 🧱 特性

- 🚀 一键部署 WireGuard + udp2raw (faketcp)
- 🧩 自动生成客户端配置文件和二维码（WireGuard 扫码即用）
- 🔒 支持通过 TCP 伪装穿透防火墙

---

## 📦 快速安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ljf1116/wg-udp2raw-autosetup/master/install.sh)



##安装 VPS 端
git clone https://github.com/ljf1116/wg-udp2raw-autosetup.git
cd wg-udp2raw-autosetup
bash install.sh

## 选择 "1" 安装服务端（WireGuard + udp2raw）

安装后输出：

VPS 公钥

WireGuard 已自动启动

udp2raw 伪装监听 TCP 端口（默认 443）

## 生成客户端配置（含二维码）
选择 "2" 生成客户端配置，会自动：

生成客户端私钥、公钥

创建 wg0-client.conf 配置文件

输出二维码图片 wg_qr.png（扫码导入 WireGuard）

输出支持扫码/点击导入的 URI 链接

##依赖项
客户端配置脚本依赖：
sudo apt install python3-pip
pip3 install qrcode

## 联系作者
GitHub: ljf1116

---

## ✅ 2. 提供 curl 一键安装入口

上传后，用户可以这样使用：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ljf1116/wg-udp2raw-autosetup/master/install.sh)



