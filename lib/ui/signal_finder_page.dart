import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/i18n.dart';
import '../services/live_monitor.dart';
import 'widgets.dart';

/// "Treasure map" signal finder: counts steps + compass heading to draw your
/// path coloured by signal, remembers the best spot and points you back to it.
class SignalFinderPage extends StatefulWidget {
  const SignalFinderPage({super.key});

  @override
  State<SignalFinderPage> createState() => _SignalFinderPageState();
}

class _P {
  _P(this.x, this.y, this.rssi);
  final double x; // metres, east
  final double y; // metres, north
  final double rssi;
}

class _SignalFinderPageState extends State<SignalFinderPage> {
  static const _stepLen = 0.7; // metres
  static const _sectors = 12;

  Timer? _read;
  Timer? _beep;
  Timer? _sensors;
  double? _smooth;
  int? _min;
  int? _max;
  String? _ssid;
  bool _sound = true;
  bool _hasCompass = false;
  double? _heading;

  // mesh
  String? _bssid;
  String? _band;
  int? _channel;
  final Map<String, int> _nodes = {};
  String? _roamMsg;
  DateTime? _roamAt;

  // path
  double _x = 0, _y = 0;
  int? _lastSteps;
  int _walked = 0;
  final List<_P> _trail = [];

  // one-time start turn (optional): which way to start exploring
  final List<double> _sum = List.filled(_sectors, 0);
  final List<int> _cnt = List.filled(_sectors, 0);
  double? _exploreDir;
  bool _calibDone = false;

  // arrow
  double _arrowTurns = 0;
  int _dir = 0, _dirCand = 0;
  DateTime _dirSince = DateTime.now();
  int _tickN = 0;

  @override
  void initState() {
    super.initState();
    RoamingLog.instance.load();
    _tick();
    _read = Timer.periodic(const Duration(milliseconds: 400), (_) => _tick());
    _scheduleBeep();
    Compass.start().then((ok) {
      if (!mounted) return;
      setState(() => _hasCompass = ok);
      if (ok) _sensors = Timer.periodic(const Duration(milliseconds: 60), (_) => _readSensors());
    });
  }

  @override
  void dispose() {
    _read?.cancel();
    _beep?.cancel();
    _sensors?.cancel();
    Compass.stop();
    super.dispose();
  }

  // ------------------------------------------------------------------ sensors
  Future<void> _readSensors() async {
    final h = await Compass.heading();
    int? steps;
    if (_tickN++ % 3 == 0) steps = await Compass.steps();
    if (!mounted || h == null) return;
    setState(() {
      final cur = _heading;
      _heading = cur == null ? h : (cur + (((h - cur + 540) % 360) - 180) * 0.2 + 360) % 360;

      if (steps != null) {
        final last = _lastSteps;
        _lastSteps = steps;
        if (last != null && steps > last && _smooth != null) {
          final rad = _heading! * pi / 180;
          for (var i = 0; i < steps - last; i++) {
            _x += sin(rad) * _stepLen;
            _y += cos(rad) * _stepLen;
            _walked++;
            _trail.add(_P(_x, _y, _smooth!));
          }
          if (_trail.length > 600) _trail.removeRange(0, _trail.length - 600);
          if (_walked >= 3) _calibDone = true; // started walking: skip the turn
        }
      }
      _updateArrow();
    });
  }

  /// World bearing (deg) the arrow should point to, or null.
  double? get _targetBearing {
    final b = _best;
    if (b != null) return (atan2(b.x - _x, b.y - _y) * 180 / pi + 360) % 360;
    return _exploreDir;
  }

  _P? get _best {
    if (_trail.length < 4 || _smooth == null) return null;
    final b = _trail.reduce((a, c) => c.rssi > a.rssi ? c : a);
    final d = sqrt(pow(b.x - _x, 2) + pow(b.y - _y, 2));
    if (d < 1.2 || b.rssi - _smooth! < 3) return null; // you're already there
    return b;
  }

