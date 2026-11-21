import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/i18n.dart';
import '../services/live_monitor.dart';
import '../services/protocols.dart';
import 'live_chart.dart';
import 'signal_finder_page.dart';
import 'widgets.dart';

class _PingStats {
  final List<(DateTime, double)> points = [];

  void add(double? ms) {
    final now = DateTime.now();
    points.add((now, ms ?? double.nan));
    points.removeWhere((p) => now.difference(p.$1).inSeconds > 65);
  }

  List<double> get _ok => points.map((p) => p.$2).where((v) => !v.isNaN).toList();
  double? get avg {
    final ok = _ok;
    return ok.isEmpty ? null : ok.reduce((a, b) => a + b) / ok.length;
  }

  double? get jitter {
    final ok = _ok;
    if (ok.length < 2) return null;
    var s = 0.0;
    for (var i = 1; i < ok.length; i++) {
      s += (ok[i] - ok[i - 1]).abs();
    }
    return s / (ok.length - 1);
  }

  double get loss => points.isEmpty
      ? 0
      : points.where((p) => p.$2.isNaN).length * 100 / points.length;
  double? get last {
    if (points.isEmpty) return null;
    final v = points.last.$2;
    return v.isNaN ? null : v;
  }
}

class MyConnectionPage extends StatefulWidget {
  const MyConnectionPage({super.key});

  @override
  State<MyConnectionPage> createState() => _MyConnectionPageState();
}

class _MyConnectionPageState extends State<MyConnectionPage> {
  LiveSample? _s;
  final List<(DateTime, double)> _signal = [];
  final _router = _PingStats();
  final _internet = _PingStats();
  Timer? _fast;
  Timer? _ping;
  bool _pinging = false;
  int _tab = 0;

  static const _internetHost = '1.1.1.1';

  @override
  void initState() {
    super.initState();
    RoamingLog.instance.load().then((_) {
      if (mounted) setState(() {});
    });
    _readSignal();
    _fast = Timer.periodic(const Duration(milliseconds: 500), (_) => _readSignal());
    _ping = Timer.periodic(const Duration(seconds: 1), (_) => _doPing());
  }

  Future<void> _readSignal() async {
    final s = await LiveWifi.read();
    if (!mounted || s == null) return;
    final now = DateTime.now();
    if (s.rssi != null) {
      _signal.add((now, s.rssi!.toDouble()));
      _signal.removeWhere((p) => now.difference(p.$1).inSeconds > 65);
    }
    final roamed = RoamingLog.instance.observe(s);
    setState(() => _s = s);
    if (roamed && mounted) {
      toast(context, tr('Te-ai mutat pe alt access point', 'Roamed to another access point'));
    }
  }

  Future<void> _doPing() async {
    if (_pinging) return;
    _pinging = true;
    final gw = scanner.network?.gateway;
    final res = await Future.wait([
      gw == null
          ? Future.value(PingResult(false))
          : PingService.ping(gw, timeout: const Duration(seconds: 1)),
      PingService.ping(_internetHost, timeout: const Duration(seconds: 1)),
    ]);
    _pinging = false;
    if (!mounted) return;
    setState(() {
      if (gw != null) _router.add(res[0].alive ? res[0].timeMs ?? 1.0 : null);
      _internet.add(res[1].alive ? res[1].timeMs ?? 1.0 : null);
    });
  }

  @override
  void dispose() {
    _fast?.cancel();
    _ping?.cancel();
    super.dispose();
  }

  String _quality(int rssi) => rssi >= -55
      ? tr('excelent', 'excellent')
      : rssi >= -65
          ? tr('bun', 'good')
          : rssi >= -75
              ? tr('slab', 'weak')
              : tr('foarte slab', 'very weak');

  Color _rssiColor(int rssi, ColorScheme cs) => rssi >= -60
      ? Colors.green.shade600
      : rssi >= -72
          ? Colors.orange.shade700
          : cs.error;

  String _ms(double? v) => v == null ? '—' : '${v.toStringAsFixed(v < 10 ? 1 : 0)} ms';

