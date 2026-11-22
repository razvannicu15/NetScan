import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/i18n.dart';
import '../services/live_monitor.dart';
import 'widgets.dart';

/// Signal meter with beeps and a "warmer / colder" compass:
/// turning slowly on the spot, your body shadows the signal, so the
/// direction with the strongest reading points roughly towards the router.
class SignalFinderPage extends StatefulWidget {
  const SignalFinderPage({super.key});

  @override
  State<SignalFinderPage> createState() => _SignalFinderPageState();
}

class _Sector {
  double? value;
  DateTime? at;
}

class _SignalFinderPageState extends State<SignalFinderPage> {
  static const _sectors = 12; // 30° each
  static const _expire = Duration(seconds: 25);

  Timer? _read;
  Timer? _beep;
  Timer? _compassTimer;
  double? _smooth;
  int? _min;
  int? _max;
  String? _ssid;
  bool _sound = true;
  bool _hasCompass = false;
  double? _heading; // smoothed, degrees
  final List<_Sector> _map = List.generate(_sectors, (_) => _Sector());
  final List<(DateTime, double)> _recent = [];

  @override
  void initState() {
    super.initState();
    _tick();
    _read = Timer.periodic(const Duration(milliseconds: 400), (_) => _tick());
    _scheduleBeep();
    Compass.start().then((ok) {
      if (!mounted) return;
      setState(() => _hasCompass = ok);
      if (ok) {
        _compassTimer = Timer.periodic(const Duration(milliseconds: 60), (_) => _readHeading());
      }
    });
  }

  Future<void> _readHeading() async {
    final h = await Compass.heading();
    if (!mounted || h == null) return;
    setState(() {
      final cur = _heading;
      if (cur == null) {
        _heading = h;
      } else {
        final d = ((h - cur + 540) % 360) - 180; // shortest way
        _heading = (cur + d * 0.25 + 360) % 360;
      }
    });
  }

  Future<void> _tick() async {
    final s = await LiveWifi.read();
    if (!mounted || s?.rssi == null) return;
    final r = s!.rssi!;
    final now = DateTime.now();
    setState(() {
      _ssid = s.ssid;
      _smooth = _smooth == null ? r.toDouble() : _smooth! * 0.6 + r * 0.4;
      _min = _min == null ? r : min(_min!, r);
      _max = _max == null ? r : max(_max!, r);
      _recent.add((now, r.toDouble()));
      _recent.removeWhere((p) => now.difference(p.$1).inSeconds > 6);
      final h = _heading;
      if (h != null) {
        final sec = _map[(h / (360 / _sectors)).floor() % _sectors];
        final old = sec.value;
        sec.value = (old == null || _expired(sec, now)) ? r.toDouble() : old * 0.5 + r * 0.5;
        sec.at = now;
      }
    });
  }

  bool _expired(_Sector s, DateTime now) => s.at == null || now.difference(s.at!) > _expire;

  int get _percent => _smooth == null ? 0 : (2 * (_smooth! + 100)).clamp(0, 100).round();

  /// (best direction in degrees, spread dB, sectors measured)
  (double?, double, int) get _direction {
    final now = DateTime.now();
    double? best;
    double? worst;
    int? bestI;
    var n = 0;
    for (var i = 0; i < _sectors; i++) {
      final s = _map[i];
      final v = s.value;
      if (v == null || _expired(s, now)) continue;
      n++;
      if (best == null || v > best) {
        best = v;
        bestI = i;
      }
      if (worst == null || v < worst) worst = v;
    }
    if (bestI == null || best == null || worst == null) return (null, 0, 0);
    return (bestI * (360 / _sectors) + 15, best - worst, n);
  }

  void _scheduleBeep() {
    _beep?.cancel();
    final ms = (1300 - _percent * 10.5).clamp(250, 1300).round();
    _beep = Timer(Duration(milliseconds: ms), () {
      if (!mounted) return;
      if (_sound && _smooth != null) {
        LiveWifi.tone((_percent / 11.2).ceil().clamp(1, 9).toInt());
        HapticFeedback.selectionClick();
      }
      _scheduleBeep();
    });
  }

