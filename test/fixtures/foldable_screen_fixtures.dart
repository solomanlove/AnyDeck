/// Samsung SM-F9710 只读快照的必要字段，移除进程与应用信息。
const foldableScreenStates = '''
Supported states: [
  DeviceState{identifier=0, name='CLOSED', app_accessible=true},
  DeviceState{identifier=1, name='TENT', app_accessible=true},
  DeviceState{identifier=2, name='HALF_OPENED', app_accessible=false},
  DeviceState{identifier=3, name='OPENED', app_accessible=true},
  DeviceState{identifier=4, name='CONCURRENT_INNER_DEFAULT', app_accessible=true},
  DeviceState{identifier=5, name='CONCURRENT_OUTER_DEFAULT', app_accessible=true}
]
''';

/// 自动模式下内屏已提交，系统没有任何状态覆盖。
const foldableScreenStateDump = '''
DEVICE STATE MANAGER (dumpsys device_state)
  mCommittedState=Optional[DeviceState{identifier=3, name='OPENED', app_accessible=true}]
  mBaseState=Optional[DeviceState{identifier=3, name='OPENED', app_accessible=true}]
  mOverrideState=Optional.empty
''';

/// 显式保留 logical display 0 随姿态重绑定的实际输出结构。
const foldableScreenDisplayDump = '''
Display Devices: size=3
  DisplayDeviceInfo{"内置屏幕": uniqueId="local:4630947004648141459", 2448 x 1848, type INTERNAL, state ON, committedState ON}
  DisplayDeviceInfo{"内置屏幕": uniqueId="local:4630947123231501204", 1248 x 1972, type INTERNAL, state OFF, committedState OFF}
  DisplayDeviceInfo{"scrcpy": uniqueId="virtual:com.android.shell,2000,scrcpy,167", 1080 x 814, type VIRTUAL, state ON}
  DeviceStateToLayoutMap:
    Registered Layouts:
    state(0): [close: [{dispId: 0(ON), displayGroupName: , addr: StablePhysical{id=4630947123231501204, port=148}, mLeadDisplayId: -1}, {dispId: 1(OFF), displayGroupName: , addr: StablePhysical{id=4630947004648141459, port=147}, mLeadDisplayId: -1}]]
    state(1): [tent: [{dispId: 0(ON), displayGroupName: , addr: StablePhysical{id=4630947123231501204, port=148}}, {dispId: 1(OFF), displayGroupName: , addr: StablePhysical{id=4630947004648141459, port=147}}]]
    state(2): [half_open: [{dispId: 0(ON), displayGroupName: , addr: StablePhysical{id=4630947004648141459, port=147}}, {dispId: 1(OFF), displayGroupName: , addr: StablePhysical{id=4630947123231501204, port=148}}]]
    state(3): [open: [{dispId: 0(ON), displayGroupName: , addr: StablePhysical{id=4630947004648141459, port=147}, mLeadDisplayId: -1}, {dispId: 1(OFF), displayGroupName: , addr: StablePhysical{id=4630947123231501204, port=148}, mLeadDisplayId: -1}]]
    state(4): [dual: [{dispId: 0(ON), displayGroupName: , addr: StablePhysical{id=4630947004648141459, port=147}}, {dispId: 1(ON), displayGroupName: , addr: StablePhysical{id=4630947123231501204, port=148}}]]
    state(5): [rear_dual: [{dispId: 0(ON), displayGroupName: , addr: StablePhysical{id=4630947123231501204, port=148}}, {dispId: 1(ON), displayGroupName: , addr: StablePhysical{id=4630947004648141459, port=147}}]]
Callbacks: size=0
''';