  /// Plain-language diagnosis from both ping targets.
  (IconData, String, Color)? _verdict(ColorScheme cs) {
    if (_internet.points.length < 8) return null;
    final rLoss = _router.loss, iLoss = _internet.loss;
    final rAvg = _router.avg ?? 0, iAvg = _internet.avg ?? 0;
    final routerBad = rLoss > 5 || rAvg > 30;
    final netBad = iLoss > 5 || iAvg > 120;
    if (routerBad) {
      return (Icons.wifi_off, tr('Problema e Wi-Fi-ul: legătura cu routerul e instabilă. Apropie-te sau schimbă canalul.',
          'The problem is Wi-Fi: the link to the router is unstable. Move closer or change channel.'), cs.error);
    }
    if (netBad) {
      return (Icons.public_off, tr('Wi-Fi-ul e bun, dar internetul are întârzieri sau pierderi — probabil la furnizor.',
          'Wi-Fi is fine, but the internet has lag or loss — likely your ISP.'), Colors.orange.shade700);
    }
    return (Icons.check_circle_outline, tr('Conexiune stabilă: Wi-Fi și internet funcționează bine.',
        'Stable connection: Wi-Fi and internet both look good.'), Colors.green.shade600);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final s = _s;
    final rssi = s?.rssi;
    final verdict = _verdict(cs);

    return Scaffold(
      appBar: AppBar(title: Text(tr('Conexiunea mea', 'My connection'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          MaxWidth(
            width: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ---------------------------------------------------- header
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wifi, size: 30, color: rssi == null ? cs.onSurfaceVariant : _rssiColor(rssi, cs)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s?.ssid ?? scanner.wifi?.ssid ?? 'Wi-Fi',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(
                              [
                                if (s?.band != null) s!.band!,
                                if (s?.channel != null) '${tr('canal', 'ch')} ${s!.channel}',
                                if (s?.linkMbps != null) '${s!.linkMbps} Mbps',
                              ].join(' · '),
                              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            if (s?.bssid != null)
                              Text('AP ${s!.bssid}',
                                  style: tt.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      fontFeatures: const [FontFeature.tabularFigures()])),
                          ],
                        ),
                      ),
                      if (rssi != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            TweenAnimationBuilder<double>(
                              tween: Tween(end: rssi.toDouble()),
                              duration: const Duration(milliseconds: 450),
                              builder: (context, v, _) => Text(
                                '${v.round()}',
                                style: tt.displaySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: _rssiColor(rssi, cs),
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                            Text('dBm · ${_quality(rssi)}',
                                style: tt.labelMedium?.copyWith(color: _rssiColor(rssi, cs))),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ---------------------------------------------------- chart
                SegmentedButton<int>(
                  segments: [
                    ButtonSegment(value: 0, icon: const Icon(Icons.network_wifi), label: Text(tr('Semnal', 'Signal'))),
                    ButtonSegment(value: 1, icon: const Icon(Icons.timer_outlined), label: Text(tr('Latență', 'Latency'))),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (v) => setState(() => _tab = v.first),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.fromLTRB(4, 12, 12, 6),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
                  ),
                  child: _tab == 0
                      ? LiveChart(
                          minY: -90,
                          maxY: -20,
                          yStep: 10,
                          series: [
                            ChartSeries(
                              color: rssi == null ? cs.primary : _rssiColor(rssi, cs),
                              points: _signal,
                              width: 3,
                              fill: true,
                            ),
                          ],
                        )
                      : LiveChart(
                          minY: 0,
                          maxY: _latencyMax(),
                          yStep: _latencyMax() / 4,
                          yFormat: (v) => '${v.round()}',
                          series: [
                            ChartSeries(color: cs.primary, points: _router.points, width: 2.5),
                            ChartSeries(color: cs.tertiary, points: _internet.points, width: 2.5),
                          ],
                        ),
                ),
                const SizedBox(height: 12),

                // ---------------------------------------------------- latency
                TableCard(
                  margin: EdgeInsets.zero,
                  header: [
                    TableCol(tr('Țintă', 'Target'), flex: 4),
                    TableCol(tr('Acum', 'Now'), flex: 3, align: TextAlign.right),
                    TableCol(tr('Medie', 'Avg'), flex: 3, align: TextAlign.right),
                    const TableCol('Jitter', flex: 3, align: TextAlign.right),
                    TableCol(tr('Pierderi', 'Loss'), flex: 3, align: TextAlign.right),
                  ],
                  children: [
                    for (final (label, color, st) in [
                      ('Router', cs.primary, _router),
                      ('Internet', cs.tertiary, _internet),
                    ])
                      TableDataRow(
                        cols: [
                          TableCol('', flex: 4),
                          const TableCol('', flex: 3, align: TextAlign.right),
                          const TableCol('', flex: 3, align: TextAlign.right),
                          const TableCol('', flex: 3, align: TextAlign.right),
                          const TableCol('', flex: 3, align: TextAlign.right),
                        ],
                        cells: [
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Flexible(child: CellText(label, bold: true)),
                          ]),
                          CellText(_ms(st.last)),
                          CellText(_ms(st.avg), muted: true),
                          CellText(_ms(st.jitter), muted: true),
                          CellText('${st.loss.round()}%',
                              color: st.loss > 5 ? cs.error : null, bold: st.loss > 5),
                        ],
                      ),
                  ],
                ),
                if (verdict != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: verdict.$3.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(children: [
                      Icon(verdict.$1, color: verdict.$3),
                      const SizedBox(width: 12),
                      Expanded(child: Text(verdict.$2, style: tt.bodyMedium)),
                    ]),
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute<void>(builder: (_) => const SignalFinderPage())),
                  icon: const Icon(Icons.explore_outlined),
                  label: Text(tr('Caută locul cu semnal bun', 'Find the best signal spot')),
                ),

                // ---------------------------------------------------- roaming
                SectionHeader(
                  tr('Roaming între access point-uri', 'Access point roaming'),
                  trailing: RoamingLog.instance.items.isEmpty
                      ? null
                      : TextButton(
                          onPressed: () async {
                            await RoamingLog.instance.clear();
                            if (mounted) setState(() {});
                          },
                          child: Text(tr('Șterge', 'Clear')),
                        ),
                ),
                if (RoamingLog.instance.items.isEmpty)
                  Text(
                    tr('Nicio schimbare înregistrată încă. Se înregistrează cât timp ecranul acesta e deschis (util la mesh / extendere).',
                        'No changes recorded yet. Recorded while this screen is open (useful with mesh / extenders).'),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  )
                else
                  TableCard(
                    margin: EdgeInsets.zero,
                    children: [
                      for (final e in RoamingLog.instance.items.take(20))
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(children: [
                            Icon(Icons.swap_horiz, size: 20, color: cs.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(
                                  '…${(e.fromBssid ?? '?').split(':').skip(3).join(':')}  →  …${(e.toBssid ?? '?').split(':').skip(3).join(':')}',
                                  style: tt.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      fontFeatures: const [FontFeature.tabularFigures()]),
                                ),
                                Text(
                                  [
                                    if (e.fromBand != e.toBand) '${e.fromBand ?? '?'} → ${e.toBand ?? '?'}'
                                    else if (e.toBand != null) e.toBand!,
                                    if (e.toChannel != null) '${tr('canal', 'ch')} ${e.toChannel}',
                                    if (e.rssi != null) '${e.rssi} dBm',
                                  ].join(' · '),
                                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ]),
                            ),
                            Text(timeAgo(e.at), style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                          ]),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _latencyMax() {
    final all = [..._router.points, ..._internet.points].map((p) => p.$2).where((v) => !v.isNaN);
    final m = all.isEmpty ? 40.0 : all.reduce((a, b) => a > b ? a : b);
    for (final step in [20.0, 40.0, 80.0, 160.0, 320.0, 640.0]) {
      if (m <= step * 0.9) return step;
    }
    return 1000;
  }
}
