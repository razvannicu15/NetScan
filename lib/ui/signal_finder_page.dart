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
  double sum = 0;
  int n = 0;
  double? get value => n == 0 ? null : sum / n;
  void clear() {
    sum = 0;
    n = 0;
  }
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
  String? _bssid;
  String? _band;
  int? _channel;
  final Map<String, int> _nodes = {}; // bssid -> 0,1,2… (Nod A, B, C)
  String? _roamMsg;
  DateTime? _roamAt;

  // Locked target (world heading) once a full turn is done.
  double? _target;
  double _gain = 0; // dB better towards target
  double? _lockRssi;
  double _arrowTurns = 0; // continuous, so the arrow never spins the long way
  int _dir = 0; // 0 ahead, 1 right, 2 behind, 3 left
  int _dirCandidate = 0;
  DateTime _dirSince = DateTime.now();

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
        _heading = (cur + d * 0.2 + 360) % 360;
      }
      final t = _target;
      if (t != null) {
        final rel = (t - _heading! + 360) % 360;
        final want = rel / 360;
        var diff = (want - _arrowTurns) % 1.0;
        if (diff > 0.5) diff -= 1.0;
        if (diff < -0.5) diff += 1.0;
        _arrowTurns += diff;
        // signed angle -180..180 → direction bucket, debounced 0.6 s
        final sgn = ((rel + 180) % 360) - 180;
        final cand = sgn.abs() <= 35
            ? 0
            : sgn.abs() >= 145
                ? 2
                : sgn > 0
                    ? 1
                    : 3;
        final now = DateTime.now();
        if (cand != _dirCandidate) {
          _dirCandidate = cand;
          _dirSince = now;
        } else if (cand != _dir && now.difference(_dirSince).inMilliseconds >= 600) {
          _dir = cand;
          HapticFeedback.selectionClick();
        }
      }
    });
  }

  void _recalibrate() {
    for (final sec in _map) {
      sec.clear();
    }
    _target = null;
    _lockRssi = null;
    _gain = 0;
  }

  /// After enough of the circle is measured, lock the best direction.
  void _tryLock() {
    final vals = [for (final s in _map) s.value];
    final measured = vals.whereType<double>().length;
    if (measured < 10) return;
    // smooth with neighbours to resist noise
    final score = <double?>[];
    for (var i = 0; i < _sectors; i++) {
      final v = vals[i];
      if (v == null) {
        score.add(null);
        continue;
      }
      final l = vals[(i - 1 + _sectors) % _sectors] ?? v;
      final r = vals[(i + 1) % _sectors] ?? v;
      score.add(v * 0.5 + l * 0.25 + r * 0.25);
    }
    final ok = score.whereType<double>().toList();
    final best = ok.reduce(max), worst = ok.reduce(min);
    if (best - worst < 4) return; // flat: no meaningful direction
    final i = score.indexOf(best);
    _target = i * (360 / _sectors) + 360 / _sectors / 2;
    _gain = best - worst;
    _lockRssi = _smooth;
    _dir = _dirCandidate = 0;
    HapticFeedback.mediumImpact();
  }

  Future<void> _tick() async {
    final s = await LiveWifi.read();
    if (!mounted || s?.rssi == null) return;
    final r = s!.rssi!;
    final now = DateTime.now();
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
      _recent.add((now, r.toDouble()));
      _recent.removeWhere((p) => now.difference(p.$1).inSeconds > 6);
      final h = _heading;
      if (h != null && _target == null) {
        _map[(h / (360 / _sectors)).floor() % _sectors]
          ..sum += r
          ..n += 1;
        _tryLock();
      }
      // walked a few metres (signal changed a lot): ask for a new turn
      final lock = _lockRssi;
      if (_target != null && lock != null && (_smooth! - lock).abs() >= 7) _recalibrate();
    });
  }

  String _node(String bssid) => '${tr('Nod', 'Node')} ${String.fromCharCode(65 + (_nodes[bssid] ?? 0))}';

  void _onRoam(String from, String to, String? band) {
    HapticFeedback.heavyImpact();
    if (_sound) LiveWifi.tone(9);
    // new access point: old directions are no longer valid
    _recalibrate();
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
    final measured = _map.where((x) => x.n > 0).length;
    final found = _hasCompass && _target != null;
    final facing = found && _dir == 0;
    final flat = _hasCompass && !found && measured >= _sectors;
    final dirText = !found
        ? ''
        : switch (_dir) {
            0 => tr('Înainte! Mergi în direcția asta', 'Straight ahead! Walk this way'),
            1 => tr('Întoarce-te la dreapta', 'Turn right'),
            2 => tr('Întoarce-te', 'Turn around'),
            _ => tr('Întoarce-te la stânga', 'Turn left'),
          };
    final showRoam = _roamMsg != null &&
        _roamAt != null &&
        DateTime.now().difference(_roamAt!).inSeconds < 10;
    final nodeLine = [
      if (_bssid != null)
        _nodes.length > 1 ? _node(_bssid!) : 'AP …${_bssid!.substring(9)}',
      if (_band != null) _band!,
      if (_channel != null) '${tr('canal', 'ch')} $_channel',
    ].join(' · ');

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
                  // ---------------------------------------------- network / node
                  if (_ssid != null)
                    Text(_ssid!,
                        textAlign: TextAlign.center,
                        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  if (nodeLine.isNotEmpty)
                    Text(nodeLine,
                        textAlign: TextAlign.center,
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: showRoam
                        ? Container(
                            key: const ValueKey('roam'),
                            margin: const EdgeInsets.only(top: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: cs.tertiaryContainer,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(children: [
                              Icon(Icons.swap_horiz, color: cs.onTertiaryContainer),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(_roamMsg!,
                                    style: tt.bodyMedium?.copyWith(
                                        color: cs.onTertiaryContainer, fontWeight: FontWeight.w600)),
                              ),
                            ]),
                          )
                        : const SizedBox(key: ValueKey('none'), height: 0),
                  ),
                  const SizedBox(height: 12),

                  // ---------------------------------------------- dial
                  AspectRatio(
                    aspectRatio: 1,
                    child: CustomPaint(
                      painter: _FinderPainter(
                        progress: _hasCompass && !found ? measured / 10 : null,
                        value: _percent / 100,
                        valueColor: c,
                        track: cs.surfaceContainerHighest,
                        accent: cs.primary,
                      ),
                      child: Center(
                        child: found
                            ? Column(mainAxisSize: MainAxisSize.min, children: [
                                AnimatedRotation(
                                  turns: _arrowTurns,
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOut,
                                  child: Icon(Icons.navigation,
                                      size: 120, color: facing ? Colors.green.shade600 : cs.primary),
                                ),
                                const SizedBox(height: 4),
                                Text('${_smooth!.round()} dBm',
                                    style: tt.titleLarge?.copyWith(
                                        color: c,
                                        fontWeight: FontWeight.w700,
                                        fontFeatures: const [FontFeature.tabularFigures()])),
                              ])
                            : Column(mainAxisSize: MainAxisSize.min, children: [
                                Text('${_smooth!.round()}',
                                    style: tt.displayLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: c,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    )),
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
                              ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ---------------------------------------------- instruction
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: found
                          ? (facing ? Colors.green.shade600.withValues(alpha: 0.14) : cs.primaryContainer)
                          : cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(children: [
                      Text(
                        !_hasCompass
                            ? tr('Plimbă-te prin casă', 'Walk around')
                            : found
                                ? dirText
                                : tr('Rotește-te încet pe loc', 'Turn slowly on the spot'),
                        textAlign: TextAlign.center,
                        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        !_hasCompass
                            ? tr('Bipuri mai rapide și mai ascuțite = semnal mai bun.',
                                'Faster, higher beeps = better signal.')
                            : found
                                ? tr('Acolo semnalul e cu ~${_gain.round()} dB mai bun. Direcția rămâne fixă; după ce te muți, îți cer o tură nouă.',
                                    'About ${_gain.round()} dB better that way. The direction stays fixed; after you move, you\'ll be asked for a new turn.')
                                : flat
                                    ? tr('Semnalul e la fel în toate direcțiile. Fă câțiva pași și încearcă din nou.',
                                        'Same signal in every direction. Take a few steps and try again.')
                                    : tr('Ține telefonul în față și fă o tură completă: ${min(measured, 10)} / 10',
                                        'Hold the phone in front of you and make a full turn: ${min(measured, 10)} / 10'),
                        textAlign: TextAlign.center,
                        style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  TableCard(margin: EdgeInsets.zero, children: [
                    InfoRow(Icons.arrow_upward, tr('Cel mai bun', 'Best'), '$_max dBm', copy: false),
                    InfoRow(Icons.arrow_downward, tr('Cel mai slab', 'Worst'), '$_min dBm', copy: false),
                    if (_nodes.length > 1)
                      InfoRow(Icons.hub_outlined, tr('Noduri mesh văzute', 'Mesh nodes seen'),
                          '${_nodes.length}', copy: false),
                  ]),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _min = null;
                      _max = null;
                      _recalibrate();
                    }),
                    icon: const Icon(Icons.restart_alt),
                    label: Text(tr('Caută din nou', 'Search again')),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Inner arc = signal strength. While calibrating, an outer ring fills
/// as you turn (how much of the full circle has been measured).
class _FinderPainter extends CustomPainter {
  _FinderPainter({
    required this.progress,
    required this.value,
    required this.valueColor,
    required this.track,
    required this.accent,
  });

  final double? progress;
  final double value;
  final Color valueColor;
  final Color track;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = min(size.width, size.height) / 2 - 10;
    final w = r * 0.06;

    void arc(double radius, double start, double sweep, Color color, double width) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: radius),
        start,
        sweep,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }

    // strength arc (270°)
    const start = 135 * pi / 180;
    const sweep = 270 * pi / 180;
    final rIn = r - w * 3;
    arc(rIn, start, sweep, track, w);
    if (value > 0) arc(rIn, start, sweep * value, valueColor, w);

    // calibration ring
    final p = progress;
    if (p != null) {
      arc(r, -pi / 2, 2 * pi, track.withValues(alpha: 0.6), w * 0.6);
      if (p > 0) arc(r, -pi / 2, 2 * pi * p.clamp(0.0, 1.0).toDouble(), accent, w * 0.6);
    }
  }

  @override
  bool shouldRepaint(covariant _FinderPainter old) =>
      old.progress != progress || old.value != value || old.valueColor != valueColor;
}
