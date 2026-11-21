import 'package:flutter/material.dart';

import '../core/ports.dart';
import '../core/utils.dart';

enum DeviceType {
  router('Router / rețea', Icons.router_outlined),
  computer('Calculator', Icons.computer_outlined),
  phone('Telefon / tabletă', Icons.smartphone_outlined),
  printer('Imprimantă', Icons.print_outlined),
  tv('TV / media', Icons.tv_outlined),
  camera('Cameră', Icons.videocam_outlined),
  nas('NAS / server', Icons.storage_outlined),
  speaker('Boxă', Icons.speaker_outlined),
  console('Consolă', Icons.sports_esports_outlined),
  iot('Smart home / IoT', Icons.lightbulb_outline),
  unknown('Necunoscut', Icons.devices_other_outlined);

  const DeviceType(this.label, this.icon);
  final String label;
  final IconData icon;
}

class OpenPort {
  OpenPort(this.port, {this.banner});
  final int port;
  String? banner;
  String get service => serviceName(port);
}

class Device {
  Device(this.ip) : firstSeen = DateTime.now(), lastSeen = DateTime.now();

  final String ip;
  String? mac;
  String? vendor;
  String? hostname; // reverse DNS
  String? netbiosName;
  String? workgroup;
  String? mdnsName;
  String? upnpName;
  String? upnpModel;
  String? upnpManufacturer;
  String? serverHeader;
  int? ttl;
  double? latencyMs;
  final Set<int> discoveryPorts = {};
  List<OpenPort> openPorts = [];
  bool isGateway = false;
  bool isSelf = false;
  bool isNew = false;
  bool online = true;
  String? customName;
  DateTime firstSeen;
  DateTime lastSeen;

  String get autoName {
    String? clean(String? s) {
      if (s == null) return null;
      var t = s.trim();
      if (t.endsWith('.')) t = t.substring(0, t.length - 1);
      if (t.endsWith('.local')) t = t.substring(0, t.length - 6);
      if (t.isEmpty || t == ip) return null;
      return t;
    }

    return clean(upnpName) ??
        clean(mdnsName) ??
        clean(netbiosName) ??
        clean(hostname) ??
        (isSelf ? 'Acest dispozitiv' : null) ??
        (isGateway ? 'Router' : null) ??
        vendor ??
        ip;
  }

  String get displayName =>
      (customName != null && customName!.trim().isNotEmpty)
          ? customName!
          : autoName;

  DeviceType get type => DeviceClassifier.classify(this);

  Set<int> get allKnownPorts =>
      {...discoveryPorts, ...openPorts.map((p) => p.port)};

  String? get osGuess {
    final t = ttl;
    if (t == null) return null;
    if (t <= 64) return 'Linux / Android / iOS / macOS';
    if (t <= 128) return 'Windows';
    return 'Echipament de rețea';
  }

  /// Key used for persistence (MAC when known, otherwise IP).
  String get storeKey => mac ?? 'ip:$ip';

  Map<String, dynamic> toJson() => {
        'ip': ip,
        'mac': mac,
        'vendor': vendor,
        'hostname': hostname,
        'netbios': netbiosName,
        'mdns': mdnsName,
        'upnp': upnpName,
        'customName': customName,
        'firstSeen': firstSeen.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
        'ports': discoveryPorts.toList(),
      };

  static Device fromJson(Map<String, dynamic> j) {
    final d = Device(j['ip'] as String)
      ..mac = j['mac'] as String?
      ..vendor = j['vendor'] as String?
      ..hostname = j['hostname'] as String?
      ..netbiosName = j['netbios'] as String?
      ..mdnsName = j['mdns'] as String?
      ..upnpName = j['upnp'] as String?
      ..customName = j['customName'] as String?
      ..online = false;
    d.firstSeen = DateTime.tryParse(j['firstSeen'] as String? ?? '') ??
        DateTime.now();
    d.lastSeen =
        DateTime.tryParse(j['lastSeen'] as String? ?? '') ?? DateTime.now();
    final ports = j['ports'];
    if (ports is List) d.discoveryPorts.addAll(ports.whereType<int>());
    return d;
  }
}

class DeviceClassifier {
  static bool _any(String text, List<String> words) =>
      words.any((w) => text.contains(w));