  void _updateArrow() {
    final t = _targetBearing;
    final h = _heading;
    if (t == null || h == null) return;
    final rel = (t - h + 360) % 360;
    var diff = (rel / 360 - _arrowTurns) % 1.0;
    if (diff > 0.5) diff -= 1.0;
    if (diff < -0.5) diff += 1.0;
    _arrowTurns += diff;
    final sgn = ((rel + 180) % 360) - 180;
    final cand = sgn.abs() <= 35 ? 0 : sgn.abs() >= 145 ? 2 : sgn > 0 ? 1 : 3;
    final now = DateTime.now();
    if (cand != _dirCand) {
      _dirCand = cand;
      _dirSince = now;
    } else if (cand != _dir && now.difference(_dirSince).inMilliseconds >= 600) {
      _dir = cand;
      HapticFeedback.selectionClick();
    }
  }

  // ------------------------------------------------------------------ wifi
  Future<void> _tick() async {
    final s = await LiveWifi.read();
    if (!mounted || s?.rssi == null) return;
    final r = s!.rssi!;
    final b = s.bssid;
    if (b != null) {
      final first = _nodes.isEmpty;
      _nodes.putIfAbsent(b, () => _nodes.length);
      if (!first && _bssid != null && b != _bssid) _onRoam(_bssid!, b, s.band);
      RoamingLog.instance.observe(s);
    }
    setState(() {
      _bssid = b ?? _bssid;
      _band = s.band;
      _channel = s.channel;
      _ssid = s.ssid;
      _smooth = _smooth == null ? r.toDouble() : _smooth! * 0.6 + r * 0.4;
      _min = _min == null ? r : min(_min!, r);
      _max = _max == null ? r : max(_max!, r);
      if (_trail.isEmpty) _trail.add(_P(0, 0, _smooth!));

      // optional start turn, only while standing still
      final h = _heading;
      if (_hasCompass && !_calibDone && h != null) {
        final i = (h / (360 / _sectors)).floor() % _sectors;
        _sum[i] += r;
        _cnt[i]++;
        if (_cnt.where((c) => c > 0).length >= 10) {
          final avg = [for (var k = 0; k < _sectors; k++) _cnt[k] == 0 ? null : _sum[k] / _cnt[k]];
          final ok = avg.whereType<double>();
          final best = ok.reduce(max), worst = ok.reduce(min);
          if (best - worst >= 3) _exploreDir = avg.indexOf(best) * 30.0 + 15;
          _calibDone = true;
          HapticFeedback.mediumImpact();
        }
      }
    });
  }

  String _node(String bssid) => '${tr('Nod', 'Node')} ${String.fromCharCode(65 + (_nodes[bssid] ?? 0))}';

  void _onRoam(String from, String to, String? band) {
    HapticFeedback.heavyImpact();
    if (_sound) LiveWifi.tone(9);
    _roamMsg = tr('Te-ai mutat de pe ${_node(from)} pe ${_node(to)}${band != null ? ' ($band)' : ''}',
        'Switched from ${_node(from)} to ${_node(to)}${band != null ? ' ($band)' : ''}');
    _roamAt = DateTime.now();
  }

  int get _percent => _smooth == null ? 0 : (2 * (_smooth! + 100)).clamp(0, 100).round();

  void _scheduleBeep() {
    _beep?.cancel();
    final ms = (1300 - _percent * 10.5).clamp(250, 1300).round();
    _beep = Timer(Duration(milliseconds: ms), () {
      if (!mounted) return;
      if (_sound && _smooth != null) {
        LiveWifi.tone((_percent / 11.2).ceil().clamp(1, 9).toInt());
      }
      _scheduleBeep();
    });
  }

