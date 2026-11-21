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
