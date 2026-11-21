import 'dart:io';

import 'package:flutter/services.dart';

import '../core/i18n.dart';
import '../core/utils.dart';

class WifiDetails {
  String? ssid;
  String? bssid;
  int? rssi; // dBm
  int? signalPercent;
  String? band; // "2.4 GHz" / "5 GHz" / "6 GHz"
  int? channel;
  String? standard; // "Wi-Fi 6"
  int? linkMbps;
  int? rxMbps;
  int? txMbps;
  String? security;
  List<String> dns = [];

  /// Android: SSID hidden because location permission / service is off.
  bool needsLocation = false;
  bool locationOff = false;

  bool get isWifi => ssid != null || bssid != null || rssi != null;

  String get signalLabel {
    final p = signalPercent;
    if (p == null) return '';
    if (p >= 75) return tr('excelent', 'excellent');
    if (p >= 50) return tr('bun', 'good');
    if (p >= 30) return tr('slab', 'weak');
    return tr('foarte slab', 'very weak');
  }
}

class WifiService {
  static const _ch = MethodChannel('netscan/wifi');
  static bool _asked = false;

  static Future<WifiDetails?> get() async {
    try {
      if (Platform.isAndroid) return await _android();
      if (Platform.isWindows) return await _windows();
    } catch (_) {}
    return null;
  }

  // ------------------------------------------------------------- Android
  static String _ipFromInt(int v) =>
      '${v & 255}.${(v >> 8) & 255}.${(v >> 16) & 255}.${(v >> 24) & 255}';

  static Future<WifiDetails?> _android() async {
    if (!_asked) {
      _asked = true;
      await _ch.invokeMethod<bool>('requestLocation');
    }
    final m = await _ch.invokeMapMethod<String, dynamic>('info');
    if (m == null) return null;
    final w = WifiDetails()
      ..ssid = m['ssid'] as String?
      ..bssid = normalizeMac(m['bssid'] as String?);
    final rssi = m['rssi'] as int?;
    if (rssi != null && rssi > -127 && rssi < 0) {
      w.rssi = rssi;
      w.signalPercent = (2 * (rssi + 100)).clamp(0, 100).toInt();
    }
    final f = m['frequency'] as int?;
    if (f != null && f > 0) {
      if (f < 3000) {
        w.band = '2.4 GHz';
        w.channel = f == 2484 ? 14 : (f - 2407) ~/ 5;
      } else if (f < 5925) {
        w.band = '5 GHz';
        w.channel = (f - 5000) ~/ 5;
      } else {
        w.band = '6 GHz';
        w.channel = (f - 5950) ~/ 5;
      }
    }
    int? pos(Object? v) => (v is int && v > 0) ? v : null;
    w.linkMbps = pos(m['linkSpeed']);
    w.rxMbps = pos(m['rxSpeed']);
    w.txMbps = pos(m['txSpeed']);
    w.standard = switch (m['standard']) {
      4 => 'Wi-Fi 4',
      5 => 'Wi-Fi 5',
      6 => w.band == '6 GHz' ? 'Wi-Fi 6E' : 'Wi-Fi 6',
      8 => 'Wi-Fi 7',
      _ => null,
    };
    w.security = switch (m['security']) {
      0 => tr('Deschisă', 'Open'),
      1 => 'WEP',
      2 => 'WPA2',
      3 => 'WPA2-Enterprise',
      4 => 'WPA3',
      5 || 9 => 'WPA3-Enterprise',
      6 => 'OWE',
      _ => null,
    };
    for (final k in ['dns1', 'dns2']) {
      final v = m[k];
      if (v is int && v != 0) w.dns.add(_ipFromInt(v));
    }
    if (w.ssid == null && w.isWifi) {
      final hasLoc = m['hasLocation'] == true;
      w.needsLocation = !hasLoc;
      if (hasLoc) {
        w.locationOff =
            !((await _ch.invokeMethod<bool>('locationEnabled')) ?? true);
      }
    }
    return w;
  }

  /// Ask again for location permission (after the user tapped the hint).
  static Future<void> requestAgain() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod<bool>('requestLocation');
    } catch (_) {}
  }

  // ------------------------------------------------------------- Windows
  static Future<WifiDetails?> _windows() async {
    final out = await runCommand('netsh', ['wlan', 'show', 'interfaces'],
        timeout: const Duration(seconds: 4));
    if (out == null) return null;
    final w = WifiDetails();
    var connected = false;
    final rates = <int>[];
    for (final raw in out.split('\n')) {
      final i = raw.indexOf(':');
      if (i < 0) continue;
      final key = raw.substring(0, i).trim();
      final value = raw.substring(i + 1).trim();
      final k = key.toLowerCase();
      if (value.isEmpty) continue;
      if (key == 'SSID') {
        w.ssid = value;
        connected = true;
      } else if (key == 'BSSID' || k.contains('bssid')) {
        w.bssid ??= normalizeMac(value);
      } else if (RegExp(r'^\d{1,3}\s?%$').hasMatch(value)) {
        w.signalPercent = int.parse(value.replaceAll(RegExp(r'[^\d]'), ''));
      } else if (value.contains('802.11')) {
        final v = value.toLowerCase();
        w.standard = v.contains('be')
            ? 'Wi-Fi 7'
            : v.contains('ax')
                ? 'Wi-Fi 6'
                : v.contains('ac')
                    ? 'Wi-Fi 5'
                    : v.contains('n')
                        ? 'Wi-Fi 4'
                        : value;
      } else if (RegExp(r'^\d(\.\d)?\s?GHz$', caseSensitive: false)
          .hasMatch(value)) {
        w.band = value.replaceAll(' ', '').replaceAll('GHz', ' GHz');
      } else if ((k.contains('chan') || k.contains('canal') || k.contains('kanal')) &&
          int.tryParse(value) != null) {
        w.channel = int.parse(value);
      } else if (value.toUpperCase().contains('WPA') ||
          value.toUpperCase().contains('WEP')) {
        w.security ??= value;
      } else if (k.contains('mbps')) {
        final n = double.tryParse(value.replaceAll(',', '.'));
        if (n != null) rates.add(n.round());
      }
    }
    if (!connected && w.bssid == null) return null;
    if (rates.isNotEmpty) w.rxMbps = rates[0];
    if (rates.length > 1) w.txMbps = rates[1];
    w.linkMbps = w.rxMbps;
    final p = w.signalPercent;
    if (p != null) w.rssi = (p / 2 - 100).round();
    if (w.band == null && w.channel != null) {
      w.band = w.channel! <= 14 ? '2.4 GHz' : '5 GHz';
    }
    if (w.band == '6 GHz' && w.standard == 'Wi-Fi 6') w.standard = 'Wi-Fi 6E';
    return w;
  }
}
