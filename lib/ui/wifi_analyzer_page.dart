import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/i18n.dart';
import '../services/wifi_info.dart';
import '../services/wifi_scan.dart';
import 'widgets.dart';

const _palette = [
  Color(0xFF2E7DF6), Color(0xFFE5484D), Color(0xFF30A46C), Color(0xFFF5A623),
  Color(0xFF8E4EC6), Color(0xFF12A594), Color(0xFFE54666), Color(0xFF7C66DC),
  Color(0xFFD6409F), Color(0xFF0090FF), Color(0xFFAD7F58), Color(0xFF65BA74),
];

Color _colorFor(String bssid) =>
    _palette[bssid.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7FFFFFFF) %
        _palette.length];

String _name(WifiAp a) => a.hidden ? tr('[ascuns]', '[hidden]') : a.ssid;

class WifiAnalyzerPage extends StatefulWidget {
  const WifiAnalyzerPage({super.key});

  @override
  State<WifiAnalyzerPage> createState() => _WifiAnalyzerPageState();
}

class _WifiAnalyzerPageState extends State<WifiAnalyzerPage> {
  List<WifiAp> _aps = [];
  final Map<String, List<(DateTime, int)>> _history = {};
  final Set<String> _selected = {};
  Timer? _timer;
  int _tick = 0;
  bool _loading = true;
  String _band = '2.4 GHz';
  WifiDetails? _own;
  bool _bandChosen = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    _own = scanner.wifi ?? await WifiService.get();
    if (_own?.band != null && !_bandChosen) _band = _own!.band!;
    await _poll(trigger: true);
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      _tick++;
      _poll(trigger: _tick % 10 == 0); // Android allows ~4 scans / 2 min
    });
  }

  Future<void> _poll({bool trigger = false}) async {
    final aps = await WifiScanService.scan(trigger: trigger);
    if (!mounted) return;
    final now = DateTime.now();
    for (final a in aps) {
      final h = _history.putIfAbsent(a.bssid, () => []);
      h.add((now, a.rssi));
      h.removeWhere((e) => now.difference(e.$1).inSeconds > 90);
    }
    aps.sort((a, b) => b.rssi.compareTo(a.rssi));
    if (_selected.isEmpty && aps.isNotEmpty) {
      _selected.addAll(aps.take(6).map((a) => a.bssid));
      final own = _own?.bssid;
      if (own != null) _selected.add(own);
    }
    setState(() {
      _aps = aps;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool _isOwn(WifiAp a) => _own?.bssid != null && a.bssid == _own!.bssid;

  @override
  Widget build(BuildContext context) {
    final bands = <String>{for (final a in _aps) a.band}.toList()..sort();
    if (!bands.contains(_band) && bands.isNotEmpty) _band = bands.first;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Analizor Wi-Fi', 'Wi-Fi analyzer')),
          actions: [
            IconButton(
              tooltip: tr('Reîmprospătează', 'Refresh'),
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _poll(trigger: true),
            ),
          ],
          bottom: TabBar(tabs: [
            Tab(text: tr('Rețele', 'Networks')),
            Tab(text: tr('Canale', 'Channels')),
            Tab(text: tr('Semnal', 'Signal')),
          ]),
        ),
        body: !WifiScanService.supported
            ? _message(Icons.wifi_off, tr('Disponibil pe Android și Windows.', 'Available on Android and Windows.'))
            : _loading
                ? const Center(child: CircularProgressIndicator())
                : _aps.isEmpty
                    ? _emptyState()
                    : TabBarView(children: [
                        _networksTab(),
                        _channelsTab(bands),
                        _signalTab(),
                      ]),
      ),
    );
  }

  Widget _message(IconData icon, String text, {Widget? action}) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
          if (action != null) ...[const SizedBox(height: 16), action],
        ]),
      ),
    );
  }

  Widget _emptyState() {
    if (Platform.isAndroid) {
      return _message(
        Icons.location_on_outlined,
        tr('Nicio rețea găsită. Android cere permisiunea și serviciul de Locație pornit ca să afișeze rețelele din jur.',
            'No networks found. Android needs Location permission and Location turned on to list nearby networks.'),
        action: FilledButton.icon(
          onPressed: () async {
            await WifiService.requestAgain();
            await _poll(trigger: true);
          },
          icon: const Icon(Icons.location_on),
          label: Text(tr('Permite Locația', 'Allow Location')),
        ),
      );
    }
    return _message(Icons.wifi_find,
        tr('Nicio rețea găsită. Verifică dacă Wi-Fi e pornit și Locația e permisă în Windows.',
            'No networks found. Check that Wi-Fi is on and Location is allowed in Windows.'));
  }

  // ================================================================ networks
  Widget _networksTab() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        MaxWidth(
          width: 760,
          child: TableCard(
            margin: EdgeInsets.zero,
            children: [
              for (final a in _aps)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: _colorFor(a.bssid), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Flexible(
                            child: Text(_name(a),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tt.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: a.hidden ? cs.onSurfaceVariant : null)),
                          ),
                          if (_isOwn(a)) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.link, size: 16, color: cs.primary),
                          ],
                        ]),
                        Text(
                          [
                            a.band,
                            '${tr('canal', 'ch')} ${a.channel}',
                            if (a.widthMhz > 20) '${a.widthMhz} MHz',
                            if (a.security != null) a.security!,
                          ].join(' · '),
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    _SignalBars(rssi: a.rssi),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 62,
                      child: Text('${a.rssi} dBm',
                          textAlign: TextAlign.right,
                          style: tt.labelLarge?.copyWith(
                              color: _rssiColor(a.rssi, cs),
                              fontFeatures: const [FontFeature.tabularFigures()])),
                    ),
                  ]),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          tr('${_aps.length} rețele · cea cu 🔗 e a ta', '${_aps.length} networks · 🔗 is yours'),
          textAlign: TextAlign.center,
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  // ================================================================ channels
  Widget _channelsTab(List<String> bands) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final inBand = _aps.where((a) => a.band == _band).toList();
    final own = _aps.where(_isOwn).firstOrNull;
    final rec = WifiScanService.recommend(_aps, _band, ownBssid: _own?.bssid);
    final ownHere = own != null && own.band == _band;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        MaxWidth(
          width: 760,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<String>(
              segments: [for (final b in bands) ButtonSegment(value: b, label: Text(b))],
              selected: {_band},
              onSelectionChanged: (s) => setState(() {
                _band = s.first;
                _bandChosen = true;
              }),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.fromLTRB(4, 12, 12, 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
              ),
              child: AspectRatio(
                aspectRatio: 1.45,
                child: CustomPaint(
                  painter: _ChannelPainter(
                    aps: inBand,
                    band: _band,
                    ownBssid: _own?.bssid,
                    grid: cs.outlineVariant.withValues(alpha: 0.5),
                    text: cs.onSurfaceVariant,
                    labelBg: cs.surface.withValues(alpha: 0.85),
                    recommended: rec,
                    recColor: Colors.green.shade600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TableCard(margin: EdgeInsets.zero, children: [
              if (ownHere)
                InfoRow(Icons.wifi, tr('Rețeaua ta', 'Your network'),
                    '${_name(own!)} · ${tr('canal', 'channel')} ${own.channel}',
                    copy: false),
              if (rec != null)
                InfoRow(
                  Icons.recommend_outlined,
                  tr('Canal recomandat', 'Recommended channel'),
                  ownHere && (own!.channel == rec || own.center == rec)
                      ? '$rec · ${tr('ești deja pe cel mai bun', 'you are already on the best one')}'
                      : '$rec · ${tr('cel mai puțin aglomerat', 'least crowded')}',
                  copy: false,
                ),
              InfoRow(Icons.router_outlined, tr('Rețele în bandă', 'Networks in band'),
                  '${inBand.length}', copy: false),
            ]),
            const SizedBox(height: 10),
            Text(
              tr('Canalul se schimbă din setările routerului. Pe 2.4 GHz folosește doar 1, 6 sau 11.',
                  'Change the channel in your router settings. On 2.4 GHz use only 1, 6 or 11.'),
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ]),
        ),
      ],
    );
  }

  // ================================================================ signal
  Widget _signalTab() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final series = <_Series>[
      for (final a in _aps)
        if (_selected.contains(a.bssid))
          _Series(_colorFor(a.bssid), _history[a.bssid] ?? const [], _isOwn(a)),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        MaxWidth(
          width: 760,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(4, 12, 12, 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
              ),
              child: AspectRatio(
                aspectRatio: 1.45,
                child: CustomPaint(
                  painter: _SignalPainter(
                    series: series,
                    grid: cs.outlineVariant.withValues(alpha: 0.5),
                    text: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TableCard(margin: EdgeInsets.zero, children: [
              for (final a in _aps)
                InkWell(
                  onTap: () => setState(() {
                    if (!_selected.remove(a.bssid)) _selected.add(a.bssid);
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    child: Row(children: [
                      Checkbox(
                        value: _selected.contains(a.bssid),
                        activeColor: _colorFor(a.bssid),
                        side: BorderSide(color: _colorFor(a.bssid), width: 2),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(a.bssid);
                          } else {
                            _selected.remove(a.bssid);
                          }
                        }),
                      ),
                      Expanded(
                        child: Text(
                          '${_name(a)}${_isOwn(a) ? '  🔗' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodyMedium?.copyWith(
                              fontWeight: _isOwn(a) ? FontWeight.w700 : FontWeight.w500),
                        ),
                      ),
                      Text('${a.band.split(' ').first} · ${a.channel}',
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      SizedBox(
                        width: 64,
                        child: Text('${a.rssi} dBm',
                            textAlign: TextAlign.right,
                            style: tt.labelLarge?.copyWith(
                                color: _rssiColor(a.rssi, cs),
                                fontFeatures: const [FontFeature.tabularFigures()])),
                      ),
                    ]),
                  ),
                ),
            ]),
            const SizedBox(height: 10),
            Text(
              Platform.isAndroid
                  ? tr('Android permite o scanare completă la ~30 s; între timp valorile se actualizează când sistemul le are.',
                      'Android allows a full scan about every 30 s; values update in between when the system has them.')
                  : tr('Se actualizează la câteva secunde.', 'Updates every few seconds.'),
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ]),
        ),
      ],
    );
  }
}

