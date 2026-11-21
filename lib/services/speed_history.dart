import 'storage.dart';

class SpeedResult {
  SpeedResult({
    required this.at,
    this.down,
    this.up,
    this.ping,
    this.jitter,
    this.network,
    this.kind,
  });

  final DateTime at;
  final double? down;
  final double? up;
  final double? ping;
  final double? jitter;
  final String? network;
  final String? kind; // wifi / cellular / ethernet …

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'down': down,
        'up': up,
        'ping': ping,
        'jitter': jitter,
        'network': network,
        'kind': kind,
      };

  static double? _d(Object? v) => v is num ? v.toDouble() : null;

  static SpeedResult? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = DateTime.tryParse(j['at'] as String? ?? '');
    if (at == null) return null;
    return SpeedResult(
      at: at,
      down: _d(j['down']),
      up: _d(j['up']),
      ping: _d(j['ping']),
      jitter: _d(j['jitter']),
      network: j['network'] as String?,
      kind: j['kind'] as String?,
    );
  }
}

/// Speed test results kept on the device (newest first, max 100).
class SpeedHistory {
  SpeedHistory._();
  static final SpeedHistory instance = SpeedHistory._();

  final List<SpeedResult> items = [];
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final j = await Storage.instance.readJson('speedtests.json');
    final list = j['items'];
    if (list is List) {
      items
        ..clear()
        ..addAll(list.map(SpeedResult.fromJson).whereType<SpeedResult>());
    }
  }

  Future<void> _save() => Storage.instance.writeJson('speedtests.json', {
        'items': [for (final r in items) r.toJson()],
      });

  Future<void> add(SpeedResult r) async {
    items.insert(0, r);
    if (items.length > 100) items.removeRange(100, items.length);
    await _save();
  }

  Future<void> remove(SpeedResult r) async {
    items.remove(r);
    await _save();
  }

  Future<void> clear() async {
    items.clear();
    await _save();
  }
}
