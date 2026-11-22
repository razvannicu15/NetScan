import 'dart:io';

import 'package:flutter/services.dart';

import '../core/i18n.dart';

int? _v(Object? x) {
  if (x is! int) return null;
  if (x == 2147483647 || x == -2147483648 || x.abs() > 100000000000) return null;
  return x;
}

class MobileCell {
  MobileCell({
    required this.type,
    required this.registered,
    this.ci,
    this.tac,
    this.pci,
    this.arfcn,
    this.bands = const [],
    this.mcc,
    this.mnc,
    this.op,
    this.dbm,
    this.level,
    this.rsrp,
    this.rsrq,
    this.snr,
  });

  final String type; // 5G / 4G / 3G / 2G
  final bool registered;
  final int? ci;
  final int? tac;
  final int? pci;
  final int? arfcn;
  final List<int> bands;
  final String? mcc;
  final String? mnc;
  final String? op;
  final int? dbm;
  final int? level;
  final int? rsrp;
  final int? rsrq;
  final int? snr;

  /// LTE: eNodeB id and sector from the 28-bit cell id.
  int? get enb => (type == '4G' && ci != null) ? ci! >> 8 : null;
  int? get sector => (type == '4G' && ci != null) ? ci! & 0xFF : null;

  /// e.g. "B3 · 1800 MHz", "n78 · 3500 MHz".
  String? get bandLabel => BandInfo.label(type, arfcn, bands);

  static MobileCell? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final bands = raw['bands'];
    return MobileCell(
      type: raw['type'] as String? ?? '?',
      registered: raw['registered'] == true,
      ci: _v(raw['ci']),
      tac: _v(raw['tac']),
      pci: _v(raw['pci']),
      arfcn: _v(raw['arfcn']),
      bands: bands is List ? bands.whereType<int>().toList() : const [],
      mcc: raw['mcc'] as String?,
      mnc: raw['mnc'] as String?,
      op: raw['op'] as String?,
      dbm: _v(raw['dbm']),
      level: _v(raw['level']),
      rsrp: _v(raw['rsrp']),
      rsrq: _v(raw['rsrq']),
      snr: _v(raw['snr']),
    );
  }
}

class MobileNetInfo {
  MobileNetInfo({
    this.operator,
    this.simOperator,
    this.simCountry,
    this.netCountry,
    this.mccmnc,
    this.roaming = false,
    this.hasLocation = true,
    this.rsrp,
    this.rsrq,
    this.sinr,
    this.dbm,
    this.cells = const [],
    this.nr = false,
  });

  final String? operator;
  final String? simOperator;
  final String? simCountry;
  final String? netCountry;
  final String? mccmnc;
  final bool roaming;
  final bool hasLocation;
  final int? rsrp;
  final int? rsrq;
  final int? sinr;
  final int? dbm;
  final List<MobileCell> cells;
  final bool nr; // quality values come from 5G

  MobileCell? get serving => cells.where((c) => c.registered).firstOrNull;
  List<MobileCell> get neighbours => cells.where((c) => !c.registered).toList()
    ..sort((a, b) => (b.dbm ?? -200).compareTo(a.dbm ?? -200));

  String? get generation => nr ? '5G' : (serving?.type ?? (rsrp != null ? '4G' : null));

  static const _ch = MethodChannel('netscan/wifi');

