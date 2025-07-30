# UDP2Raw + WireGuard (faketcp) 一键安装

此脚本会自动设置一个使用 faketcp 模式的 UDP2Raw + WireGuard VPN 服务器，以绕过 UDP 阻止。

## 功能

- 自动安装所有依赖项
- 使用安全密钥设置 WireGuard
- 在 faketcp 模式下配置 UDP2Raw
- 生成客户端配置
- 创建二维码，方便在移动设备上设置

## 安装

以 root 身份运行：

```bash
wget https://raw.githubusercontent.com/yourusername/udp2raw-wireguard/main/install.sh -O install.sh && chmod +x install.sh && ./install.sh
```

## 客户端设置

安装完成后，您可以在 `/root/wg_client/` 中找到客户端配置。

1. 对于 Linux 客户端，运行 `setup_client.sh` 脚本。
2. 对于移动设备，请扫描二维码或导入客户端配置文件。

## 生成二维码

要再次显示二维码：

```bash
./generate_qr.sh
```

## 卸载

```bash
./uninstall.sh
```

## 作者: ljf1116
