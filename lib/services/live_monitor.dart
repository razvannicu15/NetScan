import 'dart:io';

import 'package:flutter/services.dart';

import '../core/utils.dart';
import 'storage.dart';
import 'wifi_info.dart';
import 'wifi_scan.dart';

/// One fast reading of the current Wi-Fi connection.
class LiveSample {
  LiveSample({this.ssid, this.bssid, this.rssi, this.band, this.channel, this.linkMbps});
  final String? ssid;
  final String? bssid;
  final int? rssi;
  final String? band;
  final int? channel;
  final int? linkMbps;
}

class LiveWifi {
  static const _ch = MethodChannel('netscan/wifi');

  /// Cheap read of the connected network (Android: no scan throttling).
  static Future<LiveSample?> read() async {
    try {
      if (Platform.isAndroid) {
        final m = await _ch.invokeMapMethod<String, dynamic>('live');
        if (m == null) return null;
        final f = m['frequency'] as int? ?? 0;
        final rssi = m['rssi'] as int?;
        return LiveSample(
          ssid: m['ssid'] as String?,
          bssid: normalizeMac(m['bssid'] as String?),
          rssi: (rssi != null && rssi < 0 && rssi > -127) ? rssi : null,
          band: bandFromFreq(f),
          channel: channelFromFreq(f),
          linkMbps: (m['linkSpeed'] as int? ?? 0) > 0 ? m['linkSpeed'] as int : null,
        );
      }
      if (Platform.isWindows) {
        final w = await WifiService.get();
        if (w == null) return null;
        return LiveSample(
          ssid: w.ssid,
          bssid: w.bssid,
          rssi: w.rssi,
          band: w.band,
          channel: w.channel,
          linkMbps: w.linkMbps,
        );
      }
    } catch (_) {}
    return null;
  }

  /// Short tone; [level] 1 (weak, low pitch) … 9 (strong, high pitch).
  static Future<void> tone(int level) async {
    try {
      if (Platform.isAndroid) {
        await _ch.invokeMethod<void>('tone', {'level': level});
      } else {
        await SystemSound.play(SystemSoundType.click);
      }
    } catch (_) {}
  }
}

/// Access point / band changes recorded while monitoring (kept on device).
class RoamEvent {
  RoamEvent({
    required this.at,
    this.fromBssid,
    this.toBssid,
    this.fromBand,
    this.toBand,
    this.fromChannel,
    this.toChannel,
    this.rssi,
  });

  final DateTime at;
  final String? fromBssid;
  final String? toBssid;
  final String? fromBand;
  final String? toBand;
  final int? fromChannel;
  final int? toChannel;
  final int? rssi;

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'fb': fromBssid,
        'tb': toBssid,
        'fband': fromBand,
        'tband': toBand,
        'fc': fromChannel,
        'tc': toChannel,
        'rssi': rssi,
      };

  static RoamEvent? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = DateTime.tryParse(j['at'] as String? ?? '');
    if (at == null) return null;
    return RoamEvent(
      at: at,
      fromBssid: j['fb'] as String?,
      toBssid: j['tb'] as String?,
      fromBand: j['fband'] as String?,
      toBand: j['tband'] as String?,
      fromChannel: j['fc'] as int?,
      toChannel: j['tc'] as int?,
      rssi: j['rssi'] as int?,
    );
  }
}

class RoamingLog {
  RoamingLog._();
  static final RoamingLog instance = RoamingLog._();

  final List<RoamEvent> items = [];
  bool _loaded = false;
  String? _lastBssid;
  String? _lastBand;
  int? _lastChannel;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final j = await Storage.instance.readJson('roaming.json');
    final list = j['items'];
    if (list is List) {
      items.addAll(list.map(RoamEvent.fromJson).whereType<RoamEvent>());
    }
  }

  /// Feed every live sample; returns true when a roam was recorded.
  bool observe(LiveSample s) {
    final b = s.bssid;
    if (b == null) return false;
    final changed = _lastBssid != null && (b != _lastBssid || s.band != _lastBand);
    if (changed) {
      items.insert(
        0,
        RoamEvent(
          at: DateTime.now(),
          fromBssid: _lastBssid,
          toBssid: b,
          fromBand: _lastBand,
          toBand: s.band,
          fromChannel: _lastChannel,
          toChannel: s.channel,
          rssi: s.rssi,
        ),
      );
      if (items.length > 50) items.removeRange(50, items.length);
      Storage.instance.writeJson('roaming.json', {
        'items': [for (final e in items) e.toJson()],
      });
    }
    _lastBssid = b;
    _lastBand = s.band;
    _lastChannel = s.channel;
    return changed;
  }

  Future<void> clear() async {
    items.clear();
    await Storage.instance.writeJson('roaming.json', {'items': []});
  }
}

