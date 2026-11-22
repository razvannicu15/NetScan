import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/i18n.dart';
import 'package:flutter/foundation.dart';

import '../core/ports.dart';
import '../core/utils.dart';
import '../models/device.dart';
import 'local_network.dart';
import 'oui_service.dart';
import 'port_scanner.dart';
import 'protocols.dart';
import 'storage.dart';
import 'live_monitor.dart';
import 'wifi_info.dart';

enum ScanPhase { idle, discovering, resolving, done }

class ScanController extends ChangeNotifier {
  ScanController(this.settings);

  final AppSettings settings;
  final DeviceHistory history = DeviceHistory();

  LocalNetwork? network;
  WifiDetails? wifi;
  NetConnection? connection;

  /// On mobile data / offline: there is no local network to scan.
  bool get noLan =>
      connection != null &&
      (connection!.kind == NetKind.cellular || connection!.kind == NetKind.none);
  String? publicIp;
  String? isp;
  DateTime? _publicFetched;
  bool detectingNetwork = false;
  ScanPhase phase = ScanPhase.idle;
  int progressDone = 0;
  int progressTotal = 0;
  String status = '';
  DateTime? lastScan;
  final Map<String, Device> _devices = {};
  CancelToken? _cancel;
  Timer? _notifyTimer;

  bool get scanning =>
      phase == ScanPhase.discovering || phase == ScanPhase.resolving;

  double? get progress =>
      progressTotal == 0 ? null : progressDone / progressTotal;

  List<Device> get devices {
    final list = _devices.values.toList()
      ..sort((a, b) => compareIp(a.ip, b.ip));
    return list;
  }

  /// Devices remembered from previous scans that are not online now.
  List<Device> get offlineDevices {
    final net = network;
    if (net == null) return [];
    final onlineKeys = _devices.values.map((d) => d.storeKey).toSet();
    final onlineIps = _devices.keys.toSet();
    final list = history
        .forNetwork(net.id)
        .values
        .where((d) =>
            !onlineKeys.contains(d.storeKey) &&
            !(d.mac == null && onlineIps.contains(d.ip)))
        .toList()
      ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return list;
  }

  Device? byIp(String ip) => _devices[ip];

