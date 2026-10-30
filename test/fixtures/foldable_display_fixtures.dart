/// 2026-10-30 荣耀 Magic V6 实机输出，保留物理屏尺寸、模式、DPI 与开关状态。
const honorFoldableDisplayDump = '''
Display Devices: size=3
  DisplayDeviceInfo{"内置屏幕": uniqueId="local:4630946846403687059", 2172 x 2352, modeId 1, supportedModes [{id=1, width=2172, height=2352, fps=60.000004}, {id=2, width=2172, height=2352, fps=120.00001}], density 480, 405.65295 x 403.65405 dpi, type INTERNAL, state ON, committedState ON}
  DisplayDeviceInfo{"内置屏幕": uniqueId="local:4630946324137792660", 1080 x 2420, modeId 7, supportedModes [{id=5, width=1080, height=2420, fps=60.000004}, {id=6, width=1080, height=2420, fps=120.00001}], density 480, 409.43283 x 407.07285 dpi, type INTERNAL, state OFF, committedState OFF}
  DisplayDeviceInfo{"scrcpy": uniqueId="virtual:com.android.shell,2000,scrcpy,35", 996 x 1080, density 1, 1.0 x 1.0 dpi, type VIRTUAL, state ON}
''';

/// 同次读取的支持姿态；编号只作为原始证据，不用于屏幕角色判断。
const honorFoldableStates = '''
Supported states: [
  DeviceState{identifier=1, name='STATE_FLAT', app_accessible=true},
  DeviceState{identifier=2, name='STATE_HALF_OPENED', app_accessible=true},
  DeviceState{identifier=4, name='STATE_CLOSED', app_accessible=true},
  DeviceState{identifier=8, name='STATE_REAR', app_accessible=true}
]
''';

/// 与现有截图选屏回归相同的 Samsung SM-F9710 物理屏尺寸。
const samsungFoldableDisplayDump = '''
  DisplayDeviceInfo{"内置屏幕": uniqueId="local:4630947123231501204", 1248 x 1972, type INTERNAL, state ON}
  DisplayDeviceInfo{"内置屏幕": uniqueId="local:4630947004648141459", 2448 x 1848, type INTERNAL, state OFF}
''';
