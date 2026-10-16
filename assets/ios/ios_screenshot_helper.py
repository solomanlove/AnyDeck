#!/usr/bin/env python3
"""通过独立 screenshotr 服务截图，复用图标 helper 的 usbmux/plist 基础能力。"""
import argparse
import base64
from contextlib import ExitStack
import json
from pathlib import Path
import ssl
import tempfile

from ios_icon_helper import (connect_usbmuxd, get_pair_record, recv_plist,
                             send_plist, usbmuxd_connect, usbmuxd_list_devices)


def capture(udid, ios_path, output):
    """仅连接指定 USB 设备；配对证书只写入私有临时目录并立即清理。"""
    pair = get_pair_record(udid, ios_path)
    if not pair:
        raise RuntimeError('No pair record found for device')
    with connect_usbmuxd() as mux:
        devices = usbmuxd_list_devices(mux)
    target = next((d for d in devices
                   if d.get('Properties', {}).get('SerialNumber') == udid
                   and d.get('Properties', {}).get('ConnectionType') == 'USB'), None)
    if target is None:
        raise RuntimeError('Device not connected via USB')
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    with tempfile.TemporaryDirectory(prefix='anydeck_pair_') as directory:
        for name, key in [('cert', 'HostCertificate'), ('key', 'HostPrivateKey')]:
            value = pair[key]
            Path(directory, name).write_bytes(
                base64.b64decode(value) if isinstance(value, str) else value)
        ctx.load_cert_chain(str(Path(directory, 'cert')), str(Path(directory, 'key')))
    with ExitStack() as stack:
        lockdown = stack.enter_context(usbmuxd_connect(target['DeviceID'], 62078))
        send_plist(lockdown, {'Request': 'StartSession', 'HostID': pair['HostID'],
                             'SystemBUID': pair['SystemBUID']})
        response = recv_plist(lockdown)
        if response.get('Error'):
            raise RuntimeError(str(response['Error']))
        if response.get('EnableSessionSSL'):
            lockdown = stack.enter_context(ctx.wrap_socket(lockdown))
        send_plist(lockdown, {'Request': 'StartService',
                             'Service': 'com.apple.mobile.screenshotr'})
        service = recv_plist(lockdown)
        if 'Port' not in service:
            raise RuntimeError(str(service.get('Error', 'Screenshot service unavailable')))
        screenshot = stack.enter_context(usbmuxd_connect(target['DeviceID'], service['Port']))
        if service.get('EnableServiceSSL'):
            screenshot = stack.enter_context(ctx.wrap_socket(screenshot))
        hello = recv_plist(screenshot)
        if not isinstance(hello, list) or len(hello) < 2 or hello[0] != 'DLMessageVersionExchange':
            raise RuntimeError('Invalid screenshot version exchange')
        send_plist(screenshot, ['DLMessageVersionExchange', 'DLVersionsOk', hello[1]])
        if recv_plist(screenshot) != ['DLMessageDeviceReady']:
            raise RuntimeError('Screenshot service not ready')
        send_plist(screenshot, ['DLMessageProcessMessage', {'MessageType': 'ScreenShotRequest'}])
        reply = recv_plist(screenshot)
        if not isinstance(reply, list) or len(reply) < 2 or not isinstance(reply[1], dict):
            raise RuntimeError('Invalid screenshot response')
        data = reply[1].get('ScreenShotData')
        if not isinstance(data, bytes) or not data:
            raise RuntimeError('Screenshot service returned no image')
        Path(output).write_bytes(data)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--udid', required=True)
    parser.add_argument('--ios-path', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    try:
        capture(args.udid, args.ios_path, args.output)
        print(json.dumps({'success': True}))
    except Exception as error:
        print(json.dumps({'level': 'ERROR', 'err': str(error)}))
        raise SystemExit(1)