  void _scheduleNotify() {
    _notifyTimer ??= Timer(const Duration(milliseconds: 120), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  Future<void> init() async {
    await Future.wait([OuiService.instance.load(), history.load()]);
    await refreshNetwork();
  }

  Future<void> refreshNetwork() async {
    detectingNetwork = true;
    notifyListeners();
    final results = await Future.wait<Object?>([
      LocalNetworkService.detect(),
      WifiService.get(),
      NetConnection.current(),
    ]);
    network = results[0] as LocalNetwork?;
    wifi = results[1] as WifiDetails?;
    connection = results[2] as NetConnection?;
    if (noLan) wifi = null;
    detectingNetwork = false;
    notifyListeners();
    _fetchPublicIp();
  }


  Future<void> requestWifiPermission() async {
    await WifiService.requestAgain();
    wifi = await WifiService.get();
    notifyListeners();
  }

  Device? get gateway {
    for (final d in _devices.values) {
      if (d.isGateway) return d;
    }
    return null;
  }

  Future<void> _fetchPublicIp() async {
    final last = _publicFetched;
    if (last != null && DateTime.now().difference(last).inMinutes < 5) return;
    _publicFetched = DateTime.now();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(Uri.parse('https://ipinfo.io/json'));
      final res = await req.close().timeout(const Duration(seconds: 6));
      final body = await res.transform(utf8.decoder).join();
      final j = jsonDecode(body);
      if (j is Map) {
        publicIp = j['ip'] as String?;
        final org = (j['org'] as String?)?.replaceFirst(RegExp(r'^AS\d+\s+'), '');
        isp = [org, j['city']].whereType<String>().join(' · ');
        notifyListeners();
      }
    } catch (_) {
      _publicFetched = null;
    } finally {
      client.close(force: true);
    }
  }

  void cancel() {
    _cancel?.cancel();
    status = tr('Se oprește…', 'Stopping…');
    notifyListeners();
  }

  List<String> _targets(LocalNetwork net) {
    if (settings.useCustomRange &&
        isValidIp(settings.customStart) &&
        isValidIp(settings.customEnd)) {
      return ipRange(settings.customStart, settings.customEnd);
    }
    return net.hosts;
  }

  String get targetDescription {
    final net = network;
    if (net == null) return '—';
    if (settings.useCustomRange &&
        isValidIp(settings.customStart) &&
        isValidIp(settings.customEnd)) {
      return '${settings.customStart} – ${settings.customEnd}';
    }
    return net.cidr;
  }

  Future<void> scan() async {
    if (scanning) return;
    await refreshNetwork();
    final net = network;
    if (net == null || noLan) {
      status = noLan
          ? tr('Ești pe date mobile. Conectează-te la Wi-Fi ca să scanezi rețeaua.',
              'You are on mobile data. Connect to Wi-Fi to scan the network.')
          : tr('Nu ești conectat la nicio rețea locală.', 'You are not connected to a local network.');
      notifyListeners();
      return;
    }
    final cancel = _cancel = CancelToken();
    final targets = _targets(net);
    final known = history.forNetwork(net.id);
    final timeout = Duration(milliseconds: settings.probeTimeoutMs);

    _devices.clear();
    phase = ScanPhase.discovering;
    progressDone = 0;
    progressTotal = targets.length;
    status = tr('Caut dispozitive în $targetDescription…', 'Looking for devices in $targetDescription…');
    notifyListeners();

    // Self + gateway are always shown.
    final self = Device(net.ip)
      ..isSelf = true
      ..mac = net.selfMac
      ..hostname = Platform.localHostname == 'localhost'
          ? null
          : Platform.localHostname;
    _devices[net.ip] = self;

    // SSDP runs in parallel with the sweep.
    final ssdpFuture = SsdpService.discover();

    final targetSet = targets.toSet();
    final usePing = settings.usePing;
    await runPool<String>(targets, Platform.isWindows ? 24 : 20, (ip) async {
      if (ip == net.ip) {
        progressDone++;
        return;
      }
      final d = Device(ip);
      var alive = false;
      final futures = <Future<void>>[
        for (final port in kDiscoveryPorts)
          PortScanner.probe(ip, port, timeout).then((r) {
            if (r != ProbeResult.filtered) alive = true;
            if (r == ProbeResult.open) d.discoveryPorts.add(port);
          }),
        if (usePing)
          PingService.ping(ip, timeout: const Duration(seconds: 1)).then((p) {
            if (p.alive) {
              alive = true;
              d.ttl = p.ttl;
              d.latencyMs = p.timeMs;
            }
          }),
      ];
      await Future.wait(futures);
      if (alive && !cancel.isCancelled) {
        d.isGateway = ip == net.gateway;
        _devices[ip] = d;
      }
      progressDone++;
      _scheduleNotify();
    }, cancel: cancel);

    if (cancel.isCancelled) {
      _finish(net, known, cancelled: true);
      return;
    }

    // ---- ARP: catches firewalled hosts and supplies MAC addresses.
    phase = ScanPhase.resolving;
    status = tr('Identific dispozitivele…', 'Identifying devices…');
    progressTotal = 0;
    notifyListeners();

    final arp = await ArpService.readTable();
    arp.forEach((ip, mac) {
      if (!targetSet.contains(ip)) return;
      final d = _devices.putIfAbsent(ip, () => Device(ip));
      d.mac ??= mac;
      if (ip == net.gateway) d.isGateway = true;
    });

    final ips = _devices.keys.where((ip) => ip != net.ip).toList();

    // ---- Names: NetBIOS, mDNS, reverse DNS + UPnP (already running).
    final results = await Future.wait([
      NetbiosService.queryAll(ips),
      MdnsService.reverseAll(ips),
      ssdpFuture,
      SnmpService.queryAll(ips),
    ]);
    final nb = results[0] as Map<String, NetbiosInfo>;
    final md = results[1] as Map<String, String>;
    final up = results[2] as Map<String, UpnpInfo>;
    final sn = results[3] as Map<String, SnmpInfo>;
    sn.forEach((ip, info) {
      final d = _devices[ip];
      if (d == null) return;
      d.snmpName = info.name;
      d.snmpDescr = info.descr;
      d.snmpLocation = info.location;
      d.snmpUptimeSec = info.uptimeSec;
    });

    nb.forEach((ip, info) {
      final d = _devices[ip];
      if (d == null) return;
      d.netbiosName = info.name;
      d.workgroup = info.workgroup;
      d.mac ??= info.mac;
    });
    md.forEach((ip, name) => _devices[ip]?.mdnsName = name);
    up.forEach((ip, info) {
      final d = _devices[ip];
      if (d == null) {
        if (!targetSet.contains(ip)) return;
        _devices[ip] = Device(ip);
      }
      final dev = _devices[ip]!;
      dev.upnpName = info.friendlyName;
      dev.upnpModel = info.modelName;
      dev.upnpManufacturer = info.manufacturer;
      dev.serverHeader = info.server;
    });
    notifyListeners();

    await runPool<Device>(_devices.values.toList(), 16, (d) async {
      if (d.isSelf) return;
      try {
        final r = await InternetAddress(d.ip)
            .reverse()
            .timeout(const Duration(seconds: 2));
        if (r.host != d.ip) d.hostname = r.host;
      } catch (_) {}
    }, cancel: cancel);

    // ---- Full common-port scan on every device found.
    if (settings.scanPorts && !cancel.isCancelled) {
      final list = _devices.values.toList()
        ..sort((a, b) => compareIp(a.ip, b.ip));
      progressDone = 0;
      progressTotal = list.length;
      status = tr('Scanez porturile…', 'Scanning ports…');
      notifyListeners();
      final timeout = Duration(milliseconds: settings.probeTimeoutMs);
      await runPool<Device>(list, 4, (d) async {
        final open = <int>{};
        await PortScanner.scan(
          d.ip,
          kTopPorts,
          concurrency: 16,
          timeout: timeout,
          cancel: cancel,
          onOpen: open.add,
          onProgress: (_, __) {},
        );
        if (!cancel.isCancelled) {
          final sorted = open.toList()..sort();
          d.discoveryPorts
            ..clear()
            ..addAll(sorted);
          d.openPorts = [for (final p in sorted) OpenPort(p)];
        } else {
          d.discoveryPorts.addAll(open);
        }
        progressDone++;
        _scheduleNotify();
      }, cancel: cancel);
    }

    _finish(net, known, cancelled: cancel.isCancelled);
  }

  /// Finds the remembered entry for [d]: by MAC, then by IP.
  Device? _match(Map<String, Device> known, Device d) {
    final mac = d.mac;
    if (mac != null) {
      final m = known[mac];
      if (m != null) return m;
    }
    final byIp = known['ip:${d.ip}'];
    if (byIp != null) return byIp;
    if (mac == null) {
      for (final k in known.values) {
        if (k.ip == d.ip) return k;
      }
    }
    return null;
  }

  /// Incremented after every finished scan; [newCount] = new devices in it.
  int scanSerial = 0;
  int newCount = 0;

  List<Device> get newDevices => devices.where((x) => x.isNew).toList();

  void _finish(LocalNetwork net, Map<String, Device> known,
      {bool cancelled = false}) {
    final now = DateTime.now();
    final isFirstScan = known.isEmpty;
    for (final d in _devices.values) {
      d.vendor ??= OuiService.instance.lookup(d.mac);
      final prev = _match(known, d);
      if (prev != null) {
        // Same device seen before: keep identity even if this scan missed the MAC.
        if (d.mac == null && prev.mac != null) {
          d.mac = prev.mac;
          d.vendor ??= prev.vendor ?? OuiService.instance.lookup(prev.mac);
        }
        if (prev.storeKey != d.storeKey) known.remove(prev.storeKey);
        d.customName = prev.customName;
        d.known = prev.known;
        d.firstSeen = prev.firstSeen;
        d.isNew = false;
      } else {
        d.isNew = !isFirstScan && !d.isSelf;
      }
      d.lastSeen = now;
      d.online = true;
      if (d.mac != null) known.remove('ip:${d.ip}');
      known[d.storeKey] = d;
    }
    history.save();
    newCount = cancelled ? 0 : _devices.values.where((d) => d.isNew).length;
    scanSerial++;
    phase = ScanPhase.done;
    lastScan = now;
    final n = _devices.length;
    status = cancelled
        ? tr('Scanare oprită · $n dispozitive', 'Scan stopped · $n devices')
        : tr('$n dispozitive găsite', '$n devices found');
    _notifyTimer?.cancel();
    _notifyTimer = null;
    notifyListeners();
  }

  Future<void> rename(Device d, String? name) async {
    d.customName = (name == null || name.trim().isEmpty) ? null : name.trim();
    final net = network;
    if (net != null) {
      history.forNetwork(net.id)[d.storeKey] = d;
      await history.save();
    }
    notifyListeners();
  }

  /// True once the user marked at least one device (besides this one) as known.
  bool get usesKnown {
    final net = network;
    if (net == null) return false;
    return history.forNetwork(net.id).values.any((d) => d.known && !d.isSelf) ||
        _devices.values.any((d) => d.known && !d.isSelf);
  }

  List<Device> get unknownDevices =>
      usesKnown ? devices.where((d) => !d.known && !d.isSelf).toList() : [];

  List<Device> get cameras => devices.where((d) => d.isCamera).toList();

  Future<void> setKnown(Device d, bool known) async {
    d.known = known;
    if (known) d.isNew = false;
    final net = network;
    if (net != null) {
      history.forNetwork(net.id)[d.storeKey] = d;
      await history.save();
    }
    notifyListeners();
  }

  Future<void> markAllKnown() async {
    final net = network;
    for (final d in _devices.values) {
      d.known = true;
      d.isNew = false;
      if (net != null) history.forNetwork(net.id)[d.storeKey] = d;
    }
    await history.save();
    notifyListeners();
  }

  Future<void> forget(Device d) async {
    final net = network;
    if (net != null) {
      history.forNetwork(net.id).remove(d.storeKey);
      await history.save();
    }
    notifyListeners();
  }

  Future<void> clearHistory() async {
    await history.clear();
    notifyListeners();
  }

  String exportCsv() {
    final b = StringBuffer('IP,MAC,Producator,Nume,Tip,Porturi\n');
    String q(String? s) => '"${(s ?? '').replaceAll('"', '""')}"';
    for (final d in devices) {
      b.writeln([
        d.ip,
        q(d.mac),
        q(d.vendor),
        q(d.displayName),
        q(d.type.label),
        q((d.allKnownPorts.toList()..sort()).join(' ')),
      ].join(','));
    }
    return b.toString();
  }

  @override
  void dispose() {
    _notifyTimer?.cancel();
    super.dispose();
  }

  @visibleForTesting
  void debugAdd(Device d) => _devices[d.ip] = d;
}