  void _reset() {
    _x = _y = 0;
    _walked = 0;
    _trail.clear();
    _min = _max = null;
    _exploreDir = null;
    _calibDone = false;
    for (var i = 0; i < _sectors; i++) {
      _sum[i] = 0;
      _cnt[i] = 0;
    }
  }

  Color _sigColor(double v, ColorScheme cs) => v >= -60
      ? Colors.green.shade600
      : v >= -70
          ? Colors.lightGreen.shade700
          : v >= -78
              ? Colors.orange.shade700
              : cs.error;

  // ------------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (_smooth == null) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Caută semnal', 'Signal finder'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
                tr('Conectează-te la o rețea Wi-Fi ca să măsori semnalul.',
                    'Connect to a Wi-Fi network to measure the signal.'),
                textAlign: TextAlign.center,
                style: tt.bodyLarge),
          ),
        ),
      );
    }

    final c = _sigColor(_smooth!, cs);
    final best = _best;
    final target = _targetBearing;
    final calibrating = _hasCompass && !_calibDone;
    final measured = _cnt.where((k) => k > 0).length;
    final dirWord = switch (_dir) {
      0 => tr('înainte', 'straight ahead'),
      1 => tr('la dreapta', 'to your right'),
      2 => tr('în spate', 'behind you'),
      _ => tr('la stânga', 'to your left'),
    };

    final String title;
    final String sub;
    if (!_hasCompass) {
      title = tr('Plimbă-te prin casă', 'Walk around');
      sub = tr('Bipuri mai rapide și mai ascuțite = semnal mai bun.', 'Faster, higher beeps = better signal.');
    } else if (calibrating) {
      title = tr('Rotește-te o dată pe loc', 'Turn around once');
      sub = tr('Ca să știu în ce parte să pornești (${min(measured, 10)}/10). Sau pur și simplu începe să mergi.',
          'So I know which way to start (${min(measured, 10)}/10). Or just start walking.');
    } else if (best != null) {
      final d = sqrt(pow(best.x - _x, 2) + pow(best.y - _y, 2));
      title = _dir == 0
          ? tr('Mergi înainte spre ⭐', 'Walk ahead to the ⭐')
          : tr('Cel mai bun loc e $dirWord', 'The best spot is $dirWord');
      sub = tr('${best.rssi.round()} dBm, la ~${d.round()} m. Ești acum la ${_smooth!.round()} dBm.',
          '${best.rssi.round()} dBm, ~${d.round()} m away. You are at ${_smooth!.round()} dBm now.');
    } else if (_walked >= 3) {
      title = tr('Ești în cel mai bun loc găsit', 'You are at the best spot so far');
      sub = target != null
          ? tr('Explorează și $dirWord — acolo părea semnal mai bun la început.',
              'Also explore $dirWord — it looked better there at the start.')
          : tr('Explorează și alte camere; ⭐ marchează cel mai bun loc.',
              'Explore other rooms; the ⭐ marks the best spot.');
    } else if (target != null) {
      title = _dir == 0
          ? tr('Pornește înainte', 'Start walking ahead')
          : tr('Pornește $dirWord', 'Start walking $dirWord');
      sub = tr('De acolo vine semnalul mai puternic. Harta se desenează din pașii tăi.',
          'The signal is stronger that way. The map is drawn from your steps.');
    } else {
      title = tr('Începe să mergi', 'Start walking');
      sub = tr('Semnalul e la fel în jur. Harta se desenează din pașii tăi.',
          'Signal is similar all around. The map is drawn from your steps.');
    }

    final showRoam = _roamMsg != null && _roamAt != null && DateTime.now().difference(_roamAt!).inSeconds < 10;
    final nodeLine = [
      if (_bssid != null) _nodes.length > 1 ? _node(_bssid!) : 'AP …${_bssid!.substring(9)}',
      if (_band != null) _band!,
      if (_channel != null) '${tr('canal', 'ch')} $_channel',
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Caută semnal', 'Signal finder')),
        actions: [
          IconButton(
            tooltip: tr('Ia-o de la capăt', 'Start over'),
            icon: const Icon(Icons.restart_alt),
            onPressed: () => setState(_reset),
          ),
          IconButton(
            tooltip: _sound ? tr('Fără sunet', 'Mute') : tr('Cu sunet', 'Sound on'),
            icon: Icon(_sound ? Icons.volume_up : Icons.volume_off),
            onPressed: () => setState(() => _sound = !_sound),
          ),
        ],
      ),
      body: MaxWidth(
        width: 520,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            // ------------------------------------------------ live value
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_ssid ?? 'Wi-Fi',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    if (nodeLine.isNotEmpty)
                      Text(nodeLine, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ),
                Text('${_smooth!.round()}',
                    style: tt.displaySmall?.copyWith(
                        color: c, fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: 4),
                Text('dBm', style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: showRoam
                  ? Container(
                      key: const ValueKey('roam'),
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        Icon(Icons.swap_horiz, color: cs.onTertiaryContainer),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_roamMsg!,
                              style: tt.bodyMedium
                                  ?.copyWith(color: cs.onTertiaryContainer, fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    )
                  : const SizedBox(key: ValueKey('none'), height: 0),
            ),
            const SizedBox(height: 12),

            // ------------------------------------------------ map
            if (_hasCompass)
              AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _MapPainter(
                          trail: _trail,
                          x: _x,
                          y: _y,
                          heading: _heading ?? 0,
                          best: best,
                          exploreDir: best == null ? target : null,
                          grid: cs.outlineVariant.withValues(alpha: 0.5),
                          you: cs.primary,
                          text: cs.onSurfaceVariant,
                          colorFor: (v) => _sigColor(v, cs),
                          calibrating: calibrating ? min(measured, 10) / 10 : null,
                        ),
                      ),
                    ),
                    if (target != null && !calibrating)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: (_dir == 0 ? Colors.green.shade600 : cs.primary).withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          child: AnimatedRotation(
                            turns: _arrowTurns,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            child: Icon(Icons.navigation,
                                size: 40, color: _dir == 0 ? Colors.green.shade600 : cs.primary),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            const SizedBox(height: 12),

            // ------------------------------------------------ instruction
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: best != null && _dir == 0
                    ? Colors.green.shade600.withValues(alpha: 0.14)
                    : cs.secondaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(children: [
                Text(title,
                    textAlign: TextAlign.center, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(sub,
                    textAlign: TextAlign.center, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
            const SizedBox(height: 12),
            TableCard(margin: EdgeInsets.zero, children: [
              InfoRow(Icons.arrow_upward, tr('Cel mai bun', 'Best'), '$_max dBm', copy: false),
              InfoRow(Icons.arrow_downward, tr('Cel mai slab', 'Worst'), '$_min dBm', copy: false),
              if (_walked > 0)
                InfoRow(Icons.directions_walk, tr('Distanță parcursă', 'Distance walked'),
                    '~${(_walked * _stepLen).round()} m', copy: false),
              if (_nodes.length > 1)
                InfoRow(Icons.hub_outlined, tr('Noduri mesh văzute', 'Mesh nodes seen'), '${_nodes.length}',
                    copy: false),
            ]),
            const SizedBox(height: 8),
            Text(
              tr('Ține telefonul în față, în direcția în care mergi. Poziția e estimată din pași, deci e aproximativă.',
                  'Hold the phone in front of you, pointing where you walk. Position is estimated from steps, so it is approximate.'),
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Heading-up map: you are in the centre, forward is up. Path dots coloured
/// by signal, ⭐ = best spot, dashed line to it.
class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.trail,
    required this.x,
    required this.y,
    required this.heading,
    required this.best,
    required this.exploreDir,
    required this.grid,
    required this.you,
    required this.text,
    required this.colorFor,
    required this.calibrating,
  });

  final List<_P> trail;
  final double x, y, heading;
  final _P? best;
  final double? exploreDir;
  final Color grid, you, text;
  final Color Function(double) colorFor;
  final double? calibrating;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.58);
    // scale: fit trail, at least 4 m radius visible
    var maxD = 4.0;
    for (final p in trail) {
      maxD = max(maxD, sqrt(pow(p.x - x, 2) + pow(p.y - y, 2)) + 1);
    }
    final scale = (size.width * 0.42) / maxD; // px per metre
    final rot = -heading * pi / 180;
    Offset toScreen(double px, double py) {
      final dx = px - x, dy = py - y;
      final rx = dx * cos(rot) - dy * sin(rot);
      final ry = dx * sin(rot) + dy * cos(rot);
      return Offset(c.dx + rx * scale, c.dy - ry * scale);
    }

    // distance rings
    final gp = Paint()
      ..color = grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final step = maxD > 12 ? 5.0 : 2.0;
    for (var r = step; r <= maxD; r += step) {
      canvas.drawCircle(c, r * scale, gp);
      final tp = TextPainter(
        text: TextSpan(text: '${r.round()} m', style: TextStyle(color: text, fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c + Offset(4, -r * scale - tp.height));
    }

    // path
    if (trail.length > 1) {
      for (var i = 1; i < trail.length; i++) {
        final a = toScreen(trail[i - 1].x, trail[i - 1].y), b = toScreen(trail[i].x, trail[i].y);
        canvas.drawLine(
            a,
            b,
            Paint()
              ..color = colorFor(trail[i].rssi).withValues(alpha: 0.85)
              ..strokeWidth = 6
              ..strokeCap = StrokeCap.round);
      }
    }
    if (trail.isNotEmpty) {
      final s = toScreen(trail.first.x, trail.first.y);
      canvas.drawCircle(s, 5, Paint()..color = text);
    }

    // best spot + dashed line
    final b = best;
    if (b != null) {
      final bp = toScreen(b.x, b.y);
      final dist = (bp - c).distance;
      if (dist > 1) {
        final dir = (bp - c) / dist;
        final dash = Paint()
          ..color = you
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round;
        for (var t = 14.0; t < dist - 14; t += 12) {
          canvas.drawLine(c + dir * t, c + dir * min(t + 6, dist - 14), dash);
        }
      }
      final tp = TextPainter(
        text: const TextSpan(text: '⭐', style: TextStyle(fontSize: 26)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, bp - Offset(tp.width / 2, tp.height / 2));
    } else if (exploreDir != null) {
      // dotted hint towards the stronger side found at the start
      final a = (exploreDir! - heading - 90) * pi / 180;
      final dir = Offset(cos(a), sin(a));
      final dash = Paint()
        ..color = you.withValues(alpha: 0.6)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      for (var t = 20.0; t < size.width * 0.4; t += 14) {
        canvas.drawLine(c + dir * t, c + dir * (t + 6), dash);
      }
    }

    // you: dot + view cone (forward = up)
    final cone = Path()
      ..moveTo(c.dx, c.dy)
      ..lineTo(c.dx - 18, c.dy - 34)
      ..arcToPoint(Offset(c.dx + 18, c.dy - 34), radius: const Radius.circular(40))
      ..close();
    canvas.drawPath(cone, Paint()..color = you.withValues(alpha: 0.18));
    canvas.drawCircle(c, 11, Paint()..color = Colors.white);
    canvas.drawCircle(c, 8, Paint()..color = you);

    // start-turn progress ring around you
    final cal = calibrating;
    if (cal != null) {
      final rect = Rect.fromCircle(center: c, radius: 26);
      canvas.drawArc(
          rect,
          0,
          2 * pi,
          false,
          Paint()
            ..color = grid
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4);
      canvas.drawArc(
          rect,
          -pi / 2,
          2 * pi * cal,
          false,
          Paint()
            ..color = you
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => true;
}
