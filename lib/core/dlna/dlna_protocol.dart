import 'dart:convert';

/// UPnP AV 固定描述与 SOAP 响应，不包含网络和播放器状态。
class DlnaProtocol {
  static const deviceType = 'urn:schemas-upnp-org:device:MediaRenderer:1';
  static const transportType = 'urn:schemas-upnp-org:service:AVTransport:1';
  static const connectionType =
      'urn:schemas-upnp-org:service:ConnectionManager:1';
  static const renderingType =
      'urn:schemas-upnp-org:service:RenderingControl:1';
  static const uuid = '43c0b6d7-bc0d-4667-82a0-a11dec000001';
  static const serverName = 'AnyDeck DLNA';
  static const sinkProtocolInfo =
      'http-get:*:video/mp4:*,http-get:*:application/vnd.apple.mpegurl:*,http-get:*:application/dash+xml:*';
  static const searchTargets = [
    'upnp:rootdevice',
    'uuid:$uuid',
    deviceType,
    transportType,
    renderingType,
    connectionType,
  ];

  static String escape(String value) =>
      const HtmlEscape(HtmlEscapeMode.element).convert(value);

  static String deviceDescription(String baseUrl, {String name = serverName}) =>
      '''<?xml version="1.0" encoding="utf-8"?>
<root xmlns="urn:schemas-upnp-org:device-1-0"><specVersion><major>1</major><minor>0</minor></specVersion><URLBase>$baseUrl/</URLBase><device><deviceType>$deviceType</deviceType><friendlyName>${escape(name)}</friendlyName><manufacturer>AnyDeck</manufacturer><modelName>AnyDeck DLNA Renderer</modelName><UDN>uuid:$uuid</UDN><serviceList>${_service(transportType, 'AVTransport', '/avtransport')}${_service(renderingType, 'RenderingControl', '/rendering')}${_service(connectionType, 'ConnectionManager', '/connection')}</serviceList></device></root>''';

  static String _service(String type, String id, String path) =>
      '<service><serviceType>$type</serviceType><serviceId>urn:upnp-org:serviceId:$id</serviceId><SCPDURL>$path.xml</SCPDURL><controlURL>$path/control</controlURL><eventSubURL>$path/event</eventSubURL></service>';

