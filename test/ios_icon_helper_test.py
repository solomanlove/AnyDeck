"""无需设备，验证 usbmuxd/lockdown 数据分片和异常长度处理。"""
import importlib.util
from pathlib import Path
import plistlib
import struct
import unittest

spec = importlib.util.spec_from_file_location(
    'ios_icon_helper',
    Path(__file__).resolve().parents[1] / 'assets/ios/ios_icon_helper.py',
)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class FragmentedSocket:
    def __init__(self, data):
        self.data = bytearray(data)

    def recv(self, count):
        result = bytes(self.data[:min(count, 2)])
        del self.data[:len(result)]
        return result


class IconHelperTest(unittest.TestCase):
    def test_fragmented_lockdown_plist(self):
        payload = plistlib.dumps({'pngData': b'example'})
        socket = FragmentedSocket(struct.pack('>I', len(payload)) + payload)
        self.assertEqual(helper.recv_plist(socket), {'pngData': b'example'})

    def test_fragmented_usbmuxd_plist(self):
        payload = plistlib.dumps({'Number': 0})
        socket = FragmentedSocket(struct.pack('<IIII', len(payload) + 16, 1, 8, 2) + payload)
        self.assertEqual(helper.recv_mux_plist(socket), {'Number': 0})

    def test_truncated_socket_fails(self):
        with self.assertRaises(ConnectionError):
            helper.recv_plist(FragmentedSocket(b'\x00\x00'))

    def test_invalid_mux_length_fails(self):
        with self.assertRaises(ValueError):
            helper.recv_mux_plist(FragmentedSocket(struct.pack('<IIII', 8, 1, 8, 2)))


if __name__ == '__main__':
    unittest.main()
