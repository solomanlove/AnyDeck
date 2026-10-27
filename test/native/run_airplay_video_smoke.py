#!/usr/bin/env python3
"""生成无隐私样片，验证真实 AirPlay/DLNA 原生窗口；不启动 AnyDeck 主程序。"""
import functools
import http.server
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading


def run_smoke():
    root = Path(__file__).resolve().parents[2]
    flutter = Path(shutil.which('flutter')).resolve().parents[1]
    framework = os.environ.get('FLUTTER_FRAMEWORK_DIR', str(
        flutter / 'bin/cache/artifacts/engine/darwin-x64/FlutterMacOS.xcframework/macos-arm64_x86_64'))
    with tempfile.TemporaryDirectory(prefix='anydeck-video-smoke-') as folder:
        sample = Path(folder)
        binary = sample / 'player-smoke'
        subprocess.run([
            'xcrun', 'swiftc', '-F', framework, '-framework', 'FlutterMacOS',
            '-Xlinker', '-rpath', '-Xlinker', framework,
            str(root / 'macos/Runner/DlnaPlayerBridgeService.swift'),
            str(root / 'test/native/airplay_video_player_smoke.swift'), '-o', str(binary),
        ], check=True, timeout=60)
        subprocess.run([
            'ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=320x180:rate=25',
            '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=44100', '-t', '12',
            '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-g', '50', '-c:a', 'aac',
            '-movflags', '+faststart', str(sample / 'sample.mp4'),
        ], check=True, timeout=25)
        subprocess.run([
            'ffmpeg', '-v', 'error', '-i', str(sample / 'sample.mp4'), '-c', 'copy',
            '-hls_time', '2', '-hls_list_size', '0', str(sample / 'sample.m3u8'),
        ], check=True, timeout=25)

        class RangeHandler(http.server.SimpleHTTPRequestHandler):
            # AVPlayer 使用 Range 探测媒体；SimpleHTTPRequestHandler 默认 200 会导致错误。
            def do_GET(self):
                path = Path(self.translate_path(self.path))
                if not path.is_file():
                    self.send_error(404)
                    return
                data = path.read_bytes()
                start, end = 0, len(data) - 1
                ranged = self.headers.get('Range')
                if ranged:
                    left, right = ranged.removeprefix('bytes=').split('-', 1)
                    start, end = int(left or 0), min(int(right or end), end)
                self.send_response(206 if ranged else 200)
                self.send_header('Content-Type', self.guess_type(str(path)))
                self.send_header('Accept-Ranges', 'bytes')
                if ranged:
                    self.send_header('Content-Range', f'bytes {start}-{end}/{len(data)}')
                self.send_header('Content-Length', str(end - start + 1))
                self.end_headers()
                self.wfile.write(data[start:end + 1])

            def log_message(self, *_args):
                pass

        server = http.server.ThreadingHTTPServer(
            ('127.0.0.1', 0), functools.partial(RangeHandler, directory=folder))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        base = f'http://127.0.0.1:{server.server_port}'
        try:
            subprocess.run([str(binary), base + '/sample.mp4', base + '/sample.m3u8'],
                           check=True, timeout=50)
        finally:
            server.shutdown()
            server.server_close()


if __name__ == '__main__':
    run_smoke()