  static DeviceType classify(Device d) {
    if (d.isGateway) return DeviceType.router;
    final v = (d.vendor ?? '').toLowerCase();
    final n = [
      d.customName,
      d.hostname,
      d.mdnsName,
      d.netbiosName,
      d.upnpName,
      d.upnpModel,
      d.upnpManufacturer,
      d.serverHeader,
    ].whereType<String>().join(' ').toLowerCase();
    final p = d.allKnownPorts;

    if (p.contains(9100) ||
        p.contains(631) ||
        p.contains(515) ||
        _any(n, ['printer', 'laserjet', 'officejet', 'deskjet', 'imprim']) ||
        _any(v, ['seiko epson', 'brother industries', 'kyocera', 'lexmark'])) {
      return DeviceType.printer;
    }
    if (_any(n, [
          'smarttv', 'smart tv', 'smart-tv', ' tv', 'tv-', '-tv', 'bravia', 'webos', 'tizen', 'roku', 'chromecast', 'firetv',
          'fire tv', 'shield', 'kodi', 'media renderer', 'appletv', 'apple-tv'
        ]) ||
        p.contains(8008) ||
        p.contains(8009)) {
      return DeviceType.tv;
    }
    if (p.contains(554) ||
        p.contains(37777) ||
        _any(n, ['camera', 'ipcam', 'cam-', 'hikvision', 'dahua', 'reolink']) ||
        _any(v, ['hikvision', 'dahua', 'reolink', 'ezviz', 'uniview'])) {
      return DeviceType.camera;
    }
    if (_any(n, ['nas', 'synology', 'qnap', 'diskstation', 'truenas']) ||
        _any(v, ['synology', 'qnap'])) {
      return DeviceType.nas;
    }
    if (_any(n, ['sonos', 'homepod', 'amazon-echo', 'speaker', 'soundbar']) ||
        _any(v, ['sonos', 'bose', 'harman'])) {
      return DeviceType.speaker;
    }
    if (_any(n, ['xbox', 'playstation', 'ps4', 'ps5', 'nintendo']) ||
        _any(v, ['nintendo', 'sony interactive'])) {
      return DeviceType.console;
    }
    if (_any(n, ['iphone', 'ipad', 'android', 'galaxy', 'pixel', 'redmi',
          'oneplus', 'huawei-', 'phone'
        ]) ||
        p.contains(62078)) {
      return DeviceType.phone;
    }
    if (_any(v, [
      'espressif', 'tuya', 'shelly', 'itead', 'sonoff', 'signify',
      'philips lighting', 'broadlink', 'xiaomi communications', 'yeelink',
      'lumi united', 'ring llc', 'nest labs', 'ecobee', 'meross', 'wiz'
    ])) {
      return DeviceType.iot;
    }
    if (p.contains(3389) || p.contains(445) || p.contains(135)) {
      return DeviceType.computer;
    }
    if (v.contains('apple')) {
      return _any(n, ['macbook', 'imac', 'mac-', 'macmini', 'mac mini'])
          ? DeviceType.computer
          : DeviceType.phone;
    }
    if (_any(v, ['raspberry'])) return DeviceType.nas;
    if (_any(v, [
      'samsung', 'huawei', 'xiaomi', 'oneplus', 'oppo', 'vivo', 'motorola',
      'realme', 'honor', 'google'
    ])) {
      return DeviceType.phone;
    }
    if (_any(v, [
      'intel', 'realtek', 'dell', 'lenovo', 'asustek', 'hewlett', 'micro-star',
      'gigabyte', 'liteon', 'azurewave', 'hon hai', 'microsoft'
    ])) {
      return DeviceType.computer;
    }
    if (_any(v, [
          'tp-link', 'netgear', 'ubiquiti', 'mikrotik', 'routerboard', 'zyxel',
          'cisco', 'd-link', 'tenda', 'mercusys', 'aruba', 'juniper', 'avm'
        ]) ||
        p.contains(8291)) {
      return DeviceType.router;
    }
    if (p.contains(22)) return DeviceType.computer;
    if ((d.ttl ?? 0) > 64 && (d.ttl ?? 0) <= 128) return DeviceType.computer;
    if (d.mac != null && isRandomMac(d.mac!)) return DeviceType.phone;
    return DeviceType.unknown;
  }
}
