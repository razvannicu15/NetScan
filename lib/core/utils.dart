import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Simple cooperative cancellation flag.
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Runs [task] for every item using at most [concurrency] parallel workers.
Future<void> runPool<T>(
  Iterable<T> items,
  int concurrency,
  Future<void> Function(T item) task, {
  CancelToken? cancel,
}) async {
  final it = items.iterator;
  Future<void> worker() async {
    while (true) {
      if (cancel?.isCancelled ?? false) return;
      if (!it.moveNext()) return;
      final item = it.current;
      try {
        await task(item);
      } catch (_) {
        // individual failures must never stop the pool
      }
    }
  }

  await Future.wait(List.generate(concurrency, (_) => worker()));
}

/// Runs a system command and returns stdout, or null on failure / timeout.
Future<String?> runCommand(
  String executable,
  List<String> args, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  Process? process;
  try {
    process = await Process.start(executable, args, runInShell: false);
    final out = process.stdout
        .transform(const SystemEncoding().decoder)
        .join()
        .catchError((_) => '');
    process.stderr.drain<void>().catchError((_) {});
    final code = await process.exitCode.timeout(timeout);
    final text = await out;
    if (code != 0 && text.trim().isEmpty) return null;
    return text;
  } on TimeoutException {
    process?.kill();
    return null;
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------- IP helpers

final RegExp _ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');

bool isValidIp(String s) {
  final m = _ipv4.firstMatch(s.trim());
  if (m == null) return false;
  for (var i = 1; i <= 4; i++) {
    if (int.parse(m.group(i)!) > 255) return false;
  }
  return true;
}

int ipToInt(String ip) {
  final p = ip.trim().split('.').map(int.parse).toList();
  return (p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3];
}

String intToIp(int v) =>
    '${(v >> 24) & 255}.${(v >> 16) & 255}.${(v >> 8) & 255}.${v & 255}';

int prefixMask(int prefix) =>
    prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;

/// Usable host addresses of the network [ip]/[prefix].
List<String> hostsInSubnet(String ip, int prefix) {
  final mask = prefixMask(prefix);
  final net = ipToInt(ip) & mask;
  final bcast = net | (~mask & 0xFFFFFFFF);
  if (prefix >= 31) return [ip];
  return [for (var i = net + 1; i < bcast; i++) intToIp(i)];
}

String networkAddress(String ip, int prefix) =>
    intToIp(ipToInt(ip) & prefixMask(prefix));

String broadcastAddress(String ip, int prefix) {
  final mask = prefixMask(prefix);
  return intToIp((ipToInt(ip) & mask) | (~mask & 0xFFFFFFFF));
}

List<String> ipRange(String start, String end) {
  var a = ipToInt(start), b = ipToInt(end);
  if (a > b) {
    final t = a;
    a = b;
    b = t;
  }
  if (b - a > 4096) b = a + 4096; // safety limit
  return [for (var i = a; i <= b; i++) intToIp(i)];
}

bool isPrivateIp(String ip) {
  if (!isValidIp(ip)) return false;
  final p = ip.split('.').map(int.parse).toList();
  return p[0] == 10 ||
      (p[0] == 172 && p[1] >= 16 && p[1] <= 31) ||
      (p[0] == 192 && p[1] == 168) ||
      (p[0] == 100 && p[1] >= 64 && p[1] <= 127);
}

int compareIp(String a, String b) {
  if (!isValidIp(a) || !isValidIp(b)) return a.compareTo(b);
  return ipToInt(a).compareTo(ipToInt(b));
}

// --------------------------------------------------------------- MAC helpers

final RegExp macPattern =
    RegExp(r'([0-9A-Fa-f]{1,2}[:-]){5}[0-9A-Fa-f]{1,2}');

/// Normalises any MAC notation to AA:BB:CC:DD:EE:FF. Returns null if invalid.
String? normalizeMac(String? raw) {
  if (raw == null) return null;
  final m = macPattern.firstMatch(raw);
  if (m == null) return null;
  final parts = m.group(0)!.split(RegExp('[:-]'));
  final mac = parts.map((p) => p.padLeft(2, '0').toUpperCase()).join(':');
  if (mac == '00:00:00:00:00:00' || mac == 'FF:FF:FF:FF:FF:FF') return null;
  if (mac.startsWith('01:00:5E') || mac.startsWith('33:33')) return null;
  return mac;
}

/// True when the MAC is randomised (privacy MAC on phones / laptops).
bool isRandomMac(String mac) {
  final first = int.tryParse(mac.substring(0, 2), radix: 16) ?? 0;
  return (first & 0x02) != 0;
}

List<int>? macBytes(String mac) {
  final n = normalizeMac(mac);
  if (n == null) return null;
  return n.split(':').map((h) => int.parse(h, radix: 16)).toList();
}

String jsonPretty(Object o) => const JsonEncoder.withIndent('  ').convert(o);