enum NetKind { wifi, cellular, ethernet, vpn, none, other }

/// What the device is connected through right now.
class NetConnection {
  NetConnection(this.kind, {this.operator, this.ssid});
  final NetKind kind;
  final String? operator;
  final String? ssid;

  static const _ch = MethodChannel('netscan/wifi');

  static Future<NetConnection> current() async {
    try {
      if (Platform.isAndroid) {
        final m = await _ch.invokeMapMethod<String, dynamic>('connection');
        final kind = switch (m?['type']) {
          'wifi' => NetKind.wifi,
          'cellular' => NetKind.cellular,
          'ethernet' => NetKind.ethernet,
          'vpn' => NetKind.vpn,
          'none' => NetKind.none,
          _ => NetKind.other,
        };
        final op = (m?['operator'] as String?)?.trim();
        String? ssid;
        if (kind == NetKind.wifi) ssid = (await LiveWifi.read())?.ssid;
        return NetConnection(kind, operator: (op == null || op.isEmpty) ? null : op, ssid: ssid);
      }
      if (Platform.isWindows) {
        final w = await WifiService.get();
        if (w != null && w.ssid != null) return NetConnection(NetKind.wifi, ssid: w.ssid);
        return NetConnection(NetKind.ethernet);
      }
    } catch (_) {}
    return NetConnection(NetKind.other);
  }

  /// Short human label, e.g. "norAz_5G", "Date mobile · Orange RO", "Ethernet".
  String label(String Function(String ro, String en) tr) => switch (kind) {
        NetKind.wifi => ssid ?? 'Wi-Fi',
        NetKind.cellular => [tr('Date mobile', 'Mobile data'), if (operator != null) operator!].join(' · '),
        NetKind.ethernet => 'Ethernet',
        NetKind.vpn => 'VPN',
        NetKind.none => tr('Fără conexiune', 'Offline'),
        NetKind.other => tr('Rețea', 'Network'),
      };
}

/// Mobile network reading (Android 10+: generation + dBm without extra permission).
class CellReading {
  CellReading({this.operator, this.gen, this.dbm, this.level});
  final String? operator;
  final String? gen; // 5G / 4G / 3G / 2G
  final int? dbm;
  final int? level; // 0..4

  static const _ch = MethodChannel('netscan/wifi');

  static Future<CellReading?> read() async {
    if (!Platform.isAndroid) return null;
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('cell');
      if (m == null) return null;
      final d = m['dbm'] as int?;
      final op = (m['operator'] as String?)?.trim();
      return CellReading(
        operator: (op == null || op.isEmpty) ? null : op,
        gen: m['gen'] as String?,
        dbm: (d != null && d < 0 && d > -150) ? d : null,
        level: m['level'] as int?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Phone compass (Android rotation-vector sensor). Heading in degrees, 0 = north.
class Compass {
  static const _ch = MethodChannel('netscan/wifi');

  static Future<bool> start() async {
    if (!Platform.isAndroid) return false;
    try {
      return (await _ch.invokeMethod<bool>('compassStart')) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod<void>('compassStop');
    } catch (_) {}
  }

  /// Steps counted since [start] (accelerometer based).
  static Future<int?> steps() async {
    try {
      return await _ch.invokeMethod<int>('steps');
    } catch (_) {
      return null;
    }
  }

  static Future<double?> heading() async {
    try {
      return (await _ch.invokeMethod<num>('heading'))?.toDouble();
    } catch (_) {
      return null;
    }
  }
}
