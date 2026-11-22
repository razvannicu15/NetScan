import 'dart:async';

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../services/mobile_network.dart';
import '../services/wifi_info.dart';
import 'live_chart.dart';
import 'widgets.dart';

class MobileNetworkPage extends StatefulWidget {
  const MobileNetworkPage({super.key});

  @override
  State<MobileNetworkPage> createState() => _MobileNetworkPageState();
}

class _MobileNetworkPageState extends State<MobileNetworkPage> {
  MobileNetInfo? _info;
  bool _loading = true;
  bool _more = false;
  final List<(DateTime, double)> _signal = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _read();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _read());
  }

  Future<void> _read() async {
    final i = await MobileNetInfo.read();
    if (!mounted) return;
    final now = DateTime.now();
    final v = i?.rsrp ?? i?.serving?.dbm ?? i?.dbm;
    if (v != null) {
      _signal.add((now, v.toDouble()));
      _signal.removeWhere((p) => now.difference(p.$1).inSeconds > 65);
    }
    setState(() {
      _info = i;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Color _rateColor(int r, ColorScheme cs) => switch (r) {
        3 => Colors.green.shade600,
        2 => Colors.lightGreen.shade700,
        1 => Colors.orange.shade700,
        _ => cs.error,
      };

  Color _dbmColor(int? v, ColorScheme cs) =>
      v == null ? cs.onSurfaceVariant : _rateColor(SignalRating.rsrp(v), cs);

  Widget _box(Widget child) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final i = _info;

    return Scaffold(
      appBar: AppBar(title: Text(tr('Rețea mobilă', 'Mobile network'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : i == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(tr('Informațiile despre rețeaua mobilă nu sunt disponibile pe acest dispozitiv.',
                        'Mobile network info is not available on this device.'),
                        textAlign: TextAlign.center),
                  ),
                )
              : _content(i, cs, tt),
    );
  }

  Widget _content(MobileNetInfo i, ColorScheme cs, TextTheme tt) {
    final s = i.serving;
    final main = i.rsrp ?? s?.dbm ?? i.dbm;
    final verdict = SignalRating.verdict(i);
    final neighbours = i.neighbours;

    final quality = <(String, String, int?, int Function(int), String)>[
      ('RSRP', tr('putere semnal', 'signal power'), i.rsrp ?? s?.rsrp, SignalRating.rsrp, 'dBm'),
      ('RSRQ', tr('calitate', 'quality'), i.rsrq ?? s?.rsrq, SignalRating.rsrq, 'dB'),
      ('SINR', tr('semnal / zgomot', 'signal / noise'), i.sinr ?? s?.snr, SignalRating.sinr, 'dB'),
    ].where((q) => q.$3 != null).toList();

    final details = <InfoRow>[
      if (s?.enb != null) InfoRow(Icons.cell_tower, 'eNodeB · sector', '${s!.enb} · ${s.sector}'),
      InfoRow(Icons.tag, 'Cell ID', s?.ci?.toString()),
      InfoRow(Icons.map_outlined, 'TAC / LAC', s?.tac?.toString()),
      InfoRow(Icons.grain, 'PCI', s?.pci?.toString()),
      InfoRow(Icons.graphic_eq, 'ARFCN', s?.arfcn?.toString()),
      InfoRow(Icons.public, 'MCC-MNC',
          (s?.mcc != null && s?.mnc != null) ? '${s!.mcc}-${s.mnc}' : i.mccmnc),
    ].where((r) => r.visible).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        MaxWidth(
          width: 760,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ------------------------------------------------ header
              _box(Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Row(children: [
                  Icon(Icons.signal_cellular_alt, size: 30, color: _dbmColor(main, cs)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(i.operator ?? i.simOperator ?? tr('Rețea mobilă', 'Mobile network'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (i.generation != null) i.generation!,
                          if (s?.bandLabel != null) s!.bandLabel!,
                          if (i.roaming) 'Roaming',
                        ].join(' · '),
                        style: tt.bodySmall?.copyWith(
                            color: i.roaming ? Colors.orange.shade700 : cs.onSurfaceVariant),
                      ),
                    ]),
                  ),
                  if (main != null)
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(end: main.toDouble()),
                        duration: const Duration(milliseconds: 600),
                        builder: (context, v, _) => Text('${v.round()}',
                            style: tt.displaySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: _dbmColor(main, cs),
                              fontFeatures: const [FontFeature.tabularFigures()],
                            )),
                      ),
                      Text('dBm · ${SignalRating.word(SignalRating.rsrp(main))}',
                          style: tt.labelMedium?.copyWith(color: _dbmColor(main, cs))),
                    ]),
                ]),
              )),
              const SizedBox(height: 12),

              // ------------------------------------------------ chart
              _box(Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 12, 6),
                child: LiveChart(
                  minY: -130,
                  maxY: -50,
                  yStep: 10,
                  series: [
                    ChartSeries(color: _dbmColor(main, cs), points: _signal, width: 3, fill: true),
                  ],
                ),
              )),

              // ------------------------------------------------ quality
              if (quality.isNotEmpty) ...[
                SectionHeader(tr('Calitatea semnalului', 'Signal quality')),
                TableCard(
                  margin: EdgeInsets.zero,
                  children: [
                    for (final q in quality)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(children: [
                          SizedBox(
                            width: 56,
                            child: Text(q.$1, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          ),
                          Expanded(
                            child: Text(q.$2, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                          ),
                          Text('${q.$3} ${q.$5}',
                              style: tt.titleSmall?.copyWith(
                                  fontFeatures: const [FontFeature.tabularFigures()])),
                          const SizedBox(width: 10),
                          Container(
                            width: 72,
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            decoration: BoxDecoration(
                              color: _rateColor(q.$4(q.$3!), cs).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(SignalRating.word(q.$4(q.$3!)),
                                textAlign: TextAlign.center,
                                style: tt.labelMedium?.copyWith(
                                    color: _rateColor(q.$4(q.$3!), cs), fontWeight: FontWeight.w700)),
                          ),
                        ]),
                      ),
                  ],
                ),
                if (verdict != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(children: [
                      Icon(Icons.lightbulb_outline, color: cs.onPrimaryContainer),
                      const SizedBox(width: 12),
                      Expanded(child: Text(verdict, style: tt.bodyMedium)),
                    ]),
                  ),
                ],
              ],

              // ------------------------------------------------ location hint
              if (!i.hasLocation) ...[
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await WifiService.requestAgain();
                    await _read();
                  },
                  icon: const Icon(Icons.location_on_outlined),
                  label: Text(tr('Permite Locația ca să vezi antenele', 'Allow Location to see cell towers')),
                ),
              ],

              // ------------------------------------------------ serving cell
              if (s != null) ...[
                SectionHeader(tr('Antena la care ești conectat', 'Your serving cell')),
                TableCard(margin: EdgeInsets.zero, children: [
                  InfoRow(Icons.settings_input_antenna, tr('Tip', 'Type'),
                      [s.type, if (s.bandLabel != null) s.bandLabel!].join(' · '), copy: false),
                  if (_more) ...details,
                  if (details.isNotEmpty)
                    InkWell(
                      onTap: () => setState(() => _more = !_more),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(
                            _more
                                ? tr('Mai puțin', 'Less')
                                : tr('Detalii tehnice · ${details.length}', 'Technical details · ${details.length}'),
                            style: tt.labelLarge?.copyWith(color: cs.primary),
                          ),
                          Icon(_more ? Icons.expand_less : Icons.expand_more, size: 18, color: cs.primary),
                        ]),
                      ),
                    ),
                ]),
              ],

              // ------------------------------------------------ neighbours
              if (neighbours.isNotEmpty) ...[
                SectionHeader(tr('Antene din jur · ${neighbours.length}', 'Nearby cells · ${neighbours.length}')),
                TableCard(
                  margin: EdgeInsets.zero,
                  header: _cols,
                  children: [
                    for (final c in neighbours.take(15))
                      TableDataRow(cols: _cols, cells: [
                        CellText(c.type, bold: true),
                        CellText(c.pci?.toString() ?? '—', muted: true),
                        CellText(c.bandLabel ?? '—', muted: true),
                        CellText(c.dbm == null ? '—' : '${c.dbm} dBm',
                            bold: true, color: _dbmColor(c.dbm, cs)),
                      ]),
                  ],
                ),
              ],

              // ------------------------------------------------ SIM
              SectionHeader('SIM'),
              TableCard(margin: EdgeInsets.zero, children: [
                InfoRow(Icons.sim_card_outlined, tr('Operator SIM', 'SIM carrier'), i.simOperator, copy: false),
                InfoRow(Icons.flag_outlined, tr('Țara SIM', 'SIM country'), i.simCountry, copy: false),
                InfoRow(Icons.travel_explore, tr('Țara rețelei', 'Network country'), i.netCountry, copy: false),
                InfoRow(Icons.swap_horiz, 'Roaming', i.roaming ? tr('Da', 'Yes') : tr('Nu', 'No'), copy: false),
              ]),
              const SizedBox(height: 12),
              Text(
                tr('Se actualizează la 2 secunde. Antenele din jur depind de ce raportează telefonul.',
                    'Updates every 2 seconds. Nearby cells depend on what the phone reports.'),
                textAlign: TextAlign.center,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<TableCol> get _cols => [
        TableCol(tr('Tip', 'Type'), width: 44),
        const TableCol('PCI', width: 52),
        TableCol(tr('Bandă', 'Band'), flex: 3),
        const TableCol('dBm', flex: 2, align: TextAlign.right),
      ];
}