  @override
  void dispose() {
    _read?.cancel();
    _beep?.cancel();
    _compassTimer?.cancel();
    Compass.stop();
    super.dispose();
  }

  Color _color(ColorScheme cs) => _percent >= 80
      ? Colors.green.shade600
      : _percent >= 55
          ? Colors.lightGreen.shade700
          : _percent >= 35
              ? Colors.orange.shade700
              : cs.error;

  String get _label => _percent >= 80
      ? tr('Excelent', 'Excellent')
      : _percent >= 55
          ? tr('Bun', 'Good')
          : _percent >= 35
              ? tr('Slab', 'Weak')
              : tr('Foarte slab', 'Very weak');

  int get _trend {
    if (_recent.length < 6) return 0;
    final first = _recent.take(3).map((e) => e.$2).reduce((a, b) => a + b) / 3;
    final last = _recent.skip(_recent.length - 3).map((e) => e.$2).reduce((a, b) => a + b) / 3;
    if (last - first >= 3) return 1;
    if (first - last >= 3) return -1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final c = _color(cs);
    final trend = _trend;
    final (bestDir, spread, measured) = _direction;
    final showArrow = _hasCompass && bestDir != null && measured >= 6 && spread >= 3;
    final now = DateTime.now();
    final hint = !_hasCompass
        ? tr('Mergi încet prin casă. Bipuri mai rapide și mai ascuțite = semnal mai bun.',
            'Walk slowly around. Faster, higher beeps = better signal.')
        : measured < 6
            ? tr('Ține telefonul în față și rotește-te încet pe loc, o tură completă.',
                'Hold the phone in front of you and slowly turn around once.')
            : spread < 3
                ? tr('Semnalul e la fel în toate direcțiile. Fă câțiva pași și rotește-te din nou.',
                    'Signal is the same in every direction. Take a few steps and turn again.')
                : tr('Mergi în direcția săgeții, apoi rotește-te din nou ca să verifici.',
                    'Walk where the arrow points, then turn again to check.');

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Caută semnal', 'Signal finder')),
        actions: [
          IconButton(
            tooltip: _sound ? tr('Fără sunet', 'Mute') : tr('Cu sunet', 'Sound on'),
            icon: Icon(_sound ? Icons.volume_up : Icons.volume_off),
            onPressed: () => setState(() => _sound = !_sound),
          ),
        ],
      ),
      body: _smooth == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  tr('Conectează-te la o rețea Wi-Fi ca să măsori semnalul.',
                      'Connect to a Wi-Fi network to measure the signal.'),
                  textAlign: TextAlign.center,
                  style: tt.bodyLarge,
                ),
              ),
            )
          : MaxWidth(
              width: 520,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                children: [
                  if (_ssid != null)
                    Text(_ssid!,
                        textAlign: TextAlign.center,
                        style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  AspectRatio(
                    aspectRatio: 1,
                    child: CustomPaint(
                      painter: _CompassPainter(
                        sectors: [
                          for (final s in _map) (s.value == null || _expired(s, now)) ? null : s.value
                        ],
                        heading: _hasCompass ? (_heading ?? 0) : null,
                        bestDir: showArrow ? bestDir : null,
                        track: cs.surfaceContainerHighest,
                        marker: cs.onSurfaceVariant,
                        arrow: cs.primary,
                        value: _percent / 100,
                        valueColor: c,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (showArrow)
                              Transform.rotate(
                                angle: ((bestDir ?? 0) - (_heading ?? 0)) * pi / 180,
                                child: Icon(Icons.navigation, size: 40, color: cs.primary),
                              ),
                            Text(
                              '${_smooth!.round()}',
                              style: tt.displayLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: c,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                            Text('dBm', style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
                            const SizedBox(height: 6),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Text('$_label · $_percent%',
                                  style: tt.titleMedium?.copyWith(color: c, fontWeight: FontWeight.w600)),
                              const SizedBox(width: 6),
                              Icon(
                                trend > 0
                                    ? Icons.trending_up
                                    : trend < 0
                                        ? Icons.trending_down
                                        : Icons.trending_flat,
                                color: trend > 0
                                    ? Colors.green.shade600
                                    : trend < 0
                                        ? cs.error
                                        : cs.onSurfaceVariant,
                              ),
                            ]),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(children: [
                      Icon(_hasCompass ? Icons.explore_outlined : Icons.directions_walk,
                          color: cs.onSecondaryContainer),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(hint, style: tt.bodyMedium?.copyWith(color: cs.onSecondaryContainer)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  TableCard(margin: EdgeInsets.zero, children: [
                    InfoRow(Icons.arrow_upward, tr('Cel mai bun', 'Best'), '$_max dBm', copy: false),
                    InfoRow(Icons.arrow_downward, tr('Cel mai slab', 'Worst'), '$_min dBm', copy: false),
                  ]),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _min = null;
                      _max = null;
                      for (final s in _map) {
                        s.value = null;
                        s.at = null;
                      }
                    }),
                    icon: const Icon(Icons.restart_alt),
                    label: Text(tr('Ia-o de la capăt', 'Start over')),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Outer ring: 12 world-fixed sectors coloured by the signal measured there.
/// Inner arc: overall signal strength. Without a compass only the inner arc.
class _CompassPainter extends CustomPainter {
  _CompassPainter({
    required this.sectors,
    required this.heading,
    required this.bestDir,
    required this.track,
    required this.marker,
    required this.arrow,
    required this.value,
    required this.valueColor,
  });

  final List<double?> sectors;
  final double? heading;
  final double? bestDir;
  final Color track;
  final Color marker;
  final Color arrow;
  final double value;
  final Color valueColor;

  Color _heat(double v) {
    final t = ((v + 85) / 40).clamp(0.0, 1.0).toDouble(); // -85 … -45 dBm
    return Color.lerp(const Color(0xFFE5484D), const Color(0xFF30A46C), t)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final rOuter = min(size.width, size.height) / 2 - 14;
    final ringW = rOuter * 0.10;

    // inner strength arc (270°)
    final rIn = rOuter - ringW - 18;
    final rect = Rect.fromCircle(center: c, radius: rIn);
    const start = 135 * pi / 180;
    const sweep = 270 * pi / 180;
    final arcW = rIn * 0.07;
    canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = track
          ..style = PaintingStyle.stroke
          ..strokeWidth = arcW
          ..strokeCap = StrokeCap.round);
    if (value > 0) {
      canvas.drawArc(
          rect,
          start,
          sweep * value,
          false,
          Paint()
            ..color = valueColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = arcW
            ..strokeCap = StrokeCap.round);
    }

    final h = heading;
    if (h == null) return;

    // outer direction ring, rotated so the top of the screen = where you face
    final seg = 2 * pi / sectors.length;
    final orect = Rect.fromCircle(center: c, radius: rOuter - ringW / 2);
    for (var i = 0; i < sectors.length; i++) {
      final worldDeg = i * 360 / sectors.length;
      final a = (worldDeg - h - 90) * pi / 180; // -90: 0° at top
      final v = sectors[i];
      canvas.drawArc(
        orect,
        a + 0.03,
        seg - 0.06,
        false,
        Paint()
          ..color = v == null ? track : _heat(v)
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringW,
      );
    }

    // "you are facing" marker at the top
    final top = Offset(c.dx, c.dy - rOuter);
    final face = Path()
      ..moveTo(top.dx - 8, top.dy - 10)
      ..lineTo(top.dx + 8, top.dy - 10)
      ..lineTo(top.dx, top.dy)
      ..close();
    canvas.drawPath(face, Paint()..color = marker);

    // best direction marker on the ring
    final b = bestDir;
    if (b != null) {
      final a = (b - h - 90) * pi / 180;
      final p = c + Offset(cos(a), sin(a)) * (rOuter - ringW / 2);
      canvas.drawCircle(p, ringW * 0.75, Paint()..color = arrow);
      canvas.drawCircle(p, ringW * 0.35, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _CompassPainter old) => true;
}