  static String serviceDescription(String service) {
    final actions = switch (service) {
      'avtransport' => <String, ({List<String> input, List<String> output})>{
        'SetAVTransportURI': (
          input: ['InstanceID', 'CurrentURI', 'CurrentURIMetaData'],
          output: [],
        ),
        'Play': (input: ['InstanceID', 'Speed'], output: []),
        'Pause': (input: ['InstanceID'], output: []),
        'Stop': (input: ['InstanceID'], output: []),
        'Seek': (input: ['InstanceID', 'Unit', 'Target'], output: []),
        'GetTransportInfo': (
          input: ['InstanceID'],
          output: [
            'CurrentTransportState',
            'CurrentTransportStatus',
            'CurrentSpeed',
          ],
        ),
        'GetPositionInfo': (
          input: ['InstanceID'],
          output: [
            'Track',
            'TrackDuration',
            'TrackMetaData',
            'TrackURI',
            'RelTime',
            'AbsTime',
            'RelCount',
            'AbsCount',
          ],
        ),
        'GetMediaInfo': (
          input: ['InstanceID'],
          output: [
            'NrTracks',
            'MediaDuration',
            'CurrentURI',
            'CurrentURIMetaData',
            'NextURI',
            'NextURIMetaData',
            'PlayMedium',
            'RecordMedium',
            'WriteStatus',
          ],
        ),
        'GetDeviceCapabilities': (
          input: ['InstanceID'],
          output: ['PlayMedia', 'RecMedia', 'RecQualityModes'],
        ),
        'GetTransportSettings': (
          input: ['InstanceID'],
          output: ['PlayMode', 'RecQualityMode'],
        ),
      },
      'rendering' => <String, ({List<String> input, List<String> output})>{
        'SetVolume': (
          input: ['InstanceID', 'Channel', 'DesiredVolume'],
          output: [],
        ),
        'GetVolume': (
          input: ['InstanceID', 'Channel'],
          output: ['CurrentVolume'],
        ),
        'SetMute': (
          input: ['InstanceID', 'Channel', 'DesiredMute'],
          output: [],
        ),
        'GetMute': (input: ['InstanceID', 'Channel'], output: ['CurrentMute']),
      },
      _ => <String, ({List<String> input, List<String> output})>{
        'GetProtocolInfo': (input: [], output: ['Source', 'Sink']),
        'GetCurrentConnectionIDs': (input: [], output: ['ConnectionIDs']),
        'GetCurrentConnectionInfo': (
          input: ['ConnectionID'],
          output: [
            'RcsID',
            'AVTransportID',
            'ProtocolInfo',
            'PeerConnectionManager',
            'PeerConnectionID',
            'Direction',
            'Status',
          ],
        ),
      },
    };
    final variables = <String>{};
    final actionList = actions.entries.map((entry) {
      String argument(String name, String direction) {
        variables.add(name);
        return '<argument><name>$name</name><direction>$direction</direction><relatedStateVariable>A_ARG_TYPE_$name</relatedStateVariable></argument>';
      }

      final arguments = [
        ...entry.value.input.map((name) => argument(name, 'in')),
        ...entry.value.output.map((name) => argument(name, 'out')),
      ].join();
      return '<action><name>${entry.key}</name><argumentList>$arguments</argumentList></action>';
    }).join();
    final stateTable = variables
        .map(
          (name) =>
              '<stateVariable sendEvents="no"><name>A_ARG_TYPE_$name</name><dataType>string</dataType></stateVariable>',
        )
        .join();
    final eventState = service == 'connection'
        ? '<stateVariable sendEvents="yes"><name>SinkProtocolInfo</name><dataType>string</dataType></stateVariable>'
        : '<stateVariable sendEvents="yes"><name>LastChange</name><dataType>string</dataType></stateVariable>';
    return '<?xml version="1.0" encoding="utf-8"?><scpd xmlns="urn:schemas-upnp-org:service-1-0"><specVersion><major>1</major><minor>0</minor></specVersion><actionList>$actionList</actionList><serviceStateTable>$stateTable$eventState</serviceStateTable></scpd>';
  }

  static String soapResponse(
    String serviceType,
    String action,
    Map<String, String> values,
  ) {
    final fields = values.entries
        .map((entry) => '<${entry.key}>${escape(entry.value)}</${entry.key}>')
        .join();
    return '<?xml version="1.0" encoding="utf-8"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:${action}Response xmlns:u="$serviceType">$fields</u:${action}Response></s:Body></s:Envelope>';
  }

  static const soapFault =
      '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault><faultcode>s:Client</faultcode><faultstring>Invalid Action</faultstring><detail><UPnPError xmlns="urn:schemas-upnp-org:control-1-0"><errorCode>401</errorCode><errorDescription>Invalid Action</errorDescription></UPnPError></detail></s:Fault></s:Body></s:Envelope>';

  /// 控制消息仅提取简单标量元素；拒绝 DTD，避免外部实体参与 URI 解析。
  static String? element(String xml, String name) {
    if (xml.contains('<!DOCTYPE') || xml.contains('<!ENTITY')) return null;
    final match = RegExp(
      '<(?:[\\w-]+:)?$name(?:\\s[^>]*)?>([\\s\\S]*?)</(?:[\\w-]+:)?$name\\s*>',
      caseSensitive: false,
    ).firstMatch(xml);
    if (match == null) return null;
    return match
        .group(1)!
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }

  static String formatTime(double seconds) {
    final duration = Duration(
      seconds: seconds.isFinite && seconds > 0 ? seconds.floor() : 0,
    );
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(duration.inHours)}:${two(duration.inMinutes.remainder(60))}:${two(duration.inSeconds.remainder(60))}';
  }

  static double? parseTime(String value) {
    final parts = value.split(':');
    if (parts.length != 3) return null;
    final hours = int.tryParse(parts[0]);
    final minutes = int.tryParse(parts[1]);
    final seconds = double.tryParse(parts[2]);
    if (hours == null ||
        minutes == null ||
        seconds == null ||
        hours < 0 ||
        minutes < 0 ||
        minutes >= 60 ||
        seconds < 0 ||
        seconds >= 60) {
      return null;
    }
    return hours * 3600 + minutes * 60 + seconds;
  }
}
