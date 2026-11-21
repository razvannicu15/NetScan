import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/i18n.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/utils.dart';
import '../services/live_monitor.dart';
import '../services/port_scanner.dart';
import '../services/protocols.dart';
import 'my_connection_page.dart';
import 'port_scan_page.dart';
import 'signal_finder_page.dart';
import 'security_page.dart';
import 'speed_test_page.dart';
import 'traceroute_page.dart';
import 'wifi_analyzer_page.dart';
import 'widgets.dart';

class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tools = <(IconData, String, String, Widget Function())>[
      (Icons.monitor_heart_outlined, tr('Conexiunea mea', 'My connection'),
          tr('Semnal și latență live, roaming', 'Live signal & latency, roaming'),
          () => const MyConnectionPage()),
      (Icons.explore_outlined, tr('Caută semnal', 'Signal finder'),
          tr('Găsește locul cu semnal bun', 'Find the best signal spot'),
          () => const SignalFinderPage()),
      (Icons.shield_outlined, tr('Securitate rețea', 'Network security'),
          tr('Probleme și riscuri găsite la scanare', 'Issues and risks found by the scan'),
          () => const SecurityPage()),
      (Icons.videocam_outlined, tr('Camere ascunse', 'Hidden cameras'),
          tr('Camere video din rețeaua ta', 'Video cameras on your network'),
          () => const CamerasPage()),
      (Icons.wifi_find, tr('Analizor Wi-Fi', 'Wi-Fi analyzer'),
          tr('Rețele din jur, canale, semnal', 'Nearby networks, channels, signal'),
          () => const WifiAnalyzerPage()),
      (Icons.speed, 'Speed test',
          tr('Viteză internet: download, upload, ping', 'Internet speed: download, upload, ping'),
          () => const SpeedTestPage()),
      (Icons.route_outlined, 'Traceroute',
          tr('Drumul pachetelor până la o gazdă', 'Path packets take to a host'),
          () => const TraceroutePage()),
      (Icons.network_ping, 'Ping', tr('Latență și pierderi de pachete', 'Latency and packet loss'),
          () => const PingPage()),
      (Icons.travel_explore, tr('Scanare porturi', 'Port scan'), tr('Orice IP sau hostname', 'Any IP or hostname'),
          () => const _PortHostPage()),
      (Icons.power_settings_new, 'Wake-on-LAN', tr('Pornește un PC prin rețea', 'Wake a PC over the network'),
          () => const WolPage()),
      (Icons.dns_outlined, 'DNS lookup', tr('Hostname ↔ IP', 'Hostname ↔ IP'),
          () => const DnsPage()),
      (Icons.info_outline, tr('Informații rețea', 'Network info'), tr('IP local, gateway, IP public', 'Local IP, gateway, public IP'),
          () => const NetInfoPage()),
    ];
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.medium(title: Text(tr('Instrumente', 'Tools'))),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 320,
                mainAxisExtent: 140,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: tools.length,
              itemBuilder: (context, i) {
                final t = tools[i];
                final cs = Theme.of(context).colorScheme;
                return Card(
                  elevation: 0,
                  color: cs.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute<void>(builder: (_) => t.$4())),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(t.$1, color: cs.onPrimaryContainer),
                          ),
                          const Spacer(),
                          Text(t.$2,
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(t.$3,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================= Ping

class PingPage extends StatefulWidget {
  const PingPage({super.key, this.initialHost});
  final String? initialHost;

  @override
  State<PingPage> createState() => _PingPageState();
}

class _PingPageState extends State<PingPage> {
  List<TableCol> get _pingCols => [
        const TableCol('#', width: 48),
        TableCol(tr('Stare', 'Status'), flex: 2),
        TableCol(tr('Timp', 'Time'), flex: 2, align: TextAlign.right),
      ];

  late final _host = TextEditingController(
      text: widget.initialHost ?? scanner.network?.gateway ?? '8.8.8.8');
  final List<double?> _results = [];
  bool _running = false;
  bool _tcpMode = false;

  Future<void> _start() async {
    final host = _host.text.trim();
    if (host.isEmpty) return;
    setState(() {
      _results.clear();
      _running = true;
    });
    for (var i = 0; i < 1000 && _running && mounted; i++) {
      final sw = Stopwatch()..start();
      double? ms;
      if (_tcpMode) {
        final r = await PortScanner.probe(host, 80, const Duration(seconds: 2));
        if (r != ProbeResult.filtered) {
          ms = sw.elapsedMicroseconds / 1000;
        }
      } else {
        final r = await PingService.ping(host, timeout: const Duration(seconds: 2));
        if (r.alive) ms = r.timeMs ?? sw.elapsedMilliseconds.toDouble();
      }
      if (!mounted || !_running) break;
      setState(() => _results.insert(0, ms));
      final wait = 1000 - sw.elapsedMilliseconds;
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
    }
    if (mounted) setState(() => _running = false);
  }

  @override
  void dispose() {
    _running = false;
    _host.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final ok = _results.whereType<double>().toList();
    final loss = _results.isEmpty
        ? 0
        : ((_results.length - ok.length) * 100 / _results.length).round();
    String f(double v) => v.toStringAsFixed(v < 10 ? 1 : 0);

    return Scaffold(
      appBar: AppBar(title: const Text('Ping')),
      body: MaxWidth(
        width: 760,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _host,
              enabled: !_running,
              decoration: InputDecoration(
                labelText: tr('Gazdă', 'Host'),
                hintText: tr('192.168.1.1 sau google.com', '192.168.1.1 or google.com'),
                prefixIcon: Icon(Icons.dns_outlined),
              ),
              onSubmitted: (_) => _start(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('ICMP')),
                      ButtonSegment(value: true, label: Text('TCP :80')),
                    ],
                    selected: {_tcpMode},
                    onSelectionChanged: _running
                        ? null
                        : (s) => setState(() => _tcpMode = s.first),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _running
                      ? () => setState(() => _running = false)
                      : _start,
                  icon: Icon(_running ? Icons.stop : Icons.play_arrow),
                  label: Text(_running ? 'Stop' : 'Start'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_results.isNotEmpty)
              Card(
                elevation: 0,
                color: cs.primaryContainer,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 28,
                    runSpacing: 12,
                    children: [
                      for (final (l, v) in [
                        (tr('Trimise', 'Sent'), '${_results.length}'),
                        (tr('Pierdere', 'Loss'), '$loss%'),
                        ('Min', ok.isEmpty ? '—' : '${f(ok.reduce((a, b) => a < b ? a : b))} ms'),
                        (tr('Medie', 'Avg'), ok.isEmpty ? '—' : '${f(ok.reduce((a, b) => a + b) / ok.length)} ms'),
                        ('Max', ok.isEmpty ? '—' : '${f(ok.reduce((a, b) => a > b ? a : b))} ms'),
                      ])
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l,
                                style: tt.labelMedium?.copyWith(
                                    color: cs.onPrimaryContainer
                                        .withValues(alpha: 0.7))),
                            Text(v,
                                style: tt.titleLarge?.copyWith(
                                    color: cs.onPrimaryContainer)),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            if (_results.isNotEmpty) _Sparkline(values: _results.reversed.take(60).toList()),
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 8),
              TableCard(
                margin: EdgeInsets.zero,
                header: _pingCols,
                children: [
                  for (var i = 0; i < _results.length && i < 200; i++)
                    TableDataRow(
                      cols: _pingCols,
                      cells: [
                        CellText('${_results.length - i}', muted: true),
                        CellText(_results[i] == null ? 'Timeout' : 'OK',
                            color: _results[i] == null ? cs.error : cs.primary),
                        CellText(_results[i] == null ? '—' : '${f(_results[i]!)} ms',
                            bold: true),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.values});
  final List<double?> values;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 72,
      child: CustomPaint(
        painter: _SparkPainter(values, cs.primary, cs.error),
        size: Size.infinite,
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color, this.errColor);
  final List<double?> values;
  final Color color;
  final Color errColor;

  @override
  void paint(Canvas canvas, Size size) {
    final ok = values.whereType<double>();
    final maxV = ok.isEmpty ? 1.0 : ok.reduce((a, b) => a > b ? a : b) * 1.15;
    final n = values.length;
    final barW = size.width / 60;
    for (var i = 0; i < n; i++) {
      final v = values[i];
      final x = i * barW;
      final paint = Paint()
        ..color = v == null ? errColor : color.withValues(alpha: 0.8);
      final raw = v == null ? size.height : (v / maxV) * size.height;
      final double h = raw.clamp(2.0, size.height).toDouble();
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 1, size.height - h, barW - 2, h),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => true;
}

// =============================================================== Port host

class _PortHostPage extends StatefulWidget {
  const _PortHostPage();

  @override
  State<_PortHostPage> createState() => _PortHostPageState();
}

class _PortHostPageState extends State<_PortHostPage> {
  final _host = TextEditingController();

  Future<void> _go() async {
    var host = _host.text.trim();
    if (host.isEmpty) return;
    if (!isValidIp(host)) {
      try {
        final r = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 4));
        final v4 = r.where((a) => a.type == InternetAddressType.IPv4);
        host = (v4.isNotEmpty ? v4.first : r.first).address;
      } catch (_) {
        if (mounted) toast(context, tr('Nu pot rezolva „$host”', 'Cannot resolve “$host”'));
        return;
      }
    }
    if (!mounted) return;
    Navigator.pushReplacement(context,
        MaterialPageRoute<void>(builder: (_) => PortScanPage(host: host)));
  }

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Scanare porturi', 'Port scan'))),
      body: MaxWidth(
        width: 760,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _host,
              autofocus: true,
              decoration: InputDecoration(
                labelText: tr('IP sau hostname', 'IP or hostname'),
                hintText: '192.168.1.10',
                prefixIcon: Icon(Icons.dns_outlined),
              ),
              onSubmitted: (_) => _go(),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _go,
              icon: const Icon(Icons.arrow_forward),
              label: Text(tr('Continuă', 'Continue')),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================ Wake-on-LAN

class WolPage extends StatefulWidget {
  const WolPage({super.key});

  @override
  State<WolPage> createState() => _WolPageState();
}

class _WolPageState extends State<WolPage> {
  final _mac = TextEditingController();

  @override
  void dispose() {
    _mac.dispose();
    super.dispose();
  }

  Future<void> _send(String mac) async {
    if (normalizeMac(mac) == null) {
      toast(context, tr('Adresă MAC invalidă', 'Invalid MAC address'));
      return;
    }
    final ok = await WakeOnLan.send(mac, broadcast: scanner.network?.broadcast);
    if (mounted) toast(context, ok ? tr('Magic packet trimis către $mac', 'Magic packet sent to $mac') : tr('Eroare la trimitere', 'Send error'));
  }

  @override
  Widget build(BuildContext context) {
    final withMac = scanner.devices
        .where((d) => d.mac != null && !d.isSelf)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Wake-on-LAN')),
      body: MaxWidth(
        width: 760,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _mac,
              decoration: InputDecoration(
                labelText: tr('Adresă MAC', 'MAC address'),
                hintText: 'AA:BB:CC:DD:EE:FF',
                prefixIcon: Icon(Icons.fingerprint),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _send(_mac.text),
              icon: const Icon(Icons.power_settings_new),
              label: Text(tr('Trimite magic packet', 'Send magic packet')),
            ),
            if (withMac.isNotEmpty) SectionHeader(tr('Din ultima scanare', 'From last scan')),
            for (final d in withMac)
              ListTile(
                leading: DeviceAvatar(device: d, size: 40),
                title: Text(d.displayName),
                subtitle: Text('${d.ip} · ${d.mac}'),
                trailing: IconButton(
                  icon: const Icon(Icons.power_settings_new),
                  onPressed: () => _send(d.mac!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ================================================================== DNS

class DnsPage extends StatefulWidget {
  const DnsPage({super.key});

  @override
  State<DnsPage> createState() => _DnsPageState();
}

class _DnsPageState extends State<DnsPage> {
  final _q = TextEditingController();
  List<String> _out = [];
  bool _busy = false;

  Future<void> _go() async {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _busy = true;
      _out = [];
    });
    final out = <String>[];
    try {
      if (isValidIp(q)) {
        final r = await InternetAddress(q).reverse().timeout(const Duration(seconds: 5));
        out.add(r.host == q ? tr('Nicio înregistrare PTR', 'No PTR record') : r.host);
      } else {
        final r = await InternetAddress.lookup(q).timeout(const Duration(seconds: 5));
        out.addAll(r.map((a) =>
            '${a.address}  (${a.type == InternetAddressType.IPv4 ? 'IPv4' : 'IPv6'})'));
      }
    } catch (e) {
      out.add(tr('Eroare: nu s-a putut rezolva', 'Error: could not resolve'));
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _out = out;
      });
    }
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DNS lookup')),
      body: MaxWidth(
        width: 760,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _q,
              decoration: InputDecoration(
                labelText: tr('Hostname sau IP', 'Hostname or IP'),
                hintText: 'google.com / 192.168.1.1',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _busy
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        icon: const Icon(Icons.arrow_forward), onPressed: _go),
              ),
              onSubmitted: (_) => _go(),
            ),
            const SizedBox(height: 8),
            for (final o in _out)
              ListTile(
                leading: const Icon(Icons.subdirectory_arrow_right),
                title: SelectableText(o),
                onLongPress: () => copyText(context, o.split(' ').first),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================== Network info

class NetInfoPage extends StatefulWidget {
  const NetInfoPage({super.key});

  @override
  State<NetInfoPage> createState() => _NetInfoPageState();
}

class _NetInfoPageState extends State<NetInfoPage> {
  String? _publicIp;
  String? _isp;
  bool _loading = true;
  CellReading? _cell;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (scanner.noLan) {
      CellReading.read().then((c) {
        if (mounted) setState(() => _cell = c);
      });
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(Uri.parse('https://ipinfo.io/json'));
      final res = await req.close().timeout(const Duration(seconds: 6));
      final body = await res.transform(utf8.decoder).join();
      final j = jsonDecode(body) as Map<String, dynamic>;
      _publicIp = j['ip'] as String?;
      _isp = [(j['org'] as String?)?.replaceFirst(RegExp(r'^AS\d+\s+'), ''), j['city'], j['country']]
          .whereType<String>()
          .join(' · ');
    } catch (_) {
      try {
        final req = await client.getUrl(Uri.parse('https://api.ipify.org'));
        final res = await req.close().timeout(const Duration(seconds: 6));
        _publicIp = (await res.transform(utf8.decoder).join()).trim();
      } catch (_) {}
    } finally {
      client.close(force: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final net = scanner.network;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Informații rețea', 'Network info'))),
      body: MaxWidth(
        width: 760,
        child: ListView(
          children: [
            if (scanner.noLan) ...[
              SectionHeader(tr('Date mobile', 'Mobile data')),
              TableCard(children: [
                InfoRow(Icons.cell_tower, tr('Operator', 'Carrier'),
                    _cell?.operator ?? scanner.connection?.operator, copy: false),
                InfoRow(Icons.signal_cellular_alt, tr('Rețea', 'Network'), _cell?.gen, copy: false),
                InfoRow(Icons.network_cell, tr('Semnal', 'Signal'),
                    _cell?.dbm == null
                        ? null
                        : '${_cell!.dbm} dBm${_cell!.level != null ? ' · ${tr('nivel', 'level')} ${_cell!.level}/4' : ''}',
                    copy: false),
                InfoRow(Icons.lan_outlined, tr('IP în rețeaua operatorului', 'IP in carrier network'), net?.ip),
              ]),
            ] else ...[
              SectionHeader(tr('Rețea locală', 'Local network')),
              TableCard(children: [
                InfoRow(Icons.wifi, 'Wi-Fi', scanner.wifi?.ssid),
                InfoRow(Icons.settings_ethernet, tr('Interfață', 'Interface'), net?.interfaceName),
                InfoRow(Icons.lan_outlined, 'IP local', net?.ip),
                InfoRow(Icons.fingerprint, tr('MAC propriu', 'Own MAC'), net?.selfMac),
                InfoRow(Icons.account_tree_outlined, tr('Subrețea', 'Subnet'), net?.id),
                InfoRow(Icons.router_outlined, 'Gateway', net?.gateway),
                InfoRow(Icons.campaign_outlined, 'Broadcast', net?.broadcast),
                InfoRow(Icons.computer, tr('Nume dispozitiv', 'Device name'),
                    Platform.localHostname == 'localhost' ? null : Platform.localHostname),
              ]),
            ],
            const SectionHeader('Internet'),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              TableCard(children: [
                InfoRow(Icons.public, tr('IP public', 'Public IP'), _publicIp ?? tr('Indisponibil', 'Unavailable')),
                InfoRow(Icons.business_outlined, tr('Furnizor / locație', 'ISP / location'), _isp),
              ]),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }
}
