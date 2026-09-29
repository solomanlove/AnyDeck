#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
iOS App Icon Fetcher via SpringBoard Services (com.apple.springboardservices)
通过 usbmuxd 和 lockdown 会话，启动 com.apple.springboardservices 并发送 getIconPNGData 批量获取应用图标。
"""

import sys
import os
import socket
import struct
import plistlib
import ssl
import json
import argparse
import tempfile
import base64
import subprocess
import re

def send_plist(sock, obj):
    data = plistlib.dumps(obj, fmt=plistlib.FMT_XML)
    sock.sendall(struct.pack('>I', len(data)) + data)

def recv_exact(sock, length):
    """流式 socket 可能分片；连接关闭时立即失败，避免解析半包。"""
    data = bytearray()
    while len(data) < length:
        chunk = sock.recv(length - len(data))
        if not chunk:
            raise ConnectionError("Socket closed before complete response")
        data.extend(chunk)
    return bytes(data)

def recv_plist(sock):
    length = struct.unpack('>I', recv_exact(sock, 4))[0]
    if length > 16 * 1024 * 1024:
        raise ValueError("Response too large")
    return plistlib.loads(recv_exact(sock, length))

def recv_mux_plist(sock):
    length, _, _, _ = struct.unpack('<IIII', recv_exact(sock, 16))
    if length < 16 or length > 16 * 1024 * 1024:
        raise ValueError("Invalid usbmuxd response length")
    return plistlib.loads(recv_exact(sock, length - 16))

def get_pair_record(udid, ios_path):
    # 1. 优先尝试系统路径 /var/db/lockdown/<udid>.plist
    sys_path = f"/var/db/lockdown/{udid}.plist"
    if os.path.isfile(sys_path):
        try:
            with open(sys_path, 'rb') as f:
                return plistlib.load(f)
        except Exception:
            pass

    # 2. 调用 go-ios readpair 提取配对记录
    try:
        cmd = [ios_path, 'readpair']
        if udid:
            cmd.append(f'--udid={udid}')
        out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL, timeout=5).decode('utf-8', errors='ignore')
        for line in out.splitlines():
            line = line.strip()
            if line.startswith('{') and 'HostCertificate' in line:
                return json.loads(line)
    except Exception as e:
        pass

    return None

def connect_usbmuxd():
    sock = socket.socket(socket.AF_UNIX)
    sock.settimeout(5)
    sock.connect('/var/run/usbmuxd')
    return sock

def usbmuxd_list_devices(mux):
    req = {'MessageType': 'ListDevices', 'ClientVersionString': 'anydeck', 'ProgName': 'anydeck'}
    payload = plistlib.dumps(req, fmt=plistlib.FMT_XML)
    hdr = struct.pack('<IIII', len(payload) + 16, 1, 8, 1)
    mux.sendall(hdr + payload)

    data = recv_mux_plist(mux)
    return data.get('DeviceList', [])

def usbmuxd_connect(dev_id, port):
    mux = connect_usbmuxd()
    req = {
        'MessageType': 'Connect',
        'ClientVersionString': 'anydeck',
        'ProgName': 'anydeck',
        'DeviceID': dev_id,
        'PortNumber': socket.htons(port)
    }
    payload = plistlib.dumps(req, fmt=plistlib.FMT_XML)
    hdr = struct.pack('<IIII', len(payload) + 16, 1, 8, 2)
    mux.sendall(hdr + payload)
    response = recv_mux_plist(mux)
    if response.get("Number") != 0:
        mux.close()
        raise ConnectionError("usbmuxd connection rejected")
    return mux

def main():
    parser = argparse.ArgumentParser(description="Fetch iOS app icons via SpringBoard Services")
    parser.add_argument("--udid", required=True, help="iOS device UDID")
    parser.add_argument("--bundle-ids", help="Comma-separated bundle IDs")
    parser.add_argument("--output-dir", required=True, help="Directory to save png icons")
    parser.add_argument("--ios-path", default="ios", help="Resolved go-ios executable")
    args = parser.parse_args()

    udid = args.udid.strip()
    if not re.fullmatch(r"[A-Za-z0-9-]+", udid):
        parser.error("Invalid UDID")
    out_dir = os.path.abspath(args.output_dir)
    os.makedirs(out_dir, exist_ok=True)

    if not args.bundle_ids:
        print(json.dumps({"success": True, "saved": []}))
        return

    bundle_ids = [b.strip() for b in args.bundle_ids.split(",") if b.strip()]
    bundle_ids = [b for b in bundle_ids if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", b)]
    if not bundle_ids:
        print(json.dumps({"success": True, "saved": []}))
        return

    # 1. 查找配对记录
    pair = get_pair_record(udid, args.ios_path)
    if not pair:
        print(json.dumps({"success": False, "error": "No pair record found for device"}))
        sys.exit(1)

    # 2. 查找 USB 设备
    try:
        mux = connect_usbmuxd()
        devices = usbmuxd_list_devices(mux)
        mux.close()
    except Exception as e:
        print(json.dumps({"success": False, "error": f"Cannot connect to usbmuxd: {e}"}))
        sys.exit(1)

    target_dev = None
    for d in devices:
        props = d.get('Properties', {})
        if props.get('SerialNumber') == udid:
            target_dev = d
            break

    if not target_dev:
        print(json.dumps({"success": False, "error": "Device not connected via USB"}))
        sys.exit(1)

    dev_id = target_dev.get('DeviceID')

    # 3. 连接 Lockdown (Port 62078)
    try:
        lockdown_sock = usbmuxd_connect(dev_id, 62078)

        # 准备 SSL 上下文
        host_cert_data = pair['HostCertificate']
        host_key_data = pair['HostPrivateKey']
        if isinstance(host_cert_data, str):
            host_cert_bytes = base64.b64decode(host_cert_data)
        else:
            host_cert_bytes = host_cert_data

        if isinstance(host_key_data, str):
            host_key_bytes = base64.b64decode(host_key_data)
        else:
            host_key_bytes = host_key_data

        with tempfile.NamedTemporaryFile('wb', delete=False) as f_cert, tempfile.NamedTemporaryFile('wb', delete=False) as f_key:
            f_cert.write(host_cert_bytes)
            f_key.write(host_key_bytes)
            f_cert.flush()
            f_key.flush()
            cert_path = f_cert.name
            key_path = f_key.name

        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        try:
            ctx.load_cert_chain(cert_path, key_path)
        finally:
            os.unlink(cert_path)
            os.unlink(key_path)

        # 握手
        host_id = pair.get('HostID') or '00000000-0000-0000-0000-000000000000'
        sys_buid = pair.get('SystemBUID') or ''
        send_plist(lockdown_sock, {'Request': 'StartSession', 'HostID': host_id, 'SystemBUID': sys_buid})
        session_resp = recv_plist(lockdown_sock)

        # 升级为 TLS
        if not session_resp or session_resp.get("Error"):
            raise ConnectionError("Lockdown session rejected")
        s_ssl = (ctx.wrap_socket(lockdown_sock, server_side=False)
                 if session_resp.get("EnableSessionSSL") else lockdown_sock)

        # 启动 SpringBoard 专属服务
        send_plist(s_ssl, {'Request': 'StartService', 'Service': 'com.apple.springboardservices'})
        service_resp = recv_plist(s_ssl)
        if not service_resp or 'Port' not in service_resp:
            print(json.dumps({"success": False, "error": f"Failed to start springboardservices: {service_resp}"}))
            sys.exit(1)

        sb_port = service_resp['Port']
        sb_ssl = service_resp.get('EnableServiceSSL', False)

        # 连接 SpringBoard 端口
        sb_sock = usbmuxd_connect(dev_id, sb_port)
        if sb_ssl:
            sb_sock = ctx.wrap_socket(sb_sock, server_side=False)

        # 批量获取应用图标
        saved_list = []
        for bid in bundle_ids:
            try:
                send_plist(sb_sock, {'command': 'getIconPNGData', 'bundleId': bid})
                resp = recv_plist(sb_sock)
                if resp and 'pngData' in resp and resp['pngData']:
                    png_bytes = resp['pngData']
                    target_file = os.path.join(out_dir, f"{bid}.png")
                    with open(target_file, 'wb') as img_out:
                        img_out.write(png_bytes)
                    saved_list.append({"bundleId": bid, "path": target_file})
            except Exception:
                continue

        sb_sock.close()
        s_ssl.close()

        print(json.dumps({"success": True, "saved": saved_list}))

    except Exception as e:
        print(json.dumps({"success": False, "error": str(e)}))
        sys.exit(1)

if __name__ == '__main__':
    main()
