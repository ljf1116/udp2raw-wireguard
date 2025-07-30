import sys
import qrcode
import urllib.parse

def config_to_uri(config_file):
    with open(config_file, 'r') as f:
        lines = f.read().splitlines()

    config = {}
    current_section = None
    for line in lines:
        if line.startswith('['):
            current_section = line.strip('[]')
            config[current_section] = {}
        elif '=' in line:
            key, value = line.split('=', 1)
            config[current_section][key.strip()] = value.strip()

    interface = config['Interface']
    peer = config['Peer']

    uri = (
        f"wireguard://"
        f"?address={interface['Address']}"
        f"&privatekey={interface['PrivateKey']}"
        f"&dns={interface.get('DNS', '')}"
        f"&publickey={peer['PublicKey']}"
        f"&endpoint={peer['Endpoint']}"
        f"&allowedips={peer['AllowedIPs']}"
        f"&persistentkeepalive={peer.get('PersistentKeepalive', '')}"
    )

    return uri

def main():
    config_file = sys.argv[1]
    uri = config_to_uri(config_file)
    print("📲 导入链接:\n" + uri + "\n")

    img = qrcode.make(uri)
    img.save("wg_qr.png")
    print("✅ 已保存二维码: wg_qr.png")

if __name__ == '__main__':
    main()