  static Future<MobileNetInfo?> read() async {
    if (!Platform.isAndroid) return null;
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('cellinfo');
      if (m == null) return null;
      String? s(String k) {
        final v = (m[k] as String?)?.trim();
        return (v == null || v.isEmpty) ? null : v;
      }

      final nrRsrp = _v(m['nrRsrp']);
      final nr = nrRsrp != null;
      final cells = (m['cells'] as List? ?? const [])
          .map(MobileCell.fromMap)
          .whereType<MobileCell>()
          .toList();
      return MobileNetInfo(
        operator: s('operator'),
        simOperator: s('simOperator'),
        simCountry: s('simCountry')?.toUpperCase(),
        netCountry: s('netCountry')?.toUpperCase(),
        mccmnc: s('mccmnc'),
        roaming: m['roaming'] == true,
        hasLocation: m['hasLocation'] != false,
        nr: nr,
        rsrp: nr ? nrRsrp : _v(m['lteRsrp']),
        rsrq: nr ? _v(m['nrRsrq']) : _v(m['lteRsrq']),
        sinr: nr ? _v(m['nrSinr']) : _v(m['lteSnr']),
        dbm: nr ? _v(m['nrDbm']) : _v(m['lteDbm']),
        cells: cells,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Ratings in plain language: 3 = excellent … 0 = poor.
class SignalRating {
  static int rsrp(int v) => v >= -80 ? 3 : v >= -90 ? 2 : v >= -100 ? 1 : 0;
  static int rsrq(int v) => v >= -10 ? 3 : v >= -15 ? 2 : v >= -20 ? 1 : 0;
  static int sinr(int v) => v >= 20 ? 3 : v >= 13 ? 2 : v >= 0 ? 1 : 0;

  static String word(int r) => switch (r) {
        3 => tr('excelent', 'excellent'),
        2 => tr('bun', 'good'),
        1 => tr('mediu', 'fair'),
        _ => tr('slab', 'poor'),
      };

  /// One-sentence diagnosis.
  static String? verdict(MobileNetInfo i) {
    final p = i.rsrp, q = i.sinr ?? i.rsrq;
    if (p == null) return null;
    final rp = rsrp(p);
    final rq = i.sinr != null ? sinr(i.sinr!) : (i.rsrq != null ? rsrq(i.rsrq!) : 2);
    if (rp >= 2 && rq >= 2) {
      return tr('Semnal puternic și curat — conexiunea ar trebui să fie rapidă.',
          'Strong, clean signal — the connection should be fast.');
    }
    if (rp >= 2 && rq < 2) {
      return tr('Semnal puternic, dar cu interferențe: antena e aglomerată, viteza poate varia.',
          'Strong signal but noisy: the cell is busy, speed may vary.');
    }
    if (rp == 1) {
      return tr('Semnal mediu. Lângă o fereastră sau mai sus ar fi mai bine.',
          'Fair signal. Near a window or higher up it would improve.');
    }
    if (q == null || rq <= 1) {
      return tr('Semnal slab: aproape de limita de acoperire. Încearcă alt loc.',
          'Weak signal: close to the coverage edge. Try another spot.');
    }
    return tr('Semnal slab, dar stabil.', 'Weak but stable signal.');
  }
}

class BandInfo {
  // band, DL low MHz, N_offs, N range
  static const _lte = [
    (1, 2110.0, 0, 0, 599),
    (3, 1805.0, 1200, 1200, 1949),
    (7, 2620.0, 2750, 2750, 3449),
    (8, 925.0, 3450, 3450, 3799),
    (20, 791.0, 6150, 6150, 6449),
    (28, 758.0, 9210, 9210, 9659),
    (32, 1452.0, 9920, 9920, 10359),
    (38, 2570.0, 37750, 37750, 38249),
    (40, 2300.0, 38650, 38650, 39649),
    (41, 2496.0, 39650, 39650, 41589),
    (42, 3400.0, 41590, 41590, 43589),
  ];

  // NR band, ARFCN range
  static const _nr = [
    (78, 620000, 653333),
    (77, 653334, 680000),
    (28, 151600, 160600),
    (1, 422000, 434000),
    (3, 361000, 376000),
    (7, 524000, 538000),
    (38, 514000, 524000),
    (20, 158200, 164200),
    (8, 185000, 192000),
  ];

  static double nrFreq(int n) =>
      n < 600000 ? n * 0.005 : 3000 + (n - 600000) * 0.015;

  static String? label(String type, int? arfcn, List<int> bands) {
    if (type == '4G' && arfcn != null) {
      for (final b in _lte) {
        if (arfcn >= b.$4 && arfcn <= b.$5) {
          final f = b.$2 + 0.1 * (arfcn - b.$3);
          return 'B${b.$1} · ${_round(f)} MHz';
        }
      }
      if (bands.isNotEmpty) return 'B${bands.first}';
    }
    if (type == '5G' && arfcn != null) {
      final f = nrFreq(arfcn);
      final band = bands.isNotEmpty
          ? bands.first
          : _nr.where((b) => arfcn >= b.$2 && arfcn <= b.$3).map((b) => b.$1).firstOrNull;
      return [if (band != null) 'n$band', '${_round(f)} MHz'].join(' · ');
    }
    if (bands.isNotEmpty) return '${type == '5G' ? 'n' : 'B'}${bands.first}';
    return null;
  }

  /// Rounds to the usual marketing name (e.g. 1842.5 → 1800).
  static int _round(double f) {
    const names = [700, 800, 900, 1500, 1800, 2100, 2300, 2600, 3500, 3700];
    var best = f.round();
    var diff = 1e9;
    for (final n in names) {
      final d = (n - f).abs();
      if (d < diff && d < 120) {
        diff = d;
        best = n;
      }
    }
    return best;
  }
}