Color _rssiColor(int rssi, ColorScheme cs) => rssi >= -60
    ? Colors.green.shade600
    : rssi >= -72
        ? Colors.orange.shade700
        : cs.error;

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.rssi});
  final int rssi;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final level = rssi >= -55 ? 4 : rssi >= -65 ? 3 : rssi >= -75 ? 2 : 1;
    final c = _rssiColor(rssi, cs);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 4; i++)
          Container(
            margin: const EdgeInsets.only(left: 2),
            width: 4,
            height: 4.0 + i * 3,
            decoration: BoxDecoration(
              color: i <= level ? c : cs.outlineVariant,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- painters

const _minDbm = -100.0;
const _maxDbm = -20.0;

void _drawYAxis(Canvas canvas, Rect plot, Color grid, Color text) {
  final gp = Paint()
    ..color = grid
    ..strokeWidth = 1;
  for (var v = -90; v <= -30; v += 10) {
    final y = plot.bottom - (v - _minDbm) / (_maxDbm - _minDbm) * plot.height;
    canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gp);
    final tp = TextPainter(
      text: TextSpan(text: '$v', style: TextStyle(color: text, fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(plot.left - tp.width - 6, y - tp.height / 2));
  }
}

class _ChannelPainter extends CustomPainter {
  _ChannelPainter({
    required this.aps,
    required this.band,
    required this.ownBssid,
    required this.grid,
    required this.text,
    required this.labelBg,
    required this.recommended,
    required this.recColor,
  });

  final List<WifiAp> aps;
  final String band;
  final String? ownBssid;
  final Color grid;
  final Color text;
  final Color labelBg;
  final int? recommended;
  final Color recColor;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(34, 8, size.width - 4, size.height - 22);

    // x range
    double minCh, maxCh;
    List<int> ticks;
    if (band == '2.4 GHz') {
      minCh = -1;
      maxCh = 15;
      ticks = [for (var c = 1; c <= 13; c++) c];
    } else {
      final centers = aps.map((a) => a.center.toDouble()).toList();
      final lo = centers.isEmpty ? (band == '5 GHz' ? 36.0 : 1.0) : centers.reduce(min);
      final hi = centers.isEmpty ? (band == '5 GHz' ? 64.0 : 33.0) : centers.reduce(max);
      minCh = lo - 12;
      maxCh = hi + 12;
      if (maxCh - minCh < 36) {
        final mid = (minCh + maxCh) / 2;
        minCh = mid - 18;
        maxCh = mid + 18;
      }
      final step = (maxCh - minCh) > 90 ? 16 : (maxCh - minCh) > 50 ? 8 : 4;
      final start = band == '5 GHz' ? 36 : 1;
      ticks = [
        for (var c = start; c <= 196; c += step)
          if (c >= minCh && c <= maxCh) c
      ];
    }
    double x(double ch) => plot.left + (ch - minCh) / (maxCh - minCh) * plot.width;
    double y(num dbm) =>
        plot.bottom - ((dbm.clamp(_minDbm, _maxDbm) - _minDbm) / (_maxDbm - _minDbm)) * plot.height;

    _drawYAxis(canvas, plot, grid, text);

    // recommended channel marker
    final rec = recommended;
    if (rec != null && rec >= minCh && rec <= maxCh) {
      final rx = x(rec.toDouble());
      final rp = Paint()
        ..color = recColor.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill;
      final w = plot.width / (maxCh - minCh) * 2;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTRB(rx - w, plot.top, rx + w, plot.bottom), const Radius.circular(6)),
          rp);
    }

    // x ticks
    for (final c in ticks) {
      final tx = x(c.toDouble());
      final tp = TextPainter(
        text: TextSpan(
            text: '$c',
            style: TextStyle(
                color: c == rec ? recColor : text,
                fontSize: 10,
                fontWeight: c == rec ? FontWeight.w700 : FontWeight.w400)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(tx - tp.width / 2, plot.bottom + 5));
    }

    // humps (weakest first so strong ones are on top)
    final sorted = [...aps]..sort((a, b) => a.rssi.compareTo(b.rssi));
    canvas.save();
    canvas.clipRect(plot);
    for (final a in sorted) {
      final c = _colorFor(a.bssid);
      final own = a.bssid == ownBssid;
      final l = x(a.center - a.halfSpan), r = x(a.center + a.halfSpan);
      final top = y(a.rssi);
      final edge = (r - l) * 0.18;
      final path = Path()
        ..moveTo(l, plot.bottom)
        ..cubicTo(l + edge * 0.6, plot.bottom, l + edge * 0.4, top, l + edge, top)
        ..lineTo(r - edge, top)
        ..cubicTo(r - edge * 0.4, top, r - edge * 0.6, plot.bottom, r, plot.bottom);
      canvas.drawPath(
          path,
          Paint()
            ..color = c.withValues(alpha: own ? 0.22 : 0.10)
            ..style = PaintingStyle.fill);
      canvas.drawPath(
          path,
          Paint()
            ..color = c
            ..style = PaintingStyle.stroke
            ..strokeWidth = own ? 3 : 1.6);
    }
    canvas.restore();

    // labels for the strongest networks, without overlaps
    final placed = <Rect>[];
    final byStrength = [...aps]..sort((a, b) => b.rssi.compareTo(a.rssi));
    var count = 0;
    for (final a in byStrength) {
      if (count >= 7) break;
      final own = a.bssid == ownBssid;
      final tp = TextPainter(
        text: TextSpan(
          text: _name(a),
          style: TextStyle(
            color: _colorFor(a.bssid),
            fontSize: 11,
            fontWeight: own ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        maxLines: 1,
        ellipsis: '…',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 110);
      final cx = x(a.center.toDouble());
      var rect = Rect.fromLTWH(cx - tp.width / 2 - 4, y(a.rssi) - tp.height - 6,
          tp.width + 8, tp.height + 2);
      if (rect.left < plot.left) rect = rect.shift(Offset(plot.left - rect.left, 0));
      if (rect.right > plot.right) rect = rect.shift(Offset(plot.right - rect.right, 0));
      if (rect.top < plot.top) rect = rect.shift(Offset(0, plot.top - rect.top));
      var tries = 0;
      while (placed.any((p) => p.overlaps(rect)) && tries < 4) {
        rect = rect.shift(Offset(0, rect.height + 2));
        tries++;
      }
      if (placed.any((p) => p.overlaps(rect)) || rect.bottom > plot.bottom) continue;
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          Paint()..color = labelBg);
      tp.paint(canvas, Offset(rect.left + 4, rect.top + 1));
      placed.add(rect);
      count++;
    }
  }

  @override
  bool shouldRepaint(covariant _ChannelPainter old) => true;
}

class _Series {
  _Series(this.color, this.points, this.own);
  final Color color;
  final List<(DateTime, int)> points;
  final bool own;
}

class _SignalPainter extends CustomPainter {
  _SignalPainter({required this.series, required this.grid, required this.text});
  final List<_Series> series;
  final Color grid;
  final Color text;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(34, 8, size.width - 4, size.height - 22);
    _drawYAxis(canvas, plot, grid, text);
    final now = DateTime.now();
    const window = 60.0;
    double x(DateTime t) =>
        plot.right - (now.difference(t).inMilliseconds / 1000 / window) * plot.width;
    double y(num dbm) =>
        plot.bottom - ((dbm.clamp(_minDbm, _maxDbm) - _minDbm) / (_maxDbm - _minDbm)) * plot.height;

    for (final s in [0, 15, 30, 45, 60]) {
      final tx = plot.right - s / window * plot.width;
      final tp = TextPainter(
        text: TextSpan(text: s == 0 ? tr('acum', 'now') : '-${s}s', style: TextStyle(color: text, fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((tx - tp.width / 2).clamp(plot.left, plot.right - tp.width).toDouble(), plot.bottom + 5));
    }

    canvas.save();
    canvas.clipRect(plot);
    final ordered = [...series]..sort((a, b) => (a.own ? 1 : 0).compareTo(b.own ? 1 : 0));
    for (final s in ordered) {
      final pts = s.points.where((p) => now.difference(p.$1).inSeconds <= window + 3).toList();
      if (pts.isEmpty) continue;
      final path = Path()..moveTo(x(pts.first.$1), y(pts.first.$2));
      for (var i = 1; i < pts.length; i++) {
        final px = x(pts[i].$1), py = y(pts[i].$2);
        final prevX = x(pts[i - 1].$1);
        final midX = (prevX + px) / 2;
        path.cubicTo(midX, y(pts[i - 1].$2), midX, py, px, py);
      }
      path.lineTo(plot.right, y(pts.last.$2));
      canvas.drawPath(
          path,
          Paint()
            ..color = s.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = s.own ? 3.5 : 2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);
      canvas.drawCircle(Offset(plot.right - 2, y(pts.last.$2)), s.own ? 4.5 : 3,
          Paint()..color = s.color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SignalPainter old) => true;
}
